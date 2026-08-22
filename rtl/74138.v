// 74138: 3-to-8 line decoder/demultiplexer
// Enabled iff G1 == 1 && G2A_n == 0 && G2B_n == 0.
// Outputs active LOW: Y[{A2,A1,A0}] == 0 when enabled, all HIGH otherwise.
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

    wire enable = G1 & ~G2A_n & ~G2B_n;

    assign Y0 = ~(enable & ~A2 & ~A1 & ~A0);
    assign Y1 = ~(enable & ~A2 & ~A1 &  A0);
    assign Y2 = ~(enable & ~A2 &  A1 & ~A0);
    assign Y3 = ~(enable & ~A2 &  A1 &  A0);
    assign Y4 = ~(enable &  A2 & ~A1 & ~A0);
    assign Y5 = ~(enable &  A2 & ~A1 &  A0);
    assign Y6 = ~(enable &  A2 &  A1 & ~A0);
    assign Y7 = ~(enable &  A2 &  A1 &  A0);

endmodule
