"""Git-as-bus pipeline for one chip attempt.

Devin sessions are isolated cloud VMs that cannot talk to each other -- the
git repository is the shared bus. Every handoff between agents is a commit
on the attempt's dedicated branch. The orchestrator (this file), never a
Devin, decides pass/fail -- always via harness/check_vectors.py.

Full sequence (brief §1): Coder -> harness gate -> Testbencher (adds
coverage, harness re-run) -> Style (cleanup, harness re-run) -> synthesis.
Only Coder has a fail->fix loop-back; Testbencher/Style failing the harness
stops the pipeline at that stage (the brief only specifies loop-back for
Coder).
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import time

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from harness.check_vectors import run_harness  # noqa: E402
from harness.events import emit  # noqa: E402
from harness.run_synth import run_synth  # noqa: E402
from orchestrator import devin_client  # noqa: E402
from orchestrator.caps import (  # noqa: E402
    DEMO_WALLCLOCK_BUDGET_SECONDS,
    MAX_ATTEMPTS_PER_CHIP,
    SESSION_WALLCLOCK_TIMEOUT_SECONDS,
    SessionBudget,
)
from spec.registry import ChipSpec, load_chip  # noqa: E402


GITHUB_REPO = "emre9690/hackMunich"

# Stage 6 runs multiple attempts' git operations concurrently against the
# same local working copy. A bounded timeout turns any lock contention or
# network hang into a loud, visible failure instead of a silent forever-hang
# with no subprocess left to even inspect.
_GIT_TIMEOUT_SECONDS = 60

# A degraded (not down) connection can make a single git network op --
# push/fetch/ls-remote -- run past the timeout, or fail fast with a DNS/
# connection error, even though nothing is actually broken; retry a few
# times before treating it as a real failure.
_GIT_TIMEOUT_RETRY_LIMIT = 3
_GIT_TIMEOUT_RETRY_DELAY_SECONDS = 5

# Substrings of git's stderr that indicate a transient network failure
# (DNS, connection refused/reset/timed out) rather than a real git error
# (bad ref, non-fast-forward, auth) -- only these are worth retrying.
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


def _git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    last_timeout: subprocess.TimeoutExpired | None = None
    result: subprocess.CompletedProcess | None = None
    for attempt in range(_GIT_TIMEOUT_RETRY_LIMIT):
        try:
            result = subprocess.run(["git", *args], cwd=_REPO_ROOT, capture_output=True,
                                     text=True, check=False, timeout=_GIT_TIMEOUT_SECONDS)
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


def branch_name(chip_id: str, run_id: int) -> str:
    return f"attempt/{chip_id}-{run_id:02d}"


def ensure_remote_branch(branch: str) -> None:
    """Create `branch` on origin pointing at current local HEAD, if absent."""
    exists = _git("ls-remote", "--exit-code", "--heads", "origin", branch, check=False)
    if exists.returncode == 0 and exists.stdout.strip():
        return
    push = _git("push", "origin", f"HEAD:refs/heads/{branch}", check=False)
    if push.returncode != 0:
        raise RuntimeError(f"failed to create remote branch {branch}: {push.stderr}")


def fetch_file_from_branch(branch: str, path_in_repo: str) -> str | None:
    """Return the contents of `path_in_repo` as committed on origin/<branch>, or None."""
    _git("fetch", "origin", branch, check=False)
    result = _git("show", f"origin/{branch}:{path_in_repo}", check=False)
    if result.returncode != 0:
        return None
    return result.stdout


def create_and_poll(
    *,
    chip_id: str,
    branch: str,
    agent: str,
    stage: str,
    attempt: int,
    prompt: str,
    title: str,
    budget: SessionBudget,
    structured_output_schema: dict | None = None,
    timeout_override_seconds: float | None = None,
) -> tuple[devin_client.SessionState | None, devin_client.SessionHandle]:
    """Create a Devin session and poll it to completion.

    Returns (None, handle) only if the session stalled (timed out) --
    already emitted a visible 'stalled' event, so the caller should just
    propagate failure. Otherwise returns (state, handle) for the caller to
    interpret: status_enum "blocked" is NOT treated as failure here (see
    below), so the caller must check the actual git branch state itself.
    """
    emit(chip=chip_id, branch=branch, agent=agent, stage=stage, attempt=attempt,
         status="running", detail="creating Devin session")

    budget.acquire()
    try:
        handle = devin_client.create_session(
            prompt, title=title, structured_output_schema=structured_output_schema,
        )
        emit(chip=chip_id, branch=branch, agent=agent, stage=stage, attempt=attempt,
             status="running", session_id=handle.session_id, session_url=handle.url,
             detail="session created, polling for completion")

        # Live activity feed: as Devin narrates its own progress, surface each
        # new message as a 'running' event so the UI can show it happening in
        # near-real-time. Purely informational -- the harness, never this
        # chatter, decides pass/fail.
        seen_message_ids: set[str] = set()

        def on_poll(state: devin_client.SessionState) -> None:
            for msg in state.messages:
                mid = msg.get("event_id")
                if not mid or mid in seen_message_ids or msg.get("type") == "initial_user_message":
                    continue
                seen_message_ids.add(mid)
                text = (msg.get("message") or "").strip()
                if text:
                    emit(chip=chip_id, branch=branch, agent=agent, stage=stage, attempt=attempt,
                         status="running", session_id=handle.session_id, session_url=handle.url,
                         detail=text[:400])

        effective_timeout = timeout_override_seconds or SESSION_WALLCLOCK_TIMEOUT_SECONDS
        state, timed_out = devin_client.poll_until_done(
            handle.session_id, timeout_seconds=effective_timeout,
            on_poll=on_poll,
        )
    finally:
        budget.release()

    if timed_out:
        emit(chip=chip_id, branch=branch, agent=agent, stage=stage, attempt=attempt,
             status="stalled", session_id=handle.session_id, session_url=handle.url,
             detail=f"still running after {effective_timeout:.0f}s wall-clock cap")
        return None, handle

    # status_enum "blocked" is not reliably "needs human input" in practice --
    # sessions also land there after finishing their task and going idle with
    # nothing further to do. The orchestrator never messages a session back
    # either way, so instead of guessing from status_enum, the caller checks
    # the actual git branch state (the real source of truth) next.
    return state, handle


def _verify_branch_rtl(chip_id: str, branch: str, run_id: int, agent: str, attempt: int) -> dict:
    """Fetch rtl/<chip>.v from the branch tip and run the golden-vector harness on it."""
    rtl_text = fetch_file_from_branch(branch, f"rtl/{chip_id}.v")
    if rtl_text is None:
        return emit(chip=chip_id, branch=branch, agent=agent, stage="verify", attempt=attempt,
                     status="error", detail=f"rtl/{chip_id}.v not found on origin/{branch}")

    # Named per (agent, attempt) so each stage's waveform is a distinct,
    # persistent artifact the UI's proof panel can fetch after the fact --
    # deleting it right after the harness runs would 404 the very waveform
    # the proof panel is meant to show.
    local_rtl = _REPO_ROOT / "rtl" / f"_verify_{chip_id}_{run_id:02d}_{agent}_{attempt}.v"
    local_rtl.write_text(rtl_text)
    try:
        return run_harness(chip_id, local_rtl, branch=branch, agent=agent, attempt=attempt)
    finally:
        local_rtl.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Coder-Devin: implement the spec, with a capped fail->fix loop
# ---------------------------------------------------------------------------

def _coder_prompt(spec: ChipSpec, chip_id: str, branch: str, failing_detail: str | None) -> str:
    in_ports = "\n".join(f"  input  {p.name};  // 1 bit" for p in spec.inputs)
    out_ports = "\n".join(f"  output {p.name};  // 1 bit" for p in spec.outputs)
    behavior = (spec.golden_fn.__doc__ or "").strip()
    # Inlined so the session never has to go looking for it -- a prior
    # session lost real time hunting across branches for a golden model
    # that (before a since-fixed bug) hadn't actually been pushed to the
    # path the prompt pointed at. Paste it directly and correct paths are
    # both covered: nothing to go find, and if it does look, it's real.
    golden_model_path = _REPO_ROOT / "spec" / "chips" / f"{chip_id}.py"
    golden_model_source = golden_model_path.read_text() if golden_model_path.exists() else None

    prompt = f"""\
