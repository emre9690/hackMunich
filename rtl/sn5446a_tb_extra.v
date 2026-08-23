// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is ADDITIONAL regression-safety documentation only. The authoritative
// verification of this design is the exhaustive 128-vector run of the external
// harness against spec/chips/sn5446a.py; nothing here replaces that.
//
// Focus: control-input priority, the ripple-blanking boundary, the
// non-numeric codes 10..15, and transitions between input states (the design
// is combinational, so outputs must settle to the new state with no
// dependence on the previous one).
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Observed segment vector, MSB = a ... LSB = g, active low.
    wire [6:0] seg = {a, b, c, d, e, f, g};

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    task apply;
        input [3:0] code;
        input lt_n_i, rbi_n_i, bi_n_i;
        begin
            D = code[3]; C = code[2]; B = code[1]; A = code[0];
            LT_n  = lt_n_i;
            RBI_n = rbi_n_i;
            BI_n  = bi_n_i;
            #1;
        end
    endtask

    // Applies a stimulus and checks the segment outputs and RBO_n against the
    // expected values, printing one PASS/FAIL line per case.
    task check;
        input [8*48-1:0] name;
        input [3:0] code;
        input lt_n_i, rbi_n_i, bi_n_i;
        input [6:0] exp_seg;
        input exp_rbo_n;
        begin
            apply(code, lt_n_i, rbi_n_i, bi_n_i);
            if (seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b",
                         name, code, lt_n_i, rbi_n_i, bi_n_i, seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b (expected abcdefg=%b RBO_n=%b)",
                         name, code, lt_n_i, rbi_n_i, bi_n_i, seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case testbench ===");

        // 1. Control priority: BI_n low blanks everything, even when LT_n and
        //    RBI_n are also asserted and the code is non-zero.
        check("BI_n dominates LT_n",            4'd8,  1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("BI_n dominates LT_n+RBI_n",      4'd0,  1'b0, 1'b0, 1'b0, ALL_OFF, 1'b0);
        check("BI_n blanks a decoded digit",    4'd5,  1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // 2. Lamp test outranks ripple blanking, and holds RBO_n high.
        check("LT_n dominates RBI_n on zero",   4'd0,  1'b0, 1'b0, 1'b1, ALL_ON,  1'b1);
        check("LT_n ignores the input code",    4'd15, 1'b0, 1'b1, 1'b1, ALL_ON,  1'b1);

        // 3. Ripple-blanking boundary: it applies to code 0 only, and only
        //    while RBI_n is low.
        check("RBI_n low, code 0 -> blanked",   4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        check("RBI_n low, code 1 -> decoded",   4'd1,  1'b1, 1'b0, 1'b1, ~7'b0110000, 1'b1);
        check("RBI_n low, code 8 -> decoded",   4'd8,  1'b1, 1'b0, 1'b1, ~7'b1111111, 1'b1);
        check("RBI_n high, code 0 -> zero",     4'd0,  1'b1, 1'b1, 1'b1, ~7'b1111110, 1'b1);

        // 4. Numeric range endpoints and the visually similar 0 / 8 pair.
        check("digit 0",                        4'd0,  1'b1, 1'b1, 1'b1, ~7'b1111110, 1'b1);
        check("digit 8",                        4'd8,  1'b1, 1'b1, 1'b1, ~7'b1111111, 1'b1);
        check("digit 9 (last numeric)",         4'd9,  1'b1, 1'b1, 1'b1, ~7'b1110011, 1'b1);

        // 5. Non-numeric codes 10..15: distinct patterns, and code 15 is the
        //    only code that blanks all segments while RBO_n stays high.
        check("code 10",                        4'd10, 1'b1, 1'b1, 1'b1, ~7'b0001101, 1'b1);
        check("code 11",                        4'd11, 1'b1, 1'b1, 1'b1, ~7'b0011001, 1'b1);
        check("code 12",                        4'd12, 1'b1, 1'b1, 1'b1, ~7'b0100011, 1'b1);
        check("code 13",                        4'd13, 1'b1, 1'b1, 1'b1, ~7'b1001011, 1'b1);
        check("code 14",                        4'd14, 1'b1, 1'b1, 1'b1, ~7'b0001111, 1'b1);
        check("code 15 blank, RBO_n high",      4'd15, 1'b1, 1'b1, 1'b1, ALL_OFF, 1'b1);

        // 6. Transitions: the previous state must never leak into the next one.
        //    Each pair leaves the design in one state, then moves to another.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("15 -> 0 (blank to zero)",        4'd0,  1'b1, 1'b1, 1'b1, ~7'b1111110, 1'b1);

        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("ripple-blanked 0 -> 9",          4'd9,  1'b1, 1'b1, 1'b1, ~7'b1110011, 1'b1);

        apply(4'd6, 1'b1, 1'b1, 1'b0);
        check("blanked 6 -> decoded 6",         4'd6,  1'b1, 1'b1, 1'b1, ~7'b0011111, 1'b1);

        apply(4'd3, 1'b0, 1'b1, 1'b1);
        check("lamp test -> decoded 3",         4'd3,  1'b1, 1'b1, 1'b1, ~7'b1111001, 1'b1);

        // Releasing RBI_n while the code stays at 0 must un-blank the zero.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("release RBI_n on code 0",        4'd0,  1'b1, 1'b1, 1'b1, ~7'b1111110, 1'b1);

        // Walking a single input bit from 7 to 15 crosses the numeric boundary.
        apply(4'd7, 1'b1, 1'b1, 1'b1);
        check("7 -> 15 via D then C",           4'd15, 1'b1, 1'b1, 1'b1, ALL_OFF, 1'b1);

        $display("=== sn5446a_tb_extra summary: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL EDGE CASES PASSED");
        else
            $display("RESULT: %0d EDGE CASE(S) FAILED", fail_count);
        $finish;
    end

endmodule
