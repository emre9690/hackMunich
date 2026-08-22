"""FastAPI event server: streams pipeline events to the command-room UI over
SSE and exposes run controls.

Instrumentation principle (brief): all UI state comes from the structured
JSON event lines emitted by harness/events.py -- this server is a thin relay
that spawns `python3 -m orchestrator.run` as a subprocess and re-broadcasts
its stdout lines. It never parses Devin's natural-language chatter.
"""
from __future__ import annotations

import asyncio
import importlib
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
from typing import AsyncIterator

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from spec import registry as spec_registry  # noqa: E402


def available_chips() -> tuple[str, ...]:
    # Goes through the module reference (not a bound function) so that
    # importlib.reload(spec_registry) after a draft approval takes effect
    # immediately, without needing a server restart.
    return spec_registry.available_chips()

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
    fast_demo: bool = False  # skip Testbencher/Style; verification stays exhaustive


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
    if req.fast_demo:
        cmd.append("--fast-demo")
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=str(_REPO_ROOT),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    _runs[run_id] = {
        "chip": req.chip, "attempts": req.attempts, "parallel": req.parallel,
        "fast_demo": req.fast_demo,
        "pid": proc.pid, "status": "running",
    }
    _processes[run_id] = proc
    asyncio.create_task(_pump_process(run_id, proc))
    return {"run_id": run_id, "pid": proc.pid}


# ---------------------------------------------------------------------------
# Custom chip drafting: upload a datasheet -> Devin drafts to /drafts/ (never
# /spec/) -> human reviews the actual truth table -> explicit approve moves
# it into /spec/chips/ and registers it. See orchestrator/spec_drafter.py.
# ---------------------------------------------------------------------------

_CHIP_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def _register_chip(chip_id: str) -> None:
    """Human-triggered-only: called from the approve endpoint, never from
    drafting. Appends chip_id to spec/registry.py's _KNOWN_CHIP_IDS tuple
    and reloads the module so it takes effect without a server restart."""
    registry_path = _REPO_ROOT / "spec" / "registry.py"
    text = registry_path.read_text()
    match = re.search(r"_KNOWN_CHIP_IDS = \(([^)]*)\)", text)
    if not match:
        raise RuntimeError("could not find _KNOWN_CHIP_IDS tuple in spec/registry.py")

    existing_ids = re.findall(r'"([^"]+)"', match.group(1))
    if chip_id not in existing_ids:
        new_line = "_KNOWN_CHIP_IDS = (" + ", ".join(f'"{i}"' for i in existing_ids + [chip_id]) + ")"
        text = text[: match.start()] + new_line + text[match.end():]
        registry_path.write_text(text)

    importlib.reload(spec_registry)


@app.post("/api/drafts")
async def create_draft(chip_id: str = Form(...), file: UploadFile = File(...)) -> dict:
    if not _CHIP_ID_RE.match(chip_id):
        raise HTTPException(400, "chip_id must be lowercase letters/digits/underscore, starting "
                                  "with a letter")
    if chip_id in available_chips():
        raise HTTPException(400, f"chip_id {chip_id!r} is already a registered chip")

    contents = await file.read()
    if not contents:
        raise HTTPException(400, "uploaded file is empty")

    tmp_dir = pathlib.Path(tempfile.mkdtemp(prefix="draft_upload_"))
    doc_path = tmp_dir / (file.filename or "datasheet.txt")
    doc_path.write_bytes(contents)

    cmd = [
        sys.executable, "-m", "orchestrator.draft_chip",
        "--chip-id", chip_id, "--doc-path", str(doc_path),
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=str(_REPO_ROOT),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    run_id = f"draft-{chip_id}"
    _runs[run_id] = {"chip": chip_id, "kind": "draft", "pid": proc.pid, "status": "running"}
    _processes[run_id] = proc
    asyncio.create_task(_pump_process(run_id, proc))
    return {"run_id": run_id, "chip_id": chip_id, "pid": proc.pid}


@app.get("/api/drafts/{chip_id}")
def get_draft(chip_id: str) -> dict:
    from orchestrator.spec_drafter import (
        DRAFTS_DIR, DraftValidationError, load_draft_module,
        preview_vectors, validate_draft_source, validate_draft_structure,
    )

    path = DRAFTS_DIR / f"{chip_id}.py"
    if not path.exists():
        raise HTTPException(404, f"no draft found for chip_id {chip_id!r}")

    source = path.read_text()
    try:
        validate_draft_source(source)
        module = load_draft_module(path)
        validate_draft_structure(module)
        preview = preview_vectors(module)
    except DraftValidationError as e:
        raise HTTPException(422, f"draft failed validation: {e}") from e

    return {"chip_id": chip_id, "source": source, "preview": preview}


@app.post("/api/drafts/{chip_id}/approve")
def approve_draft(chip_id: str) -> dict:
    from orchestrator.spec_drafter import (
        DRAFTS_DIR, DraftValidationError, load_draft_module,
        validate_draft_source, validate_draft_structure,
    )

    draft_path = DRAFTS_DIR / f"{chip_id}.py"
    if not draft_path.exists():
        raise HTTPException(404, f"no draft found for chip_id {chip_id!r}")

    source = draft_path.read_text()
    try:
        # Re-validate right before trusting it -- the draft file could in
        # principle have been edited on disk since it was last checked.
        validate_draft_source(source)
        module = load_draft_module(draft_path)
        validate_draft_structure(module)
    except DraftValidationError as e:
        raise HTTPException(422, f"draft failed validation, refusing to approve: {e}") from e

    target_path = _REPO_ROOT / "spec" / "chips" / f"{chip_id}.py"
    target_path.write_text(source)
    draft_path.unlink()
    _register_chip(chip_id)

    return {"ok": True, "chip_id": chip_id}


@app.post("/api/drafts/{chip_id}/reject")
def reject_draft(chip_id: str) -> dict:
    from orchestrator.spec_drafter import DRAFTS_DIR
    (DRAFTS_DIR / f"{chip_id}.py").unlink(missing_ok=True)
    return {"ok": True, "chip_id": chip_id}


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


_BRANCH_RE = re.compile(r"^attempt/[a-z0-9]+-\d+$")
_RTL_PATH_RE = re.compile(r"^rtl/[\w.-]+\.v$")


@app.get("/api/branch-file")
def get_branch_file(branch: str, path: str) -> PlainTextResponse:
    """Live code panel: fetch a file's actual content straight from the git
    branch (the real source of truth), the same way the harness does --
    never from a local temp file, which the harness deletes right after
    verifying it."""
    if not _BRANCH_RE.match(branch):
        raise HTTPException(400, f"invalid branch format: {branch!r}")
    if not _RTL_PATH_RE.match(path):
        raise HTTPException(400, f"invalid rtl path format: {path!r}")

    subprocess.run(["git", "fetch", "origin", branch], cwd=str(_REPO_ROOT),
                    capture_output=True, text=True, timeout=30)
    result = subprocess.run(["git", "show", f"origin/{branch}:{path}"], cwd=str(_REPO_ROOT),
                             capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise HTTPException(404, f"{path} not found on origin/{branch}")

    return PlainTextResponse(result.stdout)


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
