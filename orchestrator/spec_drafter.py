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

Local, free steps (no API call): PDF/text extraction via pypdf, an AST
safety check, and structural validation. Only the actual understanding of
the datasheet -- turning prose/tables into working boolean logic -- goes
through a Devin session, reusing the exact same create-session/poll/git
infrastructure as the RTL pipeline (orchestrator/pipeline.py).
"""
from __future__ import annotations

import ast
import importlib.util
import io
import pathlib
import sys
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

_REFERENCE_SPEC = (_REPO_ROOT / "spec" / "chips" / "74138.py").read_text()

_ALLOWED_IMPORT_MODULE = "spec.registry"
_BLOCKED_NAMES = {
    "open", "exec", "eval", "compile", "__import__", "os", "sys", "subprocess",
    "socket", "shutil", "requests", "urllib", "input", "globals", "locals",
    "vars", "getattr", "setattr", "delattr", "importlib", "ctypes", "pickle",
}


class DraftValidationError(ValueError):
    pass


def extract_text(filename: str, data: bytes) -> str:
    """Local, free text extraction -- no API call. PDFs via pypdf, anything
    else treated as plain text."""
    if filename.lower().endswith(".pdf"):
        from pypdf import PdfReader
        reader = PdfReader(io.BytesIO(data))
        return "\n\n".join(page.extract_text() or "" for page in reader.pages)
    return data.decode(errors="replace")


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


def _drafter_prompt(chip_id: str, branch: str, doc_text: str) -> str:
    truncated = doc_text[:15000]
    return f"""\
You are drafting a HUMAN-REVIEWED CANDIDATE golden model for a digital
logic chip, from an uploaded datasheet. This is NOT the RTL-writing task
-- you are writing a Python description of the chip's expected behavior,
which a human will review before it is ever trusted as ground truth.

Repository: GitHub repo `{GITHUB_REPO}` (already connected to your Devin
org via the GitHub App -- clone it if it is not already in your session;
do not use any other repo). Check out branch `{branch}` -- it already
exists on origin, do NOT create a new branch.

Task:
1. `git checkout {branch}`
2. Read the datasheet text below (extracted from an uploaded document).
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
5. Commit `drafts/{chip_id}.py` on branch `{branch}` and push it.
6. Set structured_output to JSON: {{"commit_sha": "<sha>", "file": "drafts/{chip_id}.py"}}

Do not create a pull request. Do not touch anything under /spec/ -- that
directory is human-owned ground truth, and this draft is explicitly NOT
trusted until a human reviews and approves it through a separate process.

--- DATASHEET TEXT (extracted from the uploaded document) ---
{truncated}
--- END DATASHEET TEXT ---
"""


def draft_chip_spec(chip_id: str, doc_filename: str, doc_bytes: bytes) -> dict:
    """Runs one Devin session to draft drafts/<chip_id>.py from an uploaded
    datasheet, validates it, and saves it locally for human review.

    Never raises -- returns a result dict, mirroring pipeline.py's
    run_pipeline error-visibility contract (every failure becomes a
    visible event, never a silent crash)."""
    branch = f"drafts/{chip_id}"
    budget = SessionBudget()

    try:
        doc_text = extract_text(doc_filename, doc_bytes)
        if not doc_text.strip():
            raise DraftValidationError("could not extract any text from the uploaded document")

        ensure_remote_branch(branch)
        prompt = _drafter_prompt(chip_id, branch, doc_text)

        state, handle = create_and_poll(
            chip_id=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
            prompt=prompt, title=f"draft spec for {chip_id}", budget=budget,
        )
        if state is None:
            return {"chip_id": chip_id, "ok": False, "error": "session stalled"}

        source = fetch_file_from_branch(branch, f"drafts/{chip_id}.py")
        if source is None:
            emit(chip=chip_id, branch=branch, agent="drafter", stage="draft", attempt=1,
                 status="error", session_id=handle.session_id, session_url=handle.url,
                 detail=f"session ended but drafts/{chip_id}.py was not found on origin/{branch}")
            return {"chip_id": chip_id, "ok": False, "error": "draft file not found"}

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
