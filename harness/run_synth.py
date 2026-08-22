#!/usr/bin/env python3
"""Run Yosys synthesis against a real FPGA architecture and report resource usage.

This is the "FPGA-ready hardware" proof: the design is mapped onto actual
device primitives (e.g. SB_LUT4 for iCE40), not just an abstract gate count.
Target is configurable (default iCE40 via synth_ice40) but never invokes
place-and-route or touches physical hardware -- see scope walls in the brief.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from harness.events import emit  # noqa: E402
from spec.registry import load_chip  # noqa: E402

# One setting controls the FPGA target family; keep synth_ice40 as default.
SYNTH_COMMANDS = {
    "ice40": "synth_ice40",
    "ecp5": "synth_ecp5",
}

_CELLS_HEADER_RE = re.compile(r"^\s+(\d+)\s+cells\s*$")
_CELL_LINE_RE = re.compile(r"^\s+(\d+)\s+(\S+)\s*$")


def run_synth(
    chip_id: str,
    rtl_path: pathlib.Path,
    *,
    branch: str,
    target: str = "ice40",
    agent: str = "synth",
    attempt: int = 1,
    report_dir: pathlib.Path | None = None,
) -> dict:
    """Runs Yosys synthesis and returns the emitted event dict."""
    spec = load_chip(chip_id)

    if target not in SYNTH_COMMANDS:
        return emit(chip=chip_id, branch=branch, agent=agent, stage="synthesize", attempt=attempt,
                     status="error", detail=f"unknown synth target {target!r}, known: {list(SYNTH_COMMANDS)}")

    if not rtl_path.exists():
        return emit(chip=chip_id, branch=branch, agent=agent, stage="synthesize", attempt=attempt,
                     status="error", detail=f"RTL file not found: {rtl_path}")

    synth_cmd = SYNTH_COMMANDS[target]
    yosys_script = (
        f"read_verilog {rtl_path}; "
        f"{synth_cmd} -top {spec.module_name}; "
        f"stat"
    )
    proc = subprocess.run(["yosys", "-p", yosys_script], capture_output=True, text=True)

    if proc.returncode != 0:
        return emit(chip=chip_id, branch=branch, agent=agent, stage="synthesize", attempt=attempt,
                     status="error", detail=f"yosys failed: {proc.stderr.strip()[:800]}")

    report_dir = report_dir or rtl_path.parent
    report_path = report_dir / f"{rtl_path.stem}_synth_{target}.txt"
    report_path.write_text(proc.stdout)

    cell_counts = _parse_cell_counts(proc.stdout)
    lut_count = sum(v for k, v in cell_counts.items() if "LUT" in k.upper())
    summary = ", ".join(f"{k}={v}" for k, v in sorted(cell_counts.items())) or "no cells reported"

    return emit(chip=chip_id, branch=branch, agent=agent, stage="synthesize", attempt=attempt,
                 status="pass", passed=lut_count, total=None,
                 artifact_path=str(report_path),
                 detail=f"target={target} module={spec.module_name} LUT4-equiv={lut_count} :: {summary}")


def _parse_cell_counts(stat_output: str) -> dict[str, int]:
    """Parse the per-cell-type table from Yosys's stat output, e.g.:

            9 cells
            9   SB_LUT4

    synth_ice40 runs `stat` internally as well as our explicit trailing
    `stat` call, so the report can contain multiple such blocks -- the last
    one wins (it reflects the final, fully-mapped design).
    """
    lines = stat_output.splitlines()
    counts: dict[str, int] = {}
    i = 0
    while i < len(lines):
        if _CELLS_HEADER_RE.match(lines[i]):
            block: dict[str, int] = {}
            j = i + 1
            while j < len(lines):
                match = _CELL_LINE_RE.match(lines[j])
                if not match:
                    break
                block[match.group(2)] = int(match.group(1))
                j += 1
            counts = block
            i = j
        else:
            i += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip", required=True)
    parser.add_argument("--rtl", required=True, type=pathlib.Path)
    parser.add_argument("--branch", default="local")
    parser.add_argument("--target", default="ice40", choices=list(SYNTH_COMMANDS))
    parser.add_argument("--agent", default="synth")
    parser.add_argument("--attempt", type=int, default=1)
    args = parser.parse_args()

    event = run_synth(args.chip, args.rtl, branch=args.branch, target=args.target,
                       agent=args.agent, attempt=args.attempt)
    return 0 if event["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
