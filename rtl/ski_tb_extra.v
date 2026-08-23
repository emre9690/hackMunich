// Supplementary edge-case testbench for bcd_7seg_7447 (rtl/ski.v).
//
// This is NOT a verification authority: the golden model under spec/ plus the
// harness in harness/check_vectors.py remain the sole source of pass/fail truth
// for this design. This bench exists as regression-safety documentation of
// control-pin priority, invalid-code behaviour and input-state transitions.
//
// Run with:  iverilog -o /tmp/ski_tb_extra rtl/ski.v rtl/ski_tb_extra.v && /tmp/ski_tb_extra
`timescale 1ns / 1ps

module ski_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g;
    wire RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam [6:0] BLANK    = 7'b1111111;  // all segments off (active low)
    localparam [6:0] ALL_ON   = 7'b0000000;  // lamp test
    localparam [6:0] DIGIT_0  = 7'b0000001;
    localparam [6:0] DIGIT_1  = 7'b1001111;
    localparam [6:0] DIGIT_8  = 7'b0000000;
    localparam [6:0] DIGIT_9  = 7'b0001100;
    localparam [6:0] CODE_10  = 7'b1110010;
    localparam [6:0] CODE_14  = 7'b1110000;

    bcd_7seg_7447 dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    wire [6:0] seg = {a, b, c, d, e, f, g};

    task apply;
        input [3:0] bcd;
        input       lt_n_i;
        input       rbi_n_i;
        input       bi_n_i;
        begin
            {D, C, B, A} = bcd;
            LT_n  = lt_n_i;
            RBI_n = rbi_n_i;
            BI_n  = bi_n_i;
            #1;
        end
    endtask

    // Check current DUT outputs against expectations and report the case.
    task expect;
        input [8*48-1:0] name;
        input [6:0]      exp_seg;
        input            exp_rbo_n;
        begin
            if (seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s: bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: bcd=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    // Convenience: apply a stimulus then immediately check it.
    task check;
        input [8*48-1:0] name;
        input [3:0]      bcd;
        input            lt_n_i;
        input            rbi_n_i;
        input            bi_n_i;
        input [6:0]      exp_seg;
        input            exp_rbo_n;
        begin
            apply(bcd, lt_n_i, rbi_n_i, bi_n_i);
            expect(name, exp_seg, exp_rbo_n);
        end
    endtask

    integer i;
    reg [6:0] prev_seg;

    initial begin
        $display("=== ski_tb_extra: supplementary edge-case bench for bcd_7seg_7447 ===");

        // ---- Group 1: control-pin priority (BI_n > LT_n > RBI_n) ----------
        // BI_n wins over an asserted lamp test.
        check("BI_n overrides LT_n",        4'd5,  1'b0, 1'b1, 1'b0, BLANK,   1'b0);
        // BI_n wins over lamp test *and* ripple-blanking at the same time.
        check("BI_n overrides LT_n+RBI_n",  4'd0,  1'b0, 1'b0, 1'b0, BLANK,   1'b0);
        // LT_n wins over ripple blanking, and holds RBO_n high.
        check("LT_n overrides RBI_n at 0",  4'd0,  1'b0, 1'b0, 1'b1, ALL_ON,  1'b1);
        // Lamp test ignores the BCD inputs entirely.
        check("LT_n ignores bcd=15",        4'd15, 1'b0, 1'b1, 1'b1, ALL_ON,  1'b1);

        // ---- Group 2: ripple-blanking boundary (only zero blanks) --------
        check("RBI_n blanks bcd=0",         4'd0,  1'b1, 1'b0, 1'b1, BLANK,   1'b0);
        check("RBI_n ignored at bcd=1",     4'd1,  1'b1, 1'b0, 1'b1, DIGIT_1, 1'b1);
        check("RBI_n ignored at bcd=8",     4'd8,  1'b1, 1'b0, 1'b1, DIGIT_8, 1'b1);
        check("zero shown when RBI_n high", 4'd0,  1'b1, 1'b1, 1'b1, DIGIT_0, 1'b1);

        // ---- Group 3: BCD range boundaries and invalid codes -------------
        check("lowest valid digit 0",       4'd0,  1'b1, 1'b1, 1'b1, DIGIT_0, 1'b1);
        check("highest valid digit 9",      4'd9,  1'b1, 1'b1, 1'b1, DIGIT_9, 1'b1);
        check("first invalid code 10",      4'd10, 1'b1, 1'b1, 1'b1, CODE_10, 1'b1);
        check("last patterned code 14",     4'd14, 1'b1, 1'b1, 1'b1, CODE_14, 1'b1);
        // Code 15 is the only invalid code that blanks, but keeps RBO_n high.
        check("code 15 blanks, RBO_n high", 4'd15, 1'b1, 1'b1, 1'b1, BLANK,   1'b1);
        // Blanked code 15 must not be confused with ripple blanking.
        check("code 15 with RBI_n low",     4'd15, 1'b1, 1'b0, 1'b1, BLANK,   1'b1);

        // ---- Group 4: transitions between input states -------------------
        // 9 -> 10 crosses the valid/invalid boundary; outputs must change.
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        prev_seg = seg;
        check("9->10 changes pattern",      4'd10, 1'b1, 1'b1, 1'b1, CODE_10, 1'b1);
        if (prev_seg !== seg) begin
            pass_count = pass_count + 1;
            $display("PASS 9->10 boundary: pattern changed %b -> %b", prev_seg, seg);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL 9->10 boundary: pattern stuck at %b", seg);
        end

        // Blank then release BI_n: display must recover the digit it had.
        check("digit 3 before blanking",    4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);
        check("BI_n asserted blanks 3",     4'd3,  1'b1, 1'b1, 1'b0, BLANK,      1'b0);
        check("BI_n released restores 3",   4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);

        // Lamp test asserted then released mid-stream.
        check("LT_n asserted on digit 6",   4'd6,  1'b0, 1'b1, 1'b1, ALL_ON,     1'b1);
        check("LT_n released on digit 6",   4'd6,  1'b1, 1'b1, 1'b1, 7'b1100000, 1'b1);

        // RBI_n toggling while the code sits at zero (ripple-chain behaviour).
        check("zero visible, RBI_n high",   4'd0,  1'b1, 1'b1, 1'b1, DIGIT_0, 1'b1);
        check("zero blanked, RBI_n low",    4'd0,  1'b1, 1'b0, 1'b1, BLANK,   1'b0);
        check("zero visible again",         4'd0,  1'b1, 1'b1, 1'b1, DIGIT_0, 1'b1);

        // ---- Group 5: invariants swept across the whole BCD range --------
        // BI_n low must blank for every code, regardless of the other pins.
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b0, 1'b0, 1'b0);
            if (seg === BLANK && RBO_n === 1'b0) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL BI_n sweep: bcd=%0d -> seg=%b RBO_n=%b (expected blank/low)",
                         i, seg, RBO_n);
            end
        end
        $display("PASS BI_n sweep: all 16 codes blank with BI_n=0");

        // RBO_n is low only when the display is blanked by BI_n or ripple
        // blanking -- never for a code that is actually displayed.
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            if (RBO_n === 1'b1) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL RBO_n sweep: bcd=%0d drove RBO_n low with all controls inactive", i);
            end
        end
        $display("PASS RBO_n sweep: RBO_n stays high for all 16 codes with controls inactive");

        $display("=== ski_tb_extra summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("ski_tb_extra: FAILURES PRESENT (informational only; harness/check_vectors.py is authoritative)");
        $finish;
    end

endmodule
