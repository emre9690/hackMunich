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

POLL_INITIAL_DELAY_SECONDS = 5
POLL_MAX_DELAY_SECONDS = 30
POLL_BACKOFF_FACTOR = 1.5

# The real API's status_enum values are broader than the brief's shorthand
# (running | blocked | stopped) -- observed in practice: "working" while a
# session is in progress, "finished" on normal completion. To avoid ever
# treating an in-progress session as done just because we don't recognize
# its enum value, we do the opposite of an allowlist: only a known terminal
# value ends polling: everything else is assumed still in progress.
TERMINAL_STATUSES = {"blocked", "stopped", "finished", "expired"}


class DevinAPIError(RuntimeError):
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
        raise DevinAPIError(f"Devin API {method} {path} unreachable: {e}") from e


def ping() -> bool:
    """Minimal cheap auth check -- lists sessions, creates nothing."""
    _request("GET", "/sessions?limit=1")
    return True


def create_session(prompt: str, *, title: Optional[str] = None, idempotent: bool = False) -> SessionHandle:
    body: dict[str, Any] = {"prompt": prompt, "idempotent": idempotent}
    if title:
        body["title"] = title
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
    state = get_session(session_id)
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
        state = get_session(session_id)
