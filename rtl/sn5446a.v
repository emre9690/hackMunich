// SN5446A BCD-to-seven-segment decoder/driver.
// Active-low segment outputs, active-low LT/RBI/BI controls.
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

    reg [6:0] seg_on;
    always @(*) begin
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
            default: seg_on = 7'b0000000;
        endcase
    end

    wire blank      = ~BI_n;
    wire lamp_test  = BI_n & ~LT_n;
    wire ripple_off = BI_n & LT_n & ~RBI_n & (code == 4'd0);

    reg [6:0] seg_n;
    always @(*) begin
        if (blank)
            seg_n = 7'b1111111;
        else if (lamp_test)
            seg_n = 7'b0000000;
        else if (ripple_off)
            seg_n = 7'b1111111;
        else
            seg_n = ~seg_on;
    end

    assign {a, b, c, d, e, f, g} = seg_n;
    assign RBO_n = ~(blank | ripple_off);

endmodule
