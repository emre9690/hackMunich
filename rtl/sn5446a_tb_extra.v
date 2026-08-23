// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the golden model in
// spec/chips/sn5446a.py plus the external harness remain authoritative. This
// bench documents specific edge cases -- control-input priority, invalid BCD
// codes, boundary codes and transitions between input states -- as regression
// safety net and executable documentation.
//
// Segment outputs and RBO_n are active low: 0 = segment on.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D;
    reg LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer pass_count = 0;
    integer fail_count = 0;

    reg [255:0] case_name;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    localparam [6:0] SEG_ALL_OFF = 7'b1111111;
    localparam [6:0] SEG_ALL_ON  = 7'b0000000;

    // Apply a stimulus, then compare {a,b,c,d,e,f,g} and RBO_n against the
    // expected values and report the result for this case.
    task check;
        input [255:0] name;
        input [3:0]   code;      // {D,C,B,A}
        input         lt_n_in;
        input         rbi_n_in;
        input         bi_n_in;
        input [6:0]   exp_seg_n; // active low, order {a,b,c,d,e,f,g}
        input         exp_rbo_n;
        begin
            D     = code[3];
            C     = code[2];
            B     = code[1];
            A     = code[0];
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #1;
            if ({a, b, c, d, e, f, g} === exp_seg_n && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, code, lt_n_in, rbi_n_in, bi_n_in,
                         {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, code, lt_n_in, rbi_n_in, bi_n_in,
                         {a, b, c, d, e, f, g}, RBO_n, exp_seg_n, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("=== supplementary edge-case tests for bcd_to_7seg_sn5446a ===");

        // -- control priority: BI_n dominates every other input ---------------
        check("blank_beats_lamp_test",   4'd8, 1'b0, 1'b1, 1'b0, SEG_ALL_OFF, 1'b0);
        check("blank_beats_ripple",      4'd0, 1'b1, 1'b0, 1'b0, SEG_ALL_OFF, 1'b0);
        check("blank_all_controls_low",  4'd0, 1'b0, 1'b0, 1'b0, SEG_ALL_OFF, 1'b0);
        check("blank_max_code",          4'd15, 1'b1, 1'b1, 1'b0, SEG_ALL_OFF, 1'b0);

        // -- lamp test dominates ripple blanking, and ignores the BCD code ----
        check("lamp_test_code0",         4'd0, 1'b0, 1'b1, 1'b1, SEG_ALL_ON, 1'b1);
        check("lamp_test_beats_ripple",  4'd0, 1'b0, 1'b0, 1'b1, SEG_ALL_ON, 1'b1);
        check("lamp_test_code15",        4'd15, 1'b0, 1'b1, 1'b1, SEG_ALL_ON, 1'b1);

        // -- ripple blanking applies to code 0 only ---------------------------
        check("ripple_blank_zero",       4'd0, 1'b1, 1'b0, 1'b1, SEG_ALL_OFF, 1'b0);
        check("ripple_ignored_code1",    4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        check("ripple_ignored_code8",    4'd8, 1'b1, 1'b0, 1'b1, SEG_ALL_ON, 1'b1);
        check("zero_shown_when_rbi_high", 4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);

        // -- boundary codes of the valid BCD range and of the 4-bit range -----
        check("decode_min_code0",        4'd0, 1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);
        check("decode_bcd_max_code9",    4'd9, 1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("decode_first_invalid_10", 4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        check("decode_max_code15_blank_pattern", 4'd15, 1'b1, 1'b1, 1'b1, SEG_ALL_OFF, 1'b1);

        // Code 15 blanks the display like BI_n does, but must NOT pull RBO_n
        // low -- that distinction is the point of the two cases above.

        // -- transitions between input states --------------------------------
        // 9 -> 10: crossing out of the valid BCD range.
        check("transition_9_to_10_step1", 4'd9, 1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        check("transition_9_to_10_step2", 4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);

        // Blanking pulse: a code must be restored unchanged after BI_n returns
        // high, i.e. the decoder is purely combinational and keeps no state.
        check("pulse_before_blank",  4'd3, 1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);
        check("pulse_during_blank",  4'd3, 1'b1, 1'b1, 1'b0, SEG_ALL_OFF, 1'b0);
        check("pulse_after_blank",   4'd3, 1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);

        // Lamp-test pulse around a code, same no-state requirement.
        check("lt_pulse_before", 4'd5, 1'b1, 1'b1, 1'b1, 7'b0100100, 1'b1);
        check("lt_pulse_during", 4'd5, 1'b0, 1'b1, 1'b1, SEG_ALL_ON, 1'b1);
        check("lt_pulse_after",  4'd5, 1'b1, 1'b1, 1'b1, 7'b0100100, 1'b1);

        // Leaving code 0 with RBI_n low releases RBO_n; returning re-asserts it.
        check("rbi_low_leave_zero_step1", 4'd0, 1'b1, 1'b0, 1'b1, SEG_ALL_OFF, 1'b0);
        check("rbi_low_leave_zero_step2", 4'd2, 1'b1, 1'b0, 1'b1, 7'b0010010, 1'b1);
        check("rbi_low_return_zero",      4'd0, 1'b1, 1'b0, 1'b1, SEG_ALL_OFF, 1'b0);

        // Only the all-zero code responds to RBI_n: walk each single input bit.
        check("rbi_low_bit_A", 4'd1, 1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        check("rbi_low_bit_B", 4'd2, 1'b1, 1'b0, 1'b1, 7'b0010010, 1'b1);
        check("rbi_low_bit_C", 4'd4, 1'b1, 1'b0, 1'b1, 7'b1001100, 1'b1);
        check("rbi_low_bit_D", 4'd8, 1'b1, 1'b0, 1'b1, SEG_ALL_ON, 1'b1);

        $display("=== %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
