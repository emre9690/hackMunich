// Supplementary edge-case testbench for bcd_to_7seg_sn5546a.
//
// This is NOT the source of pass/fail truth for the design: the exhaustive
// 128-vector check against spec/chips/sn5546a.py (run by harness/check_vectors.py)
// remains authoritative. This testbench documents specific control-priority,
// boundary and input-transition scenarios so that a future regression in those
// behaviours is easy to spot and easy to read.
//
// Expected values below are stated as {a,b,c,d,e,f,g} with active-low segment
// polarity (0 = segment on) plus RBO_n, and are taken from the '46A/'47A
// function table.
`default_nettype none
`timescale 1ns / 1ps

module sn5546a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_to_7seg_sn5546a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Segment patterns (active low, {a,b,c,d,e,f,g}).
    localparam [6:0] SEG_BLANK = 7'b1111111;
    localparam [6:0] SEG_ALLON = 7'b0000000;
    localparam [6:0] SEG_0     = 7'b0000001;
    localparam [6:0] SEG_1     = 7'b1001111;
    localparam [6:0] SEG_8     = 7'b0000000;
    localparam [6:0] SEG_9     = 7'b0001100;
    localparam [6:0] SEG_10    = 7'b1110010;
    localparam [6:0] SEG_14    = 7'b1110000;
    localparam [6:0] SEG_15    = 7'b1111111;

    task drive(input [3:0] code, input lt_n_v, input rbi_n_v, input bi_n_v);
        begin
            A     = code[0];
            B     = code[1];
            C     = code[2];
            D     = code[3];
            LT_n  = lt_n_v;
            RBI_n = rbi_n_v;
            BI_n  = bi_n_v;
            #5;
        end
    endtask

    task check(input [8*48-1:0] name, input [6:0] exp_seg, input exp_rbo_n);
        begin
            if ({a, b, c, d, e, f, g} === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : seg=%b RBO_n=%b", name,
                         {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : seg=%b (exp %b) RBO_n=%b (exp %b)", name,
                         {a, b, c, d, e, f, g}, exp_seg, RBO_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("== sn5546a supplementary edge-case testbench ==");

        // --- Control-input priority ---------------------------------------
        // BI_n dominates every other input, including an asserted lamp test
        // and a code that would otherwise light all segments.
        drive(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n beats LT_n and RBI_n (code 8)", SEG_BLANK, 1'b0);

        // Lamp test beats ripple blanking of a decimal zero.
        drive(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n beats RBI_n at code 0", SEG_ALLON, 1'b1);

        // Lamp test ignores the BCD code entirely.
        drive(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n ignores code 15", SEG_ALLON, 1'b1);

        // --- Ripple blanking boundary -------------------------------------
        // RBI_n only blanks the all-zero code; code 1 decodes normally.
        drive(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks code 0, RBO_n low", SEG_BLANK, 1'b0);

        drive(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank code 1", SEG_1, 1'b1);

        drive(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n high displays zero", SEG_0, 1'b1);

        // --- Blank display vs blanked device ------------------------------
        // Code 15 shows no segments but is a decode, so RBO_n stays high;
        // this distinguishes it from BI_n / RBI_n blanking (RBO_n low).
        drive(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 blank display, RBO_n high", SEG_15, 1'b1);

        // --- Numeric / non-numeric code boundary --------------------------
        drive(4'd9, 1'b1, 1'b1, 1'b1);
        check("code 9 (last numeric)", SEG_9, 1'b1);

        drive(4'd10, 1'b1, 1'b1, 1'b1);
        check("code 10 (first non-numeric)", SEG_10, 1'b1);

        drive(4'd14, 1'b1, 1'b1, 1'b1);
        check("code 14", SEG_14, 1'b1);

        // --- Input transitions --------------------------------------------
        // Walking the code up from 8 and back must settle purely
        // combinationally, with no dependence on the previous state.
        drive(4'd8, 1'b1, 1'b1, 1'b1);
        check("transition ->8", SEG_8, 1'b1);
        drive(4'd15, 1'b1, 1'b1, 1'b1);
        check("transition 8->15", SEG_15, 1'b1);
        drive(4'd8, 1'b1, 1'b1, 1'b1);
        check("transition 15->8 (no state retained)", SEG_8, 1'b1);

        // Blanking pulse must not disturb the decode once released.
        drive(4'd10, 1'b1, 1'b1, 1'b1);
        check("pre-blank decode of code 10", SEG_10, 1'b1);
        drive(4'd10, 1'b1, 1'b1, 1'b0);
        check("blanking pulse asserted", SEG_BLANK, 1'b0);
        drive(4'd10, 1'b1, 1'b1, 1'b1);
        check("decode restored after blanking pulse", SEG_10, 1'b1);

        // RBI_n toggling while sitting on code 0 flips only the zero display.
        drive(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 with RBI_n high", SEG_0, 1'b1);
        drive(4'd0, 1'b1, 1'b0, 1'b1);
        check("code 0 after RBI_n falls", SEG_BLANK, 1'b0);
        drive(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 after RBI_n rises again", SEG_0, 1'b1);

        // Lamp test released while blanking is also requested: BI_n wins.
        drive(4'd3, 1'b0, 1'b1, 1'b1);
        check("lamp test on code 3", SEG_ALLON, 1'b1);
        drive(4'd3, 1'b1, 1'b1, 1'b0);
        check("LT_n released while BI_n low", SEG_BLANK, 1'b0);

        $display("== summary: %0d passed, %0d failed ==", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule

`default_nettype wire
