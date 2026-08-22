`default_nettype none

//
// 74138: 3-to-8 line decoder / demultiplexer.
//
// A0..A2 select one of eight outputs. Outputs are active-low: the selected
// output drives 0 while all others stay at 1. The three enable inputs must all
// be asserted (G1 high, G2A_n and G2B_n low) for any output to be driven low;
// otherwise every output is held high.
//
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

    // Combined enable: active-high G1 plus both active-low enables asserted.
    wire       enable;
    // Address inputs packed into a 3-bit select value, A2 as the MSB.
    wire [2:0] select;

    assign enable = G1 & ~G2A_n & ~G2B_n;
    assign select = {A2, A1, A0};

    // Each output is the inverse of its decoded select match, so the selected
    // line goes low and everything else (including the disabled case) is high.
    assign Y0 = ~(enable & (select == 3'd0));
    assign Y1 = ~(enable & (select == 3'd1));
    assign Y2 = ~(enable & (select == 3'd2));
    assign Y3 = ~(enable & (select == 3'd3));
    assign Y4 = ~(enable & (select == 3'd4));
    assign Y5 = ~(enable & (select == 3'd5));
    assign Y6 = ~(enable & (select == 3'd6));
    assign Y7 = ~(enable & (select == 3'd7));

endmodule

`default_nettype wire
