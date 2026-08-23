// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design; the external
// harness checking rtl/sn5446a.v against spec/chips/sn5446a.py (128 exhaustive
// vectors) remains authoritative. This testbench documents, as regression
// safety, specific edge cases and input transitions: control-input priority
// (BI_n > LT_n > RBI_n > decode), ripple blanking applying only to code 0,
// the 9->10 BCD/non-BCD boundary, the all-ones code 15 (blank), and glitch-free
// combinational settling across sequences of input changes.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g;
    wire RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Apply one input vector, then compare the settled outputs against the
    // expected segment pattern {a,b,c,d,e,f,g} (active low) and RBO_n.
    task check;
        input [3:0] code;          // {D,C,B,A}
        input lt_n_in;
        input rbi_n_in;
        input bi_n_in;
        input [6:0] exp_seg;
        input exp_rbo_n;
        input [255:0] label;
        begin
            D = code[3]; C = code[2]; B = code[1]; A = code[0];
            LT_n = lt_n_in; RBI_n = rbi_n_in; BI_n = bi_n_in;
            #1;
            if ({a, b, c, d, e, f, g} === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b",
                         label, code, lt_n_in, rbi_n_in, bi_n_in,
                         {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b (expected abcdefg=%b RBO_n=%b)",
                         label, code, lt_n_in, rbi_n_in, bi_n_in,
                         {a, b, c, d, e, f, g}, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case checks ===");

        // --- Control-input priority: BI_n dominates every other input ---
        check(4'd0,  1'b0, 1'b0, 1'b0, 7'b1111111, 1'b0, "BI over LT+RBI, code 0");
        check(4'd8,  1'b0, 1'b1, 1'b0, 7'b1111111, 1'b0, "BI over LT, code 8");
        check(4'd15, 1'b1, 1'b0, 1'b0, 7'b1111111, 1'b0, "BI with code 15");

        // --- Lamp test outranks ripple blanking when BI_n is high ---
        check(4'd0,  1'b0, 1'b0, 1'b1, 7'b0000000, 1'b1, "LT over RBI, code 0");
        check(4'd5,  1'b0, 1'b1, 1'b1, 7'b0000000, 1'b1, "LT ignores code 5");

        // --- Ripple blanking applies to code 0 only ---
        check(4'd0,  1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0, "RBI blanks code 0");
        check(4'd0,  1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1, "code 0 shown when RBI high");
        check(4'd1,  1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1, "RBI does not blank code 1");
        check(4'd8,  1'b1, 1'b0, 1'b1, 7'b0000000, 1'b1, "RBI does not blank code 8");

        // --- BCD / non-BCD boundary around 9 -> 10 ---
        check(4'd9,  1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1, "boundary code 9");
        check(4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1, "boundary code 10");
        check(4'd15, 1'b1, 1'b1, 1'b1, 7'b1111111, 1'b1, "code 15 blank pattern");

        // --- Single-bit input transitions settle to the new decode ---
        check(4'd7,  1'b1, 1'b1, 1'b1, 7'b0001111, 1'b1, "transition step 7");
        check(4'd6,  1'b1, 1'b1, 1'b1, 7'b1100000, 1'b1, "transition 7->6 (A falls)");
        check(4'd14, 1'b1, 1'b1, 1'b1, 7'b1110000, 1'b1, "transition 6->14 (D rises)");

        // --- Returning from a blanked state restores the previous decode ---
        check(4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1, "code 3 before blanking");
        check(4'd3,  1'b1, 1'b1, 1'b0, 7'b1111111, 1'b0, "code 3 blanked by BI");
        check(4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1, "code 3 restored after BI release");

        // --- Lamp test release with RBI low re-enters ripple blanking ---
        check(4'd0,  1'b0, 1'b0, 1'b1, 7'b0000000, 1'b1, "lamp test on code 0");
        check(4'd0,  1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0, "LT release -> RBI blanking");

        $display("=== sn5446a_tb_extra: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EDGE-CASE CHECK(S) FAILED", fail_count);
        $finish;
    end

endmodule
