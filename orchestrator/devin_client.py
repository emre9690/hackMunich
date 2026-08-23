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
# of a session that's likely still running fine on Devin's side -- only
# sustained unreachability means we're really unable to reach the API.
# Budgeted by TIME, not a fixed retry count: this environment has been
# observed going unreachable for 60s+ at a stretch (a git ls-remote once
# took 36s, DNS has failed outright for over a minute), so a handful of
# quick retries isn't enough margin -- 3 minutes of backoff is.
POLL_TRANSIENT_RETRY_BUDGET_SECONDS = 180
POLL_TRANSIENT_RETRY_INITIAL_DELAY_SECONDS = 5
POLL_TRANSIENT_RETRY_MAX_DELAY_SECONDS = 20

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
    playbook_id: Optional[str] = None,
    tags: Optional[list[str]] = None,
) -> SessionHandle:
    body: dict[str, Any] = {"prompt": prompt, "idempotent": idempotent}
    if title:
        body["title"] = title
    if structured_output_schema:
        body["structured_output_schema"] = structured_output_schema
    if playbook_id:
        body["playbook_id"] = playbook_id
    if tags:
        body["tags"] = tags
    resp = _request("POST", "/sessions", json_body=body)
    return SessionHandle(session_id=resp["session_id"], url=resp.get("url", ""))


def create_playbook(title: str, body: str, *, macro: Optional[str] = None) -> str:
    """Creates a reusable team Playbook, returning its playbook_id.

    Playbooks are per-org, not per-session -- there is no delete/list-by-
    title call here, so callers that create one at runtime (see pipeline.py)
    must cache the returned id themselves rather than calling this on every
    session, or they'll accumulate duplicate playbooks in the org."""
    payload: dict[str, Any] = {"title": title, "body": body}
    if macro:
        payload["macro"] = macro
    resp = _request("POST", "/playbooks", json_body=payload)
    return resp["playbook_id"]


def get_session(session_id: str) -> SessionState:
    resp = _request("GET", f"/session/{session_id}")
    return SessionState(
        session_id=session_id,
        status_enum=resp.get("status_enum") or "",
        structured_output=resp.get("structured_output") or {},
        raw=resp,
    )


def send_message(session_id: str, message: str) -> None:
    """Sends a follow-up message to an existing (idle/finished) session,
    used for the Coder retry loop so a fix-attempt resumes the SAME session
    -- same VM, same clone, same context -- instead of paying fresh
    boot+clone cost and making Devin re-derive a design it just wrote.
    Callers must treat this as best-effort: if it 404s (this API surface
    doesn't support it, or the session can't be resumed) the caller should
    fall back to create_session for a fresh session rather than fail the
    whole retry."""
    _request("POST", f"/session/{session_id}/message", json_body={"message": message})


def _get_session_resilient(session_id: str) -> SessionState:
    """Like get_session, but absorbs sustained transient network failures
    instead of letting the first one (or first few) abandon a session that
    may well still be running (or already finished) on Devin's side. Backs
    off exponentially up to POLL_TRANSIENT_RETRY_BUDGET_SECONDS of total
    wall-clock, not a fixed attempt count -- see that constant for why."""
    start = time.monotonic()
    delay = POLL_TRANSIENT_RETRY_INITIAL_DELAY_SECONDS
    while True:
        try:
            return get_session(session_id)
        except DevinAPIUnreachable:
            elapsed = time.monotonic() - start
            if elapsed >= POLL_TRANSIENT_RETRY_BUDGET_SECONDS:
                raise
            time.sleep(min(delay, POLL_TRANSIENT_RETRY_BUDGET_SECONDS - elapsed))
            delay = min(delay * 1.5, POLL_TRANSIENT_RETRY_MAX_DELAY_SECONDS)


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
