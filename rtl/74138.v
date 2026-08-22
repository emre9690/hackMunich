// 74138 3-to-8 line decoder/demultiplexer
//
// Address inputs A2..A0 select one of eight outputs (A2 is the MSB).
// Enable is asserted only when G1 == 1 && G2A_n == 0 && G2B_n == 0
// (G1 is active HIGH, G2A_n and G2B_n are active LOW).
// Outputs are active LOW: exactly one output is driven LOW when the chip is
// enabled, and all outputs stay HIGH when it is disabled.
module decoder_74138 (
    input  wire A0,
    input  wire A1,
    input  wire A2,
    input  wire G1,
    input  wire G2A_n,
    input  wire G2B_n,
    output wire Y0,
    output wire Y1,
    output wire Y2,
    output wire Y3,
    output wire Y4,
    output wire Y5,
    output wire Y6,
    output wire Y7
);

    // Combined chip enable: HIGH only when all three enable inputs agree,
    // taking their differing polarities into account.
    wire chip_enable = G1 & ~G2A_n & ~G2B_n;

    // Each output is the inverted (active-LOW) form of the AND-decode of its
    // address code, so a deselected or disabled output remains HIGH.
    assign Y0 = ~(chip_enable & ~A2 & ~A1 & ~A0);   // A2A1A0 = 000
    assign Y1 = ~(chip_enable & ~A2 & ~A1 &  A0);   // A2A1A0 = 001
    assign Y2 = ~(chip_enable & ~A2 &  A1 & ~A0);   // A2A1A0 = 010
    assign Y3 = ~(chip_enable & ~A2 &  A1 &  A0);   // A2A1A0 = 011
    assign Y4 = ~(chip_enable &  A2 & ~A1 & ~A0);   // A2A1A0 = 100
    assign Y5 = ~(chip_enable &  A2 & ~A1 &  A0);   // A2A1A0 = 101
    assign Y6 = ~(chip_enable &  A2 &  A1 & ~A0);   // A2A1A0 = 110
    assign Y7 = ~(chip_enable &  A2 &  A1 &  A0);   // A2A1A0 = 111

endmodule
