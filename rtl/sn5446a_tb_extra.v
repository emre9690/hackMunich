// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the harness
// (harness/check_vectors.py) exhaustively checks all 128 input combinations
// against the golden model in spec/chips/sn5446a.py and remains authoritative.
// This testbench documents specific edge cases -- control-input priority,
// decode/blank boundaries, invalid-BCD codes and input-state transitions --
// as regression-safety documentation.
//
// Expected values below are transcribed from the '46A/'47A/'LS47 function
// table (TI SDLS111, page 3): segment outputs are active LOW, so a segment
// that is ON reads 0 and a segment that is OFF reads 1.
//
// Run with:
//   iverilog -o /tmp/sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v
//   vvp /tmp/sn5446a_tb_extra.vvp

`timescale 1ns/1ps
module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer checks;
    integer failures;

    // Active-low expectations for the codes referenced by the cases below.
    localparam [6:0] SEG_ALL_OFF = 7'b1111111;
    localparam [6:0] SEG_ALL_ON  = 7'b0000000;
    localparam [6:0] SEG_0       = 7'b0000001;  // ON: a b c d e f
    localparam [6:0] SEG_1       = 7'b1001111;  // ON: b c
    localparam [6:0] SEG_8       = 7'b0000000;  // ON: a b c d e f g
    localparam [6:0] SEG_9       = 7'b0001100;  // ON: a b c f g
    localparam [6:0] SEG_10      = 7'b1110010;  // ON: d e g
    localparam [6:0] SEG_15      = 7'b1111111;  // ON: none

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Drive one input vector, then compare {a,b,c,d,e,f,g} and RBO_n.
    task check;
        input [127:0] name;         // short label, printed as %0s
        input        i_D, i_C, i_B, i_A;
        input        i_LT_n, i_RBI_n, i_BI_n;
        input  [6:0] exp_seg;
        input        exp_rbo_n;
        reg    [6:0] got_seg;
        begin
            D = i_D; C = i_C; B = i_B; A = i_A;
            LT_n = i_LT_n; RBI_n = i_RBI_n; BI_n = i_BI_n;
            #1;
            got_seg = {a, b, c, d, e, f, g};
            checks = checks + 1;
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                $display("PASS %0s: DCBA=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, i_D, i_C, i_B, i_A, i_LT_n, i_RBI_n, i_BI_n, got_seg, RBO_n);
            end else begin
                failures = failures + 1;
                $display("FAIL %0s: DCBA=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, i_D, i_C, i_B, i_A, i_LT_n, i_RBI_n, i_BI_n,
                         got_seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        checks = 0;
        failures = 0;

        // ---- Case group 1: control-input priority ----------------------
        // BI_n dominates every other input, including a simultaneous lamp
        // test and a ripple-blank condition.
        $display("-- group 1: control priority --");
        check("BI_over_LT",      0,0,0,1, 0, 1, 0, SEG_ALL_OFF, 0);
        check("BI_over_LT_RBI",  0,0,0,0, 0, 0, 0, SEG_ALL_OFF, 0);
        check("BI_over_decode",  1,0,0,1, 1, 1, 0, SEG_ALL_OFF, 0);
        // LT_n dominates ripple blanking (and the code) while BI_n is high.
        check("LT_over_RBI",     0,0,0,0, 0, 0, 1, SEG_ALL_ON,  1);
        check("LT_over_decode",  1,1,1,1, 0, 1, 1, SEG_ALL_ON,  1);

        // ---- Case group 2: ripple-blank boundary -----------------------
        // Ripple blanking applies to code 0 only; code 1 with the same
        // RBI_n=0 must decode normally and release RBO_n.
        $display("-- group 2: ripple-blank boundary --");
        check("RB_zero",         0,0,0,0, 1, 0, 1, SEG_ALL_OFF, 0);
        check("RB_off_zero",     0,0,0,0, 1, 1, 1, SEG_0,       1);
        check("RB_code1",        0,0,0,1, 1, 0, 1, SEG_1,       1);
        check("RB_code8",        1,0,0,0, 1, 0, 1, SEG_8,       1);
        check("RB_code15",       1,1,1,1, 1, 0, 1, SEG_15,      1);

        // ---- Case group 3: BCD/invalid-code boundary -------------------
        // 9 is the last valid BCD digit, 10 the first invalid code, 15 the
        // all-ones code that blanks all segments while RBO_n stays high.
        $display("-- group 3: valid/invalid code boundary --");
        check("code9",           1,0,0,1, 1, 1, 1, SEG_9,       1);
        check("code10",          1,0,1,0, 1, 1, 1, SEG_10,      1);
        check("code15",          1,1,1,1, 1, 1, 1, SEG_15,      1);

        // ---- Case group 4: transitions between input states ------------
        // Each check() re-drives the inputs from the previous state, so the
        // sequences below exercise transitions, not just isolated vectors.
        $display("-- group 4: transitions --");
        // 9 -> 10: rolling past the last valid digit into invalid codes.
        check("t_9",             1,0,0,1, 1, 1, 1, SEG_9,       1);
        check("t_9_to_10",       1,0,1,0, 1, 1, 1, SEG_10,      1);
        // 15 -> 0: wrap from the all-ones code back to zero.
        check("t_15",            1,1,1,1, 1, 1, 1, SEG_15,      1);
        check("t_15_to_0",       0,0,0,0, 1, 1, 1, SEG_0,       1);
        // RBI_n toggling while the code stays 0: blank, restore, blank.
        check("t_rbi_assert",    0,0,0,0, 1, 0, 1, SEG_ALL_OFF, 0);
        check("t_rbi_release",   0,0,0,0, 1, 1, 1, SEG_0,       1);
        check("t_rbi_reassert",  0,0,0,0, 1, 0, 1, SEG_ALL_OFF, 0);
        // BI_n asserted then released over a live decode of 8.
        check("t_bi_assert",     1,0,0,0, 1, 1, 0, SEG_ALL_OFF, 0);
        check("t_bi_release",    1,0,0,0, 1, 1, 1, SEG_8,       1);
        // Lamp test entered and left while a ripple-blank request is held.
        check("t_lt_enter",      0,0,0,0, 0, 0, 1, SEG_ALL_ON,  1);
        check("t_lt_leave",      0,0,0,0, 1, 0, 1, SEG_ALL_OFF, 0);

        $display("");
        $display("sn5446a_tb_extra: %0d checks, %0d failures -- %0s",
                 checks, failures, (failures == 0) ? "ALL PASS" : "FAILURES PRESENT");
        $finish;
    end

endmodule
