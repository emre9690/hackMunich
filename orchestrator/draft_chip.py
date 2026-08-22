#!/usr/bin/env python3
"""Entrypoint: draft a new chip's golden model from an uploaded datasheet.

Usage:
    python3 -m orchestrator.draft_chip --chip-id my_chip --doc-path /tmp/datasheet.pdf

Spawned as a subprocess by the server the same way orchestrator.run is, so
its stdout events flow through the exact same SSE relay.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from orchestrator.spec_drafter import draft_chip_spec  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip-id", required=True)
    parser.add_argument("--doc-path", required=True, type=pathlib.Path)
    args = parser.parse_args()

    doc_bytes = args.doc_path.read_bytes()
    result = draft_chip_spec(args.chip_id, args.doc_path.name, doc_bytes)

    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
