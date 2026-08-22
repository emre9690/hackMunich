// Supplementary edge-case testbench for fpla_82s100_addr_decoder.
//
// NOT the source of pass/fail truth for this design: the external harness
// exhaustively compares the RTL against spec/chips/82s100.py (65536 vectors).
// This bench is regression-safety documentation -- it names and exercises the
// boundary conditions and input-state transitions that are the most likely
// places for a future edit to the decoder to go wrong:
//   * every 8K region boundary (last address of region r, first of region r+1)
//   * both edges of the 0x6000-0x60FF slice carved out of region 3 for Y7
//   * the low byte being unconstrained inside the carve-out
//   * A12..A8 each individually leaving the carve-out
//   * one-hot-ness of the active-LOW outputs (exactly one asserted, always)
//   * adjacent-address transitions across each boundary (glitch-free settle)
`timescale 1ns / 1ns

module fpla_82s100_addr_decoder_tb_extra;

    reg [15:0] addr;
    wire [7:0] y;

    integer errors = 0;
    integer checks = 0;

    fpla_82s100_addr_decoder dut (
        .A0 (addr[0]),  .A1 (addr[1]),  .A2 (addr[2]),  .A3 (addr[3]),
        .A4 (addr[4]),  .A5 (addr[5]),  .A6 (addr[6]),  .A7 (addr[7]),
        .A8 (addr[8]),  .A9 (addr[9]),  .A10(addr[10]), .A11(addr[11]),
        .A12(addr[12]), .A13(addr[13]), .A14(addr[14]), .A15(addr[15]),
        .Y0 (y[0]),     .Y1 (y[1]),     .Y2 (y[2]),     .Y3 (y[3]),
        .Y4 (y[4]),     .Y5 (y[5]),     .Y6 (y[6]),     .Y7 (y[7])
    );

    // Independent restatement of the documented decode, used only by this bench.
    function [7:0] expected;
        input [15:0] a;
        reg [2:0] region;
        reg carve;
        begin
            region   = a[15:13];
            carve    = (a >= 16'h6000) && (a <= 16'h60FF);
            expected = 8'hFF;
            if (region == 3'd7)      expected[7] = 1'b0;
            else if (carve)          expected[7] = 1'b0;
            else                     expected[region] = 1'b0;
        end
    endfunction

    // Index of the single output expected to be asserted (active LOW).
    function [3:0] expected_index;
        input [15:0] a;
        reg [7:0] e;
        integer i;
        begin
            e = expected(a);
            expected_index = 4'hF;
            for (i = 0; i < 8; i = i + 1)
                if (e[i] === 1'b0) expected_index = i[3:0];
        end
    endfunction

    task check;
        input [15:0] a;
        input [8*40-1:0] label;
        reg [7:0] exp;
        integer i;
        integer ones;
        begin
            addr = a;
            #1;
            exp    = expected(a);
            checks = checks + 1;
            ones   = 0;
            for (i = 0; i < 8; i = i + 1)
                if (y[i] === 1'b0) ones = ones + 1;

            if (y !== exp || ones != 1) begin
                errors = errors + 1;
                $display("FAIL %-38s addr=0x%04h Y=%b expected=%b (active outputs=%0d)",
                         label, a, y, exp, ones);
            end else begin
                $display("PASS %-38s addr=0x%04h Y=%b (Y%0d asserted)",
                         label, a, y, expected_index(a));
            end
        end
    endtask

    // Walk two adjacent addresses and confirm the asserted output hands over
    // cleanly from one to the next with no intermediate all-high/multi-low state.
    task check_transition;
        input [15:0] a;
        input [15:0] b;
        input [8*40-1:0] label;
        begin
            addr = a;
            #1;
            if (y !== expected(a)) begin
                errors = errors + 1;
                $display("FAIL %-38s pre-state 0x%04h Y=%b expected=%b",
                         label, a, y, expected(a));
            end
            addr = b;
            #1;
            checks = checks + 1;
            if (y !== expected(b)) begin
                errors = errors + 1;
                $display("FAIL %-38s 0x%04h -> 0x%04h Y=%b expected=%b",
                         label, a, b, y, expected(b));
            end else begin
                $display("PASS %-38s 0x%04h(Y%0d) -> 0x%04h(Y%0d)",
                         label, a, expected_index(a), b, expected_index(b));
            end
        end
    endtask

    integer r;
    integer bit_i;
    reg [15:0] base;

    initial begin
        $display("== 82S100 supplementary edge-case testbench ==");
        $display("-- (external golden-model harness remains the truth source) --");

        $display("\n[1] region base/top boundaries");
        for (r = 0; r < 8; r = r + 1) begin
            base = r[2:0] << 13;
            check(base,                     "region base address");
            check(base + 16'h1FFF,          "region top address");
        end

        $display("\n[2] boundary transitions between adjacent regions");
        for (r = 0; r < 7; r = r + 1) begin
            base = r[2:0] << 13;
            check_transition(base + 16'h1FFF, base + 16'h2000,
                             "last of region -> first of next");
            check_transition(base + 16'h2000, base + 16'h1FFF,
                             "first of region -> last of prev");
        end

        $display("\n[3] carve-out 0x6000-0x60FF edges (Y7 inside region 3)");
        check(16'h5FFF, "0x5FFF: last of region 2");
        check(16'h6000, "0x6000: first carve address");
        check(16'h60FF, "0x60FF: last carve address");
        check(16'h6100, "0x6100: first Y3 address after carve");
        check(16'h7FFF, "0x7FFF: last of region 3");
        check(16'h8000, "0x8000: first of region 4");
        check_transition(16'h5FFF, 16'h6000, "Y2 -> Y7 (carve entry)");
        check_transition(16'h60FF, 16'h6100, "Y7 -> Y3 (carve exit)");
        check_transition(16'h6100, 16'h60FF, "Y3 -> Y7 (carve re-entry)");
        check_transition(16'h7FFF, 16'h8000, "Y3 -> Y4 (region 3/4 edge)");

        $display("\n[4] low byte is unconstrained inside the carve-out");
        check(16'h6001, "carve + A0 set");
        check(16'h6055, "carve + mid low byte");
        check(16'h6080, "carve + A7 set");
        check(16'h60AA, "carve + alternating low byte");
        check(16'h60FE, "carve + low byte 0xFE");

        $display("\n[5] A12..A8 each individually exit the carve-out");
        for (bit_i = 8; bit_i <= 12; bit_i = bit_i + 1) begin
            check(16'h6000 | (16'h0001 << bit_i), "one of A12..A8 set -> Y3 not Y7");
        end

        $display("\n[6] Y7's two disjoint ranges and region 7 edges");
        check(16'hDFFF, "0xDFFF: last of region 6");
        check(16'hE000, "0xE000: first of region 7");
        check(16'hFFFF, "0xFFFF: top of address space");
        check_transition(16'hDFFF, 16'hE000, "Y6 -> Y7 (region 6/7 edge)");
        check_transition(16'h60FF, 16'hE000, "Y7 carve -> Y7 region 7");
        check_transition(16'hFFFF, 16'h0000, "wrap 0xFFFF -> 0x0000");

        $display("\n[7] single-bit walks from 0x0000 (A13..A15 pick the region)");
        for (bit_i = 0; bit_i < 16; bit_i = bit_i + 1) begin
            check(16'h0001 << bit_i, "single address bit set");
        end

        $display("\n== %0d checks, %0d failures ==", checks, errors);
        if (errors == 0) $display("RESULT: ALL EDGE CASES PASS");
        else             $display("RESULT: %0d EDGE CASE FAILURE(S)", errors);
        $finish;
    end

endmodule
