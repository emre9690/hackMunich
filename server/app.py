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
import io
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import zipfile
from typing import AsyncIterator

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, Response, StreamingResponse
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


@app.get("/api/chips")
def list_chips() -> dict:
    return {"chips": list(available_chips())}


@app.get("/api/chips/{chip_id}/ports")
def chip_ports(chip_id: str) -> dict:
    """Real pin names/order for the schematic visualization -- straight from
    the same human-owned ChipSpec the harness verifies against, not a
    separate hand-maintained list that could drift from the actual RTL."""
    if chip_id not in available_chips():
        raise HTTPException(404, f"unknown chip {chip_id!r}")
    spec = spec_registry.load_chip(chip_id)
    return {
        "chip_id": chip_id,
        "module_name": spec.module_name,
        "inputs": [p.name for p in spec.inputs],
        "outputs": [p.name for p in spec.outputs],
    }


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

    start_run_id = await asyncio.to_thread(_next_start_run_id, req.chip)
    run_id = f"{req.chip}-{start_run_id}"
    # Always single-attempt, always fast-demo (skip Testbencher/Style) --
    # the live demo has a hard wall-clock budget (caps.DEMO_WALLCLOCK_BUDGET_SECONDS)
    # that only the Coder fail->fix loop + synth can fit inside.
    cmd = [
        sys.executable, "-m", "orchestrator.run",
        "--chip", req.chip,
        "--attempts", "1",
        "--start-run-id", str(start_run_id),
        "--fast-demo",
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=str(_REPO_ROOT),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    _runs[run_id] = {"chip": req.chip, "pid": proc.pid, "status": "running"}
    _processes[run_id] = proc
    asyncio.create_task(_pump_process(run_id, proc))
    return {"run_id": run_id, "pid": proc.pid}


# ---------------------------------------------------------------------------
# Custom chip drafting: upload a datasheet -> Devin drafts to /drafts/ (never
# /spec/) -> human reviews the actual truth table -> explicit approve moves
# it into /spec/chips/ and registers it. See orchestrator/spec_drafter.py.
# ---------------------------------------------------------------------------

_CHIP_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def _commit_and_push_chip_files(chip_id: str) -> None:
    """The approved golden model (and updated registry) must actually reach
    origin/main -- a Coder-Devin session shallow-clones ITS OWN fresh copy of
    the attempt branch from origin and needs spec/chips/{chip_id}.py to
    already be there. Before this existed, approval only wrote the file to
    this server's local working tree, so Coder sessions found spec/chips/
    empty and had to go hunting on the drafts/ branch instead -- correct
    paths save a real detour, not just a cosmetic one."""
    rel_paths = [f"spec/chips/{chip_id}.py", "spec/registry.py"]
    last_attempt = _SERVER_GIT_RETRY_LIMIT - 1
    for attempt in range(_SERVER_GIT_RETRY_LIMIT):
        subprocess.run(["git", "add", *rel_paths], cwd=str(_REPO_ROOT),
                        capture_output=True, text=True, timeout=30)
        commit = subprocess.run(
            ["git", "commit", "-m", f"Register {chip_id}: approved from datasheet draft"],
            cwd=str(_REPO_ROOT), capture_output=True, text=True, timeout=30,
        )
        # A re-approval with identical content is not a failure.
        if commit.returncode != 0 and "nothing to commit" not in commit.stdout.lower():
            raise RuntimeError(f"git commit failed for {chip_id!r}: {commit.stderr or commit.stdout}")

        push = subprocess.run(["git", "push", "origin", "main"], cwd=str(_REPO_ROOT),
                               capture_output=True, text=True, timeout=60)
        if push.returncode == 0:
            return
        if attempt < last_attempt and any(m in push.stderr.lower() for m in _TRANSIENT_GIT_ERROR_MARKERS):
            time.sleep(_SERVER_GIT_RETRY_DELAY_SECONDS)
            continue
        raise RuntimeError(f"git push to main failed for {chip_id!r}: {push.stderr}")


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
        # Trailing comma after EVERY entry (not just joined between them) --
        # with exactly one id, ", ".join(...) produces "( "x" )" with no
        # comma, which Python parses as a parenthesized string, not a
        # 1-tuple, so available_chips() silently iterates its characters.
        new_line = "_KNOWN_CHIP_IDS = (" + "".join(f'"{i}", ' for i in existing_ids + [chip_id]) + ")"
        text = text[: match.start()] + new_line + text[match.end():]
        registry_path.write_text(text)

    importlib.reload(spec_registry)


def _clear_chip_registry() -> None:
    """Reset button: empty spec/registry.py's _KNOWN_CHIP_IDS tuple so every
    demo run starts from a blank chip dropdown -- Add Chip is the only way
    back in. Non-destructive: the underlying spec/chips/*.py files are left
    on disk, only the registry listing is cleared, and approving the same
    chip id again just re-registers and overwrites its file as usual."""
    registry_path = _REPO_ROOT / "spec" / "registry.py"
    text = registry_path.read_text()
    match = re.search(r"_KNOWN_CHIP_IDS = \(([^)]*)\)", text)
    if not match:
        raise RuntimeError("could not find _KNOWN_CHIP_IDS tuple in spec/registry.py")

    text = text[: match.start()] + "_KNOWN_CHIP_IDS = ()" + text[match.end():]
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
    _register_chip(chip_id)
    try:
        _commit_and_push_chip_files(chip_id)
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        # Don't unlink the draft or report success -- the chip is now
        # registered locally but NOT actually reachable by a Coder-Devin
        # session's fresh clone from origin. Leaving the draft in place
        # means the same approve click can just be retried once the
        # underlying git/network issue clears.
        raise HTTPException(502, f"approved locally but failed to push to origin: {e}") from e
    draft_path.unlink()

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


_BRANCH_RE = re.compile(r"^attempt/[a-z][a-z0-9_]*-\d+$")
_RTL_PATH_RE = re.compile(r"^rtl/[\w.-]+\.v$")

# A degraded (not down) connection can make these two calls fail once even
# though the branch/file genuinely exist -- retry before reporting 404.
_TRANSIENT_GIT_ERROR_MARKERS = (
    "could not resolve host", "could not connect to server", "connection timed out",
    "connection refused", "connection reset by peer", "unable to access",
    "the remote end hung up unexpectedly", "early eof", "rpc failed",
)
# Outages on this network have been observed lasting 60s+ at a stretch; a
# fast-failing DNS error costs no time on its own, so the retry COUNT (with
# an actual sleep between attempts, not a rapid-fire retry) is what has to
# provide the margin.
_SERVER_GIT_RETRY_LIMIT = 6
_SERVER_GIT_RETRY_DELAY_SECONDS = 8


def _fetch_branch_file_text(branch: str, path: str) -> str:
    """Fetch a file's actual content straight from the git branch (the real
    source of truth), the same way the harness does -- never from a local
    temp file, which the harness deletes right after verifying it."""
    if not _BRANCH_RE.match(branch):
        raise HTTPException(400, f"invalid branch format: {branch!r}")
    if not _RTL_PATH_RE.match(path):
        raise HTTPException(400, f"invalid rtl path format: {path!r}")

    last_attempt = _SERVER_GIT_RETRY_LIMIT - 1
    for attempt in range(_SERVER_GIT_RETRY_LIMIT):
        try:
            subprocess.run(["git", "fetch", "origin", branch], cwd=str(_REPO_ROOT),
                            capture_output=True, text=True, timeout=30)
            result = subprocess.run(["git", "show", f"origin/{branch}:{path}"], cwd=str(_REPO_ROOT),
                                     capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            if attempt < last_attempt:
                time.sleep(_SERVER_GIT_RETRY_DELAY_SECONDS)
                continue
            raise HTTPException(504, f"timed out fetching {path} from origin/{branch}")
        if result.returncode == 0:
            return result.stdout
        stderr_lower = result.stderr.lower()
        if attempt < last_attempt and any(m in stderr_lower for m in _TRANSIENT_GIT_ERROR_MARKERS):
            time.sleep(_SERVER_GIT_RETRY_DELAY_SECONDS)
            continue
        raise HTTPException(404, f"{path} not found on origin/{branch}")
    raise HTTPException(404, f"{path} not found on origin/{branch}")


@app.get("/api/branch-file")
def get_branch_file(branch: str, path: str) -> PlainTextResponse:
    """Live code panel: displays the fetched file inline."""
    return PlainTextResponse(_fetch_branch_file_text(branch, path))


@app.get("/api/branch-file/download")
def download_branch_file(branch: str, path: str) -> PlainTextResponse:
    """Same file as /api/branch-file, served as an attachment so the browser
    saves it instead of just displaying it -- backs the code panel's
    Download button."""
    content = _fetch_branch_file_text(branch, path)
    filename = path.rsplit("/", 1)[-1]
    return PlainTextResponse(
        content, headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )


@app.get("/api/export/{chip_id}")
def export_chip(chip_id: str, branch: str) -> Response:
    """Zips up everything for one chip -- the RTL, its extra testbench if
    Testbencher produced one, and the human-owned golden spec -- into a
    clearly-laid-out folder so a single download gets you the whole project,
    not one file at a time."""
    if not _CHIP_ID_RE.match(chip_id):
        raise HTTPException(400, f"invalid chip id: {chip_id!r}")
    if not _BRANCH_RE.match(branch):
        raise HTTPException(400, f"invalid branch format: {branch!r}")

    # Main RTL is required -- let a missing/unreachable file 404 for real.
    files = {f"{chip_id}/rtl/{chip_id}.v": _fetch_branch_file_text(branch, f"rtl/{chip_id}.v")}

    # Everything else is best-effort: absent just means that stage didn't
    # run (e.g. Testbencher was skipped), not that the export is broken.
    for rel_path in (f"rtl/{chip_id}_tb_extra.v",):
        try:
            files[f"{chip_id}/{rel_path}"] = _fetch_branch_file_text(branch, rel_path)
        except HTTPException:
            pass

    spec_path = _REPO_ROOT / "spec" / "chips" / f"{chip_id}.py"
    if spec_path.exists():
        files[f"{chip_id}/spec/{chip_id}.py"] = spec_path.read_text()

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for arcname, content in files.items():
            zf.writestr(arcname, content)

    return Response(
        buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{chip_id}.zip"'},
    )


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
    """Clear the event history, finished/failed run records, AND the chip
    registry, so the UI starts from a fully blank slate for a fresh retest --
    the dropdown is empty again and Add Chip is the only way to populate it.
    Runs still in flight are left alone -- resetting doesn't cancel them, it
    just stops showing their past events."""
    _history.clear()
    for run_id in [k for k, v in _runs.items() if v.get("status") != "running"]:
        del _runs[run_id]
    _clear_chip_registry()
    return {"ok": True}


@app.get("/api/health")
def health() -> dict:
    return {"ok": True}
