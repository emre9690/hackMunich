// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the exhaustive
// 128-vector check against spec/chips/sn5446a.py remains authoritative. This
// bench documents specific edge cases (control-input priority, ripple-blanking
// boundary, non-decimal codes, and transitions between input states) so that a
// future regression in one of them is easy to localize.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer errors = 0;
    integer checks = 0;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    // Observed segment bus, active low, ordered {a,b,c,d,e,f,g}.
    wire [6:0] seg_n = {a, b, c, d, e, f, g};

    // Drive one input combination; `code` is the BCD value {D,C,B,A}.
    task apply(input [3:0] code, input lt_n_v, input rbi_n_v, input bi_n_v);
        begin
            A = code[0];
            B = code[1];
            C = code[2];
            D = code[3];
            LT_n  = lt_n_v;
            RBI_n = rbi_n_v;
            BI_n  = bi_n_v;
            #1;
        end
    endtask

    // Compare observed outputs against expected ones. exp_seg_n is active low.
    task check(input [8*40-1:0] name, input [6:0] exp_seg_n, input exp_rbo_n);
        begin
            checks = checks + 1;
            if (seg_n === exp_seg_n && RBO_n === exp_rbo_n) begin
                $display("PASS %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b seg_n=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg_n, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b seg_n=%b (exp %b) RBO_n=%b (exp %b)",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n,
                         seg_n, exp_seg_n, RBO_n, exp_rbo_n);
            end
        end
    endtask

    // Expected segment patterns (active low) for the decode rows touched below.
    localparam [6:0] SEG_OFF = 7'b1111111;  // all segments off
    localparam [6:0] SEG_ON  = 7'b0000000;  // all segments on (lamp test / "8")
    localparam [6:0] SEG_0   = 7'b0000001;
    localparam [6:0] SEG_1   = 7'b1001111;
    localparam [6:0] SEG_7   = 7'b0001111;
    localparam [6:0] SEG_9   = 7'b0001100;
    localparam [6:0] SEG_10  = 7'b1110010;
    localparam [6:0] SEG_14  = 7'b1110000;

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case cases ===");

        // --- Control-input priority boundary -------------------------------
        // BI_n dominates every other input, including lamp test.
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n beats LT_n and RBI_n", SEG_OFF, 1'b0);

        // Lamp test wins over ripple blanking when the BI/RBO node is high.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n beats RBI_n", SEG_ON, 1'b1);

        // Lamp test is code-independent.
        apply(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n ignores code", SEG_ON, 1'b1);

        // --- Ripple-blanking boundary --------------------------------------
        // Zero blanks only for code 0 ...
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n blanks code 0", SEG_OFF, 1'b0);

        // ... and the neighbouring codes must still decode normally.
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n ignored at code 1", SEG_1, 1'b1);
        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n ignored at code 8", SEG_ON, 1'b1);

        // Code 0 with RBI_n high displays "0" and does not assert RBO_n.
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 not blanked", SEG_0, 1'b1);

        // --- Non-decimal code boundary -------------------------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("last decimal code 9", SEG_9, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("first non-decimal code 10", SEG_10, 1'b1);
        apply(4'd14, 1'b1, 1'b1, 1'b1);
        check("code 14", SEG_14, 1'b1);
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 blank pattern", SEG_OFF, 1'b1);

        // Code 15 looks blank but must not assert RBO_n, unlike real blanking.
        if (RBO_n !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL code 15 must not assert RBO_n");
        end

        // --- Transitions between input states ------------------------------
        // Leaving blanking restores the previously selected digit.
        apply(4'd7, 1'b1, 1'b1, 1'b0);
        check("blank during code 7", SEG_OFF, 1'b0);
        apply(4'd7, 1'b1, 1'b1, 1'b1);
        check("unblank restores code 7", SEG_7, 1'b1);

        // Releasing lamp test returns to the decoded value, not to all-on.
        apply(4'd1, 1'b0, 1'b1, 1'b1);
        check("lamp test before release", SEG_ON, 1'b1);
        apply(4'd1, 1'b1, 1'b1, 1'b1);
        check("code 1 after lamp test", SEG_1, 1'b1);

        // Ripple-blanking chain handoff: RBO_n toggles as the code leaves zero.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBO_n asserted on blanked zero", SEG_OFF, 1'b0);
        apply(4'd9, 1'b1, 1'b0, 1'b1);
        check("RBO_n released on non-zero code", SEG_9, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBO_n re-asserted back at zero", SEG_OFF, 1'b0);

        // Glitch-free combinational settling: several rapid code changes in a
        // row must leave the outputs at the final code's pattern.
        apply(4'd2,  1'b1, 1'b1, 1'b1);
        apply(4'd13, 1'b1, 1'b1, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("settles after rapid code changes", SEG_10, 1'b1);

        $display("=== sn5446a_tb_extra: %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EDGE CASES PASS");
        else
            $display("RESULT: %0d EDGE CASE FAILURE(S)", errors);
        $finish;
    end

endmodule
