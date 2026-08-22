// 82S100 FPLA programmed as a 16-input address decoder / chip-select generator.
// Outputs Y0..Y7 are active LOW; exactly one output is asserted for any address.
//   Region r = A[15:13] asserts Yr, except:
//     0x6000-0x60FF is carved out of region 3 and owned by Y7
//     region 7 (0xE000-0xFFFF) asserts Y7
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
    wire [2:0] region = {A15, A14, A13};

    // 0x6000-0x60FF: region 3 with A12..A8 all zero (low byte unconstrained)
    wire in_carve = (region == 3'b011) & ~A12 & ~A11 & ~A10 & ~A9 & ~A8;

    assign Y0 = ~(region == 3'b000);
    assign Y1 = ~(region == 3'b001);
    assign Y2 = ~(region == 3'b010);
    assign Y3 = ~((region == 3'b011) & ~in_carve);
    assign Y4 = ~(region == 3'b100);
    assign Y5 = ~(region == 3'b101);
    assign Y6 = ~(region == 3'b110);
    assign Y7 = ~((region == 3'b111) | in_carve);
endmodule
