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

    wire [3:0] code = {D, C, B, A};

    // Bit order: {a, b, c, d, e, f, g}, 1 = segment on.
    reg [6:0] on;
    always @* begin
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
            default: on = 7'b0000000;
        endcase
    end

    wire zero_blank = (LT_n == 1'b1) && (RBI_n == 1'b0) && (code == 4'd0);

    reg [6:0] seg_on;
    reg       rbo_n_r;
    always @* begin
        if (BI_n == 1'b0) begin
            seg_on  = 7'b0000000;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_on  = 7'b1111111;
            rbo_n_r = 1'b1;
        end else if (zero_blank) begin
            seg_on  = 7'b0000000;
            rbo_n_r = 1'b0;
        end else begin
            seg_on  = on;
            rbo_n_r = 1'b1;
        end
    end

    assign {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = ~seg_on;
    assign RBO_n = rbo_n_r;

endmodule
