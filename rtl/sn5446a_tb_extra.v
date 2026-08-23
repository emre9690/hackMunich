// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the verification source of truth: the design is already verified
// exhaustively against the golden model in spec/chips/sn5446a.py by the external
// harness. This testbench documents specific edge cases -- control-input
// priority, the code==0 boundary of ripple blanking, the all-segments-off
// decode of code 15 versus a real blank, and input transitions -- so that a
// future regression in any of them fails loudly and readably.
//
// Segment outputs are active low: 0 = segment ON, 1 = segment OFF.
// Expected patterns below are written as {a,b,c,d,e,f,g}.
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

    wire [6:0] seg = {a, b, c, d, e, f, g};

    localparam [6:0] ALL_OFF = 7'b1111111;
    localparam [6:0] ALL_ON  = 7'b0000000;
    localparam [6:0] DIG_0   = 7'b0000001;
    localparam [6:0] DIG_1   = 7'b1001111;
    localparam [6:0] DIG_5   = 7'b0100100;
    localparam [6:0] DIG_8   = 7'b0000000;
    localparam [6:0] DIG_9   = 7'b0001100;
    localparam [6:0] CODE_10 = 7'b1110010;
    localparam [6:0] CODE_15 = 7'b1111111;

    // Drive one input vector and compare segments + RBO_n against expectation.
    task check;
        input [8*48-1:0] name;
        input [3:0] code;
        input lt_n_in, rbi_n_in, bi_n_in;
        input [6:0] exp_seg;
        input exp_rbo_n;
        begin
            {D, C, B, A} = code;
            LT_n  = lt_n_in;
            RBI_n = rbi_n_in;
            BI_n  = bi_n_in;
            #5;
            if (seg === exp_seg && RBO_n === exp_rbo_n) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b",
                         name, code, lt_n_in, rbi_n_in, bi_n_in, seg, RBO_n);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s | code=%0d LT_n=%b RBI_n=%b BI_n=%b -> seg=%b RBO_n=%b (expected seg=%b RBO_n=%b)",
                         name, code, lt_n_in, rbi_n_in, bi_n_in, seg, RBO_n, exp_seg, exp_rbo_n);
            end
            #5;
        end
    endtask

    initial begin
        $display("=== sn5446a_tb_extra: supplementary edge-case checks ===");

        // --- Control-input priority ---------------------------------------
        // BI_n dominates every other input, including lamp test.
        check("BI_n overrides lamp test",            4'd8, 1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        // BI_n dominates ripple blanking and a valid decode alike.
        check("BI_n overrides ripple blank",         4'd0, 1'b1, 1'b0, 1'b0, ALL_OFF, 1'b0);
        check("BI_n overrides valid decode",         4'd5, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);
        // Lamp test outranks ripple blanking when the BI/RBO node is high.
        check("lamp test outranks ripple blank",     4'd0, 1'b0, 1'b0, 1'b1, ALL_ON,  1'b1);
        // Lamp test ignores the BCD code entirely.
        check("lamp test ignores code 15",           4'd15, 1'b0, 1'b1, 1'b1, ALL_ON, 1'b1);

        // --- Ripple-blanking boundary (code == 0 only) ---------------------
        check("RBI_n low blanks code 0",             4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        // Code 1 is the adjacent code: ripple blanking must not reach it.
        check("RBI_n low leaves code 1 decoded",     4'd1, 1'b1, 1'b0, 1'b1, DIG_1,  1'b1);
        check("RBI_n high decodes code 0",           4'd0, 1'b1, 1'b1, 1'b1, DIG_0,  1'b1);
        // Highest code with RBI_n low: still a plain decode, RBO_n stays high.
        check("RBI_n low leaves code 15 decoded",    4'd15, 1'b1, 1'b0, 1'b1, CODE_15, 1'b1);

        // --- Blank-versus-decode aliasing ---------------------------------
        // Code 15 drives all segments off, but it is NOT a blank: RBO_n = 1
        // distinguishes it from the BI_n / ripple-blank cases above.
        check("code 15 all-off but RBO_n high",      4'd15, 1'b1, 1'b1, 1'b1, ALL_OFF, 1'b1);
        // Code 8 lights all segments, but it is NOT lamp test; same pattern,
        // reached through the decode path.
        check("code 8 all-on via decode",            4'd8, 1'b1, 1'b1, 1'b1, DIG_8,  1'b1);

        // --- BCD / non-BCD boundary ---------------------------------------
        check("last valid BCD code 9",               4'd9, 1'b1, 1'b1, 1'b1, DIG_9,  1'b1);
        check("first non-BCD code 10",               4'd10, 1'b1, 1'b1, 1'b1, CODE_10, 1'b1);

        // --- Transitions between input states -----------------------------
        // Releasing BI_n must restore the decode of the code still applied.
        check("pre-blank decode of code 5",          4'd5, 1'b1, 1'b1, 1'b1, DIG_5,  1'b1);
        check("blank applied over code 5",           4'd5, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("decode restored after blank release", 4'd5, 1'b1, 1'b1, 1'b1, DIG_5,  1'b1);

        // Releasing lamp test with BI_n low leaves the part blanked, not decoded.
        check("lamp test then blank still blank",    4'd5, 1'b0, 1'b1, 1'b0, ALL_OFF, 1'b0);
        check("lamp test released while blanked",    4'd5, 1'b1, 1'b1, 1'b0, ALL_OFF, 1'b0);

        // Walking the code inputs while ripple blanking is armed: only the
        // all-zero code blanks, and RBO_n follows on every transition.
        check("armed RBI: code 0 blanks",            4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        check("armed RBI: code 1 decodes",           4'd1, 1'b1, 1'b0, 1'b1, DIG_1,  1'b1);
        check("armed RBI: back to code 0 blanks",    4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);
        check("armed RBI: code 8 decodes",           4'd8, 1'b1, 1'b0, 1'b1, DIG_8,  1'b1);
        check("armed RBI: back to code 0 blanks",    4'd0, 1'b1, 1'b0, 1'b1, ALL_OFF, 1'b0);

        $display("=== sn5446a_tb_extra: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
