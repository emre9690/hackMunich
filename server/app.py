"""FastAPI event server: streams pipeline events to the command-room UI over
SSE and exposes run controls.

Instrumentation principle (brief): all UI state comes from the structured
JSON event lines emitted by harness/events.py -- this server is a thin relay
that spawns `python3 -m orchestrator.run` as a subprocess and re-broadcasts
its stdout lines. It never parses Devin's natural-language chatter.
"""
from __future__ import annotations

import asyncio
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
from typing import AsyncIterator

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from spec.registry import available_chips  # noqa: E402

app = FastAPI(title="Chip-Recreation Command Room")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_HISTORY_LIMIT = 2000
_REPLAY_LIMIT = 300

_history: list[dict] = []
_subscribers: list[asyncio.Queue] = []
_runs: dict[str, dict] = {}
_processes: dict[str, asyncio.subprocess.Process] = {}


async def _broadcast(event: dict) -> None:
    _history.append(event)
    if len(_history) > _HISTORY_LIMIT:
        del _history[: len(_history) - _HISTORY_LIMIT]
    for queue in list(_subscribers):
        await queue.put(event)


async def _pump_process(run_id: str, proc: asyncio.subprocess.Process) -> None:
    assert proc.stdout is not None
    async for raw_line in proc.stdout:
        line = raw_line.decode(errors="replace").strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue  # not a structured event line (e.g. the pretty-printed
            # final summary block) -- never treated as pipeline state
        await _broadcast(event)

    returncode = await proc.wait()
    _processes.pop(run_id, None)
    if run_id in _runs and _runs[run_id].get("status") != "killed":
        _runs[run_id]["status"] = "finished" if returncode == 0 else "failed"
        _runs[run_id]["returncode"] = returncode


class RunRequest(BaseModel):
    chip: str
    attempts: int = 1
    parallel: bool = False  # Stage 6: run `attempts` branches concurrently


@app.get("/api/chips")
def list_chips() -> dict:
    return {"chips": list(available_chips())}


@app.get("/api/runs")
def list_runs() -> dict:
    return {"runs": _runs}


def _next_start_run_id(chip: str) -> int:
    """Find the next unused attempt/<chip>-NN branch number on origin, so a
    fresh launch never reuses (and clobbers) an already-verified branch."""
    result = subprocess.run(
        ["git", "ls-remote", "--heads", "origin", f"attempt/{chip}-*"],
        cwd=str(_REPO_ROOT), capture_output=True, text=True,
    )
    used = [int(m.group(1)) for line in result.stdout.splitlines()
            if (m := re.search(rf"attempt/{re.escape(chip)}-(\d+)$", line))]
    return max(used, default=0) + 1


@app.post("/api/runs")
async def start_run(req: RunRequest) -> dict:
    if req.chip not in available_chips():
        raise HTTPException(400, f"unknown chip {req.chip!r}, known: {available_chips()}")
    if req.attempts < 1:
        raise HTTPException(400, "attempts must be >= 1")

    start_run_id = await asyncio.to_thread(_next_start_run_id, req.chip)
    run_id = f"{req.chip}-{start_run_id}"
    cmd = [
        sys.executable, "-m", "orchestrator.run",
        "--chip", req.chip,
        "--attempts", str(req.attempts),
        "--start-run-id", str(start_run_id),
    ]
    if req.parallel:
        cmd.append("--parallel")
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=str(_REPO_ROOT),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    _runs[run_id] = {
        "chip": req.chip, "attempts": req.attempts, "parallel": req.parallel,
        "pid": proc.pid, "status": "running",
    }
    _processes[run_id] = proc
    asyncio.create_task(_pump_process(run_id, proc))
    return {"run_id": run_id, "pid": proc.pid}


