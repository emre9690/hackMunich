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
// RBO_n is low for the ripple-blanking condition
// (LT_n == 1, RBI_n == 0, digit == 0000) and also whenever BI_n is low,
// since BI_n/RBO_n share a pin on the real device.

module bcd_7seg_7447a (
    input  wire A,      // BCD input, least significant bit
    input  wire B,
    input  wire C,
    input  wire D,      // BCD input, most significant bit
    input  wire LT_n,   // lamp test        (active low)
    input  wire RBI_n,  // ripple blank in  (active low)
    input  wire BI_n,   // blanking input   (active low)
    output wire a_n,    // segment outputs  (active low: 0 = segment lit)
    output wire b_n,
    output wire c_n,
    output wire d_n,
    output wire e_n,
    output wire f_n,
    output wire g_n,
    output wire RBO_n   // ripple blank out (active low)
);

    // The four BCD inputs viewed as one value; D is the MSB.
    wire [3:0] digit_value;
    wire       digit_is_zero;
    wire       ripple_blank;

    assign digit_value   = {D, C, B, A};
    assign digit_is_zero = (digit_value == 4'd0);

    // A zero digit is blanked only when ripple-blank-in is asserted and the
    // lamp test is inactive (lamp test has higher priority than blanking here).
    assign ripple_blank  = (LT_n == 1'b1) && (RBI_n == 1'b0) && digit_is_zero;

    // Segment pattern, packed as {a_n, b_n, c_n, d_n, e_n, f_n, g_n}:
    // bit 6 drives a_n and bit 0 drives g_n. All bits are active low, so
    // 7'b111_1111 is "display blank" and 7'b000_0000 is "all segments lit".
    reg [6:0] segments_n;

    always @(*) begin
        if (BI_n == 1'b0)
            segments_n = 7'b111_1111;      // blanking input wins over everything
        else if (LT_n == 1'b0)
            segments_n = 7'b000_0000;      // lamp test: light every segment
        else if (ripple_blank)
            segments_n = 7'b111_1111;      // leading-zero suppression
        else begin
            // Codes 10..15 produce the 7447A's non-numeric patterns, not blanks
            // (except code 15, which is blank on the real device).
            case (digit_value)
                4'd0:  segments_n = 7'b000_0001;
                4'd1:  segments_n = 7'b100_1111;
                4'd2:  segments_n = 7'b001_0010;
                4'd3:  segments_n = 7'b000_0110;
                4'd4:  segments_n = 7'b100_1100;
                4'd5:  segments_n = 7'b010_0100;
                4'd6:  segments_n = 7'b110_0000;
                4'd7:  segments_n = 7'b000_1111;
                4'd8:  segments_n = 7'b000_0000;
                4'd9:  segments_n = 7'b000_1100;
                4'd10: segments_n = 7'b111_0010;
                4'd11: segments_n = 7'b110_0110;
                4'd12: segments_n = 7'b101_1100;
                4'd13: segments_n = 7'b011_0100;
                4'd14: segments_n = 7'b111_0000;
                4'd15: segments_n = 7'b111_1111;
                default: segments_n = 7'b111_1111;
            endcase
        end
    end

    assign a_n = segments_n[6];
    assign b_n = segments_n[5];
    assign c_n = segments_n[4];
    assign d_n = segments_n[3];
    assign e_n = segments_n[2];
    assign f_n = segments_n[1];
    assign g_n = segments_n[0];

    // BI_n and RBO_n share a pin on the real part, so a low BI_n also pulls
    // RBO_n low in addition to the ripple-blanking case.
    assign RBO_n = (ripple_blank || (BI_n == 1'b0)) ? 1'b0 : 1'b1;

endmodule
