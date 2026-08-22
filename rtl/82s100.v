// 82S100 FPLA programmed as a 16-input address decoder/chip-select generator.
// Outputs Y0..Y7 are active LOW; exactly one output is asserted for any address.
// Address bits A15..A13 normally select the corresponding output, except that
// 0x6000-0x60FF is reassigned from Y3 to Y7. Region 7 also selects Y7.
module fpla_82s100_addr_decoder (
    input  A0,
    input  A1,
    input  A2,
    input  A3,
    input  A4,
    input  A5,
    input  A6,
    input  A7,
    input  A8,
    input  A9,
    input  A10,
    input  A11,
    input  A12,
    input  A13,
    input  A14,
    input  A15,
    output Y0,
    output Y1,
    output Y2,
    output Y3,
    output Y4,
    output Y5,
    output Y6,
    output Y7
);
    wire [2:0] address_region = {A15, A14, A13};

    // A7..A0 are intentionally ignored, covering the entire 0x6000-0x60FF page.
    wire carveout_selected =
        (address_region == 3'b011) & ~A12 & ~A11 & ~A10 & ~A9 & ~A8;

    assign Y0 = ~(address_region == 3'b000);
    assign Y1 = ~(address_region == 3'b001);
    assign Y2 = ~(address_region == 3'b010);
    assign Y3 = ~((address_region == 3'b011) & ~carveout_selected);
    assign Y4 = ~(address_region == 3'b100);
    assign Y5 = ~(address_region == 3'b101);
    assign Y6 = ~(address_region == 3'b110);
    assign Y7 = ~((address_region == 3'b111) | carveout_selected);
endmodule
