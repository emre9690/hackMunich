// 74138 3-to-8 line decoder/demultiplexer
//
// Active-low outputs: the selected output is driven low, all others stay high.
// The decoder is enabled only when G1 == 1 and both active-low enables
// G2A_n and G2B_n are 0; otherwise every output is held high (inactive).
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

    // Combined enable: active-high G1 gated by both active-low enables.
    wire enable_active = G1 & ~G2A_n & ~G2B_n;

    // Address inputs packed so that A2 is the most significant bit.
    wire [2:0] addr_sel = {A2, A1, A0};

    // One-of-eight decode, inverted to produce active-low outputs.
    assign Y0 = ~(enable_active & (addr_sel == 3'd0));
    assign Y1 = ~(enable_active & (addr_sel == 3'd1));
    assign Y2 = ~(enable_active & (addr_sel == 3'd2));
    assign Y3 = ~(enable_active & (addr_sel == 3'd3));
    assign Y4 = ~(enable_active & (addr_sel == 3'd4));
    assign Y5 = ~(enable_active & (addr_sel == 3'd5));
    assign Y6 = ~(enable_active & (addr_sel == 3'd6));
    assign Y7 = ~(enable_active & (addr_sel == 3'd7));

endmodule
