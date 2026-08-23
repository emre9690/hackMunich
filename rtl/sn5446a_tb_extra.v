// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This testbench does NOT replace the golden-model verification
// (spec/chips/sn5446a.py, exhaustively checked by the external harness).
// It documents and exercises specific edge cases and input transitions as
// regression-safety documentation:
//   1. Blanking input (BI_n) overrides lamp test (LT_n).
//   2. Lamp test (LT_n) overrides ripple-blanking (RBI_n) on a zero code.
//   3. Ripple blanking only blanks code 0 (RBI_n low with nonzero code shows digit).
//   4. RBO_n ripple chain behavior across zero/nonzero code transitions.
//   5. Boundary codes: 0, 9 (last BCD digit), 10 (first non-BCD), 15 (blank).
//   6. Transition out of blanking restores normal decoding combinationally.
`timescale 1ns/1ps

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

    wire [6:0] seg_n = {a, b, c, d, e, f, g};  // active-low, order a..g

    task apply(input [3:0] code, input lt_n, input rbi_n, input bi_n);
        begin
            {D, C, B, A} = code;
            LT_n  = lt_n;
            RBI_n = rbi_n;
            BI_n  = bi_n;
            #10;
        end
    endtask

    task check(input [319:0] name, input [6:0] exp_seg_n, input exp_rbo_n);
        begin
            if (seg_n === exp_seg_n && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s  seg_n=%b RBO_n=%b", name, seg_n, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s  seg_n=%b (exp %b) RBO_n=%b (exp %b)",
                         name, seg_n, exp_seg_n, RBO_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        // --- Case 1: BI_n overrides LT_n (both asserted low) -> blank ---
        apply(4'd8, 1'b0, 1'b1, 1'b0);
        check("BI_n overrides LT_n (blank)", 7'b1111111, 1'b0);

        // --- Case 2: LT_n overrides RBI_n on code 0 -> all segments on ---
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n overrides RBI_n at code 0", 7'b0000000, 1'b1);

        // --- Case 3: RBI_n low blanks only code 0 ---
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks code 0", 7'b1111111, 1'b0);
        apply(4'd5, 1'b1, 1'b0, 1'b1);
        check("RBI_n does NOT blank code 5", 7'b0100100, 1'b1);

        // --- Case 4: RBO_n ripple chain across zero/nonzero transitions ---
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("ripple: leading zero -> RBO_n low", 7'b1111111, 1'b0);
        apply(4'd7, 1'b1, 1'b0, 1'b1);
        check("ripple: 0->7 releases RBO_n", 7'b0001111, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("ripple: 7->0 re-asserts RBO_n", 7'b1111111, 1'b0);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("ripple: RBI_n released -> zero shown", 7'b0000001, 1'b1);

        // --- Case 5: boundary codes ---
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("boundary: code 0 (min BCD)", 7'b0000001, 1'b1);
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("boundary: code 9 (max BCD)", 7'b0001100, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("boundary: code 10 (first non-BCD)", 7'b1110010, 1'b1);
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("boundary: code 15 (all segments off)", 7'b1111111, 1'b1);

        // --- Case 6: leaving blanking restores decode combinationally ---
        apply(4'd3, 1'b1, 1'b1, 1'b0);
        check("blanked while code 3", 7'b1111111, 1'b0);
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check("unblank -> code 3 decodes", 7'b0000110, 1'b1);

        $display("RESULT: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
