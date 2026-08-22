`timescale 1ns / 1ps

// 74138: 3-to-8 line decoder / demultiplexer.
// Active-low outputs; enabled when G1 is high and both G2A_n, G2B_n are low.
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

    wire       enable = G1 & ~G2A_n & ~G2B_n;
    wire [2:0] sel    = {A2, A1, A0};

    assign Y0 = ~(enable & (sel == 3'd0));
    assign Y1 = ~(enable & (sel == 3'd1));
    assign Y2 = ~(enable & (sel == 3'd2));
    assign Y3 = ~(enable & (sel == 3'd3));
    assign Y4 = ~(enable & (sel == 3'd4));
    assign Y5 = ~(enable & (sel == 3'd5));
    assign Y6 = ~(enable & (sel == 3'd6));
    assign Y7 = ~(enable & (sel == 3'd7));

endmodule
