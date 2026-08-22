#!/usr/bin/env python3
"""Compile RTL with Icarus Verilog, simulate, and compare against golden vectors.

This is the ONLY source of pass/fail truth in the pipeline. It never asks a
Devin session whether its design is correct; it compiles the RTL, drives
every input combination the registry says to check, and diffs the simulated
outputs against spec.registry.ChipSpec.golden_fn.

Exit 0 on full pass, exit 1 on any mismatch, exit 2 on a compile/sim error.
Emits exactly one harness event line (harness/events.py) summarizing the run.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from harness.events import emit  # noqa: E402
from spec.registry import ChipSpec, load_chip  # noqa: E402

TB_MODULE = "golden_tb"
MAX_REPORTED_FAILURES = 5


def _bit_concat(names: list[str]) -> str:
    return "{" + ", ".join(names) + "}"


def generate_testbench(spec: ChipSpec, vcd_path: pathlib.Path) -> str:
    """Build a testbench that sweeps every input combination via a counter.

    The counter's bits map onto the input ports in registry order (first
    input = most-significant bit), exactly matching ChipSpec.iter_vectors's
    enumeration, so Python-side expected outputs line up with simulated ones
    by vector index alone -- no need to ship a vector file into the sim.
    """
    in_names = [p.name for p in spec.inputs]
    out_names = [p.name for p in spec.outputs]
    n_in = len(in_names)

    port_conns = ",\n        ".join(f".{name}({name})" for name in in_names + out_names)
    reg_decls = "\n    ".join(f"reg {name};" for name in in_names)
    wire_decls = "\n    ".join(f"wire {name};" for name in out_names)

    return f"""\
`timescale 1ns/1ps
module {TB_MODULE};
    {reg_decls}
    {wire_decls}
    integer vec;  // deliberately wider than n_in bits: an exactly-n_in-bit
                  // counter wraps at 2**n_in and never reaches vector_count,
                  // looping forever instead of terminating.

    {spec.module_name} dut (
        {port_conns}
    );

    initial begin
        $dumpfile("{vcd_path.as_posix()}");
        $dumpvars(0, {TB_MODULE});
        for (vec = 0; vec < {spec.vector_count}; vec = vec + 1) begin
            {_bit_concat(in_names)} = vec;
            #1;
            $display("VEC,%0d,%b", vec, {_bit_concat(out_names)});
        end
        $finish;
    end
endmodule
"""


def _format_failures(failures: list[tuple[dict, dict, dict | None]]) -> str:
    parts = []
    for in_map, expected, actual in failures:
        in_str = " ".join(f"{k}={v}" for k, v in in_map.items())
        parts.append(f"[{in_str}] expected={expected} actual={actual}")
    return "; ".join(parts)


def run_harness(
    chip_id: str,
    rtl_path: pathlib.Path,
    *,
    branch: str,
    agent: str = "harness",
    attempt: int = 1,
) -> dict:
    """Runs the harness and returns the emitted event dict (status/passed/total/detail).

    Callers that just need pass/fail can check event["status"] == "pass".
    """
    spec = load_chip(chip_id)

    if not rtl_path.exists():
        return emit(chip=chip_id, branch=branch, agent=agent, stage="verify", attempt=attempt,
                     status="error", detail=f"RTL file not found: {rtl_path}")

    with tempfile.TemporaryDirectory() as tmp_str:
        tmp = pathlib.Path(tmp_str)
        tb_path = tmp / "tb.v"
        vcd_path = tmp / "wave.vcd"
        sim_path = tmp / "sim.vvp"
        tb_path.write_text(generate_testbench(spec, vcd_path))

        compile_cmd = ["iverilog", "-o", str(sim_path), str(rtl_path), str(tb_path)]
        compile_proc = subprocess.run(compile_cmd, capture_output=True, text=True)
        if compile_proc.returncode != 0:
            return emit(chip=chip_id, branch=branch, agent=agent, stage="verify", attempt=attempt,
                         status="error",
                         detail=f"iverilog compile failed: {compile_proc.stderr.strip()[:800]}")

        sim_proc = subprocess.run(["vvp", str(sim_path)], capture_output=True, text=True, cwd=tmp)

        in_names = [p.name for p in spec.inputs]
        out_names = [p.name for p in spec.outputs]
        n_in = len(in_names)

        results: dict[int, dict[str, int]] = {}
        for line in sim_proc.stdout.splitlines():
            if not line.startswith("VEC,"):
                continue
            _, vec_str, bits_str = line.strip().split(",")
            vec = int(vec_str)
            bits = bits_str.strip()
            results[vec] = {name: int(b) for name, b in zip(out_names, bits)}

        if not results:
            return emit(chip=chip_id, branch=branch, agent=agent, stage="verify", attempt=attempt,
                         status="error",
                         detail=f"vvp produced no vectors (stderr: {sim_proc.stderr.strip()[:500]})")

        total = spec.vector_count
        passed = 0
        failures: list[tuple[dict, dict, dict | None]] = []
        for combo in range(total):
            bits_in = [(combo >> (n_in - 1 - i)) & 1 for i in range(n_in)]
            in_map = dict(zip(in_names, bits_in))
            expected = spec.golden_fn(in_map)
            actual = results.get(combo)
            if actual == expected:
                passed += 1
            elif len(failures) < MAX_REPORTED_FAILURES:
                failures.append((in_map, expected, actual))

        vcd_dest = None
        if vcd_path.exists():
            vcd_dest = rtl_path.parent / f"{rtl_path.stem}.vcd"
            vcd_dest.write_bytes(vcd_path.read_bytes())

        ok = passed == total
        detail = "all vectors matched" if ok else _format_failures(failures)
        return emit(chip=chip_id, branch=branch, agent=agent, stage="verify", attempt=attempt,
                     status="pass" if ok else "fail", passed=passed, total=total,
                     artifact_path=str(vcd_dest) if vcd_dest else None, detail=detail)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip", required=True, help="chip id, e.g. 74138")
    parser.add_argument("--rtl", required=True, type=pathlib.Path, help="path to the RTL .v file")
    parser.add_argument("--branch", default="local", help="git branch this run is for")
    parser.add_argument("--agent", default="harness", help="agent name for the event log")
    parser.add_argument("--attempt", type=int, default=1)
    args = parser.parse_args()

    event = run_harness(args.chip, args.rtl, branch=args.branch, agent=args.agent, attempt=args.attempt)
    return 0 if event["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
