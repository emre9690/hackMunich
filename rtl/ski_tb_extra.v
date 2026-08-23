// Supplementary edge-case testbench for bcd_7seg_7447.
//
// This is NOT the source of pass/fail truth for the design: the golden model
// and its vector harness remain authoritative. This testbench documents
// boundary conditions, control-pin priority and input-state transitions as
// regression-safety documentation.
//
// Expected values below are taken from the 7447 BCD-to-7-segment decoder
// datasheet behaviour (outputs active low, 0 = segment ON):
//   BI_n  = 0            -> all segments off, RBO_n = 0 (highest priority)
//   LT_n  = 0, BI_n = 1  -> all segments on,  RBO_n = 1 (ignores BCD inputs)
//   RBI_n = 0, BCD = 0   -> all segments off, RBO_n = 0 (ripple blank)
//   otherwise            -> decoded digit,    RBO_n = 1
//
// Run: iverilog -o ski_tb_extra rtl/ski.v rtl/ski_tb_extra.v && ./ski_tb_extra

`default_nettype none
`timescale 1ns / 1ps

module ski_tb_extra;

    reg  A, B, C, D;
    reg  LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam [6:0] ALL_OFF = 7'b111_1111;
    localparam [6:0] ALL_ON  = 7'b000_0000;

    bcd_7seg_7447 dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    wire [6:0] seg = {a, b, c, d, e, f, g};

    // Datasheet segment patterns, indexed by BCD value.
    function [6:0] digit_pattern;
        input [3:0] value;
        begin
            case (value)
                4'd0:  digit_pattern = 7'b0000001;
                4'd1:  digit_pattern = 7'b1001111;
                4'd2:  digit_pattern = 7'b0010010;
                4'd3:  digit_pattern = 7'b0000110;
                4'd4:  digit_pattern = 7'b1001100;
                4'd5:  digit_pattern = 7'b0100100;
                4'd6:  digit_pattern = 7'b1100000;
                4'd7:  digit_pattern = 7'b0001111;
                4'd8:  digit_pattern = 7'b0000000;
                4'd9:  digit_pattern = 7'b0001100;
                4'd10: digit_pattern = 7'b1110010;
                4'd11: digit_pattern = 7'b1100110;
                4'd12: digit_pattern = 7'b1011100;
                4'd13: digit_pattern = 7'b0110100;
                4'd14: digit_pattern = 7'b1110000;
                4'd15: digit_pattern = 7'b1111111;
                default: digit_pattern = 7'b1111111;
            endcase
        end
    endfunction

    task apply;
        input [3:0] bcd;
        input       lt_n_in;
        input       rbi_n_in;
        input       bi_n_in;
        begin
            A     = bcd[0];
            B     = bcd[1];
            C     = bcd[2];
            D     = bcd[3];
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #5;
        end
    endtask

    task check;
        input [8*64-1:0] name;
        input [6:0]      expected_seg;
        input            expected_rbo_n;
        begin
            if (seg === expected_seg && RBO_n === expected_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | in=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b seg=%b RBO_n=%b",
                         name, D, C, B, A, LT_n, RBI_n, BI_n, seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | in=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b seg=%b (exp %b) RBO_n=%b (exp %b)",
                         name, D, C, B, A, LT_n, RBI_n, BI_n,
                         seg, expected_seg, RBO_n, expected_rbo_n);
            end
        end
    endtask

    integer i;

    initial begin
        $display("=== ski_tb_extra: supplementary edge-case coverage for bcd_7seg_7447 ===");

        // ------------------------------------------------------------------
        // Case group 1: control-pin priority.
        // BI_n must dominate every other control input and the BCD inputs.
        // ------------------------------------------------------------------
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n=0 overrides simultaneous LT_n=0 and RBI_n=0", ALL_OFF, 1'b0);

        apply(4'd5, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 blanks an otherwise valid digit", ALL_OFF, 1'b0);

        apply(4'd0, 1'b0, 1'b1, 1'b1);
        check("LT_n=0 dominates RBI_n inactive path (lamp test)", ALL_ON, 1'b1);

        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n=0 dominates ripple-blank on BCD=0", ALL_ON, 1'b1);

        // ------------------------------------------------------------------
        // Case group 2: lamp test is independent of the BCD inputs.
        // ------------------------------------------------------------------
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b0, 1'b1, 1'b1);
            check("lamp test ignores BCD inputs", ALL_ON, 1'b1);
        end

        // ------------------------------------------------------------------
        // Case group 3: ripple blanking boundary (BCD=0 vs BCD=1).
        // ------------------------------------------------------------------
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 with BCD=0 blanks and asserts RBO_n low", ALL_OFF, 1'b0);

        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 with BCD=1 still displays, RBO_n high", digit_pattern(4'd1), 1'b1);

        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n=1 with BCD=0 displays zero, RBO_n high", digit_pattern(4'd0), 1'b1);

        // Only the zero code is ripple-blanked: every non-zero code passes through.
        for (i = 1; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b1, 1'b0, 1'b1);
            check("ripple blank affects BCD=0 only", digit_pattern(i[3:0]), 1'b1);
        end

        // ------------------------------------------------------------------
        // Case group 4: valid/invalid BCD boundary (9 -> 10) and code 15.
        // ------------------------------------------------------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("last valid BCD digit (9)", digit_pattern(4'd9), 1'b1);

        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("first invalid code (10) uses datasheet pattern", digit_pattern(4'd10), 1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank but RBO_n stays high", ALL_OFF, 1'b1);

        // ------------------------------------------------------------------
        // Case group 5: input weighting / no pin swaps ({D,C,B,A} ordering).
        // ------------------------------------------------------------------
        apply(4'b0001, 1'b1, 1'b1, 1'b1);
        check("A alone is weight 1", digit_pattern(4'd1), 1'b1);

        apply(4'b0010, 1'b1, 1'b1, 1'b1);
        check("B alone is weight 2", digit_pattern(4'd2), 1'b1);

        apply(4'b0100, 1'b1, 1'b1, 1'b1);
        check("C alone is weight 4", digit_pattern(4'd4), 1'b1);

        apply(4'b1000, 1'b1, 1'b1, 1'b1);
        check("D alone is weight 8", digit_pattern(4'd8), 1'b1);

        // ------------------------------------------------------------------
        // Case group 6: transitions between input states settle correctly,
        // i.e. outputs depend only on the present inputs (no latched state).
        // ------------------------------------------------------------------
        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check("transition setup: display 8", digit_pattern(4'd8), 1'b1);

        apply(4'd8, 1'b1, 1'b1, 1'b0);
        check("8 -> blank via BI_n falling", ALL_OFF, 1'b0);

        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check("blank -> 8 restored via BI_n rising", digit_pattern(4'd8), 1'b1);

        apply(4'd8, 1'b0, 1'b1, 1'b1);
        check("8 -> lamp test via LT_n falling", ALL_ON, 1'b1);

        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check("lamp test -> 8 restored via LT_n rising", digit_pattern(4'd8), 1'b1);

        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("8 -> ripple-blanked zero", ALL_OFF, 1'b0);

        apply(4'd9, 1'b1, 1'b0, 1'b1);
        check("ripple-blanked zero -> 9 with RBI_n still low", digit_pattern(4'd9), 1'b1);

        // Walk the full count sequence 0..15..0 to confirm every transition is
        // memoryless (each state matches its own decode, independent of order).
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            check("ascending count transition", digit_pattern(i[3:0]), 1'b1);
        end
        for (i = 15; i >= 0; i = i - 1) begin
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            check("descending count transition", digit_pattern(i[3:0]), 1'b1);
        end

        // ------------------------------------------------------------------
        // Case group 7: RBO_n is low only while blanked.
        // ------------------------------------------------------------------
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBO_n low during ripple blank", ALL_OFF, 1'b0);

        apply(4'd0, 1'b1, 1'b1, 1'b0);
        check("RBO_n low during forced blank", ALL_OFF, 1'b0);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("RBO_n high for blank code 15 (not a blanking condition)", ALL_OFF, 1'b1);

        $display("=== ski_tb_extra summary: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule

`default_nettype wire
