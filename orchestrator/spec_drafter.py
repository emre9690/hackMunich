"""Human-reviewed drafting of a new chip's golden model from an uploaded
datasheet, via a one-off Devin session that ONLY ever writes to /drafts/,
never /spec/.

Safety property this preserves -- the same rule as the RTL pipeline: no
agent may ever author both a golden model and the RTL later checked
against it. A drafting session here is never the same session (or repo
location) as a Coder-Devin session, and its output is never trusted until
a human explicitly approves it via the server's /api/drafts approve
endpoint, which is what actually moves the file into /spec/chips/ -- a
distinct, human-triggered action, not something this module ever does
itself.

The uploaded datasheet is committed as-is to the drafts branch (via a
temporary git worktree, so the shared working tree other concurrent
pipeline runs depend on staying on `main` is never touched) and Devin
reads it directly in its own session regardless -- it is still the one
that ultimately confirms the content, and correctly refuses to invent
chip behavior from memory when a document turns out to be unreadable,
rather than silently hallucinating what becomes human-reviewed ground
truth.

A first version tried local pypdf extraction and abandoned it outright,
since old/scanned datasheets are very often image-only PDFs pypdf can't
read at all. That's still true, but it doesn't mean local extraction is
worthless for the (increasingly common) case of a real text-layer PDF --
_try_local_pdf_text below is a cheap, free, best-effort attempt: when it
finds genuine embedded text, that text is handed to Devin as a head
start in the prompt so it isn't paying OCR/vision time re-deriving prose
it can already read for free; when the PDF is image-only (as detected by
the same near-empty-extraction heuristic that made prior sessions
correctly refuse to hallucinate), this returns None and behavior is
identical to before -- Devin reads and OCRs the file itself, unaided.
Tables are explicitly called out as unreliable even when extraction
"succeeds" -- plain-text extraction doesn't preserve column alignment,
so a program/function table can come out scrambled even from a real
text-layer PDF. Devin is told to treat any table-shaped content in the
extract as a hint only and verify it against the actual rendered page.

AST safety check and structural validation, run locally before a draft
is ever touched, stay local and free -- no API call for those.
"""
from __future__ import annotations

import ast
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import time
from itertools import islice

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from harness.events import emit  # noqa: E402
from orchestrator.caps import SessionBudget  # noqa: E402
from orchestrator.pipeline import (  # noqa: E402
    GITHUB_REPO,
    create_and_poll,
    ensure_remote_branch,
    fetch_file_from_branch,
)

DRAFTS_DIR = _REPO_ROOT / "drafts"

# Deliberately high. Many scanned datasheets still carry a thin text layer
# on every page for a repeated header/footer (title, date, distributor
# address) even though the actual page content is a pure image -- observed
# around 200-300 chars for that boilerplate alone. A low threshold would
# call every one of those pages "usable" and never trigger OCR on the page
# that actually matters. Real extracted body content ran several thousand
# chars in testing; this sits well above the boilerplate floor and well
# below that, so it only fires on genuine content, not page furniture.
_MIN_CHARS_PER_PAGE_FOR_REAL_TEXT = 500


