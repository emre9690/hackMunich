// 74138 3-to-8 line decoder/demultiplexer
// Outputs are active LOW; enabled iff G1=1, G2A_n=0, G2B_n=0.
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

    wire enabled = G1 & ~G2A_n & ~G2B_n;
    wire [2:0] sel = {A2, A1, A0};

    assign Y0 = ~(enabled & (sel == 3'd0));
    assign Y1 = ~(enabled & (sel == 3'd1));
    assign Y2 = ~(enabled & (sel == 3'd2));
    assign Y3 = ~(enabled & (sel == 3'd3));
    assign Y4 = ~(enabled & (sel == 3'd4));
    assign Y5 = ~(enabled & (sel == 3'd5));
    assign Y6 = ~(enabled & (sel == 3'd6));
    assign Y7 = ~(enabled & (sel == 3'd7));

endmodule
