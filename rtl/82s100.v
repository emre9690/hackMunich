// 82S100 FPLA programmed as a 16-input address decoder / chip-select generator.
//
// Purely combinational, no clock. Outputs Y0..Y7 are active LOW: exactly one
// output is low for any of the 65536 possible addresses.
//
// Base map: region r = A[15:13] selects Yr (each region is an 8 KiB block).
// Exception: the 256-byte window 0x6000-0x60FF is carved out of region 3
// (0x6000-0x7FFF) and owned by Y7 instead, so Y7 covers region 7
// (0xE000-0xFFFF) plus that carve-out window.
`default_nettype none

module fpla_82s100_addr_decoder (
    input  wire A0,
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire A4,
    input  wire A5,
    input  wire A6,
    input  wire A7,
    input  wire A8,
    input  wire A9,
    input  wire A10,
    input  wire A11,
    input  wire A12,
    input  wire A13,
    input  wire A14,
    input  wire A15,
    output wire Y0,
    output wire Y1,
    output wire Y2,
    output wire Y3,
    output wire Y4,
    output wire Y5,
    output wire Y6,
    output wire Y7
);

    // Top three address bits pick one of the eight 8 KiB regions.
    wire [2:0] region_sel = {A15, A14, A13};

    // Carve-out window 0x6000-0x60FF: region 3 with A12..A8 all zero.
    // A7..A0 are don't-care, which is what makes the window 256 bytes wide.
    wire carve_out_6000 = (region_sel == 3'b011) & ~A12 & ~A11 & ~A10 & ~A9 & ~A8;

    // One-hot region decode, inverted for active-LOW chip selects.
    assign Y0 = ~(region_sel == 3'b000);
    assign Y1 = ~(region_sel == 3'b001);
    assign Y2 = ~(region_sel == 3'b010);
    // Region 3 loses the carve-out window ...
    assign Y3 = ~((region_sel == 3'b011) & ~carve_out_6000);
    assign Y4 = ~(region_sel == 3'b100);
    assign Y5 = ~(region_sel == 3'b101);
    assign Y6 = ~(region_sel == 3'b110);
    // ... which Y7 picks up in addition to region 7.
    assign Y7 = ~((region_sel == 3'b111) | carve_out_6000);

endmodule

`default_nettype wire
