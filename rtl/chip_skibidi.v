// SN7447A BCD-to-seven-segment decoder/driver.
//
// Segment outputs a_n..g_n are active LOW (0 = segment ON). Pin 4 of the real
// device is one bidirectional wire-AND node; here it is split into the input
// BI_n (external driver) and the output RBO_n (node level).
//
// Priority: BI_n low blanks everything; else LT_n low lights all segments;
// else RBI_n low with code 0 blanks and pulls RBO_n low; else normal decode.

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

    // {a,b,c,d,e,f,g}, active HIGH (1 = segment ON) before inversion.
    reg [6:0] seg_on;
    reg       rbo_n_r;

    always @* begin
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
                4'd0:  seg_on = 7'b1111110; // abcdef
                4'd1:  seg_on = 7'b0110000; // bc
                4'd2:  seg_on = 7'b1101101; // abdeg
                4'd3:  seg_on = 7'b1111001; // abcdg
                4'd4:  seg_on = 7'b0110011; // bcfg
                4'd5:  seg_on = 7'b1011011; // acdfg
                4'd6:  seg_on = 7'b0011111; // cdefg
                4'd7:  seg_on = 7'b1110000; // abc
                4'd8:  seg_on = 7'b1111111; // abcdefg
                4'd9:  seg_on = 7'b1110011; // abcfg
                4'd10: seg_on = 7'b0001101; // deg
                4'd11: seg_on = 7'b0011001; // cdg
                4'd12: seg_on = 7'b0100011; // bfg
                4'd13: seg_on = 7'b1001011; // adfg
                4'd14: seg_on = 7'b0001111; // defg
                default: seg_on = 7'b0000000; // 15: blank
            endcase
        end
    end

    assign a_n = ~seg_on[6];
    assign b_n = ~seg_on[5];
    assign c_n = ~seg_on[4];
    assign d_n = ~seg_on[3];
    assign e_n = ~seg_on[2];
    assign f_n = ~seg_on[1];
    assign g_n = ~seg_on[0];
    assign RBO_n = rbo_n_r;

endmodule
