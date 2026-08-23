// SN5446A BCD-to-seven-segment decoder/driver.
// Segment outputs and RBO_n are active low.
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

    wire [3:0] code = {D, C, B, A};

    reg [6:0] seg_n;   // {a,b,c,d,e,f,g}, active low
    reg       rbo_n_r;

    always @(*) begin
        if (BI_n == 1'b0) begin
            seg_n   = 7'b111_1111;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_n   = 7'b000_0000;
            rbo_n_r = 1'b1;
        end else if ((RBI_n == 1'b0) && (code == 4'd0)) begin
            seg_n   = 7'b111_1111;
            rbo_n_r = 1'b0;
        end else begin
            rbo_n_r = 1'b1;
            case (code)
                4'd0:  seg_n = ~7'b111_1110;
                4'd1:  seg_n = ~7'b011_0000;
                4'd2:  seg_n = ~7'b110_1101;
                4'd3:  seg_n = ~7'b111_1001;
                4'd4:  seg_n = ~7'b011_0011;
                4'd5:  seg_n = ~7'b101_1011;
                4'd6:  seg_n = ~7'b001_1111;
                4'd7:  seg_n = ~7'b111_0000;
                4'd8:  seg_n = ~7'b111_1111;
                4'd9:  seg_n = ~7'b111_0011;
                4'd10: seg_n = ~7'b000_1101;
                4'd11: seg_n = ~7'b001_1001;
                4'd12: seg_n = ~7'b010_0011;
                4'd13: seg_n = ~7'b100_1011;
                4'd14: seg_n = ~7'b000_1111;
                4'd15: seg_n = ~7'b000_0000;
                default: seg_n = 7'b111_1111;
            endcase
        end
    end

    assign {a, b, c, d, e, f, g} = seg_n;
    assign RBO_n = rbo_n_r;

endmodule
