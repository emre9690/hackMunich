// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness checking rtl/sn5446a.v against spec/chips/sn5446a.py (128 exhaustive
// vectors) remains authoritative. This testbench documents control-input
// priority, decode boundaries and input-transition behaviour as regression
// safety notes, using expectations derived from the same datasheet function
// table (TI SDLS111, '46A/'47A/'LS47 table T1).
//
// Run: iverilog -o sim rtl/sn5446a.v rtl/sn5446a_tb_extra.v && ./sim

`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    // Segment vectors are {a,b,c,d,e,f,g}, active LOW.
    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    task apply;
        input [3:0] code;   // {D,C,B,A}
        input lt_n_v;
        input rbi_n_v;
        input bi_n_v;
        begin
            A     = code[0];
            B     = code[1];
            C     = code[2];
            D     = code[3];
            LT_n  = lt_n_v;
            RBI_n = rbi_n_v;
            BI_n  = bi_n_v;
            #5;
        end
    endtask

    task check;
        input [8*64:1] name;
        input [6:0]    exp_seg;
        input          exp_rbo_n;
        reg   [6:0]    got_seg;
        begin
            got_seg = {a, b, c, d, e, f, g};
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s | seg=%b RBO_n=%b", name, got_seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s | seg=%b (exp %b) RBO_n=%b (exp %b)",
                         name, got_seg, exp_seg, RBO_n, exp_rbo_n);
            end
        end
    endtask

    // Expected segment pattern for a plain decode of {D,C,B,A}, from the
    // datasheet function table (segment ON == 0).
    function [6:0] decode_pattern;
        input [3:0] code;
        begin
            case (code)
                4'h0: decode_pattern = 7'b0000001;
                4'h1: decode_pattern = 7'b1001111;
                4'h2: decode_pattern = 7'b0010010;
                4'h3: decode_pattern = 7'b0000110;
                4'h4: decode_pattern = 7'b1001100;
                4'h5: decode_pattern = 7'b0100100;
                4'h6: decode_pattern = 7'b1100000;
                4'h7: decode_pattern = 7'b0001111;
                4'h8: decode_pattern = 7'b0000000;
                4'h9: decode_pattern = 7'b0001100;
                4'ha: decode_pattern = 7'b1110010;
                4'hb: decode_pattern = 7'b1100110;
                4'hc: decode_pattern = 7'b1011100;
                4'hd: decode_pattern = 7'b0110100;
                4'he: decode_pattern = 7'b1110000;
                4'hf: decode_pattern = 7'b1111111;
            endcase
        end
    endfunction

    integer i;
    reg [6:0] seg_before;

    initial begin
        $display("=== sn5446a supplementary edge-case testbench ===");

        // ------------------------------------------------------------------
        // 1. Control-input priority edges: BI_n dominates every other input.
        // ------------------------------------------------------------------
        apply(4'h8, 1'b0, 1'b0, 1'b0);
        check("BI_n=0 wins over LT_n=0 and RBI_n=0 (code 8)", ALL_OFF, 1'b0);

        apply(4'hf, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 blanks max code 15", ALL_OFF, 1'b0);

        apply(4'h0, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 blanks min code 0", ALL_OFF, 1'b0);

        // LT_n outranks ripple blanking when BI_n is high.
        apply(4'h0, 1'b0, 1'b0, 1'b1);
        check("LT_n=0 wins over RBI_n=0 at code 0", ALL_ON, 1'b1);

        apply(4'hf, 1'b0, 1'b1, 1'b1);
        check("LT_n=0 ignores BCD code (15)", ALL_ON, 1'b1);

        // ------------------------------------------------------------------
        // 2. Ripple-blanking boundary: only the all-zero code is blanked.
        // ------------------------------------------------------------------
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 blanks code 0 and drives RBO_n low", ALL_OFF, 1'b0);

        apply(4'h0, 1'b1, 1'b1, 1'b1);
        check("RBI_n=1 shows zero glyph at code 0", decode_pattern(4'h0), 1'b1);

        // Each single-bit code adjacent to zero must decode normally even
        // with RBI_n asserted (the blanking condition needs D=C=B=A=0).
        apply(4'h1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 1 (A set)", decode_pattern(4'h1), 1'b1);
        apply(4'h2, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 2 (B set)", decode_pattern(4'h2), 1'b1);
        apply(4'h4, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 4 (C set)", decode_pattern(4'h4), 1'b1);
        apply(4'h8, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 8 (D set)", decode_pattern(4'h8), 1'b1);

        // ------------------------------------------------------------------
        // 3. Decode-range boundaries: BCD 9 -> 10 crossing and code 15.
        // ------------------------------------------------------------------
        apply(4'h9, 1'b1, 1'b1, 1'b1);
        check("code 9 (last BCD digit)", decode_pattern(4'h9), 1'b1);
        apply(4'ha, 1'b1, 1'b1, 1'b1);
        check("code 10 (first non-BCD glyph)", decode_pattern(4'ha), 1'b1);
        apply(4'hf, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank but RBO_n stays high", ALL_OFF, 1'b1);

        // Code 15 blanks the display, yet is distinguishable from BI_n=0
        // blanking by RBO_n.
        apply(4'hf, 1'b1, 1'b1, 1'b0);
        check("code 15 with BI_n=0 pulls RBO_n low", ALL_OFF, 1'b0);

        // ------------------------------------------------------------------
        // 4. Input transitions: outputs must settle purely combinationally,
        //    with no dependence on the previous state.
        // ------------------------------------------------------------------
        // Walk every code twice, once arriving from code 15 and once from 0,
        // and require identical settled outputs both times.
        for (i = 0; i < 16; i = i + 1) begin
            apply(4'hf, 1'b1, 1'b1, 1'b1);
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            seg_before = {a, b, c, d, e, f, g};
            apply(4'h0, 1'b1, 1'b1, 1'b1);
            apply(i[3:0], 1'b1, 1'b1, 1'b1);
            if (seg_before === {a, b, c, d, e, f, g}) begin
                pass_count = pass_count + 1;
                $display("PASS: code %0d settles identically from 15 and from 0", i);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: code %0d history-dependent: %b vs %b",
                         i, seg_before, {a, b, c, d, e, f, g});
            end
        end

        // Blank / unblank round trip returns the previous glyph.
        apply(4'h5, 1'b1, 1'b1, 1'b1);
        seg_before = {a, b, c, d, e, f, g};
        apply(4'h5, 1'b1, 1'b1, 1'b0);
        check("code 5 blanked mid-stream", ALL_OFF, 1'b0);
        apply(4'h5, 1'b1, 1'b1, 1'b1);
        check("code 5 restored after unblank", seg_before, 1'b1);

        // Lamp test asserted and released around a live digit.
        apply(4'h3, 1'b1, 1'b1, 1'b1);
        check("code 3 before lamp test", decode_pattern(4'h3), 1'b1);
        apply(4'h3, 1'b0, 1'b1, 1'b1);
        check("lamp test lights all segments over code 3", ALL_ON, 1'b1);
        apply(4'h3, 1'b1, 1'b1, 1'b1);
        check("code 3 restored after lamp test", decode_pattern(4'h3), 1'b1);

        // Ripple-blanking cascade edge: RBI_n toggling while parked at code 0
        // must toggle RBO_n, which is what feeds the next digit's RBI_n.
        apply(4'h0, 1'b1, 1'b1, 1'b1);
        check("cascade: RBO_n high with RBI_n released at code 0",
              decode_pattern(4'h0), 1'b1);
        apply(4'h0, 1'b1, 1'b0, 1'b1);
        check("cascade: RBO_n low with RBI_n asserted at code 0", ALL_OFF, 1'b0);
        apply(4'h0, 1'b1, 1'b1, 1'b1);
        check("cascade: RBO_n returns high when RBI_n released",
              decode_pattern(4'h0), 1'b1);

        // ------------------------------------------------------------------
        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL EXTRA EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EXTRA EDGE-CASE CHECK(S) FAILED", fail_count);
        $finish;
    end

endmodule
