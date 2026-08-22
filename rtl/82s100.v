// 82S100 FPLA programmed as a 16-input address decoder / chip-select generator.
// Outputs Y0..Y7 are active LOW; exactly one output is low for any address.
//   Region r = A[15:13] asserts Yr, except:
//     0x6000-0x60FF is carved out of region 3 and owned by Y7
//     Y7 also covers all of region 7 (0xE000-0xFFFF)
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

    wire [2:0] region = {A15, A14, A13};

    // 0x6000-0x60FF : region 3 with A12..A8 all zero
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

`default_nettype wire
