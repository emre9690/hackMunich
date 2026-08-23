// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness checking rtl/sn5446a.v against spec/chips/sn5446a.py (all 128 input
// combinations) remains authoritative. This bench exists as regression-safety
// documentation of the control-priority and boundary behaviour that the flat
// exhaustive sweep covers but does not name, plus input transitions that a
// combinational vector sweep never exercises at all.
//
// Run: iverilog -o sn5446a_tb_extra.vvp rtl/sn5446a.v rtl/sn5446a_tb_extra.v
//      ./sn5446a_tb_extra.vvp
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

    wire [6:0] seg_n = {a, b, c, d, e, f, g};

    localparam [6:0] ALL_OFF = 7'b1111111; // active-low segments, nothing lit
    localparam [6:0] ALL_ON  = 7'b0000000;

    // Active-low expected patterns for the decode rows referenced below.
    localparam [6:0] DIG0  = ~7'b1111110;
    localparam [6:0] DIG1  = ~7'b0110000;
    localparam [6:0] DIG8  = ~7'b1111111;
    localparam [6:0] DIG9  = ~7'b1110011;
    localparam [6:0] CODE10 = ~7'b0001101;
    localparam [6:0] CODE15 = ~7'b0000000;

    task apply;
        input [3:0] code;
        input lt_n_v, rbi_n_v, bi_n_v;
        begin
            A = code[0]; B = code[1]; C = code[2]; D = code[3];
            LT_n = lt_n_v; RBI_n = rbi_n_v; BI_n = bi_n_v;
            #1;
        end
    endtask

    task check;
        input [8*64-1:0] name;
        input [6:0] exp_seg_n;
        input exp_rbo_n;
        begin
            if (seg_n === exp_seg_n && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s | seg_n=%b RBO_n=%b", name, seg_n, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s | seg_n=%b (exp %b) RBO_n=%b (exp %b)",
                         name, seg_n, exp_seg_n, RBO_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== sn5446a supplementary edge-case testbench ===");

        // ---- Control priority: BI_n dominates every other input ----
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n=0 beats LT_n=0 and RBI_n=0 (code 8)", ALL_OFF, 1'b0);

        apply(4'd0, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 blanks code 0 with RBI_n idle", ALL_OFF, 1'b0);

        apply(4'd15, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 blanks code 15", ALL_OFF, 1'b0);

        // ---- Lamp test outranks ripple blanking, but only with BI_n high ----
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n=0 beats RBI_n=0 at code 0", ALL_ON, 1'b1);

        apply(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n=0 lights all segments regardless of code", ALL_ON, 1'b1);

        // ---- Ripple blanking fires for code 0 only ----
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 at code 0 blanks and pulls RBO_n low", ALL_OFF, 1'b0);

        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 at code 1 does not blank (boundary above 0)", DIG1, 1'b1);

        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 at code 8 does not blank", DIG8, 1'b1);

        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n=1 at code 0 decodes zero normally", DIG0, 1'b1);

        // ---- Decode boundaries: BCD range end and illegal-code region ----
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("code 9: last valid BCD digit", DIG9, 1'b1);

        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("code 10: first non-BCD pattern", CODE10, 1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15: all segments off but RBO_n stays high", CODE15, 1'b1);

        // ---- Transitions: state must depend only on the current inputs ----
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("9 -> 10 transition settles on code 10 pattern", CODE10, 1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("15 -> 0 transition settles on zero pattern", DIG0, 1'b1);

        apply(4'd8, 1'b1, 1'b1, 1'b0);
        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check("release of BI_n restores code 8 decode", DIG8, 1'b1);

        apply(4'd0, 1'b0, 1'b0, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("release of LT_n reveals ripple blanking at code 0", ALL_OFF, 1'b0);

        apply(4'd0, 1'b1, 1'b0, 1'b1);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("release of RBI_n un-blanks code 0", DIG0, 1'b1);

        // ---- RBO_n is low exactly when the display is blanked by BI/RBI ----
        apply(4'd7, 1'b1, 1'b0, 1'b1);
        check("RBO_n high when RBI_n=0 but code non-zero", ~7'b1110000, 1'b1);

        apply(4'd7, 1'b1, 1'b1, 1'b0);
        check("RBO_n low whenever BI_n=0", ALL_OFF, 1'b0);

        $display("=== %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