You are implementing a Verilog (RTL) design that must exactly reproduce the
behavior of a discontinued digital logic chip, the {chip_id}.

Repository: GitHub repo `{GITHUB_REPO}` (already connected to your Devin
org via the GitHub App; do not use any other repo). This repo's git
history is large (~100MB across many unrelated experimental branches) even
though the actual source is tiny -- do NOT run a plain `git clone`, it
will pull all of that. Instead clone ONLY this branch, shallowly:
    git clone --depth 1 --branch {branch} --single-branch \\
      https://github.com/{GITHUB_REPO}.git .
Branch `{branch}` already exists on origin -- do NOT create a new branch.

Task:
1. Confirm you're on branch `{branch}` (the shallow clone above already
   checks it out)
2. Write a single synthesizable Verilog module at `rtl/{chip_id}.v`
   implementing module `{spec.module_name}` with EXACTLY these ports (all
   1-bit signals, no other ports):
{in_ports}
{out_ports}
3. Behavior spec (read carefully -- there is a specific active-high vs.
   active-low polarity per signal and a multi-term enable/select condition):
{behavior}
   The full human-authored golden model, pasted below so you don't need to
   fetch anything, is also on this repo at spec/chips/{chip_id}.py -- read
   it there only if you want extra context; you must NEVER modify anything
   under /spec/ (that is the ground truth, human-owned only).
{"--- spec/chips/" + chip_id + ".py ---" + chr(10) + golden_model_source + chr(10) + "--- end ---" if golden_model_source else "(not found locally when this prompt was built -- read it from the repo path above)"}
4. Commit `rtl/{chip_id}.v` on branch `{branch}` with a clear message and
   push it to origin.
