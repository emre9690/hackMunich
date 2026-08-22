"""Candidate golden model for the SN7447A / SN74LS47 BCD-to-seven-segment
decoder/driver (TI SDLS111, March 1974 - revised March 1988).

AI-DRAFTED, NOT REVIEWED. This is a candidate model only; it is not ground
truth until a human reviews it against the datasheet.

Device selection (datasheet page 1 header + "PACKAGE OPTION ADDENDUM",
page 14-16): the document covers '46A/'47A/'48/'LS47/'LS48/'LS49, and the
orderable parts listed are SN5447A/SN7447A/SN54LS47/SN74LS47 (plus 'LS49).
This model implements the '47A / 'LS47 variant, i.e. FUNCTION TABLE (T1) on
page 3, which is shared by '46A, '47A and 'LS47.

Pinout (page 1, J/N/D package top view):
  Inputs:  A (pin 7), B (pin 1), C (pin 2), D (pin 6)  - BCD input, A = LSB
           LT_n  (pin 3)  - lamp test, active LOW
           RBI_n (pin 5)  - ripple-blanking input, active LOW
           BI_n           - blanking input, active LOW (pin 4, see below)
  Outputs: a (13), b (12), c (11), d (10), e (9), f (15), g (14)
           RBO_n          - ripple-blanking output, active LOW (pin 4)

BI/RBO pin split (page 3, footnote: "BI/RBO is wire AND logic serving as
blanking input (BI) and/or ripple-blanking output (RBO)"): pin 4 is a single
bidirectional wire-AND node. A pure 0/1 in/out interface cannot represent one
bidirectional pin, so it is modelled as two 1-bit signals: BI_n = the level
externally forced onto that node (1 = open/high, per Note 1) and RBO_n = the
level the device itself drives onto that node. Because the node is wire-AND,
RBO_n is reported LOW whenever either the device pulls it LOW (Note 3) or the
outside world holds it LOW (BI_n = 0).

Output polarity (page 1 features / page 2 driver-outputs table: '47A active
level "low", open-collector; page 3 description "the '46A, '47A, and 'LS47
feature active-low outputs"): a segment that is ON in the function table is a
LOW output (0) here, and OFF is HIGH (1). Open-collector OFF is modelled as
logic 1 (the pulled-up level), since Hi-Z is not representable.

Behavior rules, in the priority order given by FUNCTION TABLE (T1), page 3:
  1. BI (row "BI", Note 2): a LOW applied directly to the blanking input
     forces all seven segment outputs OFF regardless of every other input.
     Modelled as: BI_n == 0 -> all segments 1, RBO_n = 0 (node held LOW).
  2. LT (row "LT", Note 4): with BI/RBO open or held HIGH and LT_n LOW, all
     seven segment outputs are ON. Modelled as: BI_n == 1 and LT_n == 0 ->
     all segments 0, RBO_n = 1 (the device does not pull the node LOW).
  3. RBI (row "RBI", Note 3): with LT_n HIGH, RBI_n LOW and D=C=B=A LOW, all
     segments go OFF and RBO_n goes LOW (zero-blanking response condition).
  4. Otherwise (rows 0 through 15, Note 1: BI/RBO high, RBI_n high or the
     input is not a blanked zero): the segment pattern is the decode of
     {D,C,B,A} exactly as tabulated on page 3, and RBO_n stays HIGH.
     Counts 10-15 produce the unique non-numeric patterns of the table
     (page 3, "NUMERICAL DESIGNATIONS AND RESULTANT DISPLAYS").

Input space is 2**7 = 128 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_7seg_7447"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
OUTPUTS = [Port(s) for s in ("a", "b", "c", "d", "e", "f", "g")] + [Port("RBO_n")]

_SEGMENTS = ("a", "b", "c", "d", "e", "f", "g")

# FUNCTION TABLE (T1), page 3, rows 0..15. Each entry is (a, b, c, d, e, f, g)
# with 0 = ON (LOW output) and 1 = OFF (HIGH output).
_DECODE = (
    (0, 0, 0, 0, 0, 0, 1),  # 0:  ON  ON  ON  ON  ON  ON  OFF
    (1, 0, 0, 1, 1, 1, 1),  # 1:  OFF ON  ON  OFF OFF OFF OFF
    (0, 0, 1, 0, 0, 1, 0),  # 2:  ON  ON  OFF ON  ON  OFF ON
    (0, 0, 0, 0, 1, 1, 0),  # 3:  ON  ON  ON  ON  OFF OFF ON
    (1, 0, 0, 1, 1, 0, 0),  # 4:  OFF ON  ON  OFF OFF ON  ON
    (0, 1, 0, 0, 1, 0, 0),  # 5:  ON  OFF ON  ON  OFF ON  ON
    (1, 1, 0, 0, 0, 0, 0),  # 6:  OFF OFF ON  ON  ON  ON  ON
    (0, 0, 0, 1, 1, 1, 1),  # 7:  ON  ON  ON  OFF OFF OFF OFF
    (0, 0, 0, 0, 0, 0, 0),  # 8:  ON  ON  ON  ON  ON  ON  ON
    (0, 0, 0, 1, 1, 0, 0),  # 9:  ON  ON  ON  OFF OFF ON  ON
    (1, 1, 1, 0, 0, 1, 0),  # 10: OFF OFF OFF ON  ON  OFF ON
    (1, 1, 0, 0, 1, 1, 0),  # 11: OFF OFF ON  ON  OFF OFF ON
    (1, 0, 1, 1, 1, 0, 0),  # 12: OFF ON  OFF OFF OFF ON  ON
    (0, 1, 1, 0, 1, 0, 0),  # 13: ON  OFF OFF ON  OFF ON  ON
    (1, 1, 1, 0, 0, 0, 0),  # 14: OFF OFF OFF ON  ON  ON  ON
    (1, 1, 1, 1, 1, 1, 1),  # 15: OFF OFF OFF OFF OFF OFF OFF
)


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a_in, b_in = inputs["A"], inputs["B"]
    c_in, d_in = inputs["C"], inputs["D"]
    lt_n, rbi_n, bi_n = inputs["LT_n"], inputs["RBI_n"], inputs["BI_n"]

    bcd = (d_in << 3) | (c_in << 2) | (b_in << 1) | a_in

    all_off = {name: 1 for name in _SEGMENTS}
    all_on = {name: 0 for name in _SEGMENTS}

    if bi_n == 0:
        # Rule 1: direct blanking overrides everything; node held LOW.
        outputs = dict(all_off)
        rbo_n = 0
    elif lt_n == 0:
        # Rule 2: lamp test with BI/RBO high -> every segment ON.
        outputs = dict(all_on)
        rbo_n = 1
    elif rbi_n == 0 and bcd == 0:
        # Rule 3: zero-blanking response condition.
        outputs = dict(all_off)
        rbo_n = 0
    else:
        # Rule 4: normal decode of rows 0..15.
        outputs = dict(zip(_SEGMENTS, _DECODE[bcd]))
        rbo_n = 1

    outputs["RBO_n"] = rbo_n
    return outputs


SPEC = ChipSpec(
    chip_id="7447",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