def _try_local_pdf_text(doc_filename: str, doc_bytes: bytes) -> str | None:
    """Best-effort, local, free text extraction via pypdf -- no OCR, no LLM,
    no network call. Returns None (never raises) if the file isn't a PDF, or
    is a scanned/image-only PDF pypdf can't get real text out of; in either
    case the caller falls back to having Devin read the file itself, exactly
    as before this existed."""
    if not doc_filename.lower().endswith(".pdf"):
        return None
    try:
        import io

        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(doc_bytes))
        pages = [(p.extract_text() or "").strip() for p in reader.pages]
    except Exception:
        return None

    if not pages:
        return None

    # Judged PER PAGE, not by a whole-document average: a datasheet can mix
    # real text-layer back matter (ordering info, package/legal boilerplate)
    # with scanned-image front matter (the pinout and function table that
    # actually define behavior). An average would let text-heavy pages that
    # don't matter mask image-only pages that do -- classifying each page on
    # its own means a page that didn't extract is always explicitly flagged
    # as still needing OCR, never silently assumed covered.
    usable = [len(t) >= _MIN_CHARS_PER_PAGE_FOR_REAL_TEXT for t in pages]
    if not any(usable):
        return None

    parts = []
    for i, (text, is_usable) in enumerate(zip(pages, usable)):
        if is_usable:
            parts.append(f"--- page {i + 1} (extracted locally) ---\n{text}")
        else:
            parts.append(
                f"--- page {i + 1}: NO usable text extracted locally (likely "
                f"scanned/image-only -- you must read/OCR this page yourself) ---"
            )
    return "\n\n".join(parts)

_REFERENCE_SPEC = (_REPO_ROOT / "spec" / "chips" / "74138.py").read_text()

_ALLOWED_IMPORT_MODULE = "spec.registry"
_BLOCKED_NAMES = {
    "open", "exec", "eval", "compile", "__import__", "os", "sys", "subprocess",
    "socket", "shutil", "requests", "urllib", "input", "globals", "locals",
    "vars", "getattr", "setattr", "delattr", "importlib", "ctypes", "pickle",
}

_GIT_TIMEOUT_SECONDS = 60

# A degraded (not down) connection can make a single git network op run past
# the timeout, or fail fast with a DNS/connection error, even though nothing
# is actually broken; retry before treating it as a real failure. Same
# reasoning as orchestrator/pipeline.py and devin_client.py's transient
# budget -- a short retry count left too little margin against outages of
# the length actually observed here (60s+).
_GIT_TIMEOUT_RETRY_LIMIT = 6
_GIT_TIMEOUT_RETRY_DELAY_SECONDS = 8

_TRANSIENT_GIT_ERROR_MARKERS = (
    "could not resolve host",
    "could not connect to server",
    "connection timed out",
    "connection refused",
    "connection reset by peer",
    "unable to access",
    "the remote end hung up unexpectedly",
    "early eof",
    "rpc failed",
)


def _is_transient_git_error(stderr: str) -> bool:
    lowered = stderr.lower()
    return any(marker in lowered for marker in _TRANSIENT_GIT_ERROR_MARKERS)

# Forces Devin to always leave a definitive, self-contained final answer
# (never a follow-up question) -- see the CRITICAL section in the prompt.
_STRUCTURED_OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string", "enum": ["drafted", "blocked"]},
        "file": {"type": "string"},
        "commit_sha": {"type": "string"},
        "blocked_reason": {"type": "string"},
    },
    "required": ["status"],
}


class DraftValidationError(ValueError):
    pass


def _run_git(*args: str, cwd: pathlib.Path, check: bool = True) -> subprocess.CompletedProcess:
    last_timeout: subprocess.TimeoutExpired | None = None
    result: subprocess.CompletedProcess | None = None
    for attempt in range(_GIT_TIMEOUT_RETRY_LIMIT):
        try:
            result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                                     check=False, timeout=_GIT_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired as e:
            last_timeout = e
            result = None
            if attempt < _GIT_TIMEOUT_RETRY_LIMIT - 1:
                time.sleep(_GIT_TIMEOUT_RETRY_DELAY_SECONDS)
            continue
        if result.returncode != 0 and _is_transient_git_error(result.stderr) \
                and attempt < _GIT_TIMEOUT_RETRY_LIMIT - 1:
            time.sleep(_GIT_TIMEOUT_RETRY_DELAY_SECONDS)
            continue
        break
    if result is None:
        assert last_timeout is not None
        raise last_timeout
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args,
                                             output=result.stdout, stderr=result.stderr)
    return result


