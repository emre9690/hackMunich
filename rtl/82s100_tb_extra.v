// Supplementary edge-case testbench for fpla_82s100_addr_decoder.
//
// This testbench does NOT replace the exhaustive golden-model verification
// (spec/chips/82s100.py, 65536 vectors) run by the external harness. It
// documents and exercises specific edge cases as regression-safety
// documentation: region boundaries, the 0x6000-0x60FF carve-out owned by Y7,
// transitions between adjacent addresses across those boundaries, and the
// one-hot (exactly one active-LOW output) invariant at each tested point.
`default_nettype none
`timescale 1ns / 1ps

module tb_82s100_extra;

    reg [15:0] addr;
    wire [7:0] y;

    integer pass_count = 0;
    integer fail_count = 0;

    fpla_82s100_addr_decoder dut (
        .A0 (addr[0]),  .A1 (addr[1]),  .A2 (addr[2]),  .A3 (addr[3]),
        .A4 (addr[4]),  .A5 (addr[5]),  .A6 (addr[6]),  .A7 (addr[7]),
        .A8 (addr[8]),  .A9 (addr[9]),  .A10(addr[10]), .A11(addr[11]),
        .A12(addr[12]), .A13(addr[13]), .A14(addr[14]), .A15(addr[15]),
        .Y0(y[0]), .Y1(y[1]), .Y2(y[2]), .Y3(y[3]),
        .Y4(y[4]), .Y5(y[5]), .Y6(y[6]), .Y7(y[7])
    );

    // Expected output bus for a given address: active-LOW, exactly one low.
    function [7:0] expected_y;
        input [15:0] a;
        reg [2:0] region;
        reg in_carve;
        begin
            region   = a[15:13];
            in_carve = (a >= 16'h6000) && (a <= 16'h60FF);
            expected_y = 8'hFF;
            if (region == 3'd7)
                expected_y[7] = 1'b0;
            else if (in_carve)
                expected_y[7] = 1'b0;
            else
                expected_y[region] = 1'b0;
        end
    endfunction

    task check;
        input [15:0] a;
        input [8*48-1:0] label;
        reg [7:0] exp;
        begin
            addr = a;
            #1;
            exp = expected_y(a);
            // One-hot-low invariant: exactly one output asserted.
            if (y === exp && (y[0]+y[1]+y[2]+y[3]+y[4]+y[5]+y[6]+y[7]) == 7) begin
                pass_count = pass_count + 1;
                $display("PASS  addr=%04h Y=%b  %0s", a, y, label);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  addr=%04h Y=%b expected=%b  %0s", a, y, exp, label);
            end
        end
    endtask

    integer r;

    initial begin
        $display("=== 82S100 extra edge-case testbench ===");

        // --- 1. First and last address of every 8K region -------------
        $display("-- region boundary endpoints --");
        for (r = 0; r < 8; r = r + 1) begin
            check(r[2:0] * 16'h2000,             "region first address");
            check(r[2:0] * 16'h2000 + 16'h1FFF,  "region last address");
        end

        // --- 2. Transitions across each region boundary ---------------
        // Adjacent address pairs straddling every 8K boundary: the active
        // output must hand off cleanly with no overlap or gap.
        $display("-- adjacent addresses across region boundaries --");
        for (r = 1; r < 8; r = r + 1) begin
            check(r[2:0] * 16'h2000 - 16'h1, "last address below boundary");
            check(r[2:0] * 16'h2000,         "first address above boundary");
        end
        check(16'hFFFF, "wraparound: top of address space");
        check(16'h0000, "wraparound: bottom of address space");

        // --- 3. Carve-out 0x6000-0x60FF boundaries (Y7 inside region 3)
        $display("-- carve-out 0x6000-0x60FF boundaries --");
        check(16'h5FFF, "just below carve (region 2, Y2)");
        check(16'h6000, "carve first address (Y7, not Y3)");
        check(16'h6001, "carve interior low");
        check(16'h60FE, "carve interior high");
        check(16'h60FF, "carve last address (Y7, not Y3)");
        check(16'h6100, "just above carve (back to Y3)");
        check(16'h6080, "carve midpoint");

        // --- 4. Near-miss addresses that look like the carve ----------
        // Same low byte pattern but outside region 3, or region 3 with a
        // single high bit set: none may activate the carve.
        $display("-- carve near-misses --");
        check(16'h4000, "region 2 base, A12..A8 all zero (not carve)");
        check(16'h8000, "region 4 base, A12..A8 all zero (not carve)");
        check(16'h6200, "region 3, only A9 set (not carve)");
        check(16'h6400, "region 3, only A10 set (not carve)");
        check(16'h6800, "region 3, only A11 set (not carve)");
        check(16'h7000, "region 3, only A12 set (not carve)");
        check(16'h6100, "region 3, only A8 set (not carve)");

        // --- 5. Y7's two disjoint active ranges -----------------------
        $display("-- Y7 disjoint ranges --");
        check(16'h6080, "Y7 low range (carve)");
        check(16'hE000, "Y7 high range start");
        check(16'hF234, "Y7 high range interior");
        check(16'hFFFF, "Y7 high range end");
        check(16'hDFFF, "gap below Y7 high range (Y6)");
        check(16'h6100, "gap above Y7 low range (Y3)");

        // --- 6. Single-bit walks around critical boundaries -----------
        // Walk a one-hot bit through the address near 0x6000: only the
        // bit pattern matching the carve decode may select Y7.
        $display("-- single-bit walk from 0x6000 --");
        for (r = 0; r < 13; r = r + 1)
            check(16'h6000 | (16'h1 << r), "0x6000 with one low bit set");

        // --- 7. Alternating bit patterns -------------------------------
        $display("-- alternating patterns --");
        check(16'hAAAA, "alternating 1010 (region 5)");
        check(16'h5555, "alternating 0101 (region 2)");

        $display("=== RESULT: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTBENCH FAILED");
        $finish;
    end

endmodule

`default_nettype wire
