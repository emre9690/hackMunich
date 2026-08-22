// 74138 - 3-to-8 line decoder/demultiplexer
// Enabled iff G1 == 1 && G2A_n == 0 && G2B_n == 0.
// Outputs are active LOW: exactly one output LOW when enabled, all HIGH otherwise.
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

    wire enabled = G1 & ~G2A_n & ~G2B_n;

    assign Y0 = ~(enabled & ~A2 & ~A1 & ~A0);
    assign Y1 = ~(enabled & ~A2 & ~A1 &  A0);
    assign Y2 = ~(enabled & ~A2 &  A1 & ~A0);
    assign Y3 = ~(enabled & ~A2 &  A1 &  A0);
    assign Y4 = ~(enabled &  A2 & ~A1 & ~A0);
    assign Y5 = ~(enabled &  A2 & ~A1 &  A0);
    assign Y6 = ~(enabled &  A2 &  A1 & ~A0);
    assign Y7 = ~(enabled &  A2 &  A1 &  A0);

endmodule
