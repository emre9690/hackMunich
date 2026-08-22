"""DRAFT golden model for the SN7447A BCD-to-seven-segment decoder/driver.

CANDIDATE - drafted by a Devin session from the datasheet at
drafts/bcd7447_datasheet.pdf (TI SDLS111, MARCH 1974 - REVISED MARCH 1988,
"SN5446A, '47A, '48, SN54LS47, 'LS48, 'LS49 BCD-TO-SEVEN-SEGMENT
DECODERS/DRIVERS"). NOT ground truth until a human reviews it.

Ports (datasheet p.1 pinout "SN7446A, SN7447A, SN7448 ... N PACKAGE" and
p.3 "'46A, '47A, 'LS47 FUNCTION TABLE (T1)"):
  Inputs:  A, B, C, D  - BCD input, A = LSB (pins 7, 1, 2, 6)
           LT_n        - lamp test, active LOW (pin 3)
           RBI_n       - ripple-blanking input, active LOW (pin 5)
           BI_n        - blanking input, active LOW (pin 4, see note below)
  Outputs: a..g        - segment drivers, ACTIVE LOW (pins 13,12,11,10,9,15,14)
           RBO_n       - ripple-blanking output, active LOW (pin 4, see below)

Active levels (p.3 "description"): "The '46A, '47A, and 'LS47 feature
active-low outputs designed for driving common-anode LEDs"; the function
table's "ON" therefore means the segment output is LOW (0) and "OFF" means
HIGH (1).

MODELING DECISION FOR REVIEWER - pin 4 (BI/RBO):
The datasheet marks pin 4 as BI/RBO, a single bidirectional open-collector
node: table footnote (dagger) "BI/RBO is wire AND logic serving as blanking
input (BI) and/or ripple-blanking output (RBO)". A 1-bit unidirectional
port interface cannot represent one bidirectional wire-AND node, so it is
split into two plain 1-bit ports: BI_n (what an external driver applies to
the node) and RBO_n (the resulting level of the node, i.e. the wire-AND of
the external drive and this chip's internal pull-down). Consequences:
  * RBO_n == 0 whenever BI_n == 0, because the node is physically the same
    wire (wire-AND), not only in the ripple-blank case of note 3.
  * Hi-Z / open-collector electrical behavior itself is not modeled; an
    undriven (open) pin 4 corresponds to BI_n == 1 per note 1 ("The
    blanking input (BI) must be open or held at a high logic level when
    output functions 0 through 15 are desired").

Behavior rules, each from the p.3 function table and its notes, in the
priority order the notes dictate:
  1. BI (note 2): "When a low logic level is applied directly to the
     blanking input (BI), all segment outputs are off regardless of the
     level of any other input."  -> BI_n == 0: a..g all 1, RBO_n = 0.
  2. LT (note 4 / table row "LT"): "When the blanking input/ripple blanking
     output (BI/RBO) is open or held high and a low is applied to the
     lamp-test input, all segment outputs are on."  -> LT_n == 0 and
     BI_n == 1: a..g all 0, RBO_n = 1.
  3. RBI (note 3 / table row "RBI"): "When ripple-blanking input (RBI) and
     inputs A, B, C, and D are at a low level with the lamp test input
     high, all segment outputs go off and the ripple-blanking output (RBO)
     goes to a low level."  -> LT_n == 1, RBI_n == 0, DCBA == 0000:
     a..g all 1, RBO_n = 0.
  4. Decode (table rows 0..15, note 1): otherwise the segment pattern for
     the 4-bit value {D,C,B,A} is taken verbatim from the ON/OFF columns of
     the function table, including the '47A-specific patterns for 6
     (segment a OFF), 9 (segment d OFF) and the unique symbols for 10..15
     ("Display patterns for BCD input counts above 9 are unique symbols to
     authenticate input conditions", p.3 description). RBO_n = 1.

Input space is 2**7 = 128 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_7447"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
OUTPUTS = [Port(n) for n in ("a", "b", "c", "d", "e", "f", "g")] + [Port("RBO_n")]

_SEGMENTS = ("a", "b", "c", "d", "e", "f", "g")

# One tuple per BCD input value 0..15, in segment order (a, b, c, d, e, f, g).
# 1 = segment OFF (output HIGH), 0 = segment ON (output LOW), transcribed
# from the '46A, '47A, 'LS47 function table on datasheet page 3.
_PATTERNS = (
    (0, 0, 0, 0, 0, 0, 1),  # 0
    (1, 0, 0, 1, 1, 1, 1),  # 1
    (0, 0, 1, 0, 0, 1, 0),  # 2
    (0, 0, 0, 0, 1, 1, 0),  # 3
    (1, 0, 0, 1, 1, 0, 0),  # 4
    (0, 1, 0, 0, 1, 0, 0),  # 5
    (1, 1, 0, 0, 0, 0, 0),  # 6
    (0, 0, 0, 1, 1, 1, 1),  # 7
    (0, 0, 0, 0, 0, 0, 0),  # 8
    (0, 0, 0, 1, 1, 0, 0),  # 9
    (1, 1, 1, 0, 0, 1, 0),  # 10
    (1, 1, 0, 0, 1, 1, 0),  # 11
    (1, 0, 1, 1, 1, 0, 0),  # 12
    (0, 1, 1, 0, 1, 0, 0),  # 13
    (1, 1, 1, 0, 0, 0, 0),  # 14
    (1, 1, 1, 1, 1, 1, 1),  # 15
)


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a_in, b_in = inputs["A"], inputs["B"]
    c_in, d_in = inputs["C"], inputs["D"]
    lt_n, rbi_n, bi_n = inputs["LT_n"], inputs["RBI_n"], inputs["BI_n"]

    value = (d_in << 3) | (c_in << 2) | (b_in << 1) | a_in

    if bi_n == 0:
        # Rule 1: blanking overrides everything; node pin 4 is held low.
        pattern = (1, 1, 1, 1, 1, 1, 1)
        rbo_n = 0
    elif lt_n == 0:
        # Rule 2: lamp test with pin 4 high -> every segment on.
        pattern = (0, 0, 0, 0, 0, 0, 0)
        rbo_n = 1
    elif rbi_n == 0 and value == 0:
        # Rule 3: leading/trailing zero suppression; chip pulls pin 4 low.
        pattern = (1, 1, 1, 1, 1, 1, 1)
        rbo_n = 0
    else:
        # Rule 4: normal decode of {D,C,B,A}.
        pattern = _PATTERNS[value]
        rbo_n = 1

    outputs = dict(zip(_SEGMENTS, pattern))
    outputs["RBO_n"] = rbo_n
    return outputs


SPEC = ChipSpec(
    chip_id="bcd7447",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
