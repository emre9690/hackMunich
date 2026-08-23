// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: harness/check_vectors.py
// exhaustively compares the RTL against spec/chips/sn5446a.py (128 vectors) and
// remains the only authority. This testbench documents, as regression-safety
// notes, the corner cases a future edit is most likely to break: control-input
// priority, the ripple-blanking response condition, the decimal/non-decimal code
// boundary, and settling across input transitions.
//
// Expected values below are transcribed from the '46A function table via the
// golden model: segment outputs are active low (0 = segment on), and the
// checked bus order is {a,b,c,d,e,f,g,RBO_n}.
`timescale 1ns/1ps
module sn5446a_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g;
    wire RBO_n;

    integer failures = 0;
    integer checks   = 0;
    integer code;

    // Active-low segment patterns, {a,b,c,d,e,f,g}.
    localparam [6:0] SEG_ALL_OFF = 7'b1111111;
    localparam [6:0] SEG_ALL_ON  = 7'b0000000;
    localparam [6:0] SEG_0       = 7'b0000001;
    localparam [6:0] SEG_1       = 7'b1001111;
    localparam [6:0] SEG_5       = 7'b0100100;
    localparam [6:0] SEG_9       = 7'b0001100;
    localparam [6:0] SEG_10      = 7'b1110010;
    localparam [6:0] SEG_15      = 7'b1111111;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    task apply(input [3:0] bcd, input lt, input rbi, input bi);
        begin
            {D, C, B, A} = bcd;
            LT_n  = lt;
            RBI_n = rbi;
            BI_n  = bi;
            #1;
        end
    endtask

    task check(input [559:0] name, input [6:0] exp_seg, input exp_rbo);
        begin
            checks = checks + 1;
            if ({a, b, c, d, e, f, g, RBO_n} === {exp_seg, exp_rbo}) begin
                $display("PASS: %0s [code=%0d LT_n=%b RBI_n=%b BI_n=%b] seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s [code=%0d LT_n=%b RBI_n=%b BI_n=%b] got seg=%b RBO_n=%b, expected seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, {a, b, c, d, e, f, g}, RBO_n,
                         exp_seg, exp_rbo);
            end
        end
    endtask

    initial begin
        $display("== sn5446a supplementary edge-case testbench ==");

        // 1. Blanking has strict priority over lamp test and ripple blanking,
        //    and over any code, including code 8 (all segments otherwise on).
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n overrides LT_n and RBI_n at code 8", SEG_ALL_OFF, 1'b0);
        apply(4'd0, 1'b0, 1'b1, 1'b0);
        check("BI_n overrides LT_n at code 0", SEG_ALL_OFF, 1'b0);

        // 2. Lamp test outranks ripple blanking and the decoder, but only while
        //    the BI/RBO node is high; RBO_n must stay high (node not pulled low).
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n overrides RBI_n zero-blank", SEG_ALL_ON, 1'b1);
        apply(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n overrides code 15 blank pattern", SEG_ALL_ON, 1'b1);

        // 3. Ripple-blanking response condition: it applies to code 0 only.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n response condition at code 0", SEG_ALL_OFF, 1'b0);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 decoded when RBI_n high", SEG_0, 1'b1);
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n ignored at code 1", SEG_1, 1'b1);

        // 4. RBO_n must stay high for every non-zero code even with RBI_n low.
        for (code = 1; code < 16; code = code + 1) begin
            apply(code[3:0], 1'b1, 1'b0, 1'b1);
            if (RBO_n !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL: RBO_n pulled low at non-zero code %0d with RBI_n=0", code);
            end
            checks = checks + 1;
        end
        $display("INFO: RBO_n sweep over codes 1..15 with RBI_n=0 complete");

        // 5. Decimal/non-decimal boundary: 9 is the last BCD digit, 10 the first
        //    of the non-decimal patterns, 15 blanks all segments while RBO_n stays high.
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("boundary: code 9 decodes", SEG_9, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("boundary: code 10 non-decimal pattern", SEG_10, 1'b1);
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("boundary: code 15 blanks segments, RBO_n high", SEG_15, 1'b1);

        // 6. Transitions: outputs are purely combinational, so every transition
        //    must settle on the destination state with no residue of the source.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("transition 15 -> 0 wraps to decoded zero", SEG_0, 1'b1);
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("transition 9 -> 10 crosses decimal boundary", SEG_10, 1'b1);

        // 7. Blanking pulse: state before and after a BI_n pulse is identical.
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        check("pre-pulse: code 5 decoded", SEG_5, 1'b1);
        apply(4'd5, 1'b1, 1'b1, 1'b0);
        check("BI_n asserted blanks code 5", SEG_ALL_OFF, 1'b0);
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        check("BI_n released restores code 5", SEG_5, 1'b1);

        // 8. Lamp-test pulse over the ripple-blanked zero: releasing LT_n must
        //    fall back to the blanked zero, not to the decoded zero.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("pre-pulse: zero ripple-blanked", SEG_ALL_OFF, 1'b0);
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n asserted lights all segments", SEG_ALL_ON, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("LT_n released returns to ripple-blanked zero", SEG_ALL_OFF, 1'b0);

        $display("== %0d checks, %0d failures ==", checks, failures);
        if (failures == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule
