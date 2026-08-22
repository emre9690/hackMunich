// Supplementary edge-case testbench for bcd_7seg_7447a.
//
// This is NOT the verification truth source (the design is already
// exhaustively verified against the golden model by the external harness).
// It documents and exercises specific edge cases as regression-safety
// documentation:
//   - control-input priority (BI_n over LT_n over RBI_n)
//   - ripple-blanking only on digit 0
//   - RBO_n behavior, including blank-15 vs ripple-blank-0 distinction
//   - boundary digits and transitions between input states
//
// Run: iverilog -o tb rtl/chip_skibidi.v rtl/chip_skibidi_tb_extra.v && vvp tb

`timescale 1ns/1ps

module chip_skibidi_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
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

    wire [6:0] seg = {a_n, b_n, c_n, d_n, e_n, f_n, g_n};

    task apply;
        input [3:0] digit;
        input lt, rbi, bi;
        begin
            {D, C, B, A} = digit;
            LT_n  = lt;
            RBI_n = rbi;
            BI_n  = bi;
            #10;
        end
    endtask

    task check;
        input [8*40-1:0] name;
        input [6:0] exp_seg;
        input exp_rbo;
        begin
            if (seg === exp_seg && RBO_n === exp_rbo) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s (seg=%b RBO_n=%b)", name, seg, RBO_n);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s (seg=%b exp=%b, RBO_n=%b exp=%b)",
                         name, seg, exp_seg, RBO_n, exp_rbo);
            end
        end
    endtask

    initial begin
        $display("=== bcd_7seg_7447a extra edge-case testbench ===");

        // --- Control priority edge cases ---

        // BI_n low blanks even during lamp test, and forces RBO_n low.
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI over LT: blank", 7'b111_1111, 1'b0);

        // Lamp test overrides ripple blanking (all segments on, RBO_n high).
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT over RBI@0: all on", 7'b000_0000, 1'b1);

        // Lamp test ignores the digit inputs entirely.
        apply(4'd13, 1'b0, 1'b1, 1'b1);
        check("LT with digit 13: all on", 7'b000_0000, 1'b1);

        // --- Ripple blanking edge cases ---

        // RBI_n low with digit 0: blanked, RBO_n asserted.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI@0: ripple blank", 7'b111_1111, 1'b0);

        // RBI_n low with nonzero digit: decodes normally, RBO_n stays high.
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI@1: shows 1", 7'b100_1111, 1'b1);
        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI@8: shows 8", 7'b000_0000, 1'b1);

        // --- Blank-15 vs ripple-blank-0 distinction ---

        // Digit 15 blanks the display but RBO_n must remain high.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("digit 15: blank, RBO high", 7'b111_1111, 1'b1);
        apply(4'd15, 1'b1, 1'b0, 1'b1);
        check("digit 15 + RBI: RBO still high", 7'b111_1111, 1'b1);

        // --- Boundary digits (normal decode) ---

        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("digit 0 decodes", 7'b000_0001, 1'b1);
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("digit 9 (BCD max)", 7'b000_1100, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("digit 10 (first non-BCD)", 7'b111_0010, 1'b1);
        apply(4'd14, 1'b1, 1'b1, 1'b1);
        check("digit 14 (last non-blank)", 7'b111_0000, 1'b1);

        // --- Transitions between input states ---

        // Ripple blank -> increment to 1 with RBI_n still low: display returns.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("transition: ripple blanked", 7'b111_1111, 1'b0);
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("transition: 0->1 unblanks", 7'b100_1111, 1'b1);

        // Back to 0 with RBI_n released mid-stream: 0 must display.
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("transition: RBI released, 0 shows", 7'b000_0001, 1'b1);

        // Blanking released: display recovers immediately (combinational).
        apply(4'd7, 1'b1, 1'b1, 1'b0);
        check("transition: BI blanks 7", 7'b111_1111, 1'b0);
        apply(4'd7, 1'b1, 1'b1, 1'b1);
        check("transition: BI released, 7 shows", 7'b000_1111, 1'b1);

        // Lamp test released back to ripple-blank condition.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("transition: LT during RBI@0", 7'b000_0000, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("transition: LT released, blanks", 7'b111_1111, 1'b0);

        $display("=== %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule
