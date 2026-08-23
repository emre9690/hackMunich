// SN5446A BCD-to-seven-segment decoder/driver (active-low segment outputs).
module bcd_to_7seg_sn5446a (
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

    wire [3:0] code = {D, C, B, A};

    reg [6:0] seg_on;   // active-high "segment is on", order a..g
    reg [6:0] seg_n;    // active-low outputs
    reg       rbo_n_r;

    always @(*) begin
        case (code)
            4'd0:  seg_on = 7'b1111110;
            4'd1:  seg_on = 7'b0110000;
            4'd2:  seg_on = 7'b1101101;
            4'd3:  seg_on = 7'b1111001;
            4'd4:  seg_on = 7'b0110011;
            4'd5:  seg_on = 7'b1011011;
            4'd6:  seg_on = 7'b0011111;
            4'd7:  seg_on = 7'b1110000;
            4'd8:  seg_on = 7'b1111111;
            4'd9:  seg_on = 7'b1110011;
            4'd10: seg_on = 7'b0001101;
            4'd11: seg_on = 7'b0011001;
            4'd12: seg_on = 7'b0100011;
            4'd13: seg_on = 7'b1001011;
            4'd14: seg_on = 7'b0001111;
            default: seg_on = 7'b0000000;
        endcase

        if (BI_n == 1'b0) begin
            seg_n   = 7'b1111111;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_n   = 7'b0000000;
            rbo_n_r = 1'b1;
        end else if (RBI_n == 1'b0 && code == 4'd0) begin
            seg_n   = 7'b1111111;
            rbo_n_r = 1'b0;
        end else begin
            seg_n   = ~seg_on;
            rbo_n_r = 1'b1;
        end
    end

    assign a = seg_n[6];
    assign b = seg_n[5];
    assign c = seg_n[4];
    assign d = seg_n[3];
    assign e = seg_n[2];
    assign f = seg_n[1];
    assign g = seg_n[0];
    assign RBO_n = rbo_n_r;

endmodule
