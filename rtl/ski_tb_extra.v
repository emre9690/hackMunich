// Supplementary edge-case testbench for bcd_7seg_7447 (rtl/ski.v).
//
// This is NOT the source of pass/fail truth for the design -- the external
// harness checking against the human-owned golden model remains authoritative.
// This bench documents boundary conditions and input-state transitions as
// regression-safety documentation.
//
// Segment outputs are active low (0 = segment lit), as on the 7447.

`timescale 1ns / 1ps

module ski_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer errors = 0;
    integer checks = 0;

    localparam [6:0] SEG_BLANK = 7'b1111111;
    localparam [6:0] SEG_ALL   = 7'b0000000;
    localparam [6:0] SEG_ZERO  = 7'b0000001;
    localparam [6:0] SEG_NINE  = 7'b0001100;
    localparam [6:0] SEG_A     = 7'b1110010;
    localparam [6:0] SEG_F     = 7'b1111111;

    bcd_7seg_7447 dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    task apply;
        input [3:0] value;
        input lt_n_in, rbi_n_in, bi_n_in;
        begin
            D = value[3];
            C = value[2];
            B = value[1];
            A = value[0];
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #1;
        end
    endtask

    task check;
        input [8*48-1:0] name;
        input [6:0] exp_seg;
        input exp_rbo_n;
        reg [6:0] got_seg;
        begin
            checks = checks + 1;
            got_seg = {a, b, c, d, e, f, g};
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                $display("PASS  %0s  seg=%b RBO_n=%b", name, got_seg, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL  %0s  seg=%b (exp %b) RBO_n=%b (exp %b)",
                         name, got_seg, exp_seg, RBO_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== bcd_7seg_7447 supplementary edge-case tests ===");

        // --- Control priority: BI_n dominates everything -------------------
        apply(4'h8, 1'b1, 1'b1, 1'b0);
        check("BI_n asserted with digit 8", SEG_BLANK, 1'b0);

        apply(4'h8, 1'b0, 1'b1, 1'b0);
        check("BI_n beats LT_n (both asserted)", SEG_BLANK, 1'b0);

        apply(4'h0, 1'b0, 1'b0, 1'b0);
        check("BI_n beats LT_n and RBI_n on zero", SEG_BLANK, 1'b0);

        // --- Lamp test outranks ripple blanking ---------------------------
        apply(4'h0, 1'b0, 1'b0, 1'b1);
        check("LT_n beats RBI_n on zero", SEG_ALL, 1'b1);

        apply(4'hF, 1'b0, 1'b1, 1'b1);
        check("LT_n lights all segments on blank code F", SEG_ALL, 1'b1);

        // --- Ripple blanking only applies to zero -------------------------
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("RBI_n asserted on zero blanks, RBO_n low", SEG_BLANK, 1'b0);

        apply(4'h1, 1'b1, 1'b0, 1'b1);
        check("RBI_n asserted on one still displays", 7'b1001111, 1'b1);

        apply(4'h0, 1'b1, 1'b1, 1'b1);
        check("RBI_n released on zero displays zero", SEG_ZERO, 1'b1);

        // --- BCD / non-BCD boundary --------------------------------------
        apply(4'h9, 1'b1, 1'b1, 1'b1);
        check("Last valid BCD digit 9", SEG_NINE, 1'b1);

        apply(4'hA, 1'b1, 1'b1, 1'b1);
        check("First out-of-range code A", SEG_A, 1'b1);

        apply(4'hF, 1'b1, 1'b1, 1'b1);
        check("Code F is blank but RBO_n stays high", SEG_F, 1'b1);

        // --- Transitions between input states ----------------------------
        // 9 -> A -> 9 must return to the digit pattern.
        apply(4'h9, 1'b1, 1'b1, 1'b1);
        apply(4'hA, 1'b1, 1'b1, 1'b1);
        apply(4'h9, 1'b1, 1'b1, 1'b1);
        check("Transition 9->A->9 restores 9", SEG_NINE, 1'b1);

        // Blanking pulse must not latch: 5 -> blank -> 5.
        apply(4'h5, 1'b1, 1'b1, 1'b1);
        apply(4'h5, 1'b1, 1'b1, 1'b0);
        apply(4'h5, 1'b1, 1'b1, 1'b1);
        check("BI_n pulse leaves no residual state", 7'b0100100, 1'b1);

        // Lamp test pulse must not latch: 3 -> lamp test -> 3.
        apply(4'h3, 1'b1, 1'b1, 1'b1);
        apply(4'h3, 1'b0, 1'b1, 1'b1);
        apply(4'h3, 1'b1, 1'b1, 1'b1);
        check("LT_n pulse leaves no residual state", 7'b0000110, 1'b1);

        // Ripple carry chain: zero blanked, then digit change lifts RBO_n.
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        apply(4'h4, 1'b1, 1'b0, 1'b1);
        check("Zero->four with RBI_n low releases RBO_n", 7'b1001100, 1'b1);

        // Walking through every code with RBI_n low: only zero is blanked.
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("Four->zero with RBI_n low re-blanks", SEG_BLANK, 1'b0);

        $display("=== %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EXTRA EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EXTRA EDGE-CASE CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
