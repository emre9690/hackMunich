// 74138 - 3-to-8 line decoder/demultiplexer
//
// Enable logic: the decoder is enabled only when G1 == 1 and both
// active-low enables G2A_n and G2B_n are 0.
// Outputs are active LOW: when enabled, exactly one output (selected by the
// binary address A2..A0) is driven LOW and the rest stay HIGH; when disabled,
// all outputs are HIGH regardless of the address inputs.
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

    // High only when all three enable conditions are satisfied.
    wire enable = G1 & ~G2A_n & ~G2B_n;

    // Each output decodes one address combination (A2 A1 A0). The outer
    // inversion produces the active-low behavior, and it also forces every
    // output HIGH whenever `enable` is low.
    assign Y0 = ~(enable & ~A2 & ~A1 & ~A0);  // address 3'b000
    assign Y1 = ~(enable & ~A2 & ~A1 &  A0);  // address 3'b001
    assign Y2 = ~(enable & ~A2 &  A1 & ~A0);  // address 3'b010
    assign Y3 = ~(enable & ~A2 &  A1 &  A0);  // address 3'b011
    assign Y4 = ~(enable &  A2 & ~A1 & ~A0);  // address 3'b100
    assign Y5 = ~(enable &  A2 & ~A1 &  A0);  // address 3'b101
    assign Y6 = ~(enable &  A2 &  A1 & ~A0);  // address 3'b110
    assign Y7 = ~(enable &  A2 &  A1 &  A0);  // address 3'b111

endmodule
