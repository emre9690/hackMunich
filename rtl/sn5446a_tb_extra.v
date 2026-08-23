// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is ADDITIONAL regression-safety documentation only. The exhaustive
// golden-vector comparison in the external harness (spec/chips/sn5446a.py)
// remains the sole source of pass/fail truth for this design. Here we spell
// out, in readable form, the control-input priority boundaries, the BCD /
// non-BCD code boundaries and a few input-state transitions.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    // Expected segment patterns, bit order {a,b,c,d,e,f,g}, active low.
    localparam [6:0] SEG_ALL_OFF = 7'b1111111;
    localparam [6:0] SEG_ALL_ON  = 7'b0000000;
    localparam [6:0] SEG_0       = 7'b0000001;
    localparam [6:0] SEG_1       = 7'b1001111;
    localparam [6:0] SEG_4       = 7'b1001100;
    localparam [6:0] SEG_8       = 7'b0000000;
    localparam [6:0] SEG_9       = 7'b0001100;
    localparam [6:0] SEG_10      = 7'b1110010;
    localparam [6:0] SEG_15      = 7'b1111111;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    task apply;
        input [3:0] code;
        input lt_n_in, rbi_n_in, bi_n_in;
        begin
            A     = code[0];
            B     = code[1];
            C     = code[2];
            D     = code[3];
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #1;
        end
    endtask

    task check;
        input [8*48-1:0] name;
        input [6:0] exp_seg;
        input       exp_rbo_n;
        reg [6:0] got_seg;
        begin
            got_seg = {a, b, c, d, e, f, g};
            if (got_seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s  D=%b C=%b B=%b A=%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, D, C, B, A, LT_n, RBI_n, BI_n, got_seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s  D=%b C=%b B=%b A=%b LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, D, C, B, A, LT_n, RBI_n, BI_n, got_seg, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case cases ===");

        // ---- Control-input priority boundaries ----------------------------
        // BI_n low blanks everything, whatever the other inputs say.
        apply(4'd8, 1'b1, 1'b1, 1'b0);
        check("BI_n overrides normal decode", SEG_ALL_OFF, 1'b0);
        apply(4'd8, 1'b0, 1'b1, 1'b0);
        check("BI_n overrides lamp test", SEG_ALL_OFF, 1'b0);
        apply(4'd0, 1'b0, 1'b0, 1'b0);
        check("BI_n overrides LT_n and RBI_n", SEG_ALL_OFF, 1'b0);

        // Lamp test outranks ripple blanking when BI/RBO is held high.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n outranks RBI_n at code 0", SEG_ALL_ON, 1'b1);
        apply(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n ignores input code", SEG_ALL_ON, 1'b1);

        // ---- Ripple blanking, only at code 0 -----------------------------
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks decimal zero", SEG_ALL_OFF, 1'b0);
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank code 1", SEG_1, 1'b1);
        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n does not blank code 8", SEG_8, 1'b1);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 decodes when RBI_n high", SEG_0, 1'b1);

        // ---- BCD / non-BCD code boundaries -------------------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("last valid BCD code 9", SEG_9, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("first non-BCD code 10", SEG_10, 1'b1);
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 is fully blank", SEG_15, 1'b1);

        // ---- Transitions between input states ----------------------------
        // Blank and unblank around a live code: the decode must come back.
        apply(4'd4, 1'b1, 1'b1, 1'b1);
        check("pre-blank decode of code 4", SEG_4, 1'b1);
        apply(4'd4, 1'b1, 1'b1, 1'b0);
        check("blanked while code 4 held", SEG_ALL_OFF, 1'b0);
        apply(4'd4, 1'b1, 1'b1, 1'b1);
        check("decode of code 4 restored", SEG_4, 1'b1);

        // Lamp test asserted and released around a live code.
        apply(4'd4, 1'b0, 1'b1, 1'b1);
        check("lamp test over code 4", SEG_ALL_ON, 1'b1);
        apply(4'd4, 1'b1, 1'b1, 1'b1);
        check("decode after lamp test release", SEG_4, 1'b1);

        // Walk the 9 -> 10 -> ... -> 15 -> 0 wrap with RBI_n high.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("wrap step: code 15", SEG_15, 1'b1);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("wrap step: code 0", SEG_0, 1'b1);

        // RBI_n toggled while code 0 is held: blanking follows immediately.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n asserted at held code 0", SEG_ALL_OFF, 1'b0);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n released at held code 0", SEG_0, 1'b1);

        $display("=== sn5446a_tb_extra: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
