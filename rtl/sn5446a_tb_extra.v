// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the harness
// (harness/check_vectors.py) exhaustively compares the RTL against the golden
// model in spec/chips/sn5446a.py. This testbench documents specific edge cases
// -- control-input priority, ripple blanking boundaries, code boundaries and
// input transitions -- as regression-safety documentation.
//
// Expected values are written per the '46A function table: segment and RBO_n
// outputs are active low (0 = segment ON).
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // {a,b,c,d,e,f,g,RBO_n} as observed on the DUT.
    function [7:0] observed;
        input dummy;
        begin
            observed = {a, b, c, d, e, f, g, RBO_n};
        end
    endfunction

    task apply;
        input [3:0] code;   // {D,C,B,A}
        input lt_n_v;
        input rbi_n_v;
        input bi_n_v;
        begin
            D = code[3]; C = code[2]; B = code[1]; A = code[0];
            LT_n  = lt_n_v;
            RBI_n = rbi_n_v;
            BI_n  = bi_n_v;
            #1;
        end
    endtask

    task check;
        input [8*48-1:0] name;
        input [7:0] expected;   // {a,b,c,d,e,f,g,RBO_n}
        begin
            if (observed(0) === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n,
                         {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> got seg=%b RBO_n=%b, expected seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n,
                         {a, b, c, d, e, f, g}, RBO_n,
                         expected[7:1], expected[0]);
            end
        end
    endtask

    localparam [7:0] ALL_OFF_RBO_LOW  = {7'b1111111, 1'b0};
    localparam [7:0] ALL_ON_RBO_HIGH  = {7'b0000000, 1'b1};

    integer i;
    reg rbo_sweep_ok;

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case cases ===");

        // --- Control-input priority ---------------------------------------
        // BI_n dominates every other input, including lamp test and a code
        // that would otherwise light segments.
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n overrides LT_n and RBI_n (code 8)", ALL_OFF_RBO_LOW);

        apply(4'd15, 1'b1, 1'b1, 1'b0);
        check("BI_n blanks code 15", ALL_OFF_RBO_LOW);

        // Lamp test dominates ripple blanking when BI/RBO is held high.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n overrides RBI_n at code 0", ALL_ON_RBO_HIGH);

        apply(4'd5, 1'b0, 1'b1, 1'b1);
        check("LT_n lights all segments regardless of code", ALL_ON_RBO_HIGH);

        // --- Ripple-blanking boundary -------------------------------------
        // RBI_n = 0 blanks ONLY the all-zero code; code 1 must still decode.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks decimal zero", ALL_OFF_RBO_LOW);

        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank code 1", {7'b1001111, 1'b1});

        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank code 8", {7'b0000000, 1'b1});

        // Zero with RBI_n high decodes normally (g off, RBO_n high).
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 decodes when RBI_n high", {7'b0000001, 1'b1});

        // --- Code boundaries ----------------------------------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("last decimal code 9", {7'b0001100, 1'b1});

        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("first non-decimal code 10", {7'b1110010, 1'b1});

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank but RBO_n stays high", {7'b1111111, 1'b1});

        // --- Transitions between input states -----------------------------
        // Releasing BI_n must restore the decoded pattern immediately.
        apply(4'd3, 1'b1, 1'b1, 1'b0);
        check("transition: code 3 blanked", ALL_OFF_RBO_LOW);
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check("transition: code 3 restored after BI_n release", {7'b0000110, 1'b1});

        // Leaving lamp test must return to the current code, not stay lit.
        apply(4'd6, 1'b0, 1'b1, 1'b1);
        check("transition: lamp test before code 6", ALL_ON_RBO_HIGH);
        apply(4'd6, 1'b1, 1'b1, 1'b1);
        check("transition: code 6 after leaving lamp test", {7'b1100000, 1'b1});

        // Walking A while RBI_n is asserted: only code 0 blanks, and RBO_n
        // tracks that transition (0 -> 1 -> 0).
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("transition: zero blanked (RBO_n low)", ALL_OFF_RBO_LOW);
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("transition: 0->1 releases RBO_n", {7'b1001111, 1'b1});
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("transition: 1->0 re-asserts RBO_n", ALL_OFF_RBO_LOW);

        // --- RBO_n is high across every code when unblanked ----------------
        rbo_sweep_ok = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            if (RBO_n !== 1'b1) begin
                rbo_sweep_ok = 1'b0;
                $display("FAIL RBO_n high for all codes when unblanked | code=%0d -> RBO_n=%b",
                         i, RBO_n);
            end
        end
        if (rbo_sweep_ok) begin
            pass_count = pass_count + 1;
            $display("PASS RBO_n high for all 16 codes when unblanked");
        end else begin
            fail_count = fail_count + 1;
        end

        $display("=== sn5446a_tb_extra summary: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