5. Set structured_output to JSON containing at least:
   {{"commit_sha": "<sha of your commit>", "file": "rtl/{chip_id}.v"}}

Do not create a pull request. Do not modify any file outside rtl/{chip_id}.v.
An external harness (not you) is the sole source of pass/fail truth -- after
you push, it will compile and exhaustively simulate your RTL against the
golden model. Implement your best-effort correct design and push it; you do
NOT need to convince yourself it is correct via your own testing -- do NOT
install iverilog or any other simulator, and do NOT self-verify. That work
is redundant with the external harness and only spends time/ACUs you don't
need to spend; go straight from writing the file to committing and pushing.
"""
    if failing_detail:
        prompt += f"""

A PREVIOUS ATTEMPT ON THIS BRANCH FAILED VERIFICATION. Pull the latest
`{branch}` first to see that attempt's rtl/{chip_id}.v. The external harness
(ground truth) found these exact mismatches -- fix them:

{failing_detail}

Then commit and push the fix to `{branch}`.
"""
    return prompt


def run_coder_loop(
    chip_id: str, run_id: int, budget: SessionBudget, *, deadline: float | None = None,
) -> tuple[bool, str]:
    """Runs the Coder-Devin stage with a capped fail->fix loop. Returns (passed, branch).

    `deadline` (a time.monotonic() timestamp) bounds the loop for a live
    demo: once passed, no new attempt starts even if MAX_ATTEMPTS_PER_CHIP
    hasn't been reached -- the retry loop stays visible and real, it just
    can't run past the demo's time budget."""
    spec = load_chip(chip_id)
    branch = branch_name(chip_id, run_id)
    ensure_remote_branch(branch)

    failing_detail: str | None = None

    for attempt in range(1, MAX_ATTEMPTS_PER_CHIP + 1):
        if deadline is not None and time.monotonic() >= deadline:
            emit(chip=chip_id, branch=branch, agent="coder", stage="generate", attempt=attempt,
                 status="stalled",
                 detail=f"demo time budget reached before attempt {attempt}; stopping the "
                        f"fail-fix loop here")
            return False, branch

        prompt = _coder_prompt(spec, chip_id, branch, failing_detail)
        per_attempt_timeout = None
        if deadline is not None:
            per_attempt_timeout = max(20.0, deadline - time.monotonic())
        state, handle = create_and_poll(
            chip_id=chip_id, branch=branch, agent="coder", stage="generate", attempt=attempt,
            prompt=prompt, title=f"{chip_id} coder attempt {attempt}", budget=budget,
            timeout_override_seconds=per_attempt_timeout,
        )
        if state is None:
            return False, branch

        rtl_text = fetch_file_from_branch(branch, f"rtl/{chip_id}.v")
        if rtl_text is None:
            emit(chip=chip_id, branch=branch, agent="coder", stage="generate", attempt=attempt,
                 status="error", session_id=handle.session_id, session_url=handle.url,
                 detail=f"session ended (status_enum={state.status_enum}) but rtl/{chip_id}.v "
                        f"was not found on origin/{branch}; structured_output={state.structured_output}")
            return False, branch

        emit(chip=chip_id, branch=branch, agent="coder", stage="generate", attempt=attempt,
             status="pass", session_id=handle.session_id, session_url=handle.url,
             detail=f"rtl/{chip_id}.v pushed; structured_output={state.structured_output}")

        event = _verify_branch_rtl(chip_id, branch, run_id, agent="harness", attempt=attempt)
        if event["status"] == "pass":
            return True, branch

        failing_detail = event["detail"]

    return False, branch


# ---------------------------------------------------------------------------
# Testbencher-Devin: adds edge-case coverage beyond the golden vectors
# ---------------------------------------------------------------------------

def _testbencher_prompt(spec: ChipSpec, chip_id: str, branch: str) -> str:
    return f"""\
