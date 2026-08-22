// 74138 3-to-8 line decoder/demultiplexer
//
// Address inputs A2..A0 select one of eight outputs.
// The chip is enabled only when G1 == 1 and both active-low enables
// (G2A_n, G2B_n) are 0.
// Outputs are active LOW: when enabled, exactly one output is driven LOW
// (the one selected by A2..A0) and the rest stay HIGH; when disabled all
// eight outputs are HIGH.
// Purely combinational: no clock, no reset, no internal state.
module decoder_74138 (
    input  wire A0,     // address bit 0 (LSB)
    input  wire A1,     // address bit 1
    input  wire A2,     // address bit 2 (MSB)
    input  wire G1,     // active-high enable
    input  wire G2A_n,  // active-low enable
    input  wire G2B_n,  // active-low enable
    output wire Y0,     // active-low decoded outputs
    output wire Y1,
    output wire Y2,
    output wire Y3,
    output wire Y4,
    output wire Y5,
    output wire Y6,
    output wire Y7
);

    // Combined enable term: all three enable pins must agree before any
    // output may be asserted (driven LOW).
    wire chip_enable = G1 & ~G2A_n & ~G2B_n;

    // One AND term per address code; the final inversion produces the
    // active-low output polarity of the real 74138.
    assign Y0 = ~(chip_enable & ~A2 & ~A1 & ~A0);  // A2A1A0 = 000
    assign Y1 = ~(chip_enable & ~A2 & ~A1 &  A0);  // A2A1A0 = 001
    assign Y2 = ~(chip_enable & ~A2 &  A1 & ~A0);  // A2A1A0 = 010
    assign Y3 = ~(chip_enable & ~A2 &  A1 &  A0);  // A2A1A0 = 011
    assign Y4 = ~(chip_enable &  A2 & ~A1 & ~A0);  // A2A1A0 = 100
    assign Y5 = ~(chip_enable &  A2 & ~A1 &  A0);  // A2A1A0 = 101
    assign Y6 = ~(chip_enable &  A2 &  A1 & ~A0);  // A2A1A0 = 110
    assign Y7 = ~(chip_enable &  A2 &  A1 &  A0);  // A2A1A0 = 111

endmodule
