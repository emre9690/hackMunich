// SN5446A BCD-to-seven-segment decoder/driver.
// Segment outputs and RBO_n are active low. BI_n / RBO_n model the two halves
// of the physical bidirectional open-collector BI/RBO pin.
`default_nettype none

module bcd_to_7seg_sn5446a (
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

    // {a,b,c,d,e,f,g}, active low
    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    wire [3:0] code = {D, C, B, A};

    reg [6:0] seg;
    reg       rbo_n;

    always @* begin
        if (!BI_n) begin
            seg   = ALL_OFF;
            rbo_n = 1'b0;
        end else if (!LT_n) begin
            seg   = ALL_ON;
            rbo_n = 1'b1;
        end else if (!RBI_n && (code == 4'd0)) begin
            seg   = ALL_OFF;
            rbo_n = 1'b0;
        end else begin
            rbo_n = 1'b1;
            case (code)
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
                default: seg = ALL_OFF;
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = seg;
    assign RBO_n = rbo_n;

endmodule

`default_nettype wire