You are adding extra test coverage for an existing, already-verified Verilog
module in GitHub repo `{GITHUB_REPO}` (already connected to your Devin org
via the GitHub App; do not use any other repo), on branch `{branch}`:
rtl/{chip_id}.v (module `{spec.module_name}`).

This repo's git history is large (~100MB across many unrelated
experimental branches) even though the actual source is tiny -- do NOT run
a plain `git clone`, it will pull all of that. Instead clone ONLY this
branch, shallowly:
    git clone --depth 1 --branch {branch} --single-branch \\
      https://github.com/{GITHUB_REPO}.git .

This design has ALREADY been exhaustively verified against a human-owned
golden model (spec/chips/{chip_id}.py, {spec.vector_count} vectors, 100%
pass) by an external harness. Your job is NOT to re-verify or replace that
truth source -- it is to add a SEPARATE, additional testbench that documents
and exercises edge cases (e.g. boundary conditions, transitions between
input states) beyond what the golden vectors already cover, as a form of
regression-safety documentation.

Task:
1. Confirm you're on branch `{branch}` (the shallow clone above already
   checks it out; rtl/{chip_id}.v already exists there).
2. Add a new file `rtl/{chip_id}_tb_extra.v` containing a self-contained
   Verilog testbench that instantiates `{spec.module_name}` and exercises
   several specific edge-case scenarios of your choosing, with $display
   output showing pass/fail per case.
3. Do NOT modify rtl/{chip_id}.v itself, and do NOT modify anything under
   /spec/ (human-owned ground truth -- you may read it, never edit it).
4. Commit `rtl/{chip_id}_tb_extra.v` on branch `{branch}` and push it.
5. Set structured_output to JSON: {{"commit_sha": "<sha>", "file": "rtl/{chip_id}_tb_extra.v"}}

