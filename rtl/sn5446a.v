// SN5446A BCD-to-seven-segment decoder/driver
// Active-low segment outputs, active-low LT_n / RBI_n / BI_n / RBO_n.
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

    // segments_on[6:0] = {a,b,c,d,e,f,g} active-high ON pattern per code
    reg [6:0] segments_on;
    always @(*) begin
        case (code)
            4'd0:  segments_on = 7'b1111110;
            4'd1:  segments_on = 7'b0110000;
            4'd2:  segments_on = 7'b1101101;
            4'd3:  segments_on = 7'b1111001;
            4'd4:  segments_on = 7'b0110011;
            4'd5:  segments_on = 7'b1011011;
            4'd6:  segments_on = 7'b0011111;
            4'd7:  segments_on = 7'b1110000;
            4'd8:  segments_on = 7'b1111111;
            4'd9:  segments_on = 7'b1110011;
            4'd10: segments_on = 7'b0001101;
            4'd11: segments_on = 7'b0011001;
            4'd12: segments_on = 7'b0100011;
            4'd13: segments_on = 7'b1001011;
            4'd14: segments_on = 7'b0001111;
            4'd15: segments_on = 7'b0000000;
            default: segments_on = 7'b0000000;
        endcase
    end

    wire ripple_blank = (RBI_n == 1'b0) && (code == 4'd0);

    reg [6:0] seg_n;
    reg       rbo_n_r;
    always @(*) begin
        if (BI_n == 1'b0) begin
            seg_n   = 7'b1111111;
            rbo_n_r = 1'b0;
        end else if (LT_n == 1'b0) begin
            seg_n   = 7'b0000000;
            rbo_n_r = 1'b1;
        end else if (ripple_blank) begin
            seg_n   = 7'b1111111;
            rbo_n_r = 1'b0;
        end else begin
            seg_n   = ~segments_on;
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
