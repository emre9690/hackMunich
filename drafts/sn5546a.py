"""CANDIDATE golden model for the BCD-to-seven-segment decoder/driver in
drafts/sn5546a_datasheet.pdf (TI SDLS111).

DEVIN-DRAFTED, NOT YET HUMAN-REVIEWED. Not ground truth until a human approves it.

PART NUMBER NOTE (read this first, reviewer): the document contains NO device
called "SN5546A". Its title (pages 1-13, header on every page) is "SN5446A,
'47A, '48, SN54LS47, 'LS48, 'LS49 / SN7446A, '47A, '48, SN74LS47, 'LS48, 'LS49
BCD-TO-SEVEN-SEGMENT DECODERS/DRIVERS", SDLS111, March 1974, revised March 1988,
and the package addendum (pages 14-16) lists only SN5446A/SN5447A/SN5448/
SN54LS47/'LS48/'LS49 and their SN74xx counterparts. "SN5546A" is treated here as
a transposition of SN5446A: the trailing "A" suffix exists only on the '46A and
'47A, and those two share ONE logic function table ('46A, '47A, 'LS47 FUNCTION
TABLE (T1), page 3) and one output polarity (active low), so the modeled logic is
the same under either reading. The active-high parts ('48, 'LS48, table T2) and
the 'LS49 (table T3, no LT/RBI) are NOT modeled -- their part numbers carry no
"A" suffix and so cannot be the requested device. chip_id below keeps the
requested draft-slot name "sn5546a"; the device actually described is SN5446A.

All page references are to that PDF. Its body pages are image-only, so the
pinout (page 1), the driver-output table (page 2) and function table T1 with its
four notes (page 3) were read from the rendered pages cell by cell.

Ports (pinout page 1, J/N package top view; pin numbers in parentheses):
  Inputs:  A (7), B (1), C (2), D (6)  - BCD input, A = LSB, D = MSB
           LT_n (3)                    - lamp test, active LOW
           RBI_n (5)                   - ripple-blanking input, active LOW
           BI_n (4)                    - blanking input, active LOW
  Outputs: a, b, c, d, e, f, g         - segment drivers, active LOW
           RBO_n (4)                   - ripple-blanking output, active LOW

Output polarity (page 2 driver-output table: SN5446A "ACTIVE LEVEL = low",
"open-collector"; page 3 description: "The '46A, '47A, and 'LS47 feature
active-low outputs designed for driving common-anode LEDs"):
  segment ON  -> 0 (driver sinks current, output LOW)
  segment OFF -> 1
The real outputs are open collector, so a physical "OFF" segment is a
high-impedance output pulled up by the external indicator supply. This plain
0/1 interface encodes that OFF state as logic 1 (the level an external pull-up
produces); there is no separate Hi-Z encoding.

BI/RBO modeling (page 3 footnote: "BI/RBO is wire AND logic serving as blanking
input (BI) and/or ripple-blanking output (RBO)"): the device has ONE
bidirectional open-collector pin 4. A 1-bit port cannot be both driven and
sensed, so pin 4 is split into an input BI_n (what an external driver forces on
the node) and an output RBO_n (the resulting node level). The physical node is
the wire-AND of both, i.e. LOW if either side pulls LOW, which is what RBO_n
computes below (RBO_n is 0 whenever BI_n is 0).

Behavior rules, all from '46A, '47A, 'LS47 FUNCTION TABLE (T1) and its notes,
page 3, in priority order:

  1. Blanking -- table row "BI" (LT=X, RBI=X, D..A=X, BI/RBO=L, all outputs OFF)
     and note 2: "When a low logic level is applied directly to the blanking
     input (BI), all segment outputs are off regardless of the level of any
     other input." Highest priority. -> all segments OFF, RBO_n = 0.

  2. Lamp test -- table row "LT" (LT=L, RBI=X, D..A=X, BI/RBO=H, all outputs ON)
     and note 4: "When the blanking input/ripple blanking output (BI/RBO) is
     open or held high and a low is applied to the lamp-test input, all segment
     outputs are on." -> all seven segments ON, RBO_n = 1 (node held high).

  3. Ripple blanking -- table row "RBI" (LT=H, RBI=L, D=C=B=A=L, BI/RBO=L, all
     outputs OFF) and note 3: "When ripple-blanking input (RBI) and inputs A, B,
     C, and D are at a low level with the lamp test input high, all segment
     outputs go off and the ripple-blanking output (RBO) goes to a low level
     (response condition)." Applies only to the all-zero code: table row 0 lists
     RBI=H, rows 1-15 list RBI=X. -> all segments OFF, RBO_n = 0.

  4. Decoding -- table rows 0..15 with note 1: "The blanking input (BI) must be
     open or held at a high logic level when output functions 0 through 15 are
     desired. The ripple-blanking input (RBI) must be open or high if blanking
     of a decimal zero is not desired." Every decode row shows BI/RBO = H, so
     RBO_n = 1. Codes 10..15 are the unique non-numeric patterns shown in
     "NUMERICAL DESIGNATIONS AND RESULTANT DISPLAYS" (page 3); code 15 is blank.
     The per-code ON/OFF pattern in _SEGMENTS_ON is transcribed cell by cell
     from table T1 (segment order a, b, c, d, e, f, g).

Input space is 2**7 = 128 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_to_7seg_sn5546a"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
OUTPUTS = [Port(n) for n in ("a", "b", "c", "d", "e", "f", "g")] + [Port("RBO_n")]

_SEGMENT_NAMES = ("a", "b", "c", "d", "e", "f", "g")

# 1 = segment ON, 0 = segment OFF, transcribed from '46A, '47A, 'LS47 FUNCTION
# TABLE (T1), page 3. Tuple order is a, b, c, d, e, f, g.
_SEGMENTS_ON = {
    0:  (1, 1, 1, 1, 1, 1, 0),
    1:  (0, 1, 1, 0, 0, 0, 0),
    2:  (1, 1, 0, 1, 1, 0, 1),
    3:  (1, 1, 1, 1, 0, 0, 1),
    4:  (0, 1, 1, 0, 0, 1, 1),
    5:  (1, 0, 1, 1, 0, 1, 1),
    6:  (0, 0, 1, 1, 1, 1, 1),
    7:  (1, 1, 1, 0, 0, 0, 0),
    8:  (1, 1, 1, 1, 1, 1, 1),
    9:  (1, 1, 1, 0, 0, 1, 1),
    10: (0, 0, 0, 1, 1, 0, 1),
    11: (0, 0, 1, 1, 0, 0, 1),
    12: (0, 1, 0, 0, 0, 1, 1),
    13: (1, 0, 0, 1, 0, 1, 1),
    14: (0, 0, 0, 1, 1, 1, 1),
    15: (0, 0, 0, 0, 0, 0, 0),
}


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a_in, b_in = inputs["A"], inputs["B"]
    c_in, d_in = inputs["C"], inputs["D"]
    lt_n, rbi_n, bi_n = inputs["LT_n"], inputs["RBI_n"], inputs["BI_n"]

    code = (d_in << 3) | (c_in << 2) | (b_in << 1) | a_in

    all_off = {name: 1 for name in _SEGMENT_NAMES}
    all_on = {name: 0 for name in _SEGMENT_NAMES}

    # Rule 1: blanking input overrides every other input.
    if bi_n == 0:
        outputs = dict(all_off)
        rbo_n = 0
    # Rule 2: lamp test, valid because the BI/RBO node is high here.
    elif lt_n == 0:
        outputs = dict(all_on)
        rbo_n = 1
    # Rule 3: ripple blanking of a leading/trailing decimal zero.
    elif rbi_n == 0 and code == 0:
        outputs = dict(all_off)
        rbo_n = 0
    # Rule 4: normal decode of codes 0..15, active-low segment drivers.
    else:
        outputs = {
            name: (0 if on else 1)
            for name, on in zip(_SEGMENT_NAMES, _SEGMENTS_ON[code])
        }
        rbo_n = 1

    outputs["RBO_n"] = rbo_n
    return outputs


SPEC = ChipSpec(
    chip_id="sn5546a",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
