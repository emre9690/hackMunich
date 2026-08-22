// Programmed 82S100 FPLA: 16-input address decoder / chip-select generator.
// Decodes the 64K address space into eight 8K regions selected by the top
// three address bits (A15..A13). Outputs Y0..Y7 are active LOW.
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

    // Top three address bits select one of eight 8K regions.
    wire [2:0] addr_region = {A15, A14, A13};

    // Carve-out window 0x6000-0x60FF: region 3 (0x6000-0x7FFF) with
    // A12..A8 all zero. Addresses in this window are removed from Y3
    // and redirected to Y7 instead.
    wire carveout_hit = (addr_region == 3'b011) & ~A12 & ~A11 & ~A10 & ~A9 & ~A8;

    assign Y0 = ~(addr_region == 3'b000);                    // 0x0000-0x1FFF
    assign Y1 = ~(addr_region == 3'b001);                    // 0x2000-0x3FFF
    assign Y2 = ~(addr_region == 3'b010);                    // 0x4000-0x5FFF
    assign Y3 = ~((addr_region == 3'b011) & ~carveout_hit);  // 0x6000-0x7FFF minus carve-out
    assign Y4 = ~(addr_region == 3'b100);                    // 0x8000-0x9FFF
    assign Y5 = ~(addr_region == 3'b101);                    // 0xA000-0xBFFF
    assign Y6 = ~(addr_region == 3'b110);                    // 0xC000-0xDFFF
    assign Y7 = ~((addr_region == 3'b111) | carveout_hit);   // 0xE000-0xFFFF plus carve-out

endmodule