@app.post("/api/kill-all")
def kill_all() -> dict:
    """Forcibly stop every orchestrator process: the ones this server is
    tracking, plus a sweep for any `orchestrator.run` process that survived
    a server restart (in-memory tracking is lost on restart, but the child
    process it spawned is not -- this is exactly how a prior incident's
    runaway process went unnoticed).

    Important: this stops the LOCAL polling/orchestration loop, so no NEW
    Devin session gets created from here on. It does NOT cancel a Devin
    session that's already running in their cloud -- the Devin API has no
    known stop/cancel endpoint, so an in-flight session keeps running there
    regardless of this button."""
    killed_pids: list[int] = []

    for run_id, proc in list(_processes.items()):
        if proc.returncode is None:
            proc.kill()
            killed_pids.append(proc.pid)
        _processes.pop(run_id, None)
        if run_id in _runs:
            _runs[run_id]["status"] = "killed"

    sweep = subprocess.run(["pgrep", "-f", "orchestrator.run"], capture_output=True, text=True)
    for pid_str in sweep.stdout.split():
        pid = int(pid_str)
        if pid in killed_pids or pid == os.getpid():
            continue
        try:
            os.kill(pid, signal.SIGKILL)
            killed_pids.append(pid)
        except ProcessLookupError:
            pass

    return {"killed_pids": killed_pids}


@app.get("/api/events")
async def stream_events() -> StreamingResponse:
    queue: asyncio.Queue = asyncio.Queue()
    _subscribers.append(queue)

    async def gen() -> AsyncIterator[bytes]:
        try:
            for event in _history[-_REPLAY_LIMIT:]:
                yield f"data: {json.dumps(event)}\n\n".encode()
            while True:
                event = await queue.get()
                yield f"data: {json.dumps(event)}\n\n".encode()
        finally:
            _subscribers.remove(queue)

    return StreamingResponse(gen(), media_type="text/event-stream")


@app.get("/api/leaderboard")
def leaderboard(chip: str) -> dict:
    """Stage 6: compare parallel attempts by resource usage (LUT count),
    all verified against the same golden vectors. Derived entirely from the
    structured event history -- an entry only appears if its branch's most
    recent verify AND synth events both report status=='pass'."""
    by_branch: dict[str, dict] = {}
    prefix = f"attempt/{chip}-"
    for event in _history:
        branch = event.get("branch") or ""
        if event.get("chip") != chip or not branch.startswith(prefix):
            continue
        entry = by_branch.setdefault(branch, {})
        if event.get("stage") == "verify":
            entry["last_verify"] = event
        elif event.get("stage") == "synthesize":
            entry["last_synth"] = event

    rows = []
    for branch, entry in by_branch.items():
        verify = entry.get("last_verify")
        synth = entry.get("last_synth")
        if not verify or verify.get("status") != "pass":
            continue
        if not synth or synth.get("status") != "pass":
            continue
        rows.append({
            "branch": branch,
            "passed": verify.get("passed"),
            "total": verify.get("total"),
            "lut_count": synth.get("passed"),
            "synth_detail": synth.get("detail"),
        })

    rows.sort(key=lambda r: r["lut_count"])
    for i, row in enumerate(rows):
        row["best"] = i == 0

    return {"chip": chip, "entries": rows}


_ALLOWED_ARTIFACT_SUFFIXES = {".vcd", ".txt"}


@app.get("/api/artifact")
def get_artifact(path: str) -> PlainTextResponse:
    """Serve a proof-panel artifact (waveform .vcd, synth report .txt) by its
    repo-relative or absolute path, as emitted in an event's artifact_path.
    Restricted to files inside the repo to prevent path traversal."""
    candidate = pathlib.Path(path)
    if not candidate.is_absolute():
        candidate = _REPO_ROOT / candidate
    candidate = candidate.resolve()

    if _REPO_ROOT not in candidate.parents and candidate != _REPO_ROOT:
        raise HTTPException(403, "artifact path is outside the repo")
    if candidate.suffix not in _ALLOWED_ARTIFACT_SUFFIXES:
        raise HTTPException(403, f"unsupported artifact type {candidate.suffix!r}")
    if not candidate.exists():
        raise HTTPException(404, "artifact not found")

    return PlainTextResponse(candidate.read_text(errors="replace"))


@app.post("/api/reset")
def reset() -> dict:
    """Clear the event history and finished/failed run records so the UI
    (and any fresh SSE connection's replay) starts from a clean slate.
    Runs still in flight are left alone -- resetting doesn't cancel them,
    it just stops showing their past events."""
    _history.clear()
    for run_id in [k for k, v in _runs.items() if v.get("status") != "running"]:
        del _runs[run_id]
    return {"ok": True}


@app.get("/api/health")
def health() -> dict:
    return {"ok": True}
