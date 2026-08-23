"""CANDIDATE golden model for the SN5446A BCD-to-seven-segment decoder/driver.

DEVIN-DRAFTED, NOT YET HUMAN-REVIEWED. Not ground truth until a human approves it.

Source document: drafts/sn5446a_datasheet.pdf -- TI SDLS111, "SN5446A, '47A, '48,
SN54LS47, 'LS48, 'LS49 ... BCD-TO-SEVEN-SEGMENT DECODERS/DRIVERS", March 1974,
revised March 1988. All page references below are to that PDF.

Ports (pinout, page 1, J/N package top view; pin numbers in parentheses):
  Inputs:  A (7), B (1), C (2), D (6)  - BCD input, A = LSB, D = MSB
           LT_n (3)                    - lamp test, active LOW
           RBI_n (5)                   - ripple-blanking input, active LOW
           BI_n (4)                    - blanking input, active LOW (see note on
                                         BI/RBO modeling below)
  Outputs: a, b, c, d, e, f, g         - segment drivers, active LOW
           RBO_n (4)                   - ripple-blanking output, active LOW

Output polarity (page 2 driver-output table: SN5446A "ACTIVE LEVEL = low",
"open-collector"; page 3 description: "The '46A, '47A, and 'LS47 feature
active-low outputs designed for driving common-anode LEDs"):
  segment ON  -> output 0 (driver sinks current, LOW)
  segment OFF -> output 1
The real '46A outputs are open collector, so "OFF" is physically a
high-impedance state pulled up by the external indicator supply. This 0/1
model represents that OFF state as logic 1, which is what an external
pull-up produces; there is no separate Hi-Z encoding here.

BI/RBO modeling (page 3, footnote to the function table: "BI/RBO is wire AND
logic serving as blanking input (BI) and/or ripple-blanking output (RBO)"):
the physical device has ONE bidirectional open-collector pin 4. Since a plain
1-bit port cannot be both driven and sensed, that pin is split here into an
input BI_n (what an external driver forces onto the node) and an output RBO_n
(what the chip itself drives). The physical node level is the wire-AND of the
two, i.e. LOW if either is LOW, which is exactly RBO_n as computed below
(RBO_n is forced 0 whenever BI_n is 0).

Behavior rules, all from the "'46A, '47A, 'LS47 FUNCTION TABLE (T1)" and its
notes on page 3:

  1. Blanking (table row "BI", note 2): "When a low logic level is applied
     directly to the blanking input (BI), all segment outputs are off
     regardless of the level of any other input." The BI row lists LT and RBI
     as X, so BI_n = 0 has the highest priority. -> all segments OFF, RBO_n = 0.

  2. Lamp test (table row "LT", note 4): "When the blanking input/ripple
     blanking output (BI/RBO) is open or held high and a low is applied to the
     lamp-test input, all segment outputs are on." -> with BI_n = 1 and
     LT_n = 0: all seven segments ON, RBO_n = 1 (node held high).

  3. Ripple blanking (table row "RBI", note 3): "When ripple-blanking input
     (RBI) and inputs A, B, C, and D are at a low level with the lamp test
     input high, all segment outputs go off and the ripple-blanking output
     (RBO) goes to a low level (response condition)." -> with BI_n = 1,
     LT_n = 1, RBI_n = 0 and D=C=B=A=0: all segments OFF, RBO_n = 0.

  4. Decoding (table rows 0..15, note 1): "The blanking input (BI) must be open
     or held at a high logic level when output functions 0 through 15 are
     desired. The ripple-blanking input (RBI) must be open or high if blanking
     of a decimal zero is not desired." Row 0 requires RBI = H; rows 1..15 list
     RBI = X, consistent with rule 3 applying only to the all-zero code. In all
     16 decode rows BI/RBO is H, so RBO_n = 1. The ON/OFF pattern per code is
     transcribed verbatim from the function table into _SEGMENTS_ON below.

Input space is 2**7 = 128 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_to_7seg_sn5446a"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
OUTPUTS = [Port(n) for n in ("a", "b", "c", "d", "e", "f", "g")] + [Port("RBO_n")]

_SEGMENT_NAMES = ("a", "b", "c", "d", "e", "f", "g")

# Segments that are ON for each BCD code, transcribed from the '46A, '47A, 'LS47
# function table (T1), page 3. Order within each tuple is a, b, c, d, e, f, g.
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

    # Rule 1: blanking input overrides everything.
    if bi_n == 0:
        outputs = dict(all_off)
        rbo_n = 0
    # Rule 2: lamp test, valid because BI/RBO node is high here.
    elif lt_n == 0:
        outputs = dict(all_on)
        rbo_n = 1
    # Rule 3: ripple blanking of a leading/trailing decimal zero.
    elif rbi_n == 0 and code == 0:
        outputs = dict(all_off)
        rbo_n = 0
    # Rule 4: normal decode of codes 0..15.
    else:
        outputs = {
            name: (0 if on else 1)
            for name, on in zip(_SEGMENT_NAMES, _SEGMENTS_ON[code])
        }
        rbo_n = 1

    outputs["RBO_n"] = rbo_n
    return outputs


SPEC = ChipSpec(
    chip_id="sn5446a",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
