// SN7447A / SN74LS47 BCD-to-seven-segment decoder/driver.
// Segment outputs are active LOW (0 = segment ON).
// Pin 4 (BI/RBO) is modelled as separate BI_n input and RBO_n output.
module bcd_7seg_7447 (
    input  A,
    input  B,
    input  C,
    input  D,
    input  LT_n,
    input  RBI_n,
    input  BI_n,
    output a,
    output b,
    output c,
    output d,
    output e,
    output f,
    output g,
    output RBO_n
);

    wire [3:0] bcd = {D, C, B, A};

    reg [6:0] seg;
    reg       rbo_n_r;

    always @(*) begin
        if (BI_n == 1'b0) begin
            seg     = 7'b1111111;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg     = 7'b0000000;
            rbo_n_r = 1'b1;
        end else if (RBI_n == 1'b0 && bcd == 4'd0) begin
            seg     = 7'b1111111;
            rbo_n_r = 1'b0;
        end else begin
            rbo_n_r = 1'b1;
            case (bcd)
                // seg = {a,b,c,d,e,f,g}
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
                default: seg = 7'b1111111;
            endcase
        end
    end

    assign a = seg[6];
    assign b = seg[5];
    assign c = seg[4];
    assign d = seg[3];
    assign e = seg[2];
    assign f = seg[1];
    assign g = seg[0];
    assign RBO_n = rbo_n_r;

endmodule
