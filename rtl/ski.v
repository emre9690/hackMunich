// SN7447A / SN74LS47 BCD-to-seven-segment decoder/driver.
//
// Segment outputs are active LOW (0 = segment ON). The bidirectional
// BI/RBO wire-AND pin is modelled as two signals: BI_n is the level
// externally forced onto the node, RBO_n is the level seen on the node
// (LOW when either the device or the outside world pulls it LOW).
//
// Priority order per the function table:
//   1. BI_n == 0            -> all segments OFF, RBO_n = 0
//   2. LT_n == 0            -> all segments ON,  RBO_n = 1
//   3. RBI_n == 0 && BCD==0 -> all segments OFF, RBO_n = 0 (zero blanking)
//   4. otherwise            -> decode {D,C,B,A}, RBO_n = 1

module bcd_7seg_7447 (
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

    wire [3:0] bcd = {D, C, B, A};

    reg [6:0] seg;  // {a, b, c, d, e, f, g}, 0 = ON, 1 = OFF
    reg       rbo_n;

    always @(*) begin
        if (BI_n == 1'b0) begin
            seg   = 7'b1111111;
            rbo_n = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg   = 7'b0000000;
            rbo_n = 1'b1;
        end else if (RBI_n == 1'b0 && bcd == 4'd0) begin
            seg   = 7'b1111111;
            rbo_n = 1'b0;
        end else begin
            rbo_n = 1'b1;
            case (bcd)
                4'd0:  seg = 7'b0000001;
                4'd1:  seg = 7'b1001111;
                4'd2:  seg = 7'b0010010;
                4'd3:  seg = 7'b0000110;
                4'd4:  seg = 7'b1001100;
                4'd5:  seg = 7'b0100100;
                4'd6:  seg = 7'b1100000;
                4'd7:  seg = 7'b0001111;
                4'd8:  seg = 7'b0000000;
                4'd9:  seg = 7'b0001100;
                4'd10: seg = 7'b1110010;
                4'd11: seg = 7'b1100110;
                4'd12: seg = 7'b1011100;
                4'd13: seg = 7'b0110100;
                4'd14: seg = 7'b1110000;
                4'd15: seg = 7'b1111111;
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = seg;
    assign RBO_n = rbo_n;

endmodule
