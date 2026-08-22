// Supplementary edge-case testbench for decoder_74138.
//
// This is ADDITIONAL regression-safety documentation only. The authoritative
// pass/fail truth for this design is the external harness running the
// human-owned golden model in spec/chips/74138.py (64 exhaustive vectors).
// Nothing here replaces or overrides that source of truth.
//
// Focus: boundary conditions and transitions between input states, which the
// combinational exhaustive vector sweep does not explicitly document.
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

    // Packed view of the outputs: bit i == Y{i}.
    wire [7:0] y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    task apply(input a2, input a1, input a0,
               input g1, input g2a_n, input g2b_n);
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #1;
        end
    endtask

    task check(input [8*64-1:0] name, input [7:0] expected);
        begin
            if (y === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s (y=%b)", name, y);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s (y=%b, expected=%b)", name, y, expected);
            end
        end
    endtask

    // Expected packed outputs: one-cold at sel when enabled.
    function [7:0] one_cold(input [2:0] sel);
        one_cold = ~(8'b1 << sel);
    endfunction

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");
        $display("=== (advisory only; golden harness is the truth source) ===");

        // --- Case 1: select boundaries (lowest and highest address) ---
        apply(0, 0, 0, 1, 0, 0);
        check("sel=0 boundary: only Y0 low", one_cold(3'd0));
        apply(1, 1, 1, 1, 0, 0);
        check("sel=7 boundary: only Y7 low", one_cold(3'd7));

        // --- Case 2: each enable input individually breaks the enable ---
        apply(0, 1, 1, 0, 0, 0);
        check("G1=0 disables (sel=3)", 8'hFF);
        apply(0, 1, 1, 1, 1, 0);
        check("G2A_n=1 disables (sel=3)", 8'hFF);
        apply(0, 1, 1, 1, 0, 1);
        check("G2B_n=1 disables (sel=3)", 8'hFF);
        apply(0, 1, 1, 0, 1, 1);
        check("all enables wrong disables (sel=3)", 8'hFF);

        // --- Case 3: disabled state is address-independent ---
        apply(0, 0, 0, 1, 1, 1);
        check("disabled at sel=0: all high", 8'hFF);
        apply(1, 1, 1, 1, 1, 1);
        check("disabled at sel=7: all high", 8'hFF);

        // --- Case 4: address transitions while enabled (adjacent codes) ---
        apply(0, 1, 1, 1, 0, 0);   // sel=3
        check("transition step sel=3", one_cold(3'd3));
        apply(1, 0, 0, 1, 0, 0);   // sel=4, all three address bits toggle
        check("transition 3->4 (all addr bits flip): only Y4 low", one_cold(3'd4));
        apply(1, 0, 1, 1, 0, 0);   // sel=5, single bit toggle
        check("transition 4->5 (single addr bit): only Y5 low", one_cold(3'd5));

        // --- Case 5: enable transitions with the address held constant ---
        apply(1, 0, 1, 1, 0, 0);
        check("enabled at sel=5 before disable", one_cold(3'd5));
        apply(1, 0, 1, 1, 1, 0);
        check("disable via G2A_n with sel held at 5", 8'hFF);
        apply(1, 0, 1, 1, 0, 0);
        check("re-enable restores sel=5 output", one_cold(3'd5));

        // --- Case 6: address changed while disabled, then enabled ---
        apply(1, 1, 0, 1, 1, 1);   // sel=6 but disabled
        check("sel changed to 6 while disabled: all high", 8'hFF);
        apply(1, 1, 0, 1, 0, 0);
        check("enable after disabled sel change: only Y6 low", one_cold(3'd6));

        // --- Case 7: full enabled sweep asserts exactly-one-low invariant ---
        begin : sweep
            integer s;
            for (s = 0; s < 8; s = s + 1) begin
                apply(s[2], s[1], s[0], 1, 0, 0);
                if (y === one_cold(s[2:0])) begin
                    pass_count = pass_count + 1;
                    $display("PASS: exactly-one-low invariant at sel=%0d (y=%b)", s, y);
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL: exactly-one-low invariant at sel=%0d (y=%b, expected=%b)",
                             s, y, one_cold(s[2:0]));
                end
            end
        end

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("NOTE: failures here are advisory; consult the golden harness.");
        $finish;
    end

endmodule
