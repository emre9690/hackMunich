// Supplementary edge-case testbench for decoder_74138.
// The exhaustive golden-vector harness (spec/chips/74138.py) remains the sole
// source of pass/fail truth; this bench documents boundary conditions and
// input-state transitions as regression-safety documentation.
`timescale 1ns / 1ps

module decoder_74138_tb_extra;

    reg A0, A1, A2, G1, G2A_n, G2B_n;
    wire Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7;

    integer checks_run = 0;
    integer checks_failed = 0;

    decoder_74138 dut (
        .A0(A0), .A1(A1), .A2(A2),
        .G1(G1), .G2A_n(G2A_n), .G2B_n(G2B_n),
        .Y0(Y0), .Y1(Y1), .Y2(Y2), .Y3(Y3),
        .Y4(Y4), .Y5(Y5), .Y6(Y6), .Y7(Y7)
    );

    function [7:0] y_bus;
        input dummy;
        begin
            y_bus = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};
        end
    endfunction

    // Expected Y bus: all HIGH when disabled, single LOW at sel when enabled.
    function [7:0] expected_bus;
        input a0, a1, a2, g1, g2a_n, g2b_n;
        reg [2:0] sel;
        begin
            sel = {a2, a1, a0};
            if (g1 && !g2a_n && !g2b_n)
                expected_bus = ~(8'b1 << sel);
            else
                expected_bus = 8'hFF;
        end
    endfunction

    task apply;
        input a0, a1, a2, g1, g2a_n, g2b_n;
        begin
            A0 = a0; A1 = a1; A2 = a2;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    task check;
        input [8*48-1:0] label;
        reg [7:0] exp;
        reg [7:0] got;
        begin
            exp = expected_bus(A0, A1, A2, G1, G2A_n, G2B_n);
            got = y_bus(0);
            checks_run = checks_run + 1;
            if (got === exp)
                $display("PASS: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b",
                         label, A2, A1, A0, G1, G2A_n, G2B_n, got);
            else begin
                checks_failed = checks_failed + 1;
                $display("FAIL: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b (expected %b)",
                         label, A2, A1, A0, G1, G2A_n, G2B_n, got, exp);
            end
        end
    endtask

    task step;
        input [8*48-1:0] label;
        input a0, a1, a2, g1, g2a_n, g2b_n;
        begin
            apply(a0, a1, a2, g1, g2a_n, g2b_n);
            check(label);
        end
    endtask

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // --- Case group 1: select-code boundaries (min and max address) ---
        step("sel boundary: lowest address 000 enabled",  0, 0, 0, 1, 0, 0);
        step("sel boundary: highest address 111 enabled", 1, 1, 1, 1, 0, 0);

        // --- Case group 2: each enable pin individually gating the decoder ---
        step("enable: G1 deasserted disables (sel=011)",    1, 1, 0, 0, 0, 0);
        step("enable: G2A_n asserted disables (sel=011)",   1, 1, 0, 1, 1, 0);
        step("enable: G2B_n asserted disables (sel=011)",   1, 1, 0, 1, 0, 1);
        step("enable: all enables wrong (sel=011)",         1, 1, 0, 0, 1, 1);

        // --- Case group 3: enable transitions with the address held stable ---
        step("transition: hold sel=101, start disabled", 1, 0, 1, 0, 0, 0);
        step("transition: hold sel=101, enable",         1, 0, 1, 1, 0, 0);
        step("transition: hold sel=101, disable via G2A_n", 1, 0, 1, 1, 1, 0);
        step("transition: hold sel=101, re-enable",      1, 0, 1, 1, 0, 0);

        // --- Case group 4: address transitions while continuously enabled ---
        step("addr walk: 000 -> active Y0", 0, 0, 0, 1, 0, 0);
        step("addr walk: 001 -> active Y1", 1, 0, 0, 1, 0, 0);
        step("addr walk: 011 -> active Y3", 1, 1, 0, 1, 0, 0);
        step("addr walk: 111 -> active Y7", 1, 1, 1, 1, 0, 0);
        step("addr walk: 000 wrap-around",  0, 0, 0, 1, 0, 0);

        // --- Case group 5: multi-bit address changes (adjacent vs. far jumps) ---
        step("addr jump: 111 -> 000 all bits toggle (part 1)", 1, 1, 1, 1, 0, 0);
        step("addr jump: 111 -> 000 all bits toggle (part 2)", 0, 0, 0, 1, 0, 0);
        step("addr jump: 010 -> 101 all bits toggle (part 1)", 0, 1, 0, 1, 0, 0);
        step("addr jump: 010 -> 101 all bits toggle (part 2)", 1, 0, 1, 1, 0, 0);

        // --- Case group 6: address changes while disabled must stay inert ---
        step("disabled sweep: sel=000 while G1=0", 0, 0, 0, 0, 0, 0);
        step("disabled sweep: sel=010 while G1=0", 0, 1, 0, 0, 0, 0);
        step("disabled sweep: sel=110 while G1=0", 0, 1, 1, 0, 0, 0);
        step("disabled sweep: sel=111 while G1=0", 1, 1, 1, 0, 0, 0);

        // --- Case group 7: one-hot invariant (exactly one LOW when enabled) ---
        begin : one_hot_check
            integer i;
            reg [7:0] bus;
            for (i = 0; i < 8; i = i + 1) begin
                apply(i[0], i[1], i[2], 1, 0, 0);
                bus = y_bus(0);
                checks_run = checks_run + 1;
                if (^(~bus) === 1'b1 && (~bus) == (8'b1 << i))
                    $display("PASS: one-hot invariant for sel=%0d -> Y=%b", i, bus);
                else begin
                    checks_failed = checks_failed + 1;
                    $display("FAIL: one-hot invariant for sel=%0d -> Y=%b", i, bus);
                end
            end
        end

        $display("=== summary: %0d checks, %0d failures ===", checks_run, checks_failed);
        if (checks_failed == 0)
            $display("RESULT: ALL EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EDGE-CASE CHECK(S) FAILED", checks_failed);
        $finish;
    end

endmodule
