// BCD to 7-segment decoder/driver, 7447A behavior.
//
// Inputs : A (LSB), B, C, D (MSB) BCD code
//          LT_n  - lamp test, active LOW
//          RBI_n - ripple blanking input, active LOW
//          BI_n  - blanking input, active LOW
// Outputs: a_n..g_n - segment drivers, active LOW (0 = segment lit)
//          RBO_n    - ripple blanking output, active LOW
//
// Priority: BI_n (blank all) > LT_n (all segments on) > ripple blanking
// (RBI_n low with BCD input 0 blanks the digit and asserts RBO_n) > decode.
`default_nettype none

module bcd_7seg_7447a (
    input  wire A,
    input  wire B,
    input  wire C,
    input  wire D,
    input  wire LT_n,
    input  wire RBI_n,
    input  wire BI_n,
    output wire a_n,
    output wire b_n,
    output wire c_n,
    output wire d_n,
    output wire e_n,
    output wire f_n,
    output wire g_n,
    output wire RBO_n
);

    wire [3:0] value = {D, C, B, A};

    // Ripple blanking: input is zero, RBI_n asserted, no lamp test, not blanked.
    wire ripple_blank = (BI_n == 1'b1) && (LT_n == 1'b1) &&
                        (RBI_n == 1'b0) && (value == 4'd0);

    // Active-high segment pattern {a,b,c,d,e,f,g}; 1 = segment lit.
    reg [6:0] seg;

    always @(*) begin
        if (BI_n == 1'b0)
            seg = 7'b0000000;             // blanked
        else if (LT_n == 1'b0)
            seg = 7'b1111111;             // lamp test: all segments on
        else if (ripple_blank)
            seg = 7'b0000000;             // leading-zero suppression
        else begin
            case (value)
                4'd0:  seg = 7'b1111110;
                4'd1:  seg = 7'b0110000;
                4'd2:  seg = 7'b1101101;
                4'd3:  seg = 7'b1111001;
                4'd4:  seg = 7'b0110011;
                4'd5:  seg = 7'b1011011;
                4'd6:  seg = 7'b0011111;
                4'd7:  seg = 7'b1110000;
                4'd8:  seg = 7'b1111111;
                4'd9:  seg = 7'b1110011;
                4'd10: seg = 7'b0001101;
                4'd11: seg = 7'b0011001;
                4'd12: seg = 7'b0100011;
                4'd13: seg = 7'b1001011;
                4'd14: seg = 7'b0001111;
                default: seg = 7'b0000000;
            endcase
        end
    end

    assign a_n = ~seg[6];
    assign b_n = ~seg[5];
    assign c_n = ~seg[4];
    assign d_n = ~seg[3];
    assign e_n = ~seg[2];
    assign f_n = ~seg[1];
    assign g_n = ~seg[0];

    assign RBO_n = ripple_blank ? 1'b0 : 1'b1;

endmodule

`default_nettype wire
