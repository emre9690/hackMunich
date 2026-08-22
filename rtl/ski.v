// BCD-to-seven-segment decoder/driver, 7447 behavior.
//   Inputs  A (LSB) .. D (MSB) : BCD value
//           LT_n  : lamp test, active LOW
//           RBI_n : ripple blanking input, active LOW
//           BI_n  : blanking input, active LOW (highest priority)
//   Outputs a..g   : segments, active LOW
//           RBO_n  : ripple blanking output, active LOW
`default_nettype none

module bcd_7seg_7447 (
    input  wire A,
    input  wire B,
    input  wire C,
    input  wire D,
    input  wire LT_n,
    input  wire RBI_n,
    input  wire BI_n,
    output wire a,
    output wire b,
    output wire c,
    output wire d,
    output wire e,
    output wire f,
    output wire g,
    output wire RBO_n
);

    wire [3:0] val = {D, C, B, A};

    wire zero        = (val == 4'd0);
    wire ripple_blank = (RBI_n == 1'b0) && zero && (LT_n == 1'b1);

    reg [6:0] seg; // {a,b,c,d,e,f,g}, active LOW

    always @* begin
        if (BI_n == 1'b0)
            seg = 7'b1111111;              // blanked
        else if (LT_n == 1'b0)
            seg = 7'b0000000;              // lamp test: all segments on
        else if ((RBI_n == 1'b0) && zero)
            seg = 7'b1111111;              // leading-zero blanked
        else begin
            case (val)
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
                default: seg = 7'b1111111; // 15: blank
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = seg;

    assign RBO_n = BI_n & ~ripple_blank;

endmodule

`default_nettype wire
