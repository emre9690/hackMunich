"""JSON event schema shared by the harness, orchestrator, and SSE server.

Every pipeline action emits exactly one JSON line via emit(). Consumers
(stdout, the SSE stream) read structured fields only — never natural-language
Devin chatter.
"""
from __future__ import annotations

import json
import sys
import threading
from datetime import datetime, timezone
from typing import Any, Literal, Optional

AGENTS = ("coder", "testbencher", "style", "harness", "synth")
STAGES = ("generate", "verify", "coverage", "cleanup", "synthesize")
STATUSES = ("running", "pass", "fail", "stalled", "error")

# Stage 6 runs multiple attempt pipelines concurrently in separate threads,
# all emitting to the same stdout -- serialize each line so two events can
# never interleave into one malformed line for the SSE relay to choke on.
_PRINT_LOCK = threading.Lock()

Agent = Literal["coder", "testbencher", "style", "harness", "synth"]
Stage = Literal["generate", "verify", "coverage", "cleanup", "synthesize"]
Status = Literal["running", "pass", "fail", "stalled", "error"]


def emit(
    *,
    chip: str,
    branch: str,
    agent: Agent,
    stage: Stage,
    attempt: int,
    status: Status,
    passed: Optional[int] = None,
    total: Optional[int] = None,
    session_id: Optional[str] = None,
    session_url: Optional[str] = None,
    artifact_path: Optional[str] = None,
    detail: str = "",
    stream=None,
) -> dict[str, Any]:
    """Build, validate, print, and return one event dict.

    Prints one JSON line to `stream` (default stdout) and returns the same
    dict so callers (SSE server, tests) can reuse it without re-parsing.
    """
    if agent not in AGENTS:
        raise ValueError(f"invalid agent {agent!r}, must be one of {AGENTS}")
    if stage not in STAGES:
        raise ValueError(f"invalid stage {stage!r}, must be one of {STAGES}")
    if status not in STATUSES:
        raise ValueError(f"invalid status {status!r}, must be one of {STATUSES}")

    event = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "chip": chip,
        "branch": branch,
        "agent": agent,
        "stage": stage,
        "attempt": attempt,
        "passed": passed,
        "total": total,
        "status": status,
        "session_id": session_id,
        "session_url": session_url,
        "artifact_path": artifact_path,
        "detail": detail,
    }

    line = json.dumps(event)
    with _PRINT_LOCK:
        print(line, file=stream or sys.stdout, flush=True)
    return event
