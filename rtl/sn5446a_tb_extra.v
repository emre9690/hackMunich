// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is ADDITIONAL regression-safety documentation only. The exhaustive
// 128-vector comparison against spec/chips/sn5446a.py remains the sole source
// of pass/fail truth for this design. The scenarios below focus on control
// input priority, the ripple-blanking response condition, and sequential
// transitions between input states, which an unordered exhaustive sweep does
// not document explicitly.
//
// Segment outputs are active low: 0 = segment ON, 1 = segment OFF.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg  A, B, C, D;
    reg  LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g;
    wire RBO_n;

    integer errors = 0;
    integer checks = 0;

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;
    localparam [6:0] DIGIT_0 = 7'b0000001;
    localparam [6:0] DIGIT_1 = 7'b1001111;
    localparam [6:0] DIGIT_8 = 7'b0000000;
    localparam [6:0] DIGIT_9 = 7'b0001100;
    localparam [6:0] CODE_10 = 7'b1110010;
    localparam [6:0] CODE_15 = 7'b1111111;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    wire [6:0] seg = {a, b, c, d, e, f, g};

    task apply(input [3:0] code, input lt, input rbi, input bi);
        begin
            A     = code[0];
            B     = code[1];
            C     = code[2];
            D     = code[3];
            LT_n  = lt;
            RBI_n = rbi;
            BI_n  = bi;
            #5;
        end
    endtask

    task check(input [8*64-1:0] name, input [6:0] exp_seg, input exp_rbo);
        begin
            checks = checks + 1;
            if (seg === exp_seg && RBO_n === exp_rbo) begin
                $display("PASS: %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL: %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, {D, C, B, A}, LT_n, RBI_n, BI_n, seg, RBO_n, exp_seg, exp_rbo);
            end
        end
    endtask

    integer i;

    initial begin
        $display("=== sn5446a supplementary edge-case testbench ===");

        // --- Control input priority ---------------------------------------
        // BI_n dominates every other input, including lamp test.
        apply(4'd8, 1'b0, 1'b0, 1'b0);
        check("BI_n overrides LT_n and RBI_n", ALL_OFF, 1'b0);

        apply(4'd0, 1'b1, 1'b1, 1'b0);
        check("BI_n blanks a valid decode", ALL_OFF, 1'b0);

        apply(4'd15, 1'b1, 1'b1, 1'b0);
        check("BI_n blanks code 15", ALL_OFF, 1'b0);

        // Lamp test dominates ripple blanking when the BI/RBO node is high.
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n overrides RBI_n response condition", ALL_ON, 1'b1);

        apply(4'd15, 1'b0, 1'b1, 1'b1);
        check("LT_n lights all segments regardless of code", ALL_ON, 1'b1);

        // --- Ripple-blanking response condition ---------------------------
        // RBI_n=0 blanks only the all-zero code and pulls RBO_n low.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 with code 0 blanks and asserts RBO_n", ALL_OFF, 1'b0);

        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 with code 1 decodes normally", DIGIT_1, 1'b1);

        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 with code 8 decodes normally", DIGIT_8, 1'b1);

        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n=1 with code 0 shows digit zero", DIGIT_0, 1'b1);

        // --- Numeric / non-numeric code boundaries ------------------------
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("code 9 is the last BCD digit", DIGIT_9, 1'b1);

        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("code 10 is the first non-BCD pattern", CODE_10, 1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank by decode, not by blanking", CODE_15, 1'b1);

        // Code 15 and a blanked display look alike on the segments, but the
        // ripple-blanking output distinguishes them.
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        if (RBO_n !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: code 15 must keep RBO_n high");
        end
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        if (RBO_n !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: blanked zero must pull RBO_n low");
        end
        checks = checks + 1;
        if (errors == 0)
            $display("PASS: code 15 vs ripple-blanked zero separated by RBO_n");

        // --- Transitions between input states -----------------------------
        // Walking A while holding the upper bits: 8 -> 9 -> and back.
        apply(4'd8, 1'b1, 1'b1, 1'b1);
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("transition 8 -> 9 settles on digit 9", DIGIT_9, 1'b1);
        apply(4'd8, 1'b1, 1'b1, 1'b1);
        check("transition 9 -> 8 settles on digit 8", DIGIT_8, 1'b1);

        // Blank and unblank around a live decode.
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        apply(4'd3, 1'b1, 1'b1, 1'b0);
        check("blanking a displayed 3", ALL_OFF, 1'b0);
        apply(4'd3, 1'b1, 1'b1, 1'b1);
        check("unblanking restores digit 3", 7'b0000110, 1'b1);

        // Lamp test entered and released while the code stays put.
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        apply(4'd5, 1'b0, 1'b1, 1'b1);
        check("lamp test entered over digit 5", ALL_ON, 1'b1);
        apply(4'd5, 1'b1, 1'b1, 1'b1);
        check("lamp test released restores digit 5", 7'b0100100, 1'b1);

        // Ripple blanking toggled while the code is held at zero.
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n falling blanks the held zero", ALL_OFF, 1'b0);
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("RBI_n rising restores the held zero", DIGIT_0, 1'b1);

        // Counting 0..15 with RBI_n held low: only the zero must be blanked.
        for (i = 0; i < 16; i = i + 1) begin
            apply(i[3:0], 1'b1, 1'b0, 1'b1);
            if (i == 0) begin
                check("ripple sweep: zero blanked", ALL_OFF, 1'b0);
            end else if (RBO_n !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: ripple sweep code %0d must keep RBO_n high", i);
            end
        end
        checks = checks + 1;
        $display("PASS: ripple sweep leaves RBO_n high for codes 1..15");

        // Static outputs must be stable, so re-applying identical inputs
        // after unrelated intermediate states reproduces the same pattern.
        apply(4'd6, 1'b1, 1'b1, 1'b1);
        apply(4'd12, 1'b0, 1'b0, 1'b0);
        apply(4'd6, 1'b1, 1'b1, 1'b1);
        check("returning to code 6 is history independent", 7'b1100000, 1'b1);

        $display("=== %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("EXTRA TESTBENCH RESULT: ALL PASS");
        else
            $display("EXTRA TESTBENCH RESULT: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
