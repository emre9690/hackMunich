// Supplementary edge-case testbench for bcd_7seg_7447.
//
// This is NOT the source of pass/fail truth for the design: the golden
// model and its exhaustive vector set (run by the external harness) remain
// authoritative. This bench documents boundary conditions and input-state
// transitions as regression-safety documentation, with expected values
// taken from the SN7447A datasheet function table.
//
// Segment outputs are active LOW (0 = segment ON).
// Bus order used below for the 7-bit expectations: {a,b,c,d,e,f,g}.

`timescale 1ns / 1ps

module ski_tb_extra;

    reg  A, B, C, D;
    reg  LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    wire [6:0] seg = {a, b, c, d, e, f, g};

    bcd_7seg_7447 dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    localparam [6:0] BLANK = 7'b1111111;
    localparam [6:0] ALL_ON = 7'b0000000;

    task apply;
        input [3:0] bcd;
        input       lt_n;
        input       rbi_n;
        input       bi_n;
        begin
            A     = bcd[0];
            B     = bcd[1];
            C     = bcd[2];
            D     = bcd[3];
            LT_n  = lt_n;
            RBI_n = rbi_n;
            BI_n  = bi_n;
            #5;
        end
    endtask

    // Applies a stimulus, lets the combinational logic settle and compares
    // both the segment bus and the ripple-blanking output.
    task check;
        input [8*48-1:0] name;
        input [3:0]      bcd;
        input            lt_n;
        input            rbi_n;
        input            bi_n;
        input [6:0]      exp_seg;
        input            exp_rbo_n;
        begin
            apply(bcd, lt_n, rbi_n, bi_n);
            if (seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s: bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, bcd, lt_n, rbi_n, bi_n, seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, bcd, lt_n, rbi_n, bi_n, seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== ski_tb_extra: supplementary edge-case cases for bcd_7seg_7447 ===");

        // ---- Control-input precedence -------------------------------------
        // BI_n dominates every other input, including lamp test and a digit
        // that would otherwise light segments.
        check("BI overrides LT",        4'd8, 1'b0, 1'b1, 1'b0, BLANK, 1'b0);
        check("BI overrides RBI+zero",  4'd0, 1'b1, 1'b0, 1'b0, BLANK, 1'b0);
        check("BI with mid digit",      4'd5, 1'b1, 1'b1, 1'b0, BLANK, 1'b0);

        // Lamp test dominates ripple blanking and the decoded digit, and
        // must leave RBO_n de-asserted (high).
        check("LT overrides RBI+zero",  4'd0, 1'b0, 1'b0, 1'b1, ALL_ON, 1'b1);
        check("LT with digit 15",       4'd15, 1'b0, 1'b1, 1'b1, ALL_ON, 1'b1);

        // ---- Ripple blanking boundary --------------------------------------
        // RBI_n only blanks the digit zero; the very next code must decode
        // normally and release RBO_n.
        check("RBI blanks zero",        4'd0, 1'b1, 1'b0, 1'b1, BLANK, 1'b0);
        check("RBI ignored at one",     4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        check("zero shown when RBI_n=1",4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);

        // Blank-looking outputs must still be distinguishable through RBO_n:
        // code 15 is a decoded blank (RBO_n high) while a ripple-blanked or
        // BI-blanked zero asserts RBO_n low.
        check("code 15 blank pattern",  4'd15, 1'b1, 1'b1, 1'b1, BLANK, 1'b1);

        // ---- Valid/invalid BCD boundary ------------------------------------
        check("last valid digit 9",     4'd9, 1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("first invalid code 10",  4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        check("invalid code 14",        4'd14, 1'b1, 1'b1, 1'b1, 7'b1110000, 1'b1);

        // Digits 6 and 9 have no tail segments on a 7447 (a off for 6,
        // d off for 9) -- an easy place for a decode table to drift.
        check("digit 6 has no seg a",   4'd6, 1'b1, 1'b1, 1'b1, 7'b1100000, 1'b1);
        check("digit 7 minimal",        4'd7, 1'b1, 1'b1, 1'b1, 7'b0001111, 1'b1);
        check("digit 8 all segments",   4'd8, 1'b1, 1'b1, 1'b1, ALL_ON, 1'b1);

        // ---- Transitions between input states ------------------------------
        // Leaving a blanked state must restore the previously driven digit
        // rather than latching the blank.
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check("BI asserted over 3",     4'd3, 1'b1, 1'b1, 1'b0, BLANK, 1'b0);
        check("BI released over 3",     4'd3, 1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);

        // Lamp test entered and left while the data inputs hold a digit.
        check("LT asserted over 2",     4'd2, 1'b0, 1'b1, 1'b1, ALL_ON, 1'b1);
        check("LT released over 2",     4'd2, 1'b1, 1'b1, 1'b1, 7'b0010010, 1'b1);

        // Walking the zero boundary with ripple blanking held active:
        // 1 -> 0 -> 1 must blank only in the middle step.
        check("RBI walk: one",          4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        check("RBI walk: zero",         4'd0, 1'b1, 1'b0, 1'b1, BLANK, 1'b0);
        check("RBI walk: one again",    4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);

        // Releasing RBI_n while sitting on zero must light the zero digit.
        check("RBI released on zero",   4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);

        // 9 -> 10 rollover, i.e. the wrap out of the valid BCD range.
        check("rollover 9",             4'd9, 1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("rollover 10",            4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        check("rollover 15 to 0",       4'd15, 1'b1, 1'b1, 1'b1, BLANK, 1'b1);
        check("rollover back to 0",     4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);

        $display("=== ski_tb_extra: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
