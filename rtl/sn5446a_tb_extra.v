// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the external
// golden-vector harness (spec/chips/sn5446a.py, 128 exhaustive vectors)
// remains authoritative. This testbench documents, as executable regression
// notes, the control-input priority chain, the blanking-vs-dark distinction,
// and behaviour across input transitions.
//
// Run with:
//   iverilog -o /tmp/sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v
//   vvp /tmp/sn5446a_tb_extra.vvp
//
// Segment outputs and RBO_n are active low; expected segment patterns below
// are written as {a,b,c,d,e,f,g} with 0 = segment lit.
`timescale 1ns/1ps
module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer checks = 0;
    integer errors = 0;

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Drive one input combination and settle the combinational cloud.
    task apply;
        input [3:0] code;
        input       lt_n_v;
        input       rbi_n_v;
        input       bi_n_v;
        begin
            A = code[0]; B = code[1]; C = code[2]; D = code[3];
            LT_n = lt_n_v; RBI_n = rbi_n_v; BI_n = bi_n_v;
            #1;
        end
    endtask

    task check;
        input [6:0]  exp_seg;
        input        exp_rbo_n;
        input [8*48:1] label;
        begin
            checks = checks + 1;
            if ({a, b, c, d, e, f, g} === exp_seg && RBO_n === exp_rbo_n) begin
                $display("PASS: %0s | in D..A=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         label, D, C, B, A, LT_n, RBI_n, BI_n, {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL: %0s | in D..A=%b%b%b%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         label, D, C, B, A, LT_n, RBI_n, BI_n, {a, b, c, d, e, f, g}, RBO_n,
                         exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a supplementary edge-case testbench ===");

        // --- Case group 1: control-input priority chain -------------------
        // BI_n is the highest priority input: it blanks even when lamp test
        // and ripple blanking are simultaneously asserted, for any code.
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check(ALL_OFF, 1'b0, "BI_n beats LT_n and RBI_n (code 8)");
        apply(4'd0, 1'b0, 1'b0, 1'b0);
        check(ALL_OFF, 1'b0, "BI_n beats LT_n and RBI_n (code 0)");
        apply(4'd15, 1'b1, 1'b1, 1'b0);
        check(ALL_OFF, 1'b0, "BI_n blanks a dark code (15)");

        // LT_n outranks RBI_n: lamp test wins over zero ripple blanking.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check(ALL_ON, 1'b1, "LT_n beats RBI_n at code 0");
        apply(4'd0, 1'b0, 1'b1, 1'b1);
        check(ALL_ON, 1'b1, "LT_n lights all segments, RBO_n high");

        // --- Case group 2: ripple blanking is code-0 only ----------------
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check(ALL_OFF, 1'b0, "RBI_n blanks code 0, asserts RBO_n");
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check(7'b0000001, 1'b1, "RBI_n high decodes zero normally");
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check(7'b1001111, 1'b1, "RBI_n ignored at code 1 (boundary above 0)");
        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check(7'b0000000, 1'b1, "RBI_n ignored at code 8 (all segments lit)");

        // --- Case group 3: dark-by-decode vs dark-by-blanking ------------
        // Code 15 decodes to a blank glyph, but RBO_n stays high -- unlike
        // blanking/ripple-blanking, which pull RBO_n low.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check(ALL_OFF, 1'b1, "code 15 dark glyph keeps RBO_n high");
        apply(4'd15, 1'b1, 1'b0, 1'b1);
        check(ALL_OFF, 1'b1, "code 15 with RBI_n low still keeps RBO_n high");

        // --- Case group 4: BCD/non-BCD code boundaries ------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check(7'b0001100, 1'b1, "code 9, last valid BCD digit");
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check(7'b1110010, 1'b1, "code 10, first non-BCD glyph");
        apply(4'd14, 1'b1, 1'b1, 1'b1);
        check(7'b1110000, 1'b1, "code 14, last lit non-BCD glyph");

        // --- Case group 5: transitions between input states -------------
        // Leaving blanking must restore the previously decoded glyph.
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check(7'b0000110, 1'b1, "code 3 decoded before blanking");
        apply(4'd3, 1'b1, 1'b1, 1'b0);
        check(ALL_OFF, 1'b0, "code 3 blanked mid-stream");
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check(7'b0000110, 1'b1, "code 3 restored after blanking released");

        // Lamp test asserted and released around a static code.
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        check(7'b0100100, 1'b1, "code 5 decoded before lamp test");
        apply(4'd5, 1'b0, 1'b1, 1'b1);
        check(ALL_ON, 1'b1, "lamp test overrides code 5");
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        check(7'b0100100, 1'b1, "code 5 restored after lamp test");

        // Ripple blanking held low while the code walks 0 -> 1 -> 0.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check(ALL_OFF, 1'b0, "RBI_n low, code 0 blanked (entry)");
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check(7'b1001111, 1'b1, "RBI_n low, code 1 lit, RBO_n released");
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check(ALL_OFF, 1'b0, "RBI_n low, back to code 0 re-blanks");

        // Single-bit code transitions across the D boundary (7 -> 8).
        apply(4'd7, 1'b1, 1'b1, 1'b1);
        check(7'b0001111, 1'b1, "code 7 before MSB carry");
        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check(7'b0000000, 1'b1, "code 8 after MSB carry");

        $display("=== %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS (supplementary edge cases)");
        else
            $display("RESULT: FAIL (supplementary edge cases)");
        $finish;
    end

endmodule
