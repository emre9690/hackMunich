// 74138: 3-to-8 line decoder/demultiplexer with active-low outputs.
//
// The chip is enabled only when G1 is high and both active-low enables
// (G2A_n, G2B_n) are low. When enabled, the single output selected by the
// binary address {A2, A1, A0} is driven low and all others stay high; when
// disabled, every output is high.
`default_nettype none

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
    wire       chip_enable  = G1 & ~G2A_n & ~G2B_n;

    // Address bus with A2 as the most significant bit.
    wire [2:0] address      = {A2, A1, A0};

    // Active-low outputs: the addressed line is pulled low while enabled.
    assign Y0 = ~(chip_enable & (address == 3'd0));
    assign Y1 = ~(chip_enable & (address == 3'd1));
    assign Y2 = ~(chip_enable & (address == 3'd2));
    assign Y3 = ~(chip_enable & (address == 3'd3));
    assign Y4 = ~(chip_enable & (address == 3'd4));
    assign Y5 = ~(chip_enable & (address == 3'd5));
    assign Y6 = ~(chip_enable & (address == 3'd6));
    assign Y7 = ~(chip_enable & (address == 3'd7));

endmodule

`default_nettype wire
