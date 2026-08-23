// SN5446A BCD-to-seven-segment decoder/driver.
// Segment outputs and RBO_n are active low; BI_n / LT_n / RBI_n are active low.
module bcd_to_7seg_sn5446a (
    input  A,
    input  B,
    input  C,
    input  D,
    input  LT_n,
    input  RBI_n,
    input  BI_n,
    output a,
    output b,
    output c,
    output d,
    output e,
    output f,
    output g,
    output RBO_n
);

    wire [3:0] code = {D, C, B, A};
    wire ripple_blank = (RBI_n == 1'b0) && (code == 4'd0);

    // One bit per segment, MSB = a ... LSB = g, 1 = segment ON.
    reg [6:0] seg_on;

    always @* begin
        if (BI_n == 1'b0)
            seg_on = 7'b0000000;
        else if (LT_n == 1'b0)
            seg_on = 7'b1111111;
        else if (ripple_blank)
            seg_on = 7'b0000000;
        else begin
            case (code)
                4'd0:  seg_on = 7'b1111110;
                4'd1:  seg_on = 7'b0110000;
                4'd2:  seg_on = 7'b1101101;
                4'd3:  seg_on = 7'b1111001;
                4'd4:  seg_on = 7'b0110011;
                4'd5:  seg_on = 7'b1011011;
                4'd6:  seg_on = 7'b0011111;
                4'd7:  seg_on = 7'b1110000;
                4'd8:  seg_on = 7'b1111111;
                4'd9:  seg_on = 7'b1110011;
                4'd10: seg_on = 7'b0001101;
                4'd11: seg_on = 7'b0011001;
                4'd12: seg_on = 7'b0100011;
                4'd13: seg_on = 7'b1001011;
                4'd14: seg_on = 7'b0001111;
                4'd15: seg_on = 7'b0000000;
                default: seg_on = 7'b0000000;
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = ~seg_on;
    assign RBO_n = (BI_n == 1'b0) ? 1'b0
                 : ((LT_n == 1'b1) && ripple_blank) ? 1'b0 : 1'b1;

endmodule
