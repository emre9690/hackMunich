// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design; the external
// harness comparison against spec/chips/sn5446a.py (128 exhaustive vectors)
// remains authoritative. This bench documents specific edge cases and input
// transitions as regression-safety documentation:
//   * control-input priority (BI_n > LT_n > RBI_n zero-blank > decode)
//   * ripple blanking applies only to code 0, and only with LT_n high
//   * boundary codes 0, 9, 10, 15 (valid/invalid BCD boundary)
//   * transitions between input states, including glitch-free settling and
//     recovery of the previous pattern after a blank/lamp-test pulse
//   * RBO_n behaviour on the wire-AND BI/RBO node
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer errors = 0;
    integer checks = 0;

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;
    // Active-low segment patterns {a,b,c,d,e,f,g} for the decoded codes used.
    localparam [6:0] SEG_0  = ~7'b1111110;
    localparam [6:0] SEG_8  = ~7'b1111111;
    localparam [6:0] SEG_9  = ~7'b1110011;
    localparam [6:0] SEG_10 = ~7'b0001101;
    localparam [6:0] SEG_15 = ~7'b0000000;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    wire [6:0] seg = {a, b, c, d, e, f, g};

    task apply;
        input [3:0] code;
        input lt_n_i, rbi_n_i, bi_n_i;
        begin
            D = code[3]; C = code[2]; B = code[1]; A = code[0];
            LT_n = lt_n_i; RBI_n = rbi_n_i; BI_n = bi_n_i;
            #5;
        end
    endtask

    task check;
        input [8*48:1] name;
        input [6:0] exp_seg;
        input exp_rbo_n;
        begin
            checks = checks + 1;
            if (seg === exp_seg && RBO_n === exp_rbo_n) begin
                $display("PASS [%0d] %0s : seg=%b RBO_n=%b", checks, name, seg, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s : seg=%b (exp %b) RBO_n=%b (exp %b)",
                         checks, name, seg, exp_seg, RBO_n, exp_rbo_n);
            end
        end
    endtask

    task step;
        input [8*48:1] name;
        input [3:0] code;
        input lt_n_i, rbi_n_i, bi_n_i;
        input [6:0] exp_seg;
        input exp_rbo_n;
        begin
            apply(code, lt_n_i, rbi_n_i, bi_n_i);
            check(name, exp_seg, exp_rbo_n);
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case cases ===");

        // --- Control priority: BI_n dominates every other input ---
        step("BI_n low beats LT_n low (code 8)",   4'd8,  1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        step("BI_n low beats RBI_n low (code 0)",  4'd0,  1'b1, 1'b0, 1'b0, ALL_OFF, 1'b0);
        step("BI_n low, all controls low",         4'd0,  1'b0, 1'b0, 1'b0, ALL_OFF, 1'b0);
        step("BI_n low with invalid code 15",      4'd15, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // --- Lamp test outranks ripple blanking, and holds RBO node high ---
        step("LT_n low beats RBI_n zero-blank",    4'd0,  1'b0, 1'b0, 1'b1, ALL_ON,  1'b1);
        step("LT_n low with code 15",              4'd15, 1'b0, 1'b1, 1'b1, ALL_ON,  1'b1);

        // --- Ripple blanking: only for code 0, only with LT_n high ---
        step("RBI_n low, code 0 -> blank+RBO low", 4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        step("RBI_n low, code 1 -> ignored",       4'd1,  1'b1, 1'b0, 1'b1, ~7'b0110000, 1'b1);
        step("RBI_n low, code 8 -> ignored",       4'd8,  1'b1, 1'b0, 1'b1, SEG_8,   1'b1);
        step("RBI_n high, code 0 -> decodes 0",    4'd0,  1'b1, 1'b1, 1'b1, SEG_0,   1'b1);

        // --- Valid/invalid BCD boundary codes ---
        step("boundary code 9 (last valid BCD)",   4'd9,  1'b1, 1'b1, 1'b1, SEG_9,   1'b1);
        step("boundary code 10 (first invalid)",   4'd10, 1'b1, 1'b1, 1'b1, SEG_10,  1'b1);
        step("code 15 -> all segments off",        4'd15, 1'b1, 1'b1, 1'b1, SEG_15,  1'b1);

        // --- Transitions between input states ---
        // 9 -> 10 crosses the valid/invalid boundary in one step.
        step("settle on code 9 before transition", 4'd9,  1'b1, 1'b1, 1'b1, SEG_9,   1'b1);
        step("transition 9 -> 10",                 4'd10, 1'b1, 1'b1, 1'b1, SEG_10,  1'b1);
        // Blank pulse must restore the previous pattern afterwards.
        step("pre-blank state (code 8)",            4'd8, 1'b1, 1'b1, 1'b1, SEG_8,   1'b1);
        step("blank pulse asserted",                4'd8, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);
        step("recovery after blank pulse",          4'd8, 1'b1, 1'b1, 1'b1, SEG_8,   1'b1);
        // Lamp-test pulse must likewise be non-destructive.
        step("lamp-test pulse asserted",            4'd8, 1'b0, 1'b1, 1'b1, ALL_ON,  1'b1);
        step("recovery after lamp-test pulse",      4'd8, 1'b1, 1'b1, 1'b1, SEG_8,   1'b1);
        // RBI_n toggling while sitting on code 0 moves in and out of blanking.
        step("code 0 blanked by RBI_n fall",        4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        step("code 0 unblanked by RBI_n rise",      4'd0, 1'b1, 1'b1, 1'b1, SEG_0,   1'b1);
        // Leaving code 0 while RBI_n stays low releases RBO_n.
        step("0 -> 1 with RBI_n held low",          4'd1, 1'b1, 1'b0, 1'b1, ~7'b0110000, 1'b1);
        step("1 -> 0 with RBI_n held low",          4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);

        $display("=== sn5446a_tb_extra: %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EDGE CASES PASS");
        else
            $display("RESULT: %0d EDGE CASE(S) FAILED", errors);
        $finish;
    end

endmodule
