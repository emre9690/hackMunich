// Supplementary edge-case testbench for decoder_74138.
//
// NOTE: this is NOT the source of pass/fail truth for the design. The golden
// model in spec/chips/74138.py plus the external harness (64 exhaustive
// vectors) remain authoritative. This file documents additional edge-case
// scenarios -- enable-boundary conditions, select transitions and one-hot
// invariants -- as regression-safety documentation.
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

    wire [7:0] y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    function [7:0] expected;
        input a0, a1, a2, g1, g2a_n, g2b_n;
        reg [2:0] sel;
        begin
            sel = {a2, a1, a0};
            if (g1 === 1'b1 && g2a_n === 1'b0 && g2b_n === 1'b0)
                expected = ~(8'b1 << sel);
            else
                expected = 8'hFF;
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

    // Checks the current output bus against the golden-equivalent expectation.
    task check;
        input [8*48-1:0] name;
        reg [7:0] exp;
        begin
            exp = expected(A0, A1, A2, G1, G2A_n, G2B_n);
            if (y === exp) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b (expected %b)",
                         name, A2, A1, A0, G1, G2A_n, G2B_n, y, exp);
            end
        end
    endtask

    // Verifies exactly one output is low while enabled, and it is the selected one.
    task check_one_hot_low;
        input [8*48-1:0] name;
        integer i;
        integer low_count;
        reg [2:0] sel;
        begin
            low_count = 0;
            for (i = 0; i < 8; i = i + 1)
                if (y[i] === 1'b0) low_count = low_count + 1;
            sel = {A2, A1, A0};
            if (low_count == 1 && y[sel] === 1'b0) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | sel=%0d Y=%b (exactly one low, at sel)", name, sel, y);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | sel=%0d Y=%b (low_count=%0d)", name, sel, y, low_count);
            end
        end
    endtask

    integer sel_i;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // ---- Case group 1: enable boundary -- each disabling condition alone.
        $display("-- group 1: enable boundary conditions (select fixed at 3'd5)");
        apply(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0); check("enabled, sel=5");
        apply(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0); check("G1 low alone disables");
        apply(1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0); check("G2A_n high alone disables");
        apply(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1); check("G2B_n high alone disables");
        apply(1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1); check("all enables wrong");

        // ---- Case group 2: select boundaries (min/max) at both enable states.
        $display("-- group 2: select boundaries sel=0 and sel=7");
        apply(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0); check("sel=0 enabled (Y0 low)");
        apply(1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0); check("sel=7 enabled (Y7 low)");
        apply(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0); check("sel=0 disabled (all high)");
        apply(1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1); check("sel=7 disabled (all high)");

        // ---- Case group 3: one-hot invariant across the full select sweep.
        $display("-- group 3: one-hot-low invariant over sel=0..7 while enabled");
        for (sel_i = 0; sel_i < 8; sel_i = sel_i + 1) begin
            apply(sel_i[0], sel_i[1], sel_i[2], 1'b1, 1'b0, 1'b0);
            check_one_hot_low("one-hot low while enabled");
        end

        // ---- Case group 4: multi-bit select transitions (walking and wrap-around).
        $display("-- group 4: select transitions");
        apply(1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0); check("transition to sel=7");
        apply(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0); check("7 -> 0 wrap (all 3 bits toggle)");
        apply(1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0); check("0 -> 3 (two bits toggle)");
        apply(1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0); check("3 -> 4 (all 3 bits toggle)");
        apply(1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0); check("4 -> 1 (LSB+MSB toggle)");

        // ---- Case group 5: enable glitch/transition with the select held stable.
        $display("-- group 5: enable transitions with select held at 3'd2");
        apply(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0); check("sel=2, start disabled");
        apply(1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0); check("sel=2, enable asserted");
        apply(1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0); check("sel=2, disabled via G2A_n");
        apply(1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0); check("sel=2, re-enabled");

        // ---- Case group 6: select changes while disabled must never drive a low.
        $display("-- group 6: select changes while disabled keep all outputs high");
        for (sel_i = 0; sel_i < 8; sel_i = sel_i + 1) begin
            apply(sel_i[0], sel_i[1], sel_i[2], 1'b0, 1'b0, 1'b0);
            check("disabled sweep: all outputs high");
        end

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