Do not create a pull request. Your testbench is supplementary documentation;
the external harness (already run, and re-run after your commit) remains
the sole source of pass/fail truth for this design.
"""


def run_testbencher_stage(
    chip_id: str, branch: str, run_id: int, budget: SessionBudget, *, deadline: float | None = None,
) -> dict:
    """Runs Testbencher-Devin once (no loop-back), then re-runs the harness.

    `deadline` bounds this the same way run_coder_loop's does: if the demo's
    time budget is already spent by the time Coder finishes (its retries can
    eat arbitrarily much of it), Testbencher is skipped rather than run
    unbounded on top of an already-exhausted budget."""
    if deadline is not None and time.monotonic() >= deadline:
        return emit(chip=chip_id, branch=branch, agent="testbencher", stage="coverage", attempt=1,
                     status="skipped",
                     detail="demo time budget reached before Testbencher could start")

    spec = load_chip(chip_id)
    prompt = _testbencher_prompt(spec, chip_id, branch)
    per_attempt_timeout = max(20.0, deadline - time.monotonic()) if deadline is not None else None
    state, handle = create_and_poll(
        chip_id=chip_id, branch=branch, agent="testbencher", stage="coverage", attempt=1,
        prompt=prompt, title=f"{chip_id} testbencher", budget=budget,
        timeout_override_seconds=per_attempt_timeout,
    )
    if state is None:
        return {"status": "stalled"}

    tb_text = fetch_file_from_branch(branch, f"rtl/{chip_id}_tb_extra.v")
    if tb_text is None:
        return emit(chip=chip_id, branch=branch, agent="testbencher", stage="coverage", attempt=1,
                     status="error", session_id=handle.session_id, session_url=handle.url,
                     detail=f"session ended (status_enum={state.status_enum}) but "
                            f"rtl/{chip_id}_tb_extra.v was not found on origin/{branch}; "
                            f"structured_output={state.structured_output}")

    emit(chip=chip_id, branch=branch, agent="testbencher", stage="coverage", attempt=1,
         status="pass", session_id=handle.session_id, session_url=handle.url,
         detail=f"rtl/{chip_id}_tb_extra.v pushed; structured_output={state.structured_output}")

    return _verify_branch_rtl(chip_id, branch, run_id, agent="testbencher", attempt=1)


# ---------------------------------------------------------------------------
# Style-Devin: cleanup formatting/naming/comments without changing behavior
# ---------------------------------------------------------------------------

def _style_prompt(spec: ChipSpec, chip_id: str, branch: str) -> str:
    return f"""\
You are cleaning up an existing, already-verified Verilog module in GitHub
repo `{GITHUB_REPO}` (already connected to your Devin org via the GitHub
App; do not use any other repo), on branch `{branch}`: rtl/{chip_id}.v
(module `{spec.module_name}`).

This repo's git history is large (~100MB across many unrelated
experimental branches) even though the actual source is tiny -- do NOT run
a plain `git clone`, it will pull all of that. Instead clone ONLY this
branch, shallowly:
    git clone --depth 1 --branch {branch} --single-branch \\
      https://github.com/{GITHUB_REPO}.git .

This design has ALREADY been exhaustively verified against a human-owned
golden model by an external harness ({spec.vector_count} vectors, 100%
pass). Your ONLY job is cosmetic cleanup: consistent indentation, clearer
signal/variable naming (module name and port names must NOT change --
external tooling depends on them exactly as-is), and comments explaining
non-obvious logic. You must NOT change the design's behavior in any way --
same ports, same functionality, same polarity, same timing.

Task:
1. Confirm you're on branch `{branch}` (the shallow clone above already
   checks it out; rtl/{chip_id}.v already exists there).
2. Clean up rtl/{chip_id}.v: formatting, naming of INTERNAL signals only
   (never the module name or port names), and comments. Do not touch
   rtl/{chip_id}_tb_extra.v or anything under /spec/.
3. Commit the cleaned-up rtl/{chip_id}.v on branch `{branch}` and push it.
4. Set structured_output to JSON: {{"commit_sha": "<sha>", "file": "rtl/{chip_id}.v"}}

