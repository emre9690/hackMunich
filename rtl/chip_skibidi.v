// SN7447A BCD-to-seven-segment decoder/driver.
// Segment outputs are active LOW (0 = segment on). LT_n, RBI_n, BI_n and
// RBO_n are active LOW. Pin 4 (BI/RBO wire-AND node) is modeled as the
// separate input BI_n and output RBO_n.
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

    // BCD input value, D is the MSB.
    wire [3:0] bcd_value = {D, C, B, A};

    // Raw segment pattern decoded from the BCD value, before the lamp-test,
    // blanking, and ripple-blanking controls are applied.
    // Bit order: {a, b, c, d, e, f, g}, 1 = segment on.
    // Codes 10-14 produce the 7447A's characteristic partial glyphs;
    // code 15 blanks the display.
    reg [6:0] decoded_segments;
    always @* begin
        case (bcd_value)
            4'd0:  decoded_segments = 7'b1111110;
            4'd1:  decoded_segments = 7'b0110000;
            4'd2:  decoded_segments = 7'b1101101;
            4'd3:  decoded_segments = 7'b1111001;
            4'd4:  decoded_segments = 7'b0110011;
            4'd5:  decoded_segments = 7'b1011011;
            4'd6:  decoded_segments = 7'b0011111;
            4'd7:  decoded_segments = 7'b1110000;
            4'd8:  decoded_segments = 7'b1111111;
            4'd9:  decoded_segments = 7'b1110011;
            4'd10: decoded_segments = 7'b0001101;
            4'd11: decoded_segments = 7'b0011001;
            4'd12: decoded_segments = 7'b0100011;
            4'd13: decoded_segments = 7'b1001011;
            4'd14: decoded_segments = 7'b0001111;
            default: decoded_segments = 7'b0000000;
        endcase
    end

    // Ripple blanking: a zero is suppressed (all segments off) when RBI_n is
    // asserted (low) and lamp test is inactive. RBO_n goes low in this case so
    // the neighboring digit can blank its own leading/trailing zero.
    wire ripple_blank_zero = (LT_n == 1'b1) && (RBI_n == 1'b0) && (bcd_value == 4'd0);

    // Final segment pattern after the control inputs are applied.
    // Priority (highest first): BI_n, LT_n, ripple blanking, normal decode.
    reg [6:0] final_segments;
    reg       rbo_n_comb;
    always @* begin
        if (BI_n == 1'b0) begin
            // Blanking input: force all segments off regardless of other inputs.
            final_segments = 7'b0000000;
            rbo_n_comb     = 1'b0;
        end else if (LT_n == 1'b0) begin
            // Lamp test: light all segments.
            final_segments = 7'b1111111;
            rbo_n_comb     = 1'b1;
        end else if (ripple_blank_zero) begin
            final_segments = 7'b0000000;
            rbo_n_comb     = 1'b0;
        end else begin
            final_segments = decoded_segments;
            rbo_n_comb     = 1'b1;
        end
    end

    // Segment outputs are active low, so invert the active-high pattern.
    assign {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = ~final_segments;
    assign RBO_n = rbo_n_comb;

endmodule
