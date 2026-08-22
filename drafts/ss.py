"""CANDIDATE golden model for the SN74LS49 BCD-to-seven-segment decoder/driver.

DRAFT -- NOT YET HUMAN-REVIEWED. Drafted from the uploaded datasheet
drafts/ss_datasheet.pdf: Texas Instruments SDLS111, "SN5446A, '47A, '48,
SN54LS47, 'LS48, 'LS49 / SN7446A, '47A, '48, SN74LS47, 'LS48, 'LS49
BCD-TO-SEVEN-SEGMENT DECODERS/DRIVERS", March 1974, revised March 1988.
Datasheet pages 1-13 of the PDF are image-only scans; they were read via
page rendering + OCR/image reading, not text extraction.

Which device in the family this models, and why
-----------------------------------------------
The document covers six devices. Only the 'LS49 has a port list that a
plain unidirectional 1-bit interface can represent faithfully:

  * '46A, '47A, 'LS47 (function table T1, printed page 3) and '48, 'LS48
    (function table T2, printed page 4) all have a single BI/RBO pin that
    the datasheet footnote describes as "BI/RBO is wire AND logic serving
    as blanking input (BI) and/or ripple-blanking output (RBO)" -- one
    physical open-collector pin that is simultaneously an input and an
    output. That cannot be expressed as separate 1-bit INPUTS/OUTPUTS
    ports without changing the pinout, so those variants are not modeled
    here.
  * 'LS49 (function table T3, printed page 4) has a plain, input-only
    blanking input BI and no RBI/RBO/LT pins at all ("The 'LS49 circuit
    incorporates a direct blanking input", description, printed page 3),
    so every port is a plain 1-bit signal.

Ports (from function table T3 and the 'LS49 pinout on printed page 1)
---------------------------------------------------------------------
  Inputs:  A, B, C, D - BCD code input; A is the LSB, D is the MSB
                        (T3 column order is D C B A)
           BI_n       - blanking input, active LOW
  Outputs: a, b, c, d, e, f, g - segment drivers, active HIGH
                        ("The '48, 'LS48, and 'LS49 feature active-high
                        outputs for driving lamp buffers or common-cathode
                        LEDs", description, printed page 3). They are
                        open-collector outputs needing an external pull-up
                        (features list, printed page 1; driver-output table,
                        printed page 2), but the function table states them
                        purely as H/L, which is what this model returns:
                        1 = segment on (H), 0 = segment off (L).

Behavior rules (all from 'LS49 FUNCTION TABLE (T3), printed page 4)
-------------------------------------------------------------------
Rule 1 -- blanking, T3 last row plus T3 note 2 ("When a low logic level is
  applied directly to the blanking input (BI), all segment outputs are low
  regardless of the level of any other input"): if BI_n == 0, every segment
  output is 0, whatever A-D are. This overrides everything else.

Rule 2 -- decoding, T3 rows 0..15 plus T3 note 1 ("The blanking input (BI)
  must be open or held at a high logic level when output functions 0
  through 15 are desired"): with BI_n == 1, the 4-bit value
  n = {D,C,B,A} selects row n of T3, transcribed verbatim into
  _SEGMENTS below (H -> 1, L -> 0, column order a b c d e f g).
  Rows 0-9 are the decimal digits; rows 10-15 are the datasheet's unique
  symbols for BCD input counts above 9 (row 15 blanks the display), per
  the "NUMERICAL DESIGNATIONS AND RESULTANT DISPLAYS" figure and the
  description on printed page 3.

  T3 rows, exactly as printed (D C B A | a b c d e f g):
     0  L L L L | H H H H H H L        8  H L L L | H H H H H H H
     1  L L L H | L H H L L L L        9  H L L H | H H H L L H H
     2  L L H L | H H L H H L H       10  H L H L | L L L H H L H
     3  L L H H | H H H H L L H       11  H L H H | L L H H L L H
     4  L H L L | L H H L L H H       12  H H L L | L H L L L H H
     5  L H L H | H L H H L H H       13  H H L H | H L L H L H H
     6  L H H L | L L H H H H H       14  H H H L | L L L H H H H
     7  L H H H | H H H L L L L       15  H H H H | L L L L L L L

Note: 'LS49 has no lamp-test or ripple-blanking behavior to model -- those
rows exist only in T1/T2 for the other family members.

Input space is 2**5 = 32 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_seven_seg_74ls49"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("BI_n"),
]
OUTPUTS = [Port(name) for name in ("a", "b", "c", "d", "e", "f", "g")]

_SEGMENT_NAMES = ("a", "b", "c", "d", "e", "f", "g")

# Row n = T3 outputs for BCD value n, in column order a b c d e f g (H -> 1).
_SEGMENTS = (
    (1, 1, 1, 1, 1, 1, 0),  # 0
    (0, 1, 1, 0, 0, 0, 0),  # 1
    (1, 1, 0, 1, 1, 0, 1),  # 2
    (1, 1, 1, 1, 0, 0, 1),  # 3
    (0, 1, 1, 0, 0, 1, 1),  # 4
    (1, 0, 1, 1, 0, 1, 1),  # 5
    (0, 0, 1, 1, 1, 1, 1),  # 6
    (1, 1, 1, 0, 0, 0, 0),  # 7
    (1, 1, 1, 1, 1, 1, 1),  # 8
    (1, 1, 1, 0, 0, 1, 1),  # 9
    (0, 0, 0, 1, 1, 0, 1),  # 10
    (0, 0, 1, 1, 0, 0, 1),  # 11
    (0, 1, 0, 0, 0, 1, 1),  # 12
    (1, 0, 0, 1, 0, 1, 1),  # 13
    (0, 0, 0, 1, 1, 1, 1),  # 14
    (0, 0, 0, 0, 0, 0, 0),  # 15
)


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    bi_n = inputs["BI_n"]

    if bi_n == 0:
        return {name: 0 for name in _SEGMENT_NAMES}

    value = (
        (inputs["D"] << 3)
        | (inputs["C"] << 2)
        | (inputs["B"] << 1)
        | inputs["A"]
    )
    row = _SEGMENTS[value]
    return {name: row[i] for i, name in enumerate(_SEGMENT_NAMES)}


SPEC = ChipSpec(
    chip_id="ss",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
