"""Golden model for a programmed 82S100 FPLA, configured as a 16-input
address decoder / chip-select generator.

HUMAN-OWNED GROUND TRUTH. No Devin session may create or edit this file.

This is our chosen "programmed instance" of the 82S100 (build brief §7):
  Inputs:  A0..A15 - 16-bit address (A0 = LSB, A15 = MSB)
  Outputs: Y0..Y7   - active-LOW chip-selects

Base behavior: the top 3 address bits A[15:13] select one of 8 8K-aligned
regions; region r asserts Yr (active LOW), all other outputs stay HIGH.

To exercise genuine sum-of-products behavior (not just one contiguous range
per output), Y7 has TWO disjoint active ranges instead of one:
  1. All of region 7 (A[15:13] == 3'b111), i.e. addresses 0xE000-0xFFFF.
  2. A small sub-range carved out of region 3: 0x6000-0x60FF.
Region 3's own output, Y3, excludes that carved-out sub-range, so exactly
one output is active for any given address (no overlap):
  Y3 active-LOW range: 0x6000-0x7FFF EXCEPT 0x6000-0x60FF (Y7 owns that slice)
  Y7 active-LOW range: 0x6000-0x60FF, plus all of 0xE000-0xFFFF

Input space is 2**16 = 65536 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "fpla_82s100_addr_decoder"

INPUTS = [Port(f"A{i}") for i in range(16)]
OUTPUTS = [Port(f"Y{i}") for i in range(8)]

_CARVE_LOW = 0x6000
_CARVE_HIGH = 0x60FF


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    addr = 0
    for i in range(16):
        addr |= inputs[f"A{i}"] << i

    region = (addr >> 13) & 0b111
    in_carve = _CARVE_LOW <= addr <= _CARVE_HIGH

    outputs = {f"Y{i}": 1 for i in range(8)}

    if region == 7:
        outputs["Y7"] = 0
    elif in_carve:
        outputs["Y7"] = 0
    elif region == 3:
        outputs["Y3"] = 0
    else:
        outputs[f"Y{region}"] = 0

    return outputs


SPEC = ChipSpec(
    chip_id="82s100",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
