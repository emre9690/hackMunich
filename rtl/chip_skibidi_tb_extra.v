// Supplementary edge-case testbench for bcd_7seg_7447a.
// This does NOT replace the golden-model verification harness; it documents
// and exercises boundary conditions and input transitions as regression-safety
// documentation.
`timescale 1ns / 1ps

module chip_skibidi_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a_n, b_n, c_n, d_n, e_n, f_n, g_n, RBO_n;

    integer errors;

    bcd_7seg_7447a dut (
        .A(A),
        .B(B),
        .C(C),
        .D(D),
        .LT_n(LT_n),
        .RBI_n(RBI_n),
        .BI_n(BI_n),
        .a_n(a_n),
        .b_n(b_n),
        .c_n(c_n),
        .d_n(d_n),
        .e_n(e_n),
        .f_n(f_n),
        .g_n(g_n),
        .RBO_n(RBO_n)
    );

    task check;
        input [8*48-1:0] name;
        input [6:0] exp_seg;
        input exp_rbo;
        begin
            #1;
            if ({a_n, b_n, c_n, d_n, e_n, f_n, g_n} === exp_seg && RBO_n === exp_rbo)
                $display("PASS: %0s (seg=%b RBO_n=%b)", name,
                         {a_n, b_n, c_n, d_n, e_n, f_n, g_n}, RBO_n);
            else begin
                errors = errors + 1;
                $display("FAIL: %0s expected seg=%b RBO_n=%b got seg=%b RBO_n=%b",
                         name, exp_seg, exp_rbo,
                         {a_n, b_n, c_n, d_n, e_n, f_n, g_n}, RBO_n);
            end
        end
    endtask

    task drive;
        input [3:0] bcd;
        input lt, rbi, bi;
        begin
            {D, C, B, A} = bcd;
            LT_n  = lt;
            RBI_n = rbi;
            BI_n  = bi;
        end
    endtask

    initial begin
        errors = 0;

        // --- Priority / control-input edge cases ---

        // BI_n dominates everything, including lamp test and non-zero digits
        drive(4'h8, 1'b0, 1'b0, 1'b0);
        check("BI_n overrides LT_n and RBI_n (digit 8)", 7'b1111111, 1'b0);

        drive(4'hF, 1'b1, 1'b1, 1'b0);
        check("BI_n blanks with digit F", 7'b1111111, 1'b0);

        // LT_n dominates RBI_n (ripple blanking must NOT occur during lamp test)
        drive(4'h0, 1'b0, 1'b0, 1'b1);
        check("LT_n overrides RBI_n on zero", 7'b0000000, 1'b1);

        // Lamp test with a non-zero digit still lights all segments
        drive(4'h9, 1'b0, 1'b1, 1'b1);
        check("LT_n lights all segments (digit 9)", 7'b0000000, 1'b1);

        // --- Ripple-blanking boundary cases ---

        // RBI_n low + zero -> blanked, RBO_n low
        drive(4'h0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks zero", 7'b1111111, 1'b0);

        // RBI_n low + smallest non-zero digit -> NOT blanked
        drive(4'h1, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank one", 7'b1001111, 1'b1);

        // RBI_n low + only D set (8) -> NOT blanked (all four bits must be 0)
        drive(4'h8, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank eight", 7'b0000000, 1'b1);

        // Zero with RBI_n high -> displayed normally, RBO_n high
        drive(4'h0, 1'b1, 1'b1, 1'b1);
        check("zero displayed when RBI_n high", 7'b0000001, 1'b1);

        // --- BCD boundary values ---

        // Largest valid BCD digit
        drive(4'h9, 1'b1, 1'b1, 1'b1);
        check("boundary digit 9", 7'b0001100, 1'b1);

        // First invalid BCD code (10)
        drive(4'hA, 1'b1, 1'b1, 1'b1);
        check("first non-BCD code A", 7'b1110010, 1'b1);

        // All-ones input code (15) -> all segments off but RBO_n stays high
        drive(4'hF, 1'b1, 1'b1, 1'b1);
        check("code F blank but RBO_n high", 7'b1111111, 1'b1);

        // --- Input transition sequences ---

        // 9 -> A (valid to invalid BCD transition)
        drive(4'h9, 1'b1, 1'b1, 1'b1);
        #1;
        drive(4'hA, 1'b1, 1'b1, 1'b1);
        check("transition 9 -> A", 7'b1110010, 1'b1);

        // F -> 0 wraparound
        drive(4'hF, 1'b1, 1'b1, 1'b1);
        #1;
        drive(4'h0, 1'b1, 1'b1, 1'b1);
        check("transition F -> 0", 7'b0000001, 1'b1);

        // Releasing blanking restores the current digit
        drive(4'h5, 1'b1, 1'b1, 1'b0);
        check("blanked 5 while BI_n low", 7'b1111111, 1'b0);
        BI_n = 1'b1;
        check("digit 5 restored after BI_n release", 7'b0100100, 1'b1);

        // Releasing RBI_n on zero restores the zero glyph
        drive(4'h0, 1'b1, 1'b0, 1'b1);
        check("zero blanked while RBI_n low", 7'b1111111, 1'b0);
        RBI_n = 1'b1;
        check("zero restored after RBI_n release", 7'b0000001, 1'b1);

        // RBO_n toggles when leaving the blanked-zero condition via data change
        drive(4'h0, 1'b1, 1'b0, 1'b1);
        check("RBO_n low in blanked-zero state", 7'b1111111, 1'b0);
        A = 1'b1;  // 0 -> 1 with RBI_n still low
        check("RBO_n returns high when digit becomes 1", 7'b1001111, 1'b1);

        if (errors == 0)
            $display("ALL EXTRA EDGE-CASE TESTS PASSED");
        else
            $display("%0d EXTRA EDGE-CASE TEST(S) FAILED", errors);
        $finish;
    end

endmodule
