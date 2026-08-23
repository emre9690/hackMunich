// SN5446A BCD-to-seven-segment decoder/driver.
// Segment outputs and RBO_n are active low.
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

    // Bit order within each pattern: {a,b,c,d,e,f,g}, 1 = segment ON.
    reg [6:0] on;
    always @(*) begin
        case (code)
            4'd0:  on = 7'b1111110;
            4'd1:  on = 7'b0110000;
            4'd2:  on = 7'b1101101;
            4'd3:  on = 7'b1111001;
            4'd4:  on = 7'b0110011;
            4'd5:  on = 7'b1011011;
            4'd6:  on = 7'b0011111;
            4'd7:  on = 7'b1110000;
            4'd8:  on = 7'b1111111;
            4'd9:  on = 7'b1110011;
            4'd10: on = 7'b0001101;
            4'd11: on = 7'b0011001;
            4'd12: on = 7'b0100011;
            4'd13: on = 7'b1001011;
            4'd14: on = 7'b0001111;
            4'd15: on = 7'b0000000;
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
            seg_n = ~on;
    end

    assign {a, b, c, d, e, f, g} = seg_n;
    assign RBO_n = ~(blank | ripple_off);

endmodule
