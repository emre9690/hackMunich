// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness checking rtl/sn5446a.v against spec/chips/sn5446a.py (128 exhaustive
// vectors) remains authoritative. This file documents, in Verilog, the
// boundary conditions and input-state transitions that regressions are most
// likely to break: control-input priority, the RBI_n zero-suppression corner,
// the BCD/non-BCD code boundary, and settling after multi-bit input changes.
//
// Expected values are written out literally per case (a..g are active-low,
// 0 = segment ON) so the checks stand on their own.
//
// Run: iverilog -o /tmp/sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v && vvp /tmp/sn5446a_tb_extra.vvp

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

    wire [6:0] segs = {a, b, c, d, e, f, g};

    // Apply a stimulus and compare the segment bus and RBO_n against the
    // expected values given by the caller.
    task check;
        input [79:0] name;          // 10-character label
        input [3:0]  code;          // {D,C,B,A}
        input        lt, rbi, bi;
        input [6:0]  exp_segs;
        input        exp_rbo;
        begin
            D = code[3];
            C = code[2];
            B = code[1];
            A = code[0];
            LT_n  = lt;
            RBI_n = rbi;
            BI_n  = bi;
            #5;
            if (segs === exp_segs && RBO_n === exp_rbo) begin
                pass_count = pass_count + 1;
                $display("PASS %0s code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b",
                         name, code, lt, rbi, bi, segs, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b (expected abcdefg=%b RBO_n=%b)",
                         name, code, lt, rbi, bi, segs, RBO_n, exp_segs, exp_rbo);
            end
            #5;
        end
    endtask

    initial begin
        $display("== sn5446a supplementary edge-case testbench ==");

        // --- Control-input priority boundaries -------------------------------
        // BI_n dominates every other input, including a simultaneous lamp test
        // and a code that would otherwise light segments.
        $display("-- group: control priority --");
        check("BI>LT     ", 4'd8,  1'b0, 1'b1, 1'b0, 7'b1111111, 1'b0);
        check("BI>RBI0   ", 4'd0,  1'b1, 1'b0, 1'b0, 7'b1111111, 1'b0);
        check("BI>code15 ", 4'd15, 1'b1, 1'b1, 1'b0, 7'b1111111, 1'b0);
        // Lamp test dominates decoding and ripple blanking while BI_n is high.
        check("LT>RBI0   ", 4'd0,  1'b0, 1'b0, 1'b1, 7'b0000000, 1'b1);
        check("LT>code5  ", 4'd5,  1'b0, 1'b1, 1'b1, 7'b0000000, 1'b1);
        // All three controls inactive at once: plain decode of 8.
        check("noCtrl8   ", 4'd8,  1'b1, 1'b1, 1'b1, 7'b0000000, 1'b1);

        // --- Ripple-blanking corner: only code 0 is suppressed ---------------
        $display("-- group: ripple blanking --");
        check("RBI0code0 ", 4'd0,  1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0);
        check("RBI0code1 ", 4'd1,  1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        check("RBI0code8 ", 4'd8,  1'b1, 1'b0, 1'b1, 7'b0000000, 1'b1);
        check("RBI1code0 ", 4'd0,  1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);

        // --- BCD / non-BCD code boundary ------------------------------------
        $display("-- group: code boundaries --");
        check("code0     ", 4'd0,  1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);
        check("code9     ", 4'd9,  1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("code10    ", 4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        check("code15    ", 4'd15, 1'b1, 1'b1, 1'b1, 7'b1111111, 1'b1);

        // --- Transitions between input states -------------------------------
        // Each pair below changes several inputs at once; the second check of
        // the pair confirms the outputs settle at the new state rather than
        // retaining the previous one.
        $display("-- group: transitions --");
        // 9 -> 10: all four code bits change (LSB-carry boundary).
        check("t9        ", 4'd9,  1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("t9to10    ", 4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        // 15 -> 0: wrap from the blank code back to a displayed zero.
        check("t15       ", 4'd15, 1'b1, 1'b1, 1'b1, 7'b1111111, 1'b1);
        check("t15to0    ", 4'd0,  1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);
        // Zero-suppressed 0 -> 1: RBO_n must release as the code leaves zero.
        check("tsup0     ", 4'd0,  1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0);
        check("tsup0to1  ", 4'd1,  1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        // Releasing BI_n while a lamp test is still asserted must reveal the
        // lamp test rather than staying blanked.
        check("tblank8   ", 4'd8,  1'b0, 1'b1, 1'b0, 7'b1111111, 1'b0);
        check("tBIrelease", 4'd8,  1'b0, 1'b1, 1'b1, 7'b0000000, 1'b1);
        // Lamp test released back onto a suppressed zero.
        check("tLT0      ", 4'd0,  1'b0, 1'b0, 1'b1, 7'b0000000, 1'b1);
        check("tLTrelease", 4'd0,  1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0);

        // --- Summary ---------------------------------------------------------
        $display("== %0d passed, %0d failed ==", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
