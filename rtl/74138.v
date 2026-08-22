// 74138 3-to-8 line decoder/demultiplexer
//
// Behavior:
//   * The chip is enabled only when G1 is high and both G2A_n and G2B_n are low.
//   * Exactly one output is driven low (active-low outputs) when enabled: the
//     one selected by the binary address {A2, A1, A0}.
//   * When disabled, every output stays high regardless of the address inputs.
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

    // Active-high enable term: G1 asserted high, G2A_n and G2B_n asserted low.
    wire       chip_enable = G1 & ~G2A_n & ~G2B_n;

    // A2 is the most significant address bit, A0 the least significant.
    wire [2:0] addr_sel    = {A2, A1, A0};

    // Each output is the inverse of its (enabled AND address-matched) term,
    // giving the active-low one-hot behavior of the real device.
    assign Y0 = ~(chip_enable & (addr_sel == 3'd0));
    assign Y1 = ~(chip_enable & (addr_sel == 3'd1));
    assign Y2 = ~(chip_enable & (addr_sel == 3'd2));
    assign Y3 = ~(chip_enable & (addr_sel == 3'd3));
    assign Y4 = ~(chip_enable & (addr_sel == 3'd4));
    assign Y5 = ~(chip_enable & (addr_sel == 3'd5));
    assign Y6 = ~(chip_enable & (addr_sel == 3'd6));
    assign Y7 = ~(chip_enable & (addr_sel == 3'd7));

endmodule
