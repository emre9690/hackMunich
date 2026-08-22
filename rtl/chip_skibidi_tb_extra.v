// Supplementary edge-case testbench for bcd_7seg_7447a (SN7447A decoder).
//
// This bench is NOT the source of pass/fail truth for the design: the golden
// vector harness holds that role. It documents boundary conditions and input
// transitions (control-pin priority, ripple-blanking interaction, invalid BCD
// codes, and walking / toggling input sequences) as regression-safety notes.
//
// Segment expectations are given as an active-HIGH "segments on" mask in the
// bit order {a, b, c, d, e, f, g} and compared against the inverted (active
// LOW) outputs of the DUT.
`timescale 1ns / 1ps

module chip_skibidi_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a_n, b_n, c_n, d_n, e_n, f_n, g_n, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_7seg_7447a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a_n(a_n), .b_n(b_n), .c_n(c_n), .d_n(d_n),
        .e_n(e_n), .f_n(f_n), .g_n(g_n),
        .RBO_n(RBO_n)
    );

    wire [6:0] seg_on = ~{a_n, b_n, c_n, d_n, e_n, f_n, g_n};

    // Expected segment masks, {a,b,c,d,e,f,g}, 1 = segment lit.
    localparam [6:0] SEG_BLANK = 7'b0000000;
    localparam [6:0] SEG_ALL   = 7'b1111111;
    localparam [6:0] SEG_0     = 7'b1111110;
    localparam [6:0] SEG_1     = 7'b0110000;
    localparam [6:0] SEG_7     = 7'b1110000;
    localparam [6:0] SEG_8     = 7'b1111111;
    localparam [6:0] SEG_9     = 7'b1110011;
    localparam [6:0] SEG_10    = 7'b0001101;
    localparam [6:0] SEG_15    = 7'b0000000;

    task apply(input [3:0] code, input lt_n, input rbi_n, input bi_n);
        begin
            A = code[0];
            B = code[1];
            C = code[2];
            D = code[3];
            LT_n  = lt_n;
            RBI_n = rbi_n;
            BI_n  = bi_n;
            #5;
        end
    endtask

    task check(input [511:0] name, input [6:0] exp_seg, input exp_rbo_n);
        begin
            if (seg_on === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s (seg_on=%b RBO_n=%b)", name, seg_on, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s expected seg_on=%b RBO_n=%b, got seg_on=%b RBO_n=%b",
                         name, exp_seg, exp_rbo_n, seg_on, RBO_n);
            end
        end
    endtask

    // Convenience: drive then check in one step.
    task step(input [511:0] name, input [3:0] code, input lt_n, input rbi_n,
              input bi_n, input [6:0] exp_seg, input exp_rbo_n);
        begin
            apply(code, lt_n, rbi_n, bi_n);
            check(name, exp_seg, exp_rbo_n);
        end
    endtask

    integer i;

    initial begin
        $display("=== chip_skibidi_tb_extra: supplementary edge-case cases ===");

        // ---- Control-pin priority ----------------------------------------
        // BI_n dominates every other input, including lamp test and a code
        // that would otherwise light segments.
        step("BI_n low blanks digit 8",            4'd8,  1'b1, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        step("BI_n low wins over LT_n low",        4'd8,  1'b0, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        step("BI_n low wins over RBI_n low @ 0",   4'd0,  1'b1, 1'b0, 1'b0, SEG_BLANK, 1'b0);

        // LT_n dominates ripple blanking and the code inputs.
        step("LT_n low lights all (code 0)",       4'd0,  1'b0, 1'b1, 1'b1, SEG_ALL,   1'b1);
        step("LT_n low wins over RBI_n low",       4'd0,  1'b0, 1'b0, 1'b1, SEG_ALL,   1'b1);
        step("LT_n low lights all (code 15)",      4'd15, 1'b0, 1'b1, 1'b1, SEG_ALL,   1'b1);

        // ---- Ripple blanking boundary ------------------------------------
        // Blanking applies only to code 0; RBI_n low on any other code is a
        // no-op for the segments but must still release RBO_n.
        step("RBI_n low blanks zero, RBO_n low",   4'd0,  1'b1, 1'b0, 1'b1, SEG_BLANK, 1'b0);
        step("RBI_n high shows zero, RBO_n high",  4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);
        step("RBI_n low no-op on code 1",          4'd1,  1'b1, 1'b0, 1'b1, SEG_1,     1'b1);
        step("RBI_n low no-op on code 8",          4'd8,  1'b1, 1'b0, 1'b1, SEG_8,     1'b1);

        // ---- Valid/invalid BCD boundary ----------------------------------
        step("last valid code 9",                  4'd9,  1'b1, 1'b1, 1'b1, SEG_9,     1'b1);
        step("first invalid code 10",              4'd10, 1'b1, 1'b1, 1'b1, SEG_10,    1'b1);
        step("all-ones code 15 is blank",          4'd15, 1'b1, 1'b1, 1'b1, SEG_15,    1'b1);
        step("code 15 with RBI_n low still blank", 4'd15, 1'b1, 1'b0, 1'b1, SEG_15,    1'b1);

        // ---- Transitions between input states ----------------------------
        // Leaving a blanked state must restore the decoded digit, and the
        // decoder must not latch anything across the transition.
        step("pre-transition: blanked at 7",       4'd7,  1'b1, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        step("BI_n released restores 7",           4'd7,  1'b1, 1'b1, 1'b1, SEG_7,     1'b1);
        step("lamp test then back to 7",           4'd7,  1'b0, 1'b1, 1'b1, SEG_ALL,   1'b1);
        step("after lamp test, 7 again",           4'd7,  1'b1, 1'b1, 1'b1, SEG_7,     1'b1);
        step("zero blanked, then unblanked",       4'd0,  1'b1, 1'b0, 1'b1, SEG_BLANK, 1'b0);
        step("same zero with RBI_n released",      4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);
        step("9 -> 10 rollover keeps decoding",    4'd9,  1'b1, 1'b1, 1'b1, SEG_9,     1'b1);
        step("10 right after 9",                   4'd10, 1'b1, 1'b1, 1'b1, SEG_10,    1'b1);

        // Toggling a single input bit repeatedly (A between 0 and 1) must
        // track the code with no hysteresis.
        for (i = 0; i < 3; i = i + 1) begin
            step("toggle A: shows 0",              4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);
            step("toggle A: shows 1",              4'd1,  1'b1, 1'b1, 1'b1, SEG_1,     1'b1);
        end

        // Repeated identical stimulus must be idempotent.
        step("idempotent 8 (1st)",                 4'd8,  1'b1, 1'b1, 1'b1, SEG_8,     1'b1);
        step("idempotent 8 (2nd)",                 4'd8,  1'b1, 1'b1, 1'b1, SEG_8,     1'b1);

        $display("=== extra edge-case bench: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
