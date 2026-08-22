"""Golden model for the 74138 3-to-8 line decoder/demultiplexer.

HUMAN-OWNED GROUND TRUTH. No Devin session may create or edit this file.

Datasheet behavior:
  Inputs:  A0, A1, A2   - 3-bit binary select
           G1            - enable, active HIGH
           G2A_n, G2B_n  - enable, active LOW (both)
  Outputs: Y0..Y7 - active LOW; exactly one LOW when enabled, all HIGH otherwise.

Enabled iff G1 == 1 AND G2A_n == 0 AND G2B_n == 0.
When enabled: Y[sel] = 0 where sel = {A2,A1,A0}; all other Y = 1.
When disabled: all Y = 1.

Input space is 2**6 = 64 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "decoder_74138"

INPUTS = [
    Port("A0"), Port("A1"), Port("A2"),
    Port("G1"), Port("G2A_n"), Port("G2B_n"),
]
OUTPUTS = [Port(f"Y{i}") for i in range(8)]


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a0, a1, a2 = inputs["A0"], inputs["A1"], inputs["A2"]
    g1, g2a_n, g2b_n = inputs["G1"], inputs["G2A_n"], inputs["G2B_n"]

    enabled = (g1 == 1) and (g2a_n == 0) and (g2b_n == 0)
    sel = (a2 << 2) | (a1 << 1) | a0

    outputs = {f"Y{i}": 1 for i in range(8)}
    if enabled:
        outputs[f"Y{sel}"] = 0
    return outputs


SPEC = ChipSpec(
    chip_id="74138",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
