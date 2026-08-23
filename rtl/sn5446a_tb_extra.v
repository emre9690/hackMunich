// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is ADDITIONAL regression-safety documentation only. The exhaustive
// 128-vector check against spec/chips/sn5446a.py remains the sole source of
// pass/fail truth for this design; the cases below just document boundary
// conditions and input-state transitions in an executable form.
//
// Run with Icarus Verilog:
//   iverilog -o /tmp/sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v
//   vvp /tmp/sn5446a_tb_extra.vvp
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer checks = 0;
    integer failures = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Observed segment bus, active low, ordered {a,b,c,d,e,f,g}.
    wire [6:0] seg_n = {a, b, c, d, e, f, g};

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    task apply(input code_d, code_c, code_b, code_a,
               input lt, rbi, bi);
        begin
            D = code_d; C = code_c; B = code_b; A = code_a;
            LT_n = lt; RBI_n = rbi; BI_n = bi;
            #5;
        end
    endtask

    task check(input [511:0] name,
               input [6:0] exp_seg_n,
               input exp_rbo_n);
        begin
            checks = checks + 1;
            if (seg_n === exp_seg_n && RBO_n === exp_rbo_n) begin
                $display("PASS: %0s (seg_n=%b RBO_n=%b)", name, seg_n, RBO_n);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s got seg_n=%b RBO_n=%b, expected seg_n=%b RBO_n=%b",
                         name, seg_n, RBO_n, exp_seg_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a supplementary edge-case testbench ===");

        // --- Control-input priority boundaries ---------------------------

        // BI_n dominates lamp test: both asserted -> blanked, not all-on.
        apply(1, 0, 0, 1, 0, 0, 0);
        check("BI_n low overrides LT_n low (blank wins)", ALL_OFF, 1'b0);

        // BI_n dominates a valid decode of the brightest code (8).
        apply(1, 0, 0, 0, 1, 1, 0);
        check("BI_n low overrides decode of code 8", ALL_OFF, 1'b0);

        // LT_n dominates ripple blanking when BI/RBO node is high.
        apply(0, 0, 0, 0, 0, 0, 1);
        check("LT_n low overrides RBI_n low at code 0", ALL_ON, 1'b1);

        // LT_n also dominates a normal decode.
        apply(0, 1, 0, 1, 0, 1, 1);
        check("LT_n low overrides decode of code 5", ALL_ON, 1'b1);

        // --- Ripple-blanking boundary: only code 0 responds -------------

        apply(0, 0, 0, 0, 1, 0, 1);
        check("RBI_n low at code 0 blanks and pulls RBO_n low", ALL_OFF, 1'b0);

        // Code 1 is the immediate neighbour of the response condition.
        apply(0, 0, 0, 1, 1, 0, 1);
        check("RBI_n low at code 1 still decodes '1'", ~7'b0110000, 1'b1);

        // Code 0 with RBI_n high must decode zero (segment g off).
        apply(0, 0, 0, 0, 1, 1, 1);
        check("RBI_n high at code 0 decodes '0'", ~7'b1111110, 1'b1);

        // --- Numeric code boundaries ------------------------------------

        apply(1, 0, 0, 1, 1, 1, 1);
        check("code 9 (last decimal digit)", ~7'b1110011, 1'b1);

        apply(1, 0, 1, 0, 1, 1, 1);
        check("code 10 (first non-decimal code)", ~7'b0001101, 1'b1);

        apply(1, 1, 1, 1, 1, 1, 1);
        check("code 15 (all segments off, RBO_n high)", ALL_OFF, 1'b1);

        // Code 15 blanked-by-BI looks identical on segments but not on RBO_n.
        apply(1, 1, 1, 1, 1, 1, 0);
        check("code 15 with BI_n low distinguished by RBO_n", ALL_OFF, 1'b0);

        // --- Transitions between input states ---------------------------

        // Walk 15 -> 0 -> 15 and confirm the decoder is purely combinational
        // (no state carried across the boundary codes).
        apply(1, 1, 1, 1, 1, 1, 1);
        apply(0, 0, 0, 0, 1, 1, 1);
        check("transition 15 -> 0 settles to '0'", ~7'b1111110, 1'b1);
        apply(1, 1, 1, 1, 1, 1, 1);
        check("transition 0 -> 15 settles to blank", ALL_OFF, 1'b1);

        // Release blanking and confirm the previous decode is restored.
        apply(0, 1, 1, 0, 1, 1, 1);   // code 6
        check("code 6 before blanking", ~7'b0011111, 1'b1);
        apply(0, 1, 1, 0, 1, 1, 0);
        check("code 6 blanked by BI_n", ALL_OFF, 1'b0);
        apply(0, 1, 1, 0, 1, 1, 1);
        check("code 6 restored after BI_n release", ~7'b0011111, 1'b1);

        // Lamp test asserted then released while sitting on code 0 with
        // RBI_n low: output must fall back to the ripple-blanked state.
        apply(0, 0, 0, 0, 0, 0, 1);
        check("lamp test at code 0 with RBI_n low", ALL_ON, 1'b1);
        apply(0, 0, 0, 0, 1, 0, 1);
        check("lamp test released -> ripple blanked again", ALL_OFF, 1'b0);

        // RBI_n toggling under lamp test must not disturb the all-on state.
        apply(0, 0, 0, 0, 0, 1, 1);
        check("lamp test with RBI_n high", ALL_ON, 1'b1);

        // A single-bit input change across the 7/8 boundary (D rising).
        apply(0, 1, 1, 1, 1, 1, 1);
        check("code 7 before D rises", ~7'b1110000, 1'b1);
        apply(1, 0, 0, 0, 1, 1, 1);
        check("code 8 after D rises", ~7'b1111111, 1'b1);

        $display("=== %0d checks, %0d failures ===", checks, failures);
        if (failures == 0)
            $display("RESULT: ALL EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EDGE-CASE CHECK(S) FAILED", failures);
        $finish;
    end

endmodule
