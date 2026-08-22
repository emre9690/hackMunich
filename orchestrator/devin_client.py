"""Thin wrapper around the official Devin REST API.

Base: https://api.devin.ai/v1
Auth: Authorization: Bearer $DEVIN_API_KEY, read from the env var only --
never hardcoded, never logged, never printed.

The orchestrator only creates and polls sessions -- it never messages a
session interactively. Pass/fail is decided from status_enum, git branch
state, and the harness alone, never from a session's natural-language
messages; those are exposed (SessionState.messages) purely so a live
activity feed can show them, never as a source of pipeline truth.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Optional

API_BASE = "https://api.devin.ai/v1"

POLL_INITIAL_DELAY_SECONDS = 3
POLL_MAX_DELAY_SECONDS = 10
POLL_BACKOFF_FACTOR = 1.4

# A single poll hitting a transient network blip shouldn't abandon tracking
# of a session that's likely still running fine on Devin's side -- only a
# run of consecutive failures means we're really unable to reach the API.
POLL_TRANSIENT_RETRY_LIMIT = 5
POLL_TRANSIENT_RETRY_DELAY_SECONDS = 5

# The real API's status_enum values are broader than the brief's shorthand
# (running | blocked | stopped) -- observed in practice: "working" while a
# session is in progress, "finished" on normal completion. To avoid ever
# treating an in-progress session as done just because we don't recognize
# its enum value, we do the opposite of an allowlist: only a known terminal
# value ends polling: everything else is assumed still in progress.
TERMINAL_STATUSES = {"blocked", "stopped", "finished", "expired"}


class DevinAPIError(RuntimeError):
    pass


class DevinAPIUnreachable(DevinAPIError):
    """Network-level failure (DNS, dropped connection, timeout) reaching the
    Devin API -- transient and local to us, says nothing about whether the
    remote session itself is still fine. Retried a few times before being
    treated as a real failure; see poll_until_done."""
    pass


@dataclass
class SessionHandle:
    session_id: str
    url: str


@dataclass
class SessionState:
    session_id: str
    status_enum: str
    structured_output: dict[str, Any]
    raw: dict[str, Any]

    @property
    def is_running(self) -> bool:
        return self.status_enum not in TERMINAL_STATUSES

    @property
    def messages(self) -> list[dict[str, Any]]:
        """Devin's own narrated messages for this session, oldest first.

        Purely informational for a live activity feed -- never used to
        decide pass/fail (that stays the harness's job alone), and the
        first entry is always our own prompt echoed back, not new activity.
        """
        return self.raw.get("messages") or []


def _api_key() -> str:
    key = os.environ.get("DEVIN_API_KEY")
    if not key:
        raise DevinAPIError("DEVIN_API_KEY is not set in the environment")
    return key


def _request(method: str, path: str, *, json_body: Optional[dict] = None) -> dict[str, Any]:
    url = f"{API_BASE}{path}"
    data = json.dumps(json_body).encode() if json_body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {_api_key()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise DevinAPIError(f"Devin API {method} {path} failed: {e.code} {body[:800]}") from e
    except urllib.error.URLError as e:
        raise DevinAPIUnreachable(f"Devin API {method} {path} unreachable: {e}") from e


def ping() -> bool:
    """Minimal cheap auth check -- lists sessions, creates nothing."""
    _request("GET", "/sessions?limit=1")
    return True


def create_session(
    prompt: str,
    *,
    title: Optional[str] = None,
    idempotent: bool = False,
    structured_output_schema: Optional[dict] = None,
) -> SessionHandle:
    body: dict[str, Any] = {"prompt": prompt, "idempotent": idempotent}
    if title:
        body["title"] = title
    if structured_output_schema:
        body["structured_output_schema"] = structured_output_schema
    resp = _request("POST", "/sessions", json_body=body)
    return SessionHandle(session_id=resp["session_id"], url=resp.get("url", ""))


def get_session(session_id: str) -> SessionState:
    resp = _request("GET", f"/session/{session_id}")
    return SessionState(
        session_id=session_id,
        status_enum=resp.get("status_enum") or "",
        structured_output=resp.get("structured_output") or {},
        raw=resp,
    )


def _get_session_resilient(session_id: str) -> SessionState:
    """Like get_session, but absorbs a burst of transient network failures
    instead of letting the first one abandon a session that may well still
    be running (or already finished) on Devin's side."""
    last_error: DevinAPIUnreachable | None = None
    for attempt in range(POLL_TRANSIENT_RETRY_LIMIT):
        try:
            return get_session(session_id)
        except DevinAPIUnreachable as e:
            last_error = e
            if attempt < POLL_TRANSIENT_RETRY_LIMIT - 1:
                time.sleep(POLL_TRANSIENT_RETRY_DELAY_SECONDS)
    assert last_error is not None
    raise last_error


def poll_until_done(
    session_id: str,
    *,
    timeout_seconds: int,
    on_poll: Optional[Callable[[SessionState], None]] = None,
) -> tuple[SessionState, bool]:
    """Poll with exponential backoff until the session leaves 'running'.

    Returns (state, timed_out). timed_out=True means the wall-clock cap was
    hit while still running -- caller must mark this stalled and stop the
    branch, never leave a spinner hanging (brief §4).
    """
    start = time.monotonic()
    delay = POLL_INITIAL_DELAY_SECONDS
    state = _get_session_resilient(session_id)
    while True:
        if on_poll:
            on_poll(state)
        if not state.is_running:
            return state, False
        elapsed = time.monotonic() - start
        if elapsed >= timeout_seconds:
            return state, True
        time.sleep(min(delay, max(0.0, timeout_seconds - elapsed)))
        delay = min(delay * POLL_BACKOFF_FACTOR, POLL_MAX_DELAY_SECONDS)
        state = _get_session_resilient(session_id)
