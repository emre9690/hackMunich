// 74138: 3-to-8 line decoder/demultiplexer
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
