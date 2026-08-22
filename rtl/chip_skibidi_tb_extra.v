// Supplementary edge-case testbench for bcd_7seg_7447a (SN7447A BCD-to-7-segment
// decoder/driver).
//
// This testbench is NOT the source of pass/fail truth for the design: the golden
// model vectors run by the external harness remain authoritative. The cases here
// document boundary conditions and input-state transitions that the exhaustive
// vector sweep does not call out explicitly:
//   * control-input priority (BI_n over LT_n over RBI_n zero-suppression)
//   * RBO_n wire-AND behaviour for each source that can pull it low
//   * ripple-blanking boundary between code 0 and code 1
//   * the valid/invalid code boundary (9 -> 10) and the blank code (15)
//   * back-to-back input transitions through the combinational decode
//
// Expected values are taken from the SN7447A datasheet truth table, written out
// independently of the RTL implementation.
//
// Segment expectations below use the active HIGH ordering {a,b,c,d,e,f,g}
// (1 = segment lit); the DUT drives active LOW outputs, so the comparison
// inverts them.

`default_nettype none
`timescale 1ns / 1ps

module chip_skibidi_tb_extra;

    reg  A, B, C, D;
    reg  LT_n, RBI_n, BI_n;
    wire a_n, b_n, c_n, d_n, e_n, f_n, g_n, RBO_n;

    integer passes = 0;
    integer fails  = 0;

    bcd_7seg_7447a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a_n(a_n), .b_n(b_n), .c_n(c_n), .d_n(d_n),
        .e_n(e_n), .f_n(f_n), .g_n(g_n),
        .RBO_n(RBO_n)
    );

    // Segment patterns, active HIGH, bit order {a,b,c,d,e,f,g}.
    localparam [6:0] SEG_BLANK = 7'b0000000;
    localparam [6:0] SEG_ALL   = 7'b1111111;
    localparam [6:0] SEG_0     = 7'b1111110;
    localparam [6:0] SEG_1     = 7'b0110000;
    localparam [6:0] SEG_8     = 7'b1111111;
    localparam [6:0] SEG_9     = 7'b1110011;
    localparam [6:0] SEG_10    = 7'b0001101;
    localparam [6:0] SEG_14    = 7'b0001111;

    wire [6:0] seg_active = ~{a_n, b_n, c_n, d_n, e_n, f_n, g_n};

    task apply;
        input [3:0] code;
        input       lt_n_in;
        input       rbi_n_in;
        input       bi_n_in;
        begin
            {D, C, B, A} = code;
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #1;
        end
    endtask

    // Applies the stimulus and compares against the datasheet expectation.
    task check;
        input [8*48-1:0] name;
        input [3:0]      code;
        input            lt_n_in;
        input            rbi_n_in;
        input            bi_n_in;
        input [6:0]      exp_seg;
        input            exp_rbo_n;
        begin
            apply(code, lt_n_in, rbi_n_in, bi_n_in);
            if (seg_active === exp_seg && RBO_n === exp_rbo_n) begin
                passes = passes + 1;
                $display("PASS  %0s : code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b",
                         name, code, lt_n_in, rbi_n_in, bi_n_in, seg_active, RBO_n);
            end else begin
                fails = fails + 1;
                $display("FAIL  %0s : code=%0d LT_n=%b RBI_n=%b BI_n=%b -> abcdefg=%b RBO_n=%b (expected abcdefg=%b RBO_n=%b)",
                         name, code, lt_n_in, rbi_n_in, bi_n_in, seg_active, RBO_n,
                         exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== chip_skibidi_tb_extra: supplementary edge-case coverage ===");

        // --- Control-input priority ---------------------------------------
        // BI_n low blanks the display for every code and overrides lamp test
        // and ripple blanking; RBO_n follows BI_n low through the wire-AND.
        check("BI_n low blanks code 0",        4'd0,  1'b1, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        check("BI_n low blanks code 8",        4'd8,  1'b1, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        check("BI_n low blanks code 15",       4'd15, 1'b1, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        check("BI_n low beats lamp test",      4'd5,  1'b0, 1'b1, 1'b0, SEG_BLANK, 1'b0);
        check("BI_n low beats RBI_n low",      4'd0,  1'b1, 1'b0, 1'b0, SEG_BLANK, 1'b0);

        // Lamp test lights every segment regardless of code, and outranks
        // zero suppression, but must not pull RBO_n low.
        check("lamp test on code 0",           4'd0,  1'b0, 1'b1, 1'b1, SEG_ALL,   1'b1);
        check("lamp test on code 15",          4'd15, 1'b0, 1'b1, 1'b1, SEG_ALL,   1'b1);
        check("lamp test beats RBI_n low",     4'd0,  1'b0, 1'b0, 1'b1, SEG_ALL,   1'b1);

        // --- Ripple blanking boundary -------------------------------------
        // Zero suppression applies to code 0 only; the adjacent code 1 must
        // display normally and leave RBO_n high.
        check("RBI_n low blanks zero",         4'd0,  1'b1, 1'b0, 1'b1, SEG_BLANK, 1'b0);
        check("RBI_n low leaves one lit",      4'd1,  1'b1, 1'b0, 1'b1, SEG_1,     1'b1);
        check("RBI_n high shows zero",         4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);

        // --- Valid / invalid code boundary --------------------------------
        check("last decimal digit 9",          4'd9,  1'b1, 1'b1, 1'b1, SEG_9,     1'b1);
        check("first invalid code 10",         4'd10, 1'b1, 1'b1, 1'b1, SEG_10,    1'b1);
        check("last patterned code 14",        4'd14, 1'b1, 1'b1, 1'b1, SEG_14,    1'b1);
        check("code 15 is blank",              4'd15, 1'b1, 1'b1, 1'b1, SEG_BLANK, 1'b1);
        check("code 15 keeps RBO_n high",      4'd15, 1'b1, 1'b0, 1'b1, SEG_BLANK, 1'b1);
        check("all segments on code 8",        4'd8,  1'b1, 1'b1, 1'b1, SEG_8,     1'b1);

        // --- Input-state transitions ---------------------------------------
        // Walk through transitions and re-check the settled outputs, so a
        // latch or accidental sequential element would show up as a mismatch.
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("9 -> 0 after 9",                4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("15 -> 1 after blank code",      4'd1,  1'b1, 1'b1, 1'b1, SEG_1,     1'b1);

        apply(4'd0, 1'b1, 1'b0, 1'b1); // suppressed zero
        check("blanked 0 -> lit 0 on RBI_n",   4'd0,  1'b1, 1'b1, 1'b1, SEG_0,     1'b1);

        apply(4'd8, 1'b1, 1'b1, 1'b0); // blanked by BI_n
        check("release BI_n restores 8",       4'd8,  1'b1, 1'b1, 1'b1, SEG_8,     1'b1);

        apply(4'd3, 1'b0, 1'b1, 1'b1); // lamp test
        check("release LT_n restores 3",       4'd3,  1'b1, 1'b1, 1'b1, 7'b1111001, 1'b1);

        $display("=== chip_skibidi_tb_extra summary: %0d passed, %0d failed ===",
                 passes, fails);
        if (fails != 0)
            $display("NOTE: mismatches above are informational; the external golden-model harness is the source of truth.");
        $finish;
    end

endmodule

`default_nettype wire
