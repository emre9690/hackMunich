`default_nettype none
`timescale 1ns / 1ps

// Supplementary edge-case testbench for decoder_74138.
// The exhaustive 64-vector golden-model check in the external harness remains
// the sole source of pass/fail truth; this bench documents boundary conditions
// and input-state transitions as regression-safety documentation.

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

    // Expected bus: one-hot-low on `sel` when enabled, all high otherwise.
    function [7:0] expected_bus;
        input [2:0] sel;
        input enabled;
        begin
            expected_bus = 8'hFF;
            if (enabled) expected_bus[sel] = 1'b0;
        end
    endfunction

    task check;
        input [8*40-1:0] label;
        input [7:0] expected;
        reg [7:0] actual;
        begin
            actual = y_bus(1'b0);
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS | %0s | Y=%b", label, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | %0s | Y=%b expected=%b", label, actual, expected);
            end
        end
    endtask

    task drive;
        input [2:0] sel;
        input g1;
        input g2a_n;
        input g2b_n;
        begin
            A0 = sel[0];
            A1 = sel[1];
            A2 = sel[2];
            G1 = g1;
            G2A_n = g2a_n;
            G2B_n = g2b_n;
            #1;
        end
    endtask

    task apply_and_check;
        input [8*40-1:0] label;
        input [2:0] sel;
        input g1;
        input g2a_n;
        input g2b_n;
        begin
            drive(sel, g1, g2a_n, g2b_n);
            check(label, expected_bus(sel, g1 & ~g2a_n & ~g2b_n));
        end
    endtask

    // Counts how many outputs are asserted (low) in the current Y bus.
    function integer low_count;
        input [7:0] bus;
        integer b;
        begin
            low_count = 0;
            for (b = 0; b < 8; b = b + 1)
                if (bus[b] === 1'b0) low_count = low_count + 1;
        end
    endfunction

    integer i;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // Case group 1: address boundaries with the decoder fully enabled.
        apply_and_check("addr min (sel=0) enabled",  3'd0, 1'b1, 1'b0, 1'b0);
        apply_and_check("addr max (sel=7) enabled",  3'd7, 1'b1, 1'b0, 1'b0);

        // Case group 2: every enable-input combination that must disable.
        apply_and_check("disabled: G1=0",            3'd3, 1'b0, 1'b0, 1'b0);
        apply_and_check("disabled: G2A_n=1",         3'd3, 1'b1, 1'b1, 1'b0);
        apply_and_check("disabled: G2B_n=1",         3'd3, 1'b1, 1'b0, 1'b1);
        apply_and_check("disabled: both G2 high",    3'd3, 1'b1, 1'b1, 1'b1);
        apply_and_check("disabled: all enables off", 3'd3, 1'b0, 1'b1, 1'b1);

        // Case group 3: address changes while disabled must not select anything.
        for (i = 0; i < 8; i = i + 1) begin
            apply_and_check("addr sweep while disabled", i[2:0], 1'b0, 1'b0, 1'b0);
        end

        // Case group 4: enable/disable transitions holding the address stable.
        apply_and_check("transition: enable at sel=5",   3'd5, 1'b1, 1'b0, 1'b0);
        apply_and_check("transition: disable at sel=5",  3'd5, 1'b1, 1'b0, 1'b1);
        apply_and_check("transition: re-enable at sel=5", 3'd5, 1'b1, 1'b0, 1'b0);

        // Case group 5: adjacent-address transitions (single-bit A changes)
        // and the max->min wrap, checking no stale output stays low.
        for (i = 0; i < 8; i = i + 1) begin
            apply_and_check("walk sel up while enabled", i[2:0], 1'b1, 1'b0, 1'b0);
        end
        apply_and_check("wrap sel 7 -> 0 enabled", 3'd0, 1'b1, 1'b0, 1'b0);
        apply_and_check("adjacent 3 -> 4 enabled", 3'd4, 1'b1, 1'b0, 1'b0);
        apply_and_check("adjacent 4 -> 3 enabled", 3'd3, 1'b1, 1'b0, 1'b0);

        // Case group 6: all three address bits toggling simultaneously.
        apply_and_check("all-A toggle: sel=0", 3'd0, 1'b1, 1'b0, 1'b0);
        apply_and_check("all-A toggle: sel=7", 3'd7, 1'b1, 1'b0, 1'b0);
        apply_and_check("all-A toggle: sel=0", 3'd0, 1'b1, 1'b0, 1'b0);

        // Case group 7: one-hot-low invariant: exactly one output low when
        // enabled, and zero outputs low when disabled.
        for (i = 0; i < 8; i = i + 1) begin
            drive(i[2:0], 1'b1, 1'b0, 1'b0);
            if (low_count(y_bus(1'b0)) == 1) begin
                pass_count = pass_count + 1;
                $display("PASS | one-hot-low invariant enabled sel=%0d | Y=%b", i, y_bus(1'b0));
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL | one-hot-low invariant enabled sel=%0d | Y=%b", i, y_bus(1'b0));
            end
        end
        drive(3'd2, 1'b1, 1'b1, 1'b0);
        if (y_bus(1'b0) === 8'hFF) begin
            pass_count = pass_count + 1;
            $display("PASS | no output low while disabled | Y=%b", y_bus(1'b0));
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL | no output low while disabled | Y=%b", y_bus(1'b0));
        end

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0) $display("RESULT: FAIL");
        else $display("RESULT: PASS");
        $finish;
    end

endmodule

`default_nettype wire
