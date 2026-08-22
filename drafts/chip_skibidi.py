"""DRAFT candidate golden model for the SN7447A BCD-to-seven-segment
decoder/driver (TI datasheet SDLS111, MARCH 1974 - REVISED MARCH 1988).

DEVIN-DRAFTED CANDIDATE, NOT GROUND TRUTH. A human must review this file
against the datasheet before it is trusted or moved under /spec/.

Source document: drafts/chip_skibidi_datasheet.pdf. Pages 1-13 of that PDF are
scanned images; they were read with OCR (tesseract at 400 dpi). Page numbers
below are 1-based PDF page numbers.

Variant choice (REVIEW ITEM)
  The datasheet covers six devices (page 1 title): '46A, '47A, '48, 'LS47,
  'LS48, 'LS49. They do not all share one function table:
    - page 3, FUNCTION TABLE (T1): '46A, '47A, 'LS47 -- active-LOW segments
    - page 4, FUNCTION TABLE (T2): '48, 'LS48 -- same decode, active-HIGH
      segments (page 3 description: "'46A, '47A, and 'LS47 feature active-low
      outputs ... The '48, 'LS48, and 'LS49 feature active-high outputs")
    - page 4, FUNCTION TABLE (T3): 'LS49 -- no LT/RBI, direct BI input only
  This model describes the SN7447A, i.e. FUNCTION TABLE (T1) with active-LOW
  segment outputs. It is NOT valid for the '48/'LS48/'LS49 variants.

Pinout (page 1, N package top view; page 2 logic symbol for '46A/'47A/'LS47)
  Inputs:  A, B, C, D  - BCD code inputs, A = LSB (pins 7, 1, 2, 6)
           LT_n        - lamp test, active LOW (pin 3)
           RBI_n       - ripple-blanking input, active LOW (pin 5)
           BI_n        - blanking input, active LOW (pin 4, see note below)
  Outputs: a_n .. g_n  - segment drivers, active LOW (0 = segment ON)
           RBO_n       - ripple-blanking output, active LOW (pin 4)

BI/RBO modeling (REVIEW ITEM)
  Pin 4 is a single bidirectional pin: page 3 footnote "BI/RBO is wire AND
  logic serving as blanking input (BI) and/or ripple-blanking output (RBO)".
  A plain 1-bit-in / 1-bit-out interface cannot express one bidirectional
  wire-AND node, so the pin is split here into an input BI_n (what an external
  driver forces onto the node) and an output RBO_n (the level of the node).
  The logical wire-AND is preserved: RBO_n is 0 whenever the internal RBO
  driver pulls low (zero-suppression, page 3 note 3) OR the external driver
  forces it low (BI_n == 0). Open/high on the real pin corresponds to
  BI_n == 1.

Behavior rules, all from page 3 FUNCTION TABLE (T1) and its notes 1-4
  1. BI (table row "BI", note 2): BI_n == 0 -> all seven segments OFF,
     regardless of every other input. Highest priority.
  2. LT (table row "LT", note 4): BI_n == 1 and LT_n == 0 -> all seven
     segments ON (RBI is irrelevant, "X" in the table).
  3. RBI zero blanking (table row "RBI", note 3): LT_n == 1, RBI_n == 0 and
     D == C == B == A == 0 -> all segments OFF and RBO pulled LOW.
  4. Decode (table rows 0-15, note 1): otherwise the segment pattern for
     DCBA is taken from the table; rows 10-15 are the unique non-decimal
     symbols the datasheet shows ("Display patterns for BCD input counts
     above 9 are unique symbols to authenticate input conditions", page 3).
     Note that for decimal 0 the table requires RBI = H, which is rule 3's
     complement, and for rows 1-15 RBI is "X" (irrelevant).
  5. RBO_n (BI/RBO column of T1): LOW only in the two blanked cases above
     (rule 1's external low and rule 3's response condition); HIGH ("H" in
     the BI/RBO column) for every decode row and for lamp test.

Segment patterns as read from page 3 (ON segments per digit), sanity-checked
against the "NUMERICAL DESIGNATIONS AND RESULTANT DISPLAYS" figure on page 3:
  0: a b c d e f      8: a b c d e f g
  1: b c               9: a b c f g
  2: a b d e g        10: d e g
  3: a b c d g        11: c d g
  4: b c f g          12: b f g
  5: a c d f g        13: a d f g
  6: c d e f g        14: d e f g
  7: a b c            15: (blank)

Input space is 2**7 = 128 combinations -> verified exhaustively by the harness.
"""
from spec.registry import ChipSpec, Port

MODULE_NAME = "bcd_7seg_7447a"

INPUTS = [
    Port("A"), Port("B"), Port("C"), Port("D"),
    Port("LT_n"), Port("RBI_n"), Port("BI_n"),
]
_SEGMENTS = ["a", "b", "c", "d", "e", "f", "g"]
OUTPUTS = [Port(f"{s}_n") for s in _SEGMENTS] + [Port("RBO_n")]

# ON segments for each of the 16 input codes, page 3 FUNCTION TABLE (T1).
_PATTERNS = [
    "abcdef",   # 0
    "bc",       # 1
    "abdeg",    # 2
    "abcdg",    # 3
    "bcfg",     # 4
    "acdfg",    # 5
    "cdefg",    # 6
    "abc",      # 7
    "abcdefg",  # 8
    "abcfg",    # 9
    "deg",      # 10
    "cdg",      # 11
    "bfg",      # 12
    "adfg",     # 13
    "defg",     # 14
    "",         # 15
]


def golden_fn(inputs: dict[str, int]) -> dict[str, int]:
    a, b, c, d = inputs["A"], inputs["B"], inputs["C"], inputs["D"]
    lt_n, rbi_n, bi_n = inputs["LT_n"], inputs["RBI_n"], inputs["BI_n"]

    code = (d << 3) | (c << 2) | (b << 1) | a

    if bi_n == 0:
        # Rule 1: blanking input overrides everything.
        on_segments = ""
        rbo_n = 0
    elif lt_n == 0:
        # Rule 2: lamp test with BI/RBO high turns every segment on.
        on_segments = "abcdefg"
        rbo_n = 1
    elif rbi_n == 0 and code == 0:
        # Rule 3: leading/trailing zero suppression, RBO pulled low.
        on_segments = ""
        rbo_n = 0
    else:
        # Rule 4: normal decode.
        on_segments = _PATTERNS[code]
        rbo_n = 1

    # Segment outputs are active LOW: 0 = segment ON, 1 = segment OFF.
    outputs = {f"{s}_n": (0 if s in on_segments else 1) for s in _SEGMENTS}
    outputs["RBO_n"] = rbo_n
    return outputs


SPEC = ChipSpec(
    chip_id="7447a",
    module_name=MODULE_NAME,
    inputs=INPUTS,
    outputs=OUTPUTS,
    golden_fn=golden_fn,
)
