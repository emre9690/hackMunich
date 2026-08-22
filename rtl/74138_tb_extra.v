// Supplementary edge-case testbench for decoder_74138.
//
// This is NOT the source of pass/fail truth for the design: the external
// harness checks rtl/74138.v exhaustively (64 vectors) against the
// human-owned golden model in spec/chips/74138.py. This file documents
// additional edge cases -- enable boundary conditions, select-line
// transitions, and one-cold output invariants -- as regression-safety
// documentation.
`timescale 1ns / 1ps

module decoder_74138_tb_extra;

    reg A0, A1, A2, G1, G2A_n, G2B_n;
    wire Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7;

    integer pass_count = 0;
    integer fail_count = 0;

    decoder_74138 dut (
        .A0(A0), .A1(A1), .A2(A2),
        .G1(G1), .G2A_n(G2A_n), .G2B_n(G2B_n),
        .Y0(Y0), .Y1(Y1), .Y2(Y2), .Y3(Y3),
        .Y4(Y4), .Y5(Y5), .Y6(Y6), .Y7(Y7)
    );

    wire [7:0] Y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    // Expected output bus: all HIGH when disabled, one-cold at sel otherwise.
    function [7:0] expected_bus;
        input enabled;
        input [2:0] sel;
        begin
            expected_bus = enabled ? ~(8'b1 << sel) : 8'hFF;
        end
    endfunction

    task apply_inputs;
        input a2, a1, a0;
        input g1, g2a_n, g2b_n;
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    // Drive inputs, then compare the output bus against the expectation.
    task check_case;
        input [8*40:1] name;
        input a2, a1, a0;
        input g1, g2a_n, g2b_n;
        reg enabled;
        reg [2:0] sel;
        reg [7:0] exp;
        begin
            apply_inputs(a2, a1, a0, g1, g2a_n, g2b_n);
            enabled = g1 & ~g2a_n & ~g2b_n;
            sel = {a2, a1, a0};
            exp = expected_bus(enabled, sel);
            if (Y === exp) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b | Y=%b",
                         name, a2, a1, a0, g1, g2a_n, g2b_n, Y);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b | Y=%b expected %b",
                         name, a2, a1, a0, g1, g2a_n, g2b_n, Y, exp);
            end
        end
    endtask

    // Independent invariant: enabled outputs must be exactly one-cold.
    task check_one_cold;
        input [8*40:1] name;
        integer i;
        integer low_count;
        begin
            low_count = 0;
            for (i = 0; i < 8; i = i + 1)
                if (Y[i] === 1'b0) low_count = low_count + 1;
            if (low_count == 1) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | Y=%b has exactly one LOW", name, Y);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | Y=%b has %0d LOW outputs, expected 1",
                         name, Y, low_count);
            end
        end
    endtask

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        $display("-- select boundaries (min and max address, fully enabled) --");
        check_case("sel min 000 -> Y0 low",   1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_one_cold("sel min 000 one-cold");
        check_case("sel max 111 -> Y7 low",   1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        check_one_cold("sel max 111 one-cold");

        $display("-- enable boundary: each enable wrong in isolation --");
        check_case("G1=0 only",              1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        check_case("G2A_n=1 only",           1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0);
        check_case("G2B_n=1 only",           1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1);
        check_case("all enables wrong",      1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1);

        $display("-- disabled outputs stay HIGH across every select value --");
        begin : disabled_sweep
            integer s;
            for (s = 0; s < 8; s = s + 1)
                check_case("disabled, sweeping select",
                           (s >> 2) & 1'b1, (s >> 1) & 1'b1, s & 1'b1,
                           1'b0, 1'b0, 1'b0);
        end

        $display("-- single-bit select transitions (adjacent codes) --");
        begin : adjacent_sweep
            integer s;
            for (s = 0; s < 8; s = s + 1) begin
                check_case("gray-ish step: A0 toggled",
                           (s >> 2) & 1'b1, (s >> 1) & 1'b1, ~s & 1'b1,
                           1'b1, 1'b0, 1'b0);
                check_case("gray-ish step: A2 toggled",
                           ~(s >> 2) & 1'b1, (s >> 1) & 1'b1, s & 1'b1,
                           1'b1, 1'b0, 1'b0);
            end
        end

        $display("-- all-bits select transition 000 <-> 111 --");
        check_case("000 after 111",          1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_case("111 after 000",          1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);

        $display("-- enable transitions with select held constant (sel=101) --");
        check_case("sel 101 enabled",        1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0);
        check_one_cold("sel 101 enabled one-cold");
        check_case("sel 101 disabled by G1", 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        check_case("sel 101 re-enabled",     1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0);
        check_one_cold("sel 101 re-enabled one-cold");

        $display("-- select changes while disabled, then enable --");
        apply_inputs(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0); // sel=010, disabled
        apply_inputs(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0); // sel=100, still disabled
        check_case("enable after hidden select change",
                   1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL EDGE CASES PASSED");
        else
            $display("RESULT: %0d EDGE CASE(S) FAILED", fail_count);
        $finish;
    end

endmodule
