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

    wire [3:0] code = {D, C, B, A};

    // Active HIGH segment pattern, bit order {a,b,c,d,e,f,g}.
    reg [6:0] decoded;
    always @* begin
        case (code)
            4'd0:  decoded = 7'b1111110; // a b c d e f
            4'd1:  decoded = 7'b0110000; // b c
            4'd2:  decoded = 7'b1101101; // a b d e g
            4'd3:  decoded = 7'b1111001; // a b c d g
            4'd4:  decoded = 7'b0110011; // b c f g
            4'd5:  decoded = 7'b1011011; // a c d f g
            4'd6:  decoded = 7'b0011111; // c d e f g
            4'd7:  decoded = 7'b1110000; // a b c
            4'd8:  decoded = 7'b1111111; // a b c d e f g
            4'd9:  decoded = 7'b1110011; // a b c f g
            4'd10: decoded = 7'b0001101; // d e g
            4'd11: decoded = 7'b0011001; // c d g
            4'd12: decoded = 7'b0100011; // b f g
            4'd13: decoded = 7'b1001011; // a d f g
            4'd14: decoded = 7'b0001111; // d e f g
            default: decoded = 7'b0000000; // 15: blank
        endcase
    end

    wire blank_zero = (LT_n == 1'b1) && (RBI_n == 1'b0) && (code == 4'd0);
    wire lamp_test  = (BI_n == 1'b1) && (LT_n == 1'b0);

    reg [6:0] segments;
    always @* begin
        if (BI_n == 1'b0)
            segments = 7'b0000000;
        else if (lamp_test)
            segments = 7'b1111111;
        else if (blank_zero)
            segments = 7'b0000000;
        else
            segments = decoded;
    end

    assign {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = ~segments;
    assign RBO_n = (BI_n == 1'b0 || blank_zero) ? 1'b0 : 1'b1;

endmodule

`default_nettype wire
