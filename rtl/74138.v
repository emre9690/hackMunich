// 74138: 3-to-8 line decoder / demultiplexer.
//
// The three address inputs (A2..A0) select one of eight outputs.
// Outputs are active-low: the selected output is driven low and all
// others stay high. When the part is disabled, every output is high.
module decoder_74138 (
    input  A0,
    input  A1,
    input  A2,
    input  G1,
    input  G2A_n,
    input  G2B_n,
    output Y0,
    output Y1,
    output Y2,
    output Y3,
    output Y4,
    output Y5,
    output Y6,
    output Y7
);
    // Decoding is enabled only when the active-high enable G1 is asserted
    // and both active-low enables (G2A_n, G2B_n) are asserted (driven low).
    wire decode_enable = G1 & ~G2A_n & ~G2B_n;

    // Address inputs grouped MSB-first: A2 is the most significant bit.
    wire [2:0] addr = {A2, A1, A0};

    // Each output is the inverted (active-low) match of its own address.
    assign Y0 = ~(decode_enable & (addr == 3'd0));
    assign Y1 = ~(decode_enable & (addr == 3'd1));
    assign Y2 = ~(decode_enable & (addr == 3'd2));
    assign Y3 = ~(decode_enable & (addr == 3'd3));
    assign Y4 = ~(decode_enable & (addr == 3'd4));
    assign Y5 = ~(decode_enable & (addr == 3'd5));
    assign Y6 = ~(decode_enable & (addr == 3'd6));
    assign Y7 = ~(decode_enable & (addr == 3'd7));
endmodule