def _commit_datasheet_to_branch(branch: str, chip_id: str, doc_filename: str, doc_bytes: bytes) -> str:
    """Commit the raw uploaded file to `branch` via a temporary git worktree
    -- never checks out `branch` in the shared _REPO_ROOT working tree.
    Returns the committed path, relative to the repo root."""
    suffix = pathlib.Path(doc_filename).suffix or ".txt"
    rel_path = f"drafts/{chip_id}_datasheet{suffix}"

    worktree_dir = pathlib.Path(tempfile.mkdtemp(prefix=f"draft_worktree_{chip_id}_"))
    try:
        _run_git("worktree", "add", str(worktree_dir), branch, cwd=_REPO_ROOT)
        target = worktree_dir / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(doc_bytes)
        # -f: /drafts/ is gitignored (so local unreviewed drafts never land
        # on main by accident) -- but that rule is checked out on this
        # branch too, and here we're deliberately committing to a drafts/*
        # branch, so it needs to be forced past the ignore.
        _run_git("add", "-f", rel_path, cwd=worktree_dir)
        _run_git("commit", "-m", f"Add uploaded datasheet for {chip_id}", cwd=worktree_dir)
        _run_git("push", "origin", branch, cwd=worktree_dir)
    finally:
        _run_git("worktree", "remove", "--force", str(worktree_dir), cwd=_REPO_ROOT, check=False)

    return rel_path


def validate_draft_source(source: str) -> None:
    """AST-level safety net before a draft is ever loaded/exec'd, even just
    for a review preview. This is a plain allowlist/blocklist, reasonable
    for a locally-run tool -- not a hardened sandbox against a deliberate
    adversary."""
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        raise DraftValidationError(f"draft has invalid Python syntax: {e}") from e

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
            raise DraftValidationError(f"draft imports {names}; only "
                                        f"'from {_ALLOWED_IMPORT_MODULE} import ...' is allowed")
        if isinstance(node, ast.ImportFrom) and node.module != _ALLOWED_IMPORT_MODULE:
            raise DraftValidationError(f"draft imports from {node.module!r}; only "
                                        f"{_ALLOWED_IMPORT_MODULE!r} is allowed")
        if isinstance(node, ast.Name) and node.id in _BLOCKED_NAMES:
            raise DraftValidationError(f"draft references disallowed name {node.id!r}")
        if isinstance(node, ast.Attribute) and node.attr in _BLOCKED_NAMES:
            raise DraftValidationError(f"draft references disallowed attribute {node.attr!r}")


