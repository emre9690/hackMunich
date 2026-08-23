// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness checks the RTL exhaustively (128 vectors) against
// spec/chips/sn5446a.py. This testbench exists as regression-safety
// documentation of the control-input edge cases and of input transitions,
// which an exhaustive static sweep does not describe explicitly:
//   * control-input priority (BI_n > LT_n > RBI_n > decode)
//   * ripple blanking applies to code 0 only, including the 0 <-> 1 and
//     0 <-> 8 code boundaries
//   * RBO_n follows the blanking rules, not the code
//   * decode boundaries 0, 9, 10, 15 (BCD range end / illegal-code region)
//   * glitch-free settling across back-to-back input transitions
//
// Run: iverilog -o sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v
//      ./sn5446a_tb_extra.vvp

`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer passes = 0;
    integer fails  = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Observed {a,b,c,d,e,f,g} (active low) and RBO_n as one 8-bit value.
    function [7:0] observed;
        input dummy;
        begin
            observed = {a, b, c, d, e, f, g, RBO_n};
        end
    endfunction

    task apply;
        input [3:0] code;
        input lt_n_v, rbi_n_v, bi_n_v;
        begin
            A     = code[0];
            B     = code[1];
            C     = code[2];
            D     = code[3];
            LT_n  = lt_n_v;
            RBI_n = rbi_n_v;
            BI_n  = bi_n_v;
            #1;
        end
    endtask

    // Drive the inputs, then compare the settled outputs with the expectation.
    task check;
        input [8*40-1:0] name;
        input [3:0] code;
        input lt_n_v, rbi_n_v, bi_n_v;
        input [6:0] exp_seg_n; // {a,b,c,d,e,f,g}, 0 = segment on
        input exp_rbo_n;
        reg [7:0] got, exp;
        begin
            apply(code, lt_n_v, rbi_n_v, bi_n_v);
            got = observed(0);
            exp = {exp_seg_n, exp_rbo_n};
            if (got === exp) begin
                passes = passes + 1;
                $display("PASS %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg_n=%b RBO_n=%b",
                         name, code, lt_n_v, rbi_n_v, bi_n_v, got[7:1], got[0]);
            end else begin
                fails = fails + 1;
                $display("FAIL %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg_n=%b RBO_n=%b (expected seg_n=%b RBO_n=%b)",
                         name, code, lt_n_v, rbi_n_v, bi_n_v,
                         got[7:1], got[0], exp[7:1], exp[0]);
            end
        end
    endtask

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;
    localparam [6:0] SEG_0   = ~7'b1111110;
    localparam [6:0] SEG_1   = ~7'b0110000;
    localparam [6:0] SEG_8   = ~7'b1111111;
    localparam [6:0] SEG_9   = ~7'b1110011;
    localparam [6:0] SEG_10  = ~7'b0001101;
    localparam [6:0] SEG_15  = ~7'b0000000;

    initial begin
        $display("== sn5446a supplementary edge-case testbench ==");

        // 1. Control priority: BI_n dominates every other input, including
        //    lamp test and a ripple-blank request, and forces RBO_n low.
        check("BI_n beats LT_n",            4'd0,  1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("BI_n beats LT_n+RBI_n",      4'd0,  1'b0, 1'b0, 1'b0, ALL_OFF, 1'b0);
        check("BI_n beats decode (code 8)", 4'd8,  1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("BI_n beats decode (code 15)",4'd15, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // 2. Lamp test dominates ripple blanking and the code, and leaves the
        //    BI/RBO node undriven (RBO_n high).
        check("LT_n beats RBI_n at code 0", 4'd0,  1'b0, 1'b0, 1'b1, ALL_ON, 1'b1);
        check("LT_n ignores code 15",       4'd15, 1'b0, 1'b1, 1'b1, ALL_ON, 1'b1);

        // 3. Ripple blanking is code-0 only: the 0/1 and 0/8 code boundaries
        //    (LSB and MSB adjacency) must still decode normally with RBI_n low.
        check("RBI_n blanks code 0",        4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        check("RBI_n leaves code 1",        4'd1,  1'b1, 1'b0, 1'b1, SEG_1,  1'b1);
        check("RBI_n leaves code 8",        4'd8,  1'b1, 1'b0, 1'b1, SEG_8,  1'b1);
        check("code 0 with RBI_n high",     4'd0,  1'b1, 1'b1, 1'b1, SEG_0,  1'b1);

        // 4. Decode boundaries: last BCD digit and the illegal-code region.
        check("decode 9 (last BCD)",        4'd9,  1'b1, 1'b1, 1'b1, SEG_9,  1'b1);
        check("decode 10 (first illegal)",  4'd10, 1'b1, 1'b1, 1'b1, SEG_10, 1'b1);
        check("decode 15 (blank pattern)",  4'd15, 1'b1, 1'b1, 1'b1, SEG_15, 1'b1);

        // 5. Transitions: outputs must depend only on the settled input state,
        //    with no residue from the previous state.
        check("transition 9 -> 10",         4'd10, 1'b1, 1'b1, 1'b1, SEG_10, 1'b1);
        check("transition 10 -> 9",         4'd9,  1'b1, 1'b1, 1'b1, SEG_9,  1'b1);
        check("transition 9 -> 15",         4'd15, 1'b1, 1'b1, 1'b1, SEG_15, 1'b1);
        check("transition 15 -> 0",         4'd0,  1'b1, 1'b1, 1'b1, SEG_0,  1'b1);

        // 6. Blanking release: leaving BI_n low must restore the decode and
        //    release RBO_n, and re-asserting it must blank again.
        check("blank code 15",              4'd15, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("unblank code 15",            4'd15, 1'b1, 1'b1, 1'b1, SEG_15, 1'b1);
        check("blank again",                4'd15, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // 7. Ripple-blank release while the code stays at 0, i.e. RBO_n
        //    toggling driven only by RBI_n.
        check("rbi asserted at code 0",     4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        check("rbi released at code 0",     4'd0,  1'b1, 1'b1, 1'b1, SEG_0,  1'b1);

        $display("== summary: %0d passed, %0d failed ==", passes, fails);
        if (fails != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
