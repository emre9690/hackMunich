// Supplementary edge-case testbench for decoder_74138.
//
// This is ADDITIONAL regression-safety documentation only. The exhaustive
// 64-vector verification against spec/chips/74138.py remains the sole source
// of pass/fail truth for this design; nothing here replaces it.
//
// Scenarios exercised:
//   1. Enable-gating boundary: all 8 combinations of {G1, G2A_n, G2B_n},
//      confirming exactly one of them enables the decoder.
//   2. Select walk while enabled: sel 0..7 in order, each asserting one-hot-low.
//   3. Address transitions: adjacent (Gray-like) and maximal (000<->111) changes,
//      confirming no stale output remains LOW after the address moves.
//   4. Disable while a select is active: outputs must all go HIGH regardless of
//      which address is applied, then recover when re-enabled.
//   5. Enable de-glitch ordering: toggling only G2A_n / only G2B_n with the
//      other enables held, checking each enable input independently gates.
//
// Run: iverilog -o tb rtl/74138.v rtl/74138_tb_extra.v && ./tb

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

    // Y7..Y0 packed for easy comparison.
    wire [7:0] y_bus = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    // Apply inputs and settle.
    task apply;
        input a2, a1, a0, g1, g2a_n, g2b_n;
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    // Compare y_bus against expectation and report.
    task check;
        input [7:0] expected;
        input [8*48:1] name;
        begin
            if (y_bus === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y_bus);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b (expected %b)",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y_bus, expected);
            end
        end
    endtask

    // Expected bus when enabled with the given select: one-hot LOW.
    function [7:0] onehot_low;
        input [2:0] sel;
        begin
            onehot_low = ~(8'b1 << sel);
        end
    endfunction

    integer i;
    reg [2:0] sel;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");
        $display("(informational only; golden-model harness owns pass/fail truth)");

        // --- Scenario 1: enable-gating boundary over all {G1,G2A_n,G2B_n} ---
        $display("-- Scenario 1: enable combinations at sel=3 --");
        for (i = 0; i < 8; i = i + 1) begin
            apply(0, 1, 1, i[2], i[1], i[0]); // sel = 3
            if (i[2] == 1'b1 && i[1] == 1'b0 && i[0] == 1'b0)
                check(onehot_low(3'd3), "enable combo: enabled -> Y3 low");
            else
                check(8'hFF, "enable combo: disabled -> all high");
        end

        // --- Scenario 2: full select walk while enabled ---
        $display("-- Scenario 2: select walk 0..7 while enabled --");
        for (i = 0; i < 8; i = i + 1) begin
            sel = i[2:0];
            apply(sel[2], sel[1], sel[0], 1'b1, 1'b0, 1'b0);
            check(onehot_low(sel), "select walk one-hot low");
        end

        // --- Scenario 3: address transitions (adjacent and maximal) ---
        $display("-- Scenario 3: address transitions --");
        apply(0, 0, 0, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd0), "transition start sel=0");
        apply(0, 0, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd1), "adjacent 000->001, Y0 released");
        apply(0, 1, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd3), "adjacent 001->011");
        apply(1, 1, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd7), "maximal 011->111");
        apply(0, 0, 0, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd0), "maximal 111->000, Y7 released");
        apply(1, 0, 0, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd4), "single-bit A2 flip 000->100");

        // --- Scenario 4: disable while a select is active, then recover ---
        $display("-- Scenario 4: disable/re-enable with select held --");
        apply(1, 0, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd5), "sel=5 enabled");
        apply(1, 0, 1, 1'b0, 1'b0, 1'b0);
        check(8'hFF, "G1 dropped -> all high, sel held");
        apply(1, 0, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd5), "G1 restored -> Y5 low again");
        apply(1, 0, 1, 1'b1, 1'b1, 1'b0);
        check(8'hFF, "G2A_n high -> all high");
        apply(1, 0, 1, 1'b1, 1'b0, 1'b1);
        check(8'hFF, "G2B_n high -> all high");
        apply(1, 0, 1, 1'b1, 1'b1, 1'b1);
        check(8'hFF, "both G2 high -> all high");
        apply(1, 0, 1, 1'b1, 1'b0, 1'b0);
        check(onehot_low(3'd5), "both G2 low -> Y5 low again");

        // --- Scenario 5: independent gating of each enable input ---
        $display("-- Scenario 5: each enable input gates independently --");
        for (i = 0; i < 8; i = i + 1) begin
            sel = i[2:0];
            apply(sel[2], sel[1], sel[0], 1'b0, 1'b0, 1'b0);
            check(8'hFF, "G1=0 blocks every select");
        end
        for (i = 0; i < 8; i = i + 1) begin
            sel = i[2:0];
            apply(sel[2], sel[1], sel[0], 1'b1, 1'b1, 1'b0);
            check(8'hFF, "G2A_n=1 blocks every select");
        end
        for (i = 0; i < 8; i = i + 1) begin
            sel = i[2:0];
            apply(sel[2], sel[1], sel[0], 1'b1, 1'b0, 1'b1);
            check(8'hFF, "G2B_n=1 blocks every select");
        end

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

endmodule
