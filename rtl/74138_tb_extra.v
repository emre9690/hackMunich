// Supplementary edge-case testbench for decoder_74138.
//
// The golden model (spec/chips/74138.py) plus the external harness already
// verify all 64 input combinations exhaustively; that harness remains the sole
// source of pass/fail truth. This testbench is additional regression-safety
// documentation: it exercises boundary conditions and input transitions
// (enable glitches, select walking, one-hot invariants) and prints a
// PASS/FAIL line per scenario.
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

    // Outputs packed as {Y7..Y0} for easy comparison.
    wire [7:0] y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    // Expected bus: all ones when disabled, otherwise a single zero at sel.
    function [7:0] expected;
        input a2, a1, a0, g1, g2a_n, g2b_n;
        integer sel;
        begin
            if (g1 === 1'b1 && g2a_n === 1'b0 && g2b_n === 1'b0) begin
                sel = (a2 << 2) | (a1 << 1) | a0;
                expected = ~(8'b1 << sel);
            end else begin
                expected = 8'hFF;
            end
        end
    endfunction

    task apply;
        input a2, a1, a0, g1, g2a_n, g2b_n;
        begin
            A2 = a2; A1 = a1; A0 = a0;
            G1 = g1; G2A_n = g2a_n; G2B_n = g2b_n;
            #5;
        end
    endtask

    // Drive the inputs, then compare the outputs against the expected bus.
    task check;
        input [8*40:1] name;
        input a2, a1, a0, g1, g2a_n, g2b_n;
        reg [7:0] exp;
        begin
            apply(a2, a1, a0, g1, g2a_n, g2b_n);
            exp = expected(a2, a1, a0, g1, g2a_n, g2b_n);
            checks = checks + 1;
            if (y === exp)
                $display("PASS | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b",
                         name, a2, a1, a0, g1, g2a_n, g2b_n, y);
            else begin
                errors = errors + 1;
                $display("FAIL | %0s | A=%b%b%b G1=%b G2A_n=%b G2B_n=%b -> Y=%b expected %b",
                         name, a2, a1, a0, g1, g2a_n, g2b_n, y, exp);
            end
        end
    endtask

    // Enabled outputs must be exactly one-hot-low; disabled must be all high.
    task check_onehot;
        input [8*40:1] name;
        integer i;
        integer lows;
        begin
            lows = 0;
            for (i = 0; i < 8; i = i + 1)
                if (y[i] === 1'b0) lows = lows + 1;
            checks = checks + 1;
            if (lows == 1)
                $display("PASS | %0s | exactly one active-low output (Y=%b)", name, y);
            else begin
                errors = errors + 1;
                $display("FAIL | %0s | %0d active-low outputs, expected 1 (Y=%b)",
                         name, lows, y);
            end
        end
    endtask

    integer i;

    initial begin
        $display("=== decoder_74138 supplementary edge-case testbench ===");

        // Scenario 1: select boundaries (lowest and highest addresses).
        $display("-- scenario 1: select boundaries --");
        check("sel=0 boundary (all A low)",  0, 0, 0, 1, 0, 0);
        check("sel=7 boundary (all A high)", 1, 1, 1, 1, 0, 0);

        // Scenario 2: every enable combination at a fixed select; only the
        // G1=1,G2A_n=0,G2B_n=0 corner may assert an output.
        $display("-- scenario 2: enable-term coverage at sel=3 --");
        check("G1=0 G2A_n=0 G2B_n=0 (disabled)", 0, 1, 1, 0, 0, 0);
        check("G1=0 G2A_n=0 G2B_n=1 (disabled)", 0, 1, 1, 0, 0, 1);
        check("G1=0 G2A_n=1 G2B_n=0 (disabled)", 0, 1, 1, 0, 1, 0);
        check("G1=0 G2A_n=1 G2B_n=1 (disabled)", 0, 1, 1, 0, 1, 1);
        check("G1=1 G2A_n=0 G2B_n=1 (disabled)", 0, 1, 1, 1, 0, 1);
        check("G1=1 G2A_n=1 G2B_n=0 (disabled)", 0, 1, 1, 1, 1, 0);
        check("G1=1 G2A_n=1 G2B_n=1 (disabled)", 0, 1, 1, 1, 1, 1);
        check("G1=1 G2A_n=0 G2B_n=0 (enabled)",  0, 1, 1, 1, 0, 0);

        // Scenario 3: address lines must be ignored while disabled.
        $display("-- scenario 3: select sweep while disabled --");
        for (i = 0; i < 8; i = i + 1)
            check("disabled sweep (G1=0)", (i >> 2) & 1, (i >> 1) & 1, i & 1, 0, 0, 0);

        // Scenario 4: walking select transitions, including the 3->4 and 7->0
        // multi-bit address changes, with the one-hot invariant re-checked.
        $display("-- scenario 4: walking select transitions --");
        for (i = 0; i < 9; i = i + 1) begin
            check("walking select", ((i % 8) >> 2) & 1, ((i % 8) >> 1) & 1, (i % 8) & 1, 1, 0, 0);
            check_onehot("walking select one-hot");
        end

        // Scenario 5: enable toggling at a fixed select (assert/deassert edges).
        $display("-- scenario 5: enable toggle at sel=5 --");
        check("enable asserted",     1, 0, 1, 1, 0, 0);
        check("G2A_n deasserts",     1, 0, 1, 1, 1, 0);
        check("re-enabled",          1, 0, 1, 1, 0, 0);
        check("G2B_n deasserts",     1, 0, 1, 1, 0, 1);
        check("re-enabled again",    1, 0, 1, 1, 0, 0);
        check("G1 deasserts",        1, 0, 1, 0, 0, 0);
        check("re-enabled once more",1, 0, 1, 1, 0, 0);

        // Scenario 6: address changed while disabled, then enabled -- the new
        // address must take effect immediately on enable.
        $display("-- scenario 6: address change while disabled --");
        check("sel=2 enabled",           0, 1, 0, 1, 0, 0);
        check("disable, retarget sel=6", 1, 1, 0, 0, 0, 0);
        check("enable at sel=6",         1, 1, 0, 1, 0, 0);
        check_onehot("post-retarget one-hot");

        $display("=== summary: %0d checks, %0d failures ===", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL EDGE-CASE CHECKS PASSED");
        else
            $display("RESULT: %0d EDGE-CASE CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
