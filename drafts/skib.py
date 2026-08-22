"""Golden model for the SN7447A / SN74LS47 BCD-to-seven-segment decoder/driver.

DEVIN-DRAFTED CANDIDATE. NOT trusted until a human reviews and approves it.

Source: TI datasheet SDLS111 (March 1974, revised March 1988),
"SN5446A, '47A, '48, SN54LS47, 'LS48, 'LS49 / SN7446A, '47A, '48,
SN74LS47, 'LS48, 'LS49 BCD-TO-SEVEN-SEGMENT DECODERS/DRIVERS".
The PDF's TI package-option addendum lists only SN5447A/SN7447A/SN54LS47/
SN74LS47 orderable parts, so this models the '46A/'47A/'LS47 variant
(function table T1, datasheet page 3).

Datasheet behavior ('46A, '47A, 'LS47 -- function table T1, page 3):
  Inputs:  A, B, C, D  - BCD select, A = LSB, D = MSB (pinout, page 1)
           LT_n        - lamp-test input, active LOW (pin 3)
           RBI_n       - ripple-blanking input, active LOW (pin 5)
           BI_n        - blanking input, active LOW (pin 4, see pin-split
                         note below)
  Outputs: a..g        - segment outputs, ACTIVE LOW ("open-collector
                         outputs drive indicators directly", page 1;
                         table T1 lists segments as ON/OFF, where
                         ON = output LOW): 0 = segment lit, 1 = dark.
           RBO_n       - ripple-blanking output, active LOW (pin 4,
                         see pin-split note below)

Pin-split note: on the physical chip, BI/RBO is a single wire-AND pin
(T1 footnote: "BI/RBO is wire-AND logic serving as blanking input (BI)
and/or ripple-blanking output (RBO)"). A plain unidirectional 0/1 port
list cannot express one bidirectional open-collector node, so this model
splits it: BI_n is the externally applied blanking level and RBO_n is
the level the chip itself drives onto that pin. The physical pin level
is the AND of the two. A human reviewer must confirm this split matches
how the RTL under test exposes the pin.

Rules, each cited to table T1 and its notes (page 3):
  1. BI_n == 0: all segment outputs OFF (=1) regardless of every other
     input (T1 "BI" row; note 2).
  2. Else LT_n == 0: all segment outputs ON (=0) -- lamp test (T1 "LT"
     row; note 4: applies when BI/RBO is open or held high).
  3. Else RBI_n == 0 and D=C=B=A=0: all segment outputs OFF (=1) --
     leading/trailing zero suppression (T1 "RBI" row; note 3).
  4. Else: decode {D,C,B,A} per T1 rows 0-15 (ON = 0, OFF = 1). Rows
     10-15 are the unique non-numeric authentication symbols; row 15 is
     all OFF (blank).
  RBO_n == 0 iff LT_n == 1 and RBI_n == 0 and D=C=B=A=0 (note 3:
     "when ripple-blanking input (RBI) and inputs A, B, C, and D are at
     a low level with the lamp test input high ... the ripple-blanking
     output (RBO) goes to a low level"); otherwise RBO_n == 1.

Input space is 2**7 = 128 combinations -> verified exhaustively by the
harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd7seg_7447a"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
OUTPUTS = [Port(s) for s in "abcdefg"] + [Port("RBO_n")]

# Function table T1 rows 0-15, segments (a, b, c, d, e, f, g);
# 0 = ON (output LOW), 1 = OFF (output HIGH).
_SEGMENTS = {
    0:  (0, 0, 0, 0, 0, 0, 1),
    1:  (1, 0, 0, 1, 1, 1, 1),
    2:  (0, 0, 1, 0, 0, 1, 0),
    3:  (0, 0, 0, 0, 1, 1, 0),
    4:  (1, 0, 0, 1, 1, 0, 0),
    5:  (0, 1, 0, 0, 1, 0, 0),
    6:  (1, 1, 0, 0, 0, 0, 0),
    7:  (0, 0, 0, 1, 1, 1, 1),
    8:  (0, 0, 0, 0, 0, 0, 0),
    9:  (0, 0, 0, 1, 1, 0, 0),
    10: (1, 1, 1, 0, 0, 1, 0),
    11: (1, 1, 0, 0, 1, 1, 0),
    12: (1, 0, 1, 1, 1, 0, 0),
    13: (0, 1, 1, 0, 1, 0, 0),
    14: (1, 1, 1, 0, 0, 0, 0),
    15: (1, 1, 1, 1, 1, 1, 1),
}


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a, b, c, d = inputs["A"], inputs["B"], inputs["C"], inputs["D"]
    lt_n, rbi_n, bi_n = inputs["LT_n"], inputs["RBI_n"], inputs["BI_n"]

    code = (d << 3) | (c << 2) | (b << 1) | a
    ripple_blank = (lt_n == 1) and (rbi_n == 0) and (code == 0)

    if bi_n == 0:
        segs = (1, 1, 1, 1, 1, 1, 1)   # note 2: blanked, overrides all
    elif lt_n == 0:
        segs = (0, 0, 0, 0, 0, 0, 0)   # note 4: lamp test, all segments on
    elif ripple_blank:
        segs = (1, 1, 1, 1, 1, 1, 1)   # note 3: zero suppression
    else:
        segs = _SEGMENTS[code]         # table T1 rows 0-15

    outputs = dict(zip("abcdefg", segs))
    outputs["RBO_n"] = 0 if ripple_blank else 1
    return outputs


SPEC = ChipSpec(
    chip_id="7447a",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