Do not create a pull request. The external harness will re-run after your
commit to confirm behavior is unchanged -- if it fails, this cleanup will be
rejected, so be conservative and do not touch the logic itself.
"""


def run_style_stage(chip_id: str, branch: str, run_id: int, budget: SessionBudget) -> dict:
    """Runs Style-Devin once (no loop-back), then re-runs the harness to confirm no regressions."""
    spec = load_chip(chip_id)
    prompt = _style_prompt(spec, chip_id, branch)
    state, handle = create_and_poll(
        chip_id=chip_id, branch=branch, agent="style", stage="cleanup", attempt=1,
        prompt=prompt, title=f"{chip_id} style cleanup", budget=budget,
    )
    if state is None:
        return {"status": "stalled"}

    rtl_text = fetch_file_from_branch(branch, f"rtl/{chip_id}.v")
    if rtl_text is None:
        return emit(chip=chip_id, branch=branch, agent="style", stage="cleanup", attempt=1,
                     status="error", session_id=handle.session_id, session_url=handle.url,
                     detail=f"session ended (status_enum={state.status_enum}) but rtl/{chip_id}.v "
                            f"disappeared from origin/{branch}; structured_output={state.structured_output}")

    emit(chip=chip_id, branch=branch, agent="style", stage="cleanup", attempt=1,
         status="pass", session_id=handle.session_id, session_url=handle.url,
         detail=f"rtl/{chip_id}.v cleaned up and pushed; structured_output={state.structured_output}")

    return _verify_branch_rtl(chip_id, branch, run_id, agent="style", attempt=1)


# ---------------------------------------------------------------------------
# Full pipeline: Coder -> Testbencher -> Style -> Synthesis
# ---------------------------------------------------------------------------

def run_pipeline(
    chip_id: str, run_id: int, budget: SessionBudget, *,
    synth_target: str = "ice40", fast_demo: bool = False,
) -> dict:
    """Runs the full pipeline for one attempt. Never raises: any unexpected
    failure (e.g. a git operation timing out under Stage 6's concurrent
    attempts) is caught and turned into a visible error event + failed
    result, so one attempt's crash can never silently kill the whole batch
    or leave a hung UI state (brief §4: every failure is visible).

    fast_demo=True skips Testbencher/Style (the two sequential Devin calls
    that make a full pipeline take minutes) and goes straight from a
    verified Coder RTL to synthesis. This ONLY reduces how many agents run
    -- exhaustive vector verification against every input is never reduced,
    at any setting. Vector count is not what makes a run slow (65536
    vectors verify in ~1s); sequential Devin sessions are.
    """
    branch = branch_name(chip_id, run_id)
    try:
        return _run_pipeline_inner(chip_id, run_id, budget, synth_target=synth_target,
                                    fast_demo=fast_demo)
    except Exception as e:  # noqa: BLE001 -- deliberately broad, see docstring
        emit(chip=chip_id, branch=branch, agent="harness", stage="verify", attempt=0,
             status="error", detail=f"pipeline crashed unexpectedly: {e!r}")
        return {"chip": chip_id, "run_id": run_id, "branch": branch, "coder_passed": False,
                "error": repr(e)}


def _run_pipeline_inner(
    chip_id: str, run_id: int, budget: SessionBudget, *, synth_target: str, fast_demo: bool,
) -> dict:
    result: dict = {"chip": chip_id, "run_id": run_id, "fast_demo": fast_demo}

    deadline = time.monotonic() + DEMO_WALLCLOCK_BUDGET_SECONDS
    coder_passed, branch = run_coder_loop(chip_id, run_id, budget, deadline=deadline)
    result["branch"] = branch
    result["coder_passed"] = coder_passed
    if not coder_passed:
        return result

    # Testbencher always runs now (deadline-bounded, so a Coder retry loop
    # that already ate the whole demo budget makes it skip rather than run
    # unbounded). Style stays skipped regardless of fast_demo -- it's purely
    # cosmetic cleanup with no verification value, the first thing worth
    # cutting to keep the live-demo path fast.
    tb_event = run_testbencher_stage(chip_id, branch, run_id, budget, deadline=deadline)
    result["testbencher"] = tb_event
    if tb_event.get("status") not in ("pass", "skipped"):
        return result

    if not fast_demo:
        style_event = run_style_stage(chip_id, branch, run_id, budget)
        result["style"] = style_event
        if style_event.get("status") != "pass":
            return result
    else:
        emit(chip=chip_id, branch=branch, agent="style", stage="cleanup", attempt=1,
             status="skipped", detail="skipped for demo speed")

    rtl_text = fetch_file_from_branch(branch, f"rtl/{chip_id}.v")
    local_rtl = _REPO_ROOT / "rtl" / f"_synth_{chip_id}_{run_id:02d}.v"
    local_rtl.write_text(rtl_text)
    try:
        synth_event = run_synth(chip_id, local_rtl, branch=branch, agent="synth", attempt=1,
                                 target=synth_target)
    finally:
        local_rtl.with_suffix(".vcd").unlink(missing_ok=True)
        local_rtl.unlink(missing_ok=True)

    result["synth"] = synth_event
    return result
