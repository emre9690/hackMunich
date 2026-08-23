// SN5446A BCD-to-seven-segment decoder/driver.
// Segment outputs are active low (0 = segment ON). BI_n overrides all other
// inputs; LT_n turns all segments on when BI_n is high; RBI_n blanks a zero
// code. RBO_n mirrors the wire-AND BI/RBO node: low when blanked.
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

    wire blank = ~BI_n | (LT_n & ~RBI_n & (code == 4'd0));
    wire lamp_test = BI_n & ~LT_n;

    assign RBO_n = ~blank;

    // Segments ON (active-low pattern computed as {a,b,c,d,e,f,g} ON bits).
    reg [6:0] seg_on;
    always @* begin
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
        endcase
    end

    wire [6:0] seg_on_eff = blank ? 7'b0000000 :
                            lamp_test ? 7'b1111111 : seg_on;

    assign {a, b, c, d, e, f, g} = ~seg_on_eff;

endmodule
