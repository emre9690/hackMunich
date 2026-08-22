`default_nettype none
`timescale 1ns / 1ps

// Supplementary edge-case testbench for decoder_74138.
//
// The authoritative verification of this design is the external harness
// running the human-owned golden model (spec/chips/74138.py, 64 exhaustive
// vectors). This testbench adds no truth of its own: it documents and
// exercises specific edge cases (enable boundaries, select transitions,
// one-hot invariants) as regression-safety documentation.

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

    function [7:0] y_bus;
        input dummy;
        begin
            y_bus = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};
        end
    endfunction

    task apply;
        input a2, a1, a0;
        input g1, g2a_n, g2b_n;
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    task check;
        input [511:0] name;
        input [7:0] expected;
        begin
            if (y_bus(0) === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s (Y=%b)", name, y_bus(0));
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s (Y=%b, expected %b)", name, y_bus(0), expected);
            end
        end
    endtask

    // Expected one-hot-low bus for a given select index.
    function [7:0] sel_low;
        input [2:0] sel;
        begin
            sel_low = ~(8'b1 << sel);
        end
    endfunction

    integer i;
    reg [7:0] prev;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // --- Edge case 1: enable boundary conditions ---------------------
        // Only G1=1, G2A_n=0, G2B_n=0 enables the decoder. Check every
        // near-miss around that single enabling corner while select is held
        // at a non-zero value, so a stuck-enable bug cannot hide behind Y0.
        apply(1, 0, 1, 1, 0, 0);  // sel = 5, fully enabled
        check("enable corner: G1=1,G2A_n=0,G2B_n=0 -> Y5 low", sel_low(3'd5));
        apply(1, 0, 1, 0, 0, 0);
        check("disable via G1=0", 8'hFF);
        apply(1, 0, 1, 1, 1, 0);
        check("disable via G2A_n=1", 8'hFF);
        apply(1, 0, 1, 1, 0, 1);
        check("disable via G2B_n=1", 8'hFF);
        apply(1, 0, 1, 1, 1, 1);
        check("disable via both G2A_n=1 and G2B_n=1", 8'hFF);
        apply(1, 0, 1, 0, 1, 1);
        check("disable via all enables inactive", 8'hFF);

        // --- Edge case 2: select boundaries (min / max) ------------------
        apply(0, 0, 0, 1, 0, 0);
        check("select minimum sel=0 -> Y0 low", sel_low(3'd0));
        apply(1, 1, 1, 1, 0, 0);
        check("select maximum sel=7 -> Y7 low", sel_low(3'd7));

        // Select address is ignored entirely while disabled, including at
        // the min/max boundaries.
        apply(0, 0, 0, 0, 0, 0);
        check("disabled at sel=0 -> all high", 8'hFF);
        apply(1, 1, 1, 0, 0, 0);
        check("disabled at sel=7 -> all high", 8'hFF);

        // --- Edge case 3: one-hot invariant across every select ---------
        for (i = 0; i < 8; i = i + 1) begin
            apply(i[2], i[1], i[0], 1, 0, 0);
            check("one-hot-low invariant while enabled", sel_low(i[2:0]));
        end

        // --- Edge case 4: adjacent and multi-bit select transitions -----
        // Walk 3 -> 4 (all three select bits toggle at once) and back, and
        // 0 -> 7 -> 0, verifying the output settles on the new select and
        // never latches the previous value.
        apply(0, 1, 1, 1, 0, 0);
        check("transition start sel=3", sel_low(3'd3));
        prev = y_bus(0);
        apply(1, 0, 0, 1, 0, 0);
        check("multi-bit transition sel=3 -> sel=4", sel_low(3'd4));
        if (y_bus(0) !== prev) begin
            pass_count = pass_count + 1;
            $display("PASS: sel=3 -> sel=4 output changed (no stale latch)");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: sel=3 -> sel=4 output unchanged (stale latch?)");
        end
        apply(0, 1, 1, 1, 0, 0);
        check("multi-bit transition sel=4 -> sel=3", sel_low(3'd3));
        apply(0, 0, 0, 1, 0, 0);
        check("transition sel=3 -> sel=0", sel_low(3'd0));
        apply(1, 1, 1, 1, 0, 0);
        check("transition sel=0 -> sel=7", sel_low(3'd7));
        apply(0, 0, 0, 1, 0, 0);
        check("transition sel=7 -> sel=0", sel_low(3'd0));

        // --- Edge case 5: enable glitch / toggle while select is held ----
        // Hold sel=6 and toggle each enable off then on again; the same
        // single output must return low, with all-high in between.
        apply(1, 1, 0, 1, 0, 0);
        check("hold sel=6 enabled", sel_low(3'd6));
        apply(1, 1, 0, 1, 1, 0);
        check("hold sel=6, G2A_n pulsed high -> all high", 8'hFF);
        apply(1, 1, 0, 1, 0, 0);
        check("hold sel=6, G2A_n back low -> Y6 low again", sel_low(3'd6));
        apply(1, 1, 0, 0, 0, 0);
        check("hold sel=6, G1 pulsed low -> all high", 8'hFF);
        apply(1, 1, 0, 1, 0, 0);
        check("hold sel=6, G1 back high -> Y6 low again", sel_low(3'd6));

        // --- Edge case 6: select changes while disabled stay invisible ---
        apply(0, 0, 0, 1, 1, 1);
        check("disabled, sel=0 -> all high", 8'hFF);
        for (i = 0; i < 8; i = i + 1) begin
            apply(i[2], i[1], i[0], 1, 1, 1);
            check("disabled sweep of all selects -> all high", 8'hFF);
        end
        apply(0, 1, 0, 1, 0, 0);
        check("re-enable after disabled sweep -> Y2 low", sel_low(3'd2));

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL EDGE CASES PASSED");
        else
            $display("RESULT: %0d EDGE CASE(S) FAILED", fail_count);
        $finish;
    end

endmodule

`default_nettype wire
