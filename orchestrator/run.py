#!/usr/bin/env python3
"""Entrypoint: run the pipeline for one chip attempt (or a sequence of them).

Usage:
    python3 -m orchestrator.run --chip 74138

Enforces the global session ceiling (orchestrator/caps.py) across the run.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from orchestrator.caps import SessionBudget  # noqa: E402
from orchestrator.pipeline import run_pipeline  # noqa: E402
from spec.registry import available_chips  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip", required=True, choices=list(available_chips()))
    parser.add_argument("--attempts", type=int, default=1,
                         help="number of attempt branches to run sequentially")
    parser.add_argument("--start-run-id", type=int, default=1)
    args = parser.parse_args()

    budget = SessionBudget()
    results = []
    for i in range(args.attempts):
        run_id = args.start_run_id + i
        result = run_pipeline(args.chip, run_id, budget)
        results.append(result)

    print(json.dumps({"results": results, "sessions_used": budget.total_created}, indent=2))
    return 0 if all(r.get("coder_passed") for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