def load_draft_module(path: pathlib.Path):
    """Load a validated draft by file path (validate_draft_source must be
    called first -- this executes the file)."""
    spec = importlib.util.spec_from_file_location(f"_draft_{path.stem}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_draft_structure(module) -> None:
    for attr in ("SPEC", "INPUTS", "OUTPUTS", "golden_fn", "MODULE_NAME"):
        if not hasattr(module, attr):
            raise DraftValidationError(f"draft is missing required attribute {attr!r}")

    chip_spec = module.SPEC
    expected_names = {p.name for p in chip_spec.outputs}
    for in_map, out_map in islice(chip_spec.iter_vectors(), 8):
        if set(out_map.keys()) != expected_names:
            raise DraftValidationError(
                f"golden_fn's output keys {set(out_map.keys())} don't match "
                f"OUTPUTS {expected_names} for input {in_map}"
            )


def preview_vectors(module, cap: int = 128) -> dict:
    chip_spec = module.SPEC
    rows = [
        {**in_map, **out_map}
        for in_map, out_map in islice(chip_spec.iter_vectors(), cap)
    ]
    return {
        "columns": [p.name for p in chip_spec.inputs] + [p.name for p in chip_spec.outputs],
        "rows": rows,
        "total_vectors": chip_spec.vector_count,
        "truncated": chip_spec.vector_count > cap,
    }


def _drafter_prompt(
    chip_id: str, branch: str, datasheet_path: str, local_text: str | None = None,
) -> str:
    local_text_section = ""
    if local_text:
        local_text_section = f"""

A LOCAL, NON-OCR TEXT EXTRACTION of the PDF is included below as a head
start, so you don't have to spend time re-deriving prose you can already
read for free. It came from pulling the PDF's embedded text layer, not
from OCR or vision, so two things can still be wrong with it: (1) any
page that was actually a scanned image extracted to little/nothing (not
included below -- open the real file and OCR/read that page yourself,
same as always), and (2) plain-text extraction does NOT preserve column
alignment, so any table-shaped content below (function tables, program
tables, pinouts) can come out scrambled even on a real text page --
treat tabular content here as a hint only and VERIFY the exact table
against the actually-rendered document before trusting it for behavior.
Prose (feature lists, descriptions, notes) is generally reliable as-is.

--- extracted text start ---
{local_text}
--- extracted text end ---
"""

    return f"""\
You are drafting a HUMAN-REVIEWED CANDIDATE golden model for a digital
logic chip, from an uploaded datasheet. This is NOT the RTL-writing task
-- you are writing a Python description of the chip's expected behavior,
which a human will review before it is ever trusted as ground truth.

Repository: GitHub repo `{GITHUB_REPO}` (already connected to your Devin
org via the GitHub App; do not use any other repo). This repo's git
history is large (~100MB across many unrelated experimental branches) even
though the actual source is tiny -- do NOT run a plain `git clone`, it
will pull all of that. Instead clone ONLY this branch, shallowly:
    git clone --depth 1 --branch {branch} --single-branch \\
      https://github.com/{GITHUB_REPO}.git .
Branch `{branch}` already exists on origin -- do NOT create a new branch.
{local_text_section}
Task:
1. Confirm you're on branch `{branch}` (the shallow clone above already
   checks it out)
2. Read the datasheet at `{datasheet_path}` in this repo (already
   committed there for you) -- unless the extraction above already gives
   you everything you need (including a verified table), in which case
   you may skip re-reading pages it already covered accurately. If it's a
   PDF and some pages don't yield readable text directly -- a common
   issue with scanned/image-only pages in old datasheets -- you have full
   shell access in your environment: use whatever tool you need (OCR,
   your own document/image understanding, installing packages, etc.) to
   actually read the real content before proceeding. Do NOT invent or
   guess the chip's behavior from memory if you cannot read the datasheet
   -- stop and report that instead, exactly like a prior session
   correctly did when given a document that turned out to have no
   readable content.
3. Write a single file `drafts/{chip_id}.py` matching EXACTLY this
   interface (a real example from this repo, spec/chips/74138.py, for a
   DIFFERENT chip -- match its structure exactly, just with the new
   chip's ports and behavior):

--- EXAMPLE (spec/chips/74138.py) ---
{_REFERENCE_SPEC}
--- END EXAMPLE ---

4. Your file MUST:
   - contain exactly one import: `from spec.registry import ChipSpec, Port`
   - define MODULE_NAME (str), INPUTS (list of Port(name)), OUTPUTS (list
     of Port(name)), golden_fn(inputs: dict[str,int]) -> dict[str,int],
     and SPEC = ChipSpec(chip_id=..., module_name=..., inputs=...,
     outputs=..., golden_fn=...)
   - every port is a plain 1-bit signal
   - golden_fn is pure boolean/arithmetic logic only -- no file I/O, no
     network calls, no imports beyond spec.registry
   - a docstring citing which part of the datasheet each behavior rule
     comes from, so a human reviewer can check it against the source
5. Commit `drafts/{chip_id}.py` on branch `{branch}` and push it. NOTE:
   `/drafts/` is in this repo's .gitignore (it protects `main` from
   accidental unreviewed commits) -- that rule is checked out on this
   branch too, so use `git add -f drafts/{chip_id}.py` or your `git add`
   will silently do nothing. Leave the datasheet file itself as-is; do
   not delete or modify it.

Do not create a pull request. Do not touch anything under /spec/ -- that
directory is human-owned ground truth, and this draft is explicitly NOT
trusted until a human reviews and approves it through a separate process.

CRITICAL -- there is NO ONE available to answer questions in this
session, ever, and it will NOT be resumed:
- Never ask a question and wait. Never present options ("A) ... B) ...")
  and pause for a reply. If you cannot produce a correct golden model
  (blank/unprogrammed program table, an electrical state like Hi-Z that
  a plain 0/1 interface can't represent, ambiguous pinout, etc.), that is
  your FINAL conclusion, not an open question -- decide "blocked" and
  end the session yourself. Do not leave it open or waiting.
- You MUST set structured_output before ending, in exactly one of these
  two shapes:
  - success: {{"status": "drafted", "file": "drafts/{chip_id}.py", "commit_sha": "<sha>"}}
  - can't proceed: {{"status": "blocked", "blocked_reason": "<a complete,
    specific, final explanation of exactly what's missing or unsupported
    -- this is the ONLY thing a human will see, so make it stand alone>"}}
"""


def _extract_blocked_reason(state) -> str:
    """No file was pushed -- figure out WHY, so a human never has to open
    Devin's own dashboard to find out. Prefers the structured_output the
    prompt requires; falls back to the last real message if Devin didn't
    comply, so this is never just a bare 'not found'."""
    structured = state.structured_output or {}
    if structured.get("blocked_reason"):
        return structured["blocked_reason"]

    for msg in reversed(state.messages):
        if msg.get("type") == "initial_user_message":
            continue
        text = (msg.get("message") or "").strip()
        if text:
            return text[:800]

    return f"session ended with status_enum={state.status_enum!r} but produced no draft " \
           f"file and no explanation"


def draft_chip_spec(chip_id: str, doc_filename: str, doc_bytes: bytes) -> dict:
    """Runs one Devin session to draft drafts/<chip_id>.py from an uploaded
    datasheet, validates it, and saves it locally for human review.

    Never raises -- returns a result dict, mirroring pipeline.py's
    run_pipeline error-visibility contract (every failure becomes a
    visible event, never a silent crash)."""
    branch = f"drafts/{chip_id}"
    budget = SessionBudget()

    try:
        ensure_remote_branch(branch)
        datasheet_path = _commit_datasheet_to_branch(branch, chip_id, doc_filename, doc_bytes)
        local_text = _try_local_pdf_text(doc_filename, doc_bytes)
        prompt = _drafter_prompt(chip_id, branch, datasheet_path, local_text)

        state, handle = create_and_poll(
            chip_id=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
            prompt=prompt, title=f"draft spec for {chip_id}", budget=budget,
            structured_output_schema=_STRUCTURED_OUTPUT_SCHEMA,
        )
        if state is None:
            return {"chip_id": chip_id, "ok": False, "error": "session stalled"}

        source = fetch_file_from_branch(branch, f"drafts/{chip_id}.py")
        if source is None:
            reason = _extract_blocked_reason(state)
            emit(chip=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
                 status="error", session_id=handle.session_id, session_url=handle.url,
                 detail=reason)
            return {"chip_id": chip_id, "ok": False, "error": reason}

        validate_draft_source(source)
        DRAFTS_DIR.mkdir(exist_ok=True)
        local_path = DRAFTS_DIR / f"{chip_id}.py"
        local_path.write_text(source)

        module = load_draft_module(local_path)
        validate_draft_structure(module)

        emit(chip=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
             status="pass", session_id=handle.session_id, session_url=handle.url,
             detail=f"drafts/{chip_id}.py drafted and validated; awaiting human review")
        return {"chip_id": chip_id, "ok": True, "branch": branch}

    except Exception as e:  # noqa: BLE001 -- see run_pipeline's identical contract
        emit(chip=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
             status="error", detail=f"drafting failed: {e!r}")
        return {"chip_id": chip_id, "ok": False, "error": repr(e)}
