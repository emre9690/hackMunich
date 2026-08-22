// Supplementary edge-case testbench for bcd_7seg_7447 (SN7447A BCD-to-7-seg).
//
// This is NOT the source of pass/fail truth for the design -- the external
// harness checking rtl/ski.v against the human-owned golden model remains the
// only authority. This file documents, as regression-safety notes, a set of
// boundary conditions and input-state transitions: control-input priority
// (BI_n > LT_n > RBI_n), the ripple-blank boundary at BCD 0 vs 1, the
// 9 -> 10 boundary between decimal digits and the datasheet's non-numeric
// patterns, and combinational settling across back-to-back input changes.
//
// Expected values are taken from the SN7447A datasheet truth table; segment
// outputs are active low (0 = segment ON).
//
// Run: iverilog -o ski_tb_extra.vvp rtl/ski.v rtl/ski_tb_extra.v && ./ski_tb_extra.vvp
`timescale 1ns / 1ps

module ski_tb_extra;

    reg  A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_7seg_7447 dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Drive one input state and compare the whole output vector.
    task check;
        input [3:0] bcd;
        input       lt_n;
        input       rbi_n;
        input       bi_n;
        input [6:0] exp_seg;   // {a,b,c,d,e,f,g}
        input       exp_rbo_n;
        input [8*40:1] name;
        reg   [6:0] got_seg;
        begin
            {D, C, B, A} = bcd;
            LT_n  = lt_n;
            RBI_n = rbi_n;
            BI_n  = bi_n;
            #1;
            got_seg = {a, b, c, d, e, f, g};
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s | bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, bcd, lt_n, rbi_n, bi_n, got_seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s | bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, bcd, lt_n, rbi_n, bi_n, got_seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== bcd_7seg_7447 supplementary edge-case testbench ===");

        // --- Control-input priority ---------------------------------------
        // BI_n dominates everything, including lamp test and a live digit.
        $display("-- control priority --");
        check(4'd8, 1'b1, 1'b1, 1'b0, 7'b1111111, 1'b0, "BI_n blanks digit 8");
        check(4'd8, 1'b0, 1'b0, 1'b0, 7'b1111111, 1'b0, "BI_n beats LT_n and RBI_n");
        // LT_n dominates RBI_n and the BCD inputs (but not BI_n).
        check(4'd0, 1'b0, 1'b0, 1'b1, 7'b0000000, 1'b1, "LT_n beats RBI_n at bcd=0");
        check(4'd15, 1'b0, 1'b1, 1'b1, 7'b0000000, 1'b1, "LT_n beats bcd=15");

        // --- Ripple blanking boundary at bcd 0 / 1 ------------------------
        // RBI_n only blanks the zero; the neighbouring code must still show.
        $display("-- ripple-blank boundary --");
        check(4'd0, 1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0, "RBI_n blanks bcd=0, RBO_n low");
        check(4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1, "RBI_n ignored at bcd=1");
        check(4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1, "bcd=0 displayed when RBI_n high");

        // --- Decimal / non-numeric boundary at 9 -> 10 --------------------
        $display("-- 9/10 boundary and code extremes --");
        check(4'd9,  1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1, "last decimal digit 9");
        check(4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1, "first non-numeric code 10");
        check(4'd15, 1'b1, 1'b1, 1'b1, 7'b1111111, 1'b1, "code 15 is blank, RBO_n high");
        // Blank-by-code-15 must be distinguishable from blank-by-BI_n via RBO_n.
        check(4'd15, 1'b1, 1'b1, 1'b0, 7'b1111111, 1'b0, "code 15 vs BI_n differ on RBO_n");

        // --- Transitions between input states ----------------------------
        // Back-to-back changes: outputs must settle purely combinationally,
        // with no dependence on the previously latched state.
        $display("-- transitions --");
        check(4'd8, 1'b1, 1'b1, 1'b1, 7'b0000000, 1'b1, "all segments on via bcd=8");
        check(4'd8, 1'b1, 1'b1, 1'b0, 7'b1111111, 1'b0, "8 -> blanked");
        check(4'd8, 1'b1, 1'b1, 1'b1, 7'b0000000, 1'b1, "blanked -> 8 restored");
        check(4'd0, 1'b1, 1'b0, 1'b1, 7'b1111111, 1'b0, "8 -> ripple-blanked 0");
        check(4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1, "RBI_n released, 0 reappears");
        check(4'd0, 1'b0, 1'b1, 1'b1, 7'b0000000, 1'b1, "0 -> lamp test");
        check(4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1, "lamp test released, 0 again");
        // Single-bit BCD walk across the 7 -> 8 carry boundary.
        check(4'd7, 1'b1, 1'b1, 1'b1, 7'b0001111, 1'b1, "bcd=7 before carry");
        check(4'd8, 1'b1, 1'b1, 1'b1, 7'b0000000, 1'b1, "bcd=8 after carry");

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
