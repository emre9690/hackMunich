// BCD-to-seven-segment decoder/driver (SN5446A/SN5447A family, active-low
// segment outputs). Generated per spec/chips/sn5546a.py.
`default_nettype none

module bcd_to_7seg_sn5546a (
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

    reg [6:0] seg_on;   // bit6..bit0 = a..g, 1 = segment ON
    reg       rbo_n_r;

    always @(*) begin
        if (BI_n == 1'b0) begin
            seg_on  = 7'b0000000;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_on  = 7'b1111111;
            rbo_n_r = 1'b1;
        end else if ((RBI_n == 1'b0) && (code == 4'd0)) begin
            seg_on  = 7'b0000000;
            rbo_n_r = 1'b0;
        end else begin
            rbo_n_r = 1'b1;
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
        end
    end

    assign a = ~seg_on[6];
    assign b = ~seg_on[5];
    assign c = ~seg_on[4];
    assign d = ~seg_on[3];
    assign e = ~seg_on[2];
    assign f = ~seg_on[1];
    assign g = ~seg_on[0];
    assign RBO_n = rbo_n_r;

endmodule

`default_nettype wire
