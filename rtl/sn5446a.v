// SN5446A BCD-to-seven-segment decoder/driver
// Active-low segment outputs, active-low control signals.
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

    reg [6:0] seg_on;   // 1 = segment on, order {a,b,c,d,e,f,g}
    reg [6:0] seg_out;  // active-low outputs
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
            seg_out = 7'b1111111;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_out = 7'b0000000;
            rbo_n_r = 1'b1;
        end else if ((RBI_n == 1'b0) && (code == 4'd0)) begin
            seg_out = 7'b1111111;
            rbo_n_r = 1'b0;
        end else begin
            seg_out = ~seg_on;
            rbo_n_r = 1'b1;
        end
    end

    assign {a, b, c, d, e, f, g} = seg_out;
    assign RBO_n = rbo_n_r;

endmodule
