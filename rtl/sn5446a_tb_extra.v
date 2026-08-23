// Supplementary edge-case testbench for bcd_to_7seg_sn5446a (SN5446A).
//
// This is ADDITIONAL regression-safety documentation only. The exhaustive
// 128-vector comparison against spec/chips/sn5446a.py remains the sole source
// of pass/fail truth for this design; the cases below simply spell out the
// control-priority, boundary-code and input-transition behaviour that the
// exhaustive sweep covers implicitly.
//
// Run: iverilog -o tb rtl/sn5446a.v rtl/sn5446a_tb_extra.v && ./tb

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

    // Observed outputs, active-low segments in order {a,b,c,d,e,f,g}.
    wire [6:0] seg = {a, b, c, d, e, f, g};

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;

    task apply(input [3:0] code, input lt, input rbi, input bi);
        begin
            A    = code[0];
            B    = code[1];
            C    = code[2];
            D    = code[3];
            LT_n = lt;
            RBI_n = rbi;
            BI_n = bi;
            #5;
        end
    endtask

    // Checks the current outputs against expectations and reports one line.
    task expect_out(input [255:0] name, input [6:0] exp_seg, input exp_rbo);
        begin
            checks = checks + 1;
            if (seg === exp_seg && RBO_n === exp_rbo) begin
                $display("PASS %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL %0s: code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n, exp_seg, exp_rbo);
            end
        end
    endtask

    task step(input [255:0] name, input [3:0] code, input lt, input rbi, input bi,
              input [6:0] exp_seg, input exp_rbo);
        begin
            apply(code, lt, rbi, bi);
            expect_out(name, exp_seg, exp_rbo);
        end
    endtask

    initial begin
        $display("=== sn5446a extra edge-case testbench ===");

        // ---- Control priority: BI_n beats everything ----------------------
        // Blanking must win over lamp test, over ripple blanking, and over any
        // BCD code, and must pull RBO_n low (wire-AND of pin 4).
        step("BI over LT",            4'd8,  1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        step("BI over RBI at zero",   4'd0,  1'b1, 1'b0, 1'b0, ALL_OFF, 1'b0);
        step("BI over LT and RBI",    4'd5,  1'b0, 1'b0, 1'b0, ALL_OFF, 1'b0);
        step("BI with code 15",       4'd15, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // ---- Lamp test beats ripple blanking and decoding -----------------
        step("LT with RBI low",       4'd0,  1'b0, 1'b0, 1'b1, ALL_ON,  1'b1);
        step("LT with code 15",       4'd15, 1'b0, 1'b1, 1'b1, ALL_ON,  1'b1);

        // ---- Ripple blanking applies to code 0 only -----------------------
        step("RBI blanks zero",       4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        step("zero shown, RBI high",  4'd0,  1'b1, 1'b1, 1'b1, 7'b0000001, 1'b1);
        // Code 1 is the boundary just above the blanked code: RBI must be
        // ignored, so RBO_n stays high and segments b,c light.
        step("RBI ignored at one",    4'd1,  1'b1, 1'b0, 1'b1, 7'b1001111, 1'b1);
        step("RBI ignored at eight",  4'd8,  1'b1, 1'b0, 1'b1, ALL_ON,     1'b1);

        // ---- BCD boundaries: last digit, first non-digit, last code -------
        step("code 9 boundary",       4'd9,  1'b1, 1'b1, 1'b1, 7'b0001100, 1'b1);
        step("code 10 boundary",      4'd10, 1'b1, 1'b1, 1'b1, 7'b1110010, 1'b1);
        step("code 15 all off",       4'd15, 1'b1, 1'b1, 1'b1, ALL_OFF,    1'b1);
        // Code 15 and hard blanking produce identical segments, but code 15
        // must leave RBO_n high (already checked above with BI_n low).

        // ---- Transitions between input states -----------------------------
        // Leaving lamp test must restore the decoded value, not stick at ALL_ON.
        step("digit 3 before LT",     4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);
        step("LT asserted",           4'd3,  1'b0, 1'b1, 1'b1, ALL_ON,     1'b1);
        step("LT released restores 3",4'd3,  1'b1, 1'b1, 1'b1, 7'b0000110, 1'b1);

        // Leaving blanking must restore the decoded value and release RBO_n.
        step("BI asserted on 6",      4'd6,  1'b1, 1'b1, 1'b0, ALL_OFF,    1'b0);
        step("BI released shows 6",   4'd6,  1'b1, 1'b1, 1'b1, 7'b1100000, 1'b1);

        // Ripple-blank cascade transition: zero blanked, then code changes to a
        // non-zero digit with RBI_n still low -> RBO_n must rise again.
        step("cascade zero blanked",  4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF,    1'b0);
        step("cascade to digit 7",    4'd7,  1'b1, 1'b0, 1'b1, 7'b0001111, 1'b1);
        step("cascade back to zero",  4'd0,  1'b1, 1'b0, 1'b1, ALL_OFF,    1'b0);

        // Single-bit input walk across a code boundary (7 -> 8), i.e. all four
        // BCD bits changing, checked at both endpoints.
        step("code 7 before carry",   4'd7,  1'b1, 1'b1, 1'b1, 7'b0001111, 1'b1);
        step("code 8 after carry",    4'd8,  1'b1, 1'b1, 1'b1, ALL_ON,     1'b1);

        // Purely combinational: re-applying the same stimulus must be stable.
        step("stable repeat of 8",    4'd8,  1'b1, 1'b1, 1'b1, ALL_ON,     1'b1);

        $display("=== %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EDGE CASES PASSED");
        else
            $display("RESULT: %0d EDGE CASE(S) FAILED", errors);
        $finish;
    end

endmodule
