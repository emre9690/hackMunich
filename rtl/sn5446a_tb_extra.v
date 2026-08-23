// Supplementary edge-case testbench for bcd_to_7seg_sn5446a (SN5446A).
//
// This is NOT the source of pass/fail truth for the design: the exhaustive
// 128-vector comparison against the human-owned golden model
// (spec/chips/sn5446a.py) run by the external harness remains authoritative.
// This testbench documents, in Verilog, the control-input priority rules and
// input-state transitions that are easy to break in a refactor, so that a
// regression shows up as a readable named failure.
//
// Conventions (see spec/chips/sn5446a.py): all control inputs are active LOW,
// segment outputs are active LOW (0 = segment ON), and BCD code = {D,C,B,A}.
//
// Run: iverilog -o /tmp/tb rtl/sn5446a.v rtl/sn5446a_tb_extra.v && /tmp/tb

`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Drive one input combination and let the combinational logic settle.
    task apply;
        input [3:0] code;
        input lt_n_v, rbi_n_v, bi_n_v;
        begin
            D = code[3]; C = code[2]; B = code[1]; A = code[0];
            LT_n = lt_n_v; RBI_n = rbi_n_v; BI_n = bi_n_v;
            #1;
        end
    endtask

    // Compare current outputs against expectation and report.
    task check;
        input [8*44:1] name;
        input [6:0] exp_seg;
        input exp_rbo_n;
        reg [6:0] got_seg;
        begin
            got_seg = {a, b, c, d, e, f, g};
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s | in D%b C%b B%b A%b LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b",
                         name, D, C, B, A, LT_n, RBI_n, BI_n, got_seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s | in D%b C%b B%b A%b LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b (expected abcdefg=%b RBO_n=%b)",
                         name, D, C, B, A, LT_n, RBI_n, BI_n, got_seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    task expect_stable_over_bcd;
        input [8*44:1] name;
        input lt_n_v, rbi_n_v, bi_n_v;
        input [6:0] exp_seg;
        input exp_rbo_n;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                apply(i[3:0], lt_n_v, rbi_n_v, bi_n_v);
                check(name, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case testbench ===");

        // --- Control-input priority boundaries -----------------------------
        // BI_n outranks every other input, including lamp test.
        apply(4'h8, 1'b0, 1'b0, 1'b0);
        check("BI_n beats LT_n and RBI_n", ALL_OFF, 1'b0);

        // LT_n outranks ripple blanking when the BI/RBO node is high.
        apply(4'h0, 1'b0, 1'b0, 1'b1);
        check("LT_n beats RBI_n at code 0", ALL_ON, 1'b1);

        // Blanking is independent of the BCD code (note 2 of the function table).
        expect_stable_over_bcd("BI_n=0 blanks for every code", 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // Lamp test is likewise independent of the BCD code (note 4).
        expect_stable_over_bcd("LT_n=0 lights all for every code", 1'b0, 1'b1, 1'b1, ALL_ON, 1'b1);

        // --- Ripple blanking applies to code 0 only ------------------------
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 blanks code 0", ALL_OFF, 1'b0);

        // One-hot neighbours of code 0: each single input bit defeats blanking.
        apply(4'h1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 1 (A)", 7'b1001111, 1'b1);
        apply(4'h2, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 2 (B)", 7'b0010010, 1'b1);
        apply(4'h4, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 4 (C)", 7'b1001100, 1'b1);
        apply(4'h8, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 8 (D)", ALL_ON, 1'b1);

        // Code 0 with RBI_n high decodes to a zero glyph, and RBO_n stays high.
        apply(4'h0, 1'b1, 1'b1, 1'b1);
        check("RBI_n=1 shows zero glyph", 7'b0000001, 1'b1);

        // --- Decode-range boundaries: last BCD digit vs first non-BCD code --
        apply(4'h9, 1'b1, 1'b1, 1'b1);
        check("code 9 (last BCD digit)", 7'b0001100, 1'b1);
        apply(4'hA, 1'b1, 1'b1, 1'b1);
        check("code 10 (first non-BCD code)", 7'b1110010, 1'b1);
        apply(4'hF, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank but RBO_n high", ALL_OFF, 1'b1);

        // Code 15 and true blanking look identical on the segments; the
        // RBO_n pin is what distinguishes them.
        apply(4'hF, 1'b1, 1'b1, 1'b1);
        if (RBO_n === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS  code 15 distinguishable from blanking via RBO_n");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  code 15 distinguishable from blanking via RBO_n | RBO_n=%b expected 1", RBO_n);
        end

        // --- Transitions between input states ------------------------------
        // Releasing BI_n must restore the decode of the code held on the inputs.
        apply(4'h3, 1'b1, 1'b1, 1'b0);
        check("hold code 3 blanked", ALL_OFF, 1'b0);
        apply(4'h3, 1'b1, 1'b1, 1'b1);
        check("code 3 restored after BI_n release", 7'b0000110, 1'b1);

        // Releasing LT_n must likewise restore the decode (no latched state).
        apply(4'h6, 1'b0, 1'b1, 1'b1);
        check("hold code 6 in lamp test", ALL_ON, 1'b1);
        apply(4'h6, 1'b1, 1'b1, 1'b1);
        check("code 6 restored after LT_n release", 7'b1100000, 1'b1);

        // Walking 0 -> 1 -> 0 with RBI_n low toggles RBO_n both ways.
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("ripple blank asserted at code 0", ALL_OFF, 1'b0);
        apply(4'h1, 1'b1, 1'b0, 1'b1);
        check("ripple blank released at code 1", 7'b1001111, 1'b1);
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("ripple blank re-asserted at code 0", ALL_OFF, 1'b0);

        // Every adjacent code step 0 -> 15 must be purely combinational, i.e.
        // the same code reached by walking up must match a direct application.
        check_walk_matches_direct;

        $display("=== sn5446a_tb_extra summary: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

    // Walk the BCD codes in sequence, then re-apply each code after a detour
    // through the blanked state; results must be identical (no hidden state).
    task check_walk_matches_direct;
        integer i;
        reg [6:0] walked [0:15];
        reg [6:0] direct;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                apply(i[3:0], 1'b1, 1'b1, 1'b1);
                walked[i] = {a, b, c, d, e, f, g};
            end
            for (i = 0; i < 16; i = i + 1) begin
                apply(4'h0, 1'b1, 1'b1, 1'b0);   // detour: blank
                apply(i[3:0], 1'b1, 1'b1, 1'b1); // re-apply code
                direct = {a, b, c, d, e, f, g};
                if (direct === walked[i]) begin
                    pass_count = pass_count + 1;
                    $display("PASS  code %0d stateless after blanking detour -> abcdefg=%b", i, direct);
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL  code %0d stateless after blanking detour -> abcdefg=%b (walked=%b)",
                             i, direct, walked[i]);
                end
            end
        end
    endtask

endmodule
