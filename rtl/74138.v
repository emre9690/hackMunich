// 74138: 3-to-8 line decoder/demultiplexer
// Enabled iff G1 == 1 && G2A_n == 0 && G2B_n == 0.
// Outputs active LOW: Y[{A2,A1,A0}] == 0 when enabled, all HIGH otherwise.
module decoder_74138 (
    input  A0,     // Address bit 0 (LSB of select code)
    input  A1,     // Address bit 1
    input  A2,     // Address bit 2 (MSB of select code)
    input  G1,     // Enable, active HIGH
    input  G2A_n,  // Enable, active LOW
    input  G2B_n,  // Enable, active LOW
    output Y0,
    output Y1,
    output Y2,
    output Y3,
    output Y4,
    output Y5,
    output Y6,
    output Y7
);

    // Decoder is enabled only when all three enable conditions are met:
    // G1 asserted (HIGH) and both active-low enables asserted (LOW).
    wire chip_enabled = G1 & ~G2A_n & ~G2B_n;

    // One-hot decode of {A2,A1,A0}: the selected output goes LOW when the
    // chip is enabled; every other output (and all outputs when disabled)
    // stays HIGH. The outer inversion implements the active-low polarity.
    assign Y0 = ~(chip_enabled & ~A2 & ~A1 & ~A0);
    assign Y1 = ~(chip_enabled & ~A2 & ~A1 &  A0);
    assign Y2 = ~(chip_enabled & ~A2 &  A1 & ~A0);
    assign Y3 = ~(chip_enabled & ~A2 &  A1 &  A0);
    assign Y4 = ~(chip_enabled &  A2 & ~A1 & ~A0);
    assign Y5 = ~(chip_enabled &  A2 & ~A1 &  A0);
    assign Y6 = ~(chip_enabled &  A2 &  A1 & ~A0);
    assign Y7 = ~(chip_enabled &  A2 &  A1 &  A0);

endmodule
