// BCD to 7-segment decoder/driver, 7447A behavior.
//
// Segment outputs a_n..g_n are active LOW (0 = segment ON).
// LT_n, RBI_n, BI_n are active LOW inputs; RBO_n is an active LOW output.
//
// Priority:
//   BI_n == 0                                  -> all segments off (blanked)
//   LT_n == 0                                  -> all segments on  (lamp test)
//   RBI_n == 0 and digit == 0                  -> all segments off (ripple blank)
//   otherwise                                  -> decode digit 0..15
//
// RBO_n is low only for the ripple-blanking condition
// (LT_n == 1, RBI_n == 0, digit == 0000).

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

    wire [3:0] digit = {D, C, B, A};
    wire zero = (digit == 4'd0);
    wire ripple_blank = (LT_n == 1'b1) && (RBI_n == 1'b0) && zero;

    reg [6:0] seg;

    always @(*) begin
        if (BI_n == 1'b0)
            seg = 7'b111_1111;
        else if (LT_n == 1'b0)
            seg = 7'b000_0000;
        else if (ripple_blank)
            seg = 7'b111_1111;
        else begin
            case (digit)
                4'd0:  seg = 7'b000_0001;
                4'd1:  seg = 7'b100_1111;
                4'd2:  seg = 7'b001_0010;
                4'd3:  seg = 7'b000_0110;
                4'd4:  seg = 7'b100_1100;
                4'd5:  seg = 7'b010_0100;
                4'd6:  seg = 7'b110_0000;
                4'd7:  seg = 7'b000_1111;
                4'd8:  seg = 7'b000_0000;
                4'd9:  seg = 7'b000_1100;
                4'd10: seg = 7'b111_0010;
                4'd11: seg = 7'b110_0110;
                4'd12: seg = 7'b101_1100;
                4'd13: seg = 7'b011_0100;
                4'd14: seg = 7'b111_0000;
                4'd15: seg = 7'b111_1111;
                default: seg = 7'b111_1111;
            endcase
        end
    end

    assign a_n = seg[6];
    assign b_n = seg[5];
    assign c_n = seg[4];
    assign d_n = seg[3];
    assign e_n = seg[2];
    assign f_n = seg[1];
    assign g_n = seg[0];

    assign RBO_n = ripple_blank ? 1'b0 : 1'b1;

endmodule
