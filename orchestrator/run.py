#!/usr/bin/env python3
"""Entrypoint: run the pipeline for one chip attempt (or a sequence of them).

Usage:
    python3 -m orchestrator.run --chip 74138
    python3 -m orchestrator.run --chip 74138 --attempts 4 --parallel   # Stage 6

Enforces the global session ceiling (orchestrator/caps.py) across the run.
Sequential is the default and only mode used by the core single-pipeline
demo (Stages 2-5); --parallel is an opt-in flag for the Stage 6 leaderboard
so it can never destabilize the default path.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from orchestrator.caps import MAX_CONCURRENT_SESSIONS, SessionBudget  # noqa: E402
from orchestrator.pipeline import run_pipeline  # noqa: E402
from spec.registry import available_chips  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip", required=True, choices=list(available_chips()))
    parser.add_argument("--attempts", type=int, default=1,
                         help="number of attempt branches to run")
    parser.add_argument("--start-run-id", type=int, default=1)
    parser.add_argument("--parallel", action="store_true",
                         help="Stage 6: run attempts concurrently instead of sequentially")
    args = parser.parse_args()

    budget = SessionBudget()
    run_ids = [args.start_run_id + i for i in range(args.attempts)]

    if args.parallel and len(run_ids) > 1:
        results = []
        with ThreadPoolExecutor(max_workers=min(len(run_ids), MAX_CONCURRENT_SESSIONS)) as pool:
            futures = {pool.submit(run_pipeline, args.chip, run_id, budget): run_id for run_id in run_ids}
            for future in as_completed(futures):
                results.append(future.result())
        results.sort(key=lambda r: r["run_id"])
    else:
        results = [run_pipeline(args.chip, run_id, budget) for run_id in run_ids]

    print(json.dumps({"results": results, "sessions_used": budget.total_created}, indent=2))
    return 0 if all(r.get("coder_passed") for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
