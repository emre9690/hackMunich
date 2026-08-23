// Supplementary edge-case testbench for bcd_to_7seg_sn5446a.
//
// This is NOT the source of pass/fail truth for the design: the exhaustive
// 128-vector sweep against spec/chips/sn5446a.py remains that. This bench
// documents specific boundary conditions and input-state transitions as
// regression-safety notes, with one expectation per named scenario.
`timescale 1ns / 1ps

module sn5446a_tb_extra;

    reg A, B, C, D, LT_n, RBI_n, BI_n;
    wire a, b, c, d, e, f, g, RBO_n;

    integer errors = 0;
    integer checks = 0;

    localparam [6:0] ALL_OFF = 7'b111_1111;  // segments active low
    localparam [6:0] ALL_ON  = 7'b000_0000;
    localparam [6:0] SEG_0   = ~7'b111_1110;
    localparam [6:0] SEG_8   = ~7'b111_1111;
    localparam [6:0] SEG_15  = ~7'b000_0000;

    bcd_to_7seg_sn5446a dut (
        .A(A), .B(B), .C(C), .D(D),
        .LT_n(LT_n), .RBI_n(RBI_n), .BI_n(BI_n),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
        .RBO_n(RBO_n)
    );

    task apply;
        input [3:0] code;
        input lt_n_i, rbi_n_i, bi_n_i;
        begin
            A = code[0];
            B = code[1];
            C = code[2];
            D = code[3];
            LT_n  = lt_n_i;
            RBI_n = rbi_n_i;
            BI_n  = bi_n_i;
            #1;
        end
    endtask

    task check;
        input [8*48-1:0] name;
        input [6:0] exp_seg;
        input       exp_rbo_n;
        begin
            checks = checks + 1;
            if ({a, b, c, d, e, f, g} === exp_seg && RBO_n === exp_rbo_n) begin
                $display("PASS: %0s (seg=%b rbo_n=%b)", name,
                         {a, b, c, d, e, f, g}, RBO_n);
            end else begin
                errors = errors + 1;
                $display("FAIL: %0s got seg=%b rbo_n=%b, expected seg=%b rbo_n=%b",
                         name, {a, b, c, d, e, f, g}, RBO_n, exp_seg, exp_rbo_n);
            end
        end
    endtask

    initial begin
        $display("--- sn5446a_tb_extra: supplementary edge-case cases ---");

        // 1. Control-input priority: BI_n dominates a simultaneous lamp test.
        apply(4'd8, 1'b0, 1'b1, 1'b0);
        check("BI_n=0 overrides LT_n=0 (blank wins)", ALL_OFF, 1'b0);

        // 2. BI_n dominates the ripple-blank response condition too.
        apply(4'd0, 1'b1, 1'b0, 1'b0);
        check("BI_n=0 overrides RBI_n=0 at code 0", ALL_OFF, 1'b0);

        // 3. Lamp test outranks ripple blanking (all segments on, node high).
        apply(4'd0, 1'b0, 1'b0, 1'b1);
        check("LT_n=0 overrides RBI_n=0 at code 0", ALL_ON, 1'b1);

        // 4. Ripple blanking is code-sensitive: only the all-zero code blanks.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 blanks code 0", ALL_OFF, 1'b0);
        apply(4'd1, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 1 (LSB boundary)", ~7'b011_0000, 1'b1);
        apply(4'd8, 1'b1, 1'b0, 1'b1);
        check("RBI_n=0 does not blank code 8 (MSB boundary)", SEG_8, 1'b1);

        // 5. Decode boundaries of the 4-bit code space.
        apply(4'd0, 1'b1, 1'b1, 1'b1);
        check("code 0 with RBI_n=1 decodes normally", SEG_0, 1'b1);
        apply(4'd9, 1'b1, 1'b1, 1'b1);
        check("code 9, last valid BCD digit", ~7'b111_0011, 1'b1);
        apply(4'd10, 1'b1, 1'b1, 1'b1);
        check("code 10, first non-BCD pattern", ~7'b000_1101, 1'b1);
        apply(4'd15, 1'b1, 1'b1, 1'b1);
        check("code 15 is blank-like but RBO_n stays high", SEG_15, 1'b1);

        // 6. Code 15 vs true blanking: same segments, different RBO_n.
        if (RBO_n !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: code 15 must not assert RBO_n");
        end
        apply(4'd15, 1'b1, 1'b1, 1'b0);
        check("BI_n=0 at code 15 asserts RBO_n, decode 15 does not",
              ALL_OFF, 1'b0);

        // 7. Transitions between input states: combinational output must track
        //    the new state with no dependence on the previous one.
        apply(4'd0, 1'b1, 1'b0, 1'b1);   // blanked zero
        apply(4'd0, 1'b1, 1'b1, 1'b1);   // release RBI_n only
        check("RBI_n 0->1 at code 0 unblanks to digit 0", SEG_0, 1'b1);

        apply(4'd8, 1'b0, 1'b1, 1'b1);   // lamp test
        apply(4'd8, 1'b1, 1'b1, 1'b1);   // release LT_n only
        check("LT_n 0->1 returns to decode of code 8", SEG_8, 1'b1);

        apply(4'd3, 1'b1, 1'b1, 1'b0);   // blanked
        apply(4'd3, 1'b1, 1'b1, 1'b1);   // release BI_n only
        check("BI_n 0->1 restores decode of code 3", ~7'b111_1001, 1'b1);

        apply(4'd15, 1'b1, 1'b1, 1'b1);  // all-ones code
        apply(4'd0, 1'b1, 1'b1, 1'b1);   // all-zero code, every input bit flips
        check("code 15->0 in one step (all code bits toggle)", SEG_0, 1'b1);

        apply(4'd7, 1'b1, 1'b1, 1'b1);
        apply(4'd8, 1'b1, 1'b1, 1'b1);   // 0111 -> 1000 carry boundary
        check("code 7->8 carry boundary", SEG_8, 1'b1);

        // 8. Ripple-blank chain behavior: RBO_n low only in the response
        //    condition or under blanking, so a downstream stage sees a clean
        //    enable. Walk the zero code with RBI_n held low, then leave it.
        apply(4'd0, 1'b1, 1'b0, 1'b1);
        check("chain: zero suppressed, RBO_n propagates low", ALL_OFF, 1'b0);
        apply(4'd2, 1'b1, 1'b0, 1'b1);
        check("chain: first significant digit releases RBO_n", ~7'b110_1101, 1'b1);

        // 9. All three control inputs low at once.
        apply(4'd0, 1'b0, 1'b0, 1'b0);
        check("LT_n=RBI_n=BI_n=0 resolves to blank", ALL_OFF, 1'b0);

        $display("--- sn5446a_tb_extra: %0d checks, %0d failures ---",
                 checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EXTRA EDGE CASES PASSED");
        else
            $display("RESULT: %0d EXTRA EDGE CASE(S) FAILED", errors);
        $finish;
    end

endmodule
