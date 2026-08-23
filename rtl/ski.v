// SN7447A / SN74LS47 BCD-to-seven-segment decoder/driver
// Active-low segment outputs (0 = segment ON), open-collector OFF modelled as 1.
// Pin 4 (BI/RBO wire-AND node) split into BI_n (externally forced) and
// RBO_n (level reported on the node).
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

    wire [3:0] bcd = {D, C, B, A};

    reg [6:0] seg;   // {a,b,c,d,e,f,g}
    reg       rbo_n;

    always @* begin
        if (BI_n == 1'b0) begin
            // Blanking input: all segments off, node held low.
            seg   = 7'b111_1111;
            rbo_n = 1'b0;
        end else if (LT_n == 1'b0) begin
            // Lamp test: all segments on.
            seg   = 7'b000_0000;
            rbo_n = 1'b1;
        end else if ((RBI_n == 1'b0) && (bcd == 4'd0)) begin
            // Ripple blanking of a leading zero.
            seg   = 7'b111_1111;
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
                default: seg = 7'b1111111;
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = seg;
    assign RBO_n = rbo_n;

endmodule
