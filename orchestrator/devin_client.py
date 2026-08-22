"""Thin wrapper around the official Devin REST API.

Base: https://api.devin.ai/v1
Auth: Authorization: Bearer $DEVIN_API_KEY, read from the env var only --
never hardcoded, never logged, never printed.

The orchestrator only creates and polls sessions. It never messages a
session interactively, and it never reads a session's natural-language
output for pipeline state -- only status_enum and structured_output.
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

# Real observed status_enum values include more than the brief's shorthand
# (running | blocked | stopped) -- e.g. "finished", "expired". Treat anything
# other than "running" as terminal so the poller never hangs on an enum value
# we didn't anticipate.
RUNNING_STATUS = "running"
BLOCKED_STATUS = "blocked"


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
        return self.status_enum == RUNNING_STATUS

    @property
    def is_blocked(self) -> bool:
        return self.status_enum == BLOCKED_STATUS


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
        status_enum=resp.get("status_enum", RUNNING_STATUS),
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
