`default_nettype none

// 74138: 3-to-8 line decoder / demultiplexer with active-low outputs.
// Enable is the AND of one active-high input (G1) and two active-low
// inputs (G2A_n, G2B_n); when disabled, every output is held high.
module decoder_74138 (
    input  wire A0,     // address bit 0 (LSB)
    input  wire A1,     // address bit 1
    input  wire A2,     // address bit 2 (MSB)
    input  wire G1,     // active-high enable
    input  wire G2A_n,  // active-low enable
    input  wire G2B_n,  // active-low enable
    output wire Y0,
    output wire Y1,
    output wire Y2,
    output wire Y3,
    output wire Y4,
    output wire Y5,
    output wire Y6,
    output wire Y7
);

    // High only when all three enable inputs are asserted.
    wire       decode_enable = G1 & ~G2A_n & ~G2B_n;

    // Address inputs grouped MSB-first into the selected output index.
    wire [2:0] addr          = {A2, A1, A0};

    // Exactly one output is driven low (the selected one) while enabled;
    // all outputs stay high when decode_enable is low.
    assign Y0 = ~(decode_enable & (addr == 3'd0));
    assign Y1 = ~(decode_enable & (addr == 3'd1));
    assign Y2 = ~(decode_enable & (addr == 3'd2));
    assign Y3 = ~(decode_enable & (addr == 3'd3));
    assign Y4 = ~(decode_enable & (addr == 3'd4));
    assign Y5 = ~(decode_enable & (addr == 3'd5));
    assign Y6 = ~(decode_enable & (addr == 3'd6));
    assign Y7 = ~(decode_enable & (addr == 3'd7));

endmodule

`default_nettype wire
