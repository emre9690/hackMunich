// Supplementary edge-case testbench for decoder_74138.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness comparing rtl/74138.v against spec/chips/74138.py (64 exhaustive
// vectors) remains authoritative. This bench documents boundary conditions
// and input-state transitions as regression-safety documentation.
`timescale 1ns / 1ps

module decoder_74138_tb_extra;

    reg A0, A1, A2, G1, G2A_n, G2B_n;
    wire Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7;

    integer errors = 0;
    integer checks = 0;

    decoder_74138 dut (
        .A0(A0), .A1(A1), .A2(A2),
        .G1(G1), .G2A_n(G2A_n), .G2B_n(G2B_n),
        .Y0(Y0), .Y1(Y1), .Y2(Y2), .Y3(Y3),
        .Y4(Y4), .Y5(Y5), .Y6(Y6), .Y7(Y7)
    );

    // Packed view of the outputs: bit i == Yi.
    wire [7:0] y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    // Expected output word: all HIGH, except the selected line when enabled.
    function [7:0] expected;
        input [2:0] sel;
        input       enabled;
        begin
            expected = 8'hFF;
            if (enabled) expected[sel] = 1'b0;
        end
    endfunction

    task apply;
        input a2, a1, a0, g1, g2a_n, g2b_n;
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    task check;
        input [8*64-1:0] name;
        input [7:0]      exp;
        begin
            checks = checks + 1;
            if (y === exp) begin
                $display("PASS: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y);
            end else begin
                errors = errors + 1;
                $display("FAIL: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b (expected %b)",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y, exp);
            end
        end
    endtask

    // Enabled case with an explicit expected word.
    task check_enabled;
        input [8*64-1:0] name;
        input [2:0]      sel;
        begin
            check(name, expected(sel, 1'b1));
        end
    endtask

    task check_disabled;
        input [8*64-1:0] name;
        begin
            check(name, 8'hFF);
        end
    endtask

    integer i;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // --- Case group 1: select boundaries (min and max address) ---
        apply(0, 0, 0, 1, 0, 0);
        check_enabled("boundary: lowest select (A=000) asserts Y0", 3'd0);
        apply(1, 1, 1, 1, 0, 0);
        check_enabled("boundary: highest select (A=111) asserts Y7", 3'd7);

        // --- Case group 2: every disable combination at a fixed select ---
        // Only G1=1, G2A_n=0, G2B_n=0 may enable the part.
        apply(1, 0, 1, 0, 0, 0);
        check_disabled("disable: G1 low alone blocks output");
        apply(1, 0, 1, 1, 1, 0);
        check_disabled("disable: G2A_n high alone blocks output");
        apply(1, 0, 1, 1, 0, 1);
        check_disabled("disable: G2B_n high alone blocks output");
        apply(1, 0, 1, 1, 1, 1);
        check_disabled("disable: both active-low gates high block output");
        apply(1, 0, 1, 0, 1, 1);
        check_disabled("disable: all enables wrong blocks output");

        // --- Case group 3: select changes while disabled stay inert ---
        for (i = 0; i < 8; i = i + 1) begin
            apply(i[2], i[1], i[0], 0, 0, 0);
            check_disabled("disabled sweep: select change must not drive a line");
        end

        // --- Case group 4: enable transitions at a fixed select ---
        apply(0, 1, 1, 1, 0, 0);
        check_enabled("transition: enable asserted selects Y3", 3'd3);
        apply(0, 1, 1, 1, 0, 1);
        check_disabled("transition: de-assert G2B_n releases Y3");
        apply(0, 1, 1, 1, 0, 0);
        check_enabled("transition: re-enable re-asserts Y3", 3'd3);

        // --- Case group 5: adjacent-select transitions (one-hot handoff) ---
        // Walking the select up and back down must move the single LOW line
        // without ever leaving two lines low.
        for (i = 0; i < 8; i = i + 1) begin
            apply(i[2], i[1], i[0], 1, 0, 0);
            check_enabled("walk up: exactly one line low follows select", i[2:0]);
        end
        for (i = 7; i >= 0; i = i - 1) begin
            apply(i[2], i[1], i[0], 1, 0, 0);
            check_enabled("walk down: exactly one line low follows select", i[2:0]);
        end

        // --- Case group 6: multi-bit select jumps (000 <-> 111, 011 <-> 100) ---
        apply(0, 0, 0, 1, 0, 0);
        check_enabled("jump: 000 before all-bits flip", 3'd0);
        apply(1, 1, 1, 1, 0, 0);
        check_enabled("jump: 111 after all-bits flip", 3'd7);
        apply(0, 1, 1, 1, 0, 0);
        check_enabled("jump: 011 before carry-style flip", 3'd3);
        apply(1, 0, 0, 1, 0, 0);
        check_enabled("jump: 100 after carry-style flip", 3'd4);

        // --- Case group 7: enable glitch while select is mid-change ---
        apply(0, 1, 0, 1, 0, 0);
        check_enabled("glitch: stable Y2 before enable pulse", 3'd2);
        G1 = 1'b0; #1;
        check_disabled("glitch: enable low during select change");
        A2 = 1'b1; A1 = 1'b0; A0 = 1'b1; #1;
        check_disabled("glitch: select changed while disabled stays inert");
        G1 = 1'b1; #1;
        check_enabled("glitch: enable restored asserts new select Y5", 3'd5);

        $display("=== summary: %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EDGE-CASE CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
