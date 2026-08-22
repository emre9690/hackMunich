// SN7447A BCD-to-seven-segment decoder/driver.
//
// Segment outputs a_n..g_n are active LOW (0 = segment ON).
// BI_n / RBI_n / LT_n are active LOW inputs; RBO_n is an active LOW output.
// Pin 4 of the real device (BI/RBO) is a bidirectional wire-AND node; here it
// is split into the input BI_n and the output RBO_n, with the wire-AND
// preserved: RBO_n is low when the internal zero-suppression driver pulls it
// low or when BI_n is driven low.

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

    // A is the LSB of the BCD input, D the MSB.
    wire [3:0] bcd_value = {D, C, B, A};

    // Active HIGH segment pattern, bit order {a,b,c,d,e,f,g}.
    // Codes 10..15 reproduce the SN7447A's documented non-numeric patterns.
    reg [6:0] decoded_segments;
    always @* begin
        case (bcd_value)
            4'd0:    decoded_segments = 7'b1111110; // a b c d e f
            4'd1:    decoded_segments = 7'b0110000; // b c
            4'd2:    decoded_segments = 7'b1101101; // a b d e g
            4'd3:    decoded_segments = 7'b1111001; // a b c d g
            4'd4:    decoded_segments = 7'b0110011; // b c f g
            4'd5:    decoded_segments = 7'b1011011; // a c d f g
            4'd6:    decoded_segments = 7'b0011111; // c d e f g
            4'd7:    decoded_segments = 7'b1110000; // a b c
            4'd8:    decoded_segments = 7'b1111111; // a b c d e f g
            4'd9:    decoded_segments = 7'b1110011; // a b c f g
            4'd10:   decoded_segments = 7'b0001101; // d e g
            4'd11:   decoded_segments = 7'b0011001; // c d g
            4'd12:   decoded_segments = 7'b0100011; // b f g
            4'd13:   decoded_segments = 7'b1001011; // a d f g
            4'd14:   decoded_segments = 7'b0001111; // d e f g
            default: decoded_segments = 7'b0000000; // 15: blank
        endcase
    end

    // Ripple blanking: a leading zero is suppressed only when the ripple carry
    // in is asserted, the digit is 0, and lamp test is inactive.
    wire ripple_blank = (LT_n == 1'b1) && (RBI_n == 1'b0) && (bcd_value == 4'd0);

    // Lamp test lights every segment, but blanking input still overrides it.
    wire lamp_test = (BI_n == 1'b1) && (LT_n == 1'b0);

    // Priority (highest first): blanking input, lamp test, ripple blanking,
    // then the decoded digit pattern.
    reg [6:0] segments;
    always @* begin
        if (BI_n == 1'b0)
            segments = 7'b0000000;
        else if (lamp_test)
            segments = 7'b1111111;
        else if (ripple_blank)
            segments = 7'b0000000;
        else
            segments = decoded_segments;
    end

    // Outputs are active LOW, so invert the active HIGH pattern.
    assign {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = ~segments;

    // Wire-AND of the internal zero-suppression driver with the BI_n input.
    assign RBO_n = (BI_n == 1'b0 || ripple_blank) ? 1'b0 : 1'b1;

endmodule

`default_nettype wire
