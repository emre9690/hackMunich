// Supplementary edge-case testbench for fpla_82s100_addr_decoder.
//
// The design is already exhaustively verified against the golden model in
// spec/chips/82s100.py by the external harness; that harness remains the sole
// source of pass/fail truth. This testbench is regression-safety documentation:
// it names and exercises the boundaries and state transitions that matter for
// this programmed FPLA (region edges, the 0x6000-0x60FF carve-out owned by Y7,
// and one-hot activity of the active-LOW outputs).
`timescale 1ns / 1ps

module fpla_82s100_addr_decoder_tb_extra;

    reg [15:0] addr;
    wire [7:0] y;

    integer pass_count = 0;
    integer fail_count = 0;

    fpla_82s100_addr_decoder dut (
        .A0 (addr[0]),  .A1 (addr[1]),  .A2 (addr[2]),  .A3 (addr[3]),
        .A4 (addr[4]),  .A5 (addr[5]),  .A6 (addr[6]),  .A7 (addr[7]),
        .A8 (addr[8]),  .A9 (addr[9]),  .A10(addr[10]), .A11(addr[11]),
        .A12(addr[12]), .A13(addr[13]), .A14(addr[14]), .A15(addr[15]),
        .Y0 (y[0]),     .Y1 (y[1]),     .Y2 (y[2]),     .Y3 (y[3]),
        .Y4 (y[4]),     .Y5 (y[5]),     .Y6 (y[6]),     .Y7 (y[7])
    );

    // Independent expectation: which output index should be active LOW.
    function [3:0] expected_active;
        input [15:0] a;
        reg [2:0] region;
        reg in_carve;
        begin
            region = a[15:13];
            in_carve = (a >= 16'h6000) && (a <= 16'h60FF);
            if (region == 3'd7)      expected_active = 4'd7;
            else if (in_carve)       expected_active = 4'd7;
            else if (region == 3'd3) expected_active = 4'd3;
            else                     expected_active = {1'b0, region};
        end
    endfunction

    task check;
        input [15:0] a;
        input [511:0] label;
        reg [7:0] exp_y;
        begin
            addr = a;
            #1;
            exp_y = ~(8'b1 << expected_active(a));
            if (y === exp_y) begin
                pass_count = pass_count + 1;
                $display("PASS  addr=0x%04h  Y=%b  (active Y%0d)  %0s",
                         a, y, expected_active(a), label);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  addr=0x%04h  Y=%b  expected Y=%b  %0s",
                         a, y, exp_y, label);
            end
        end
    endtask

    // Exactly one active-LOW output must be asserted for any address.
    task check_one_hot_low;
        input [15:0] a;
        input [511:0] label;
        integer i;
        integer lows;
        begin
            addr = a;
            #1;
            lows = 0;
            for (i = 0; i < 8; i = i + 1)
                if (y[i] === 1'b0) lows = lows + 1;
            if (lows == 1) begin
                pass_count = pass_count + 1;
                $display("PASS  addr=0x%04h  Y=%b  exactly one output LOW  %0s",
                         a, y, label);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  addr=0x%04h  Y=%b  %0d outputs LOW (expected 1)  %0s",
                         a, y, lows, label);
            end
        end
    endtask

    // A single-address step across a boundary must change the decoded output.
    task check_transition;
        input [15:0] a_before;
        input [15:0] a_after;
        input [511:0] label;
        reg [7:0] y_before;
        begin
            addr = a_before;
            #1;
            y_before = y;
            addr = a_after;
            #1;
            if (y_before !== y &&
                y_before === ~(8'b1 << expected_active(a_before)) &&
                y       === ~(8'b1 << expected_active(a_after))) begin
                pass_count = pass_count + 1;
                $display("PASS  0x%04h->0x%04h  Y %b->%b  (Y%0d->Y%0d)  %0s",
                         a_before, a_after, y_before, y,
                         expected_active(a_before), expected_active(a_after), label);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  0x%04h->0x%04h  Y %b->%b  expected %b->%b  %0s",
                         a_before, a_after, y_before, y,
                         ~(8'b1 << expected_active(a_before)),
                         ~(8'b1 << expected_active(a_after)), label);
            end
        end
    endtask

    integer k;

    initial begin
        $display("=== 82S100 supplementary edge-case testbench ===");

        $display("--- Case group 1: first/last address of every 8K region ---");
        for (k = 0; k < 8; k = k + 1) begin
            check(k * 16'h2000,               "region base address");
            check(k * 16'h2000 + 16'h1FFF,    "region top address");
        end

        $display("--- Case group 2: carve-out (0x6000-0x60FF, owned by Y7) edges ---");
        check(16'h5FFF, "last address below region 3 (Y2)");
        check(16'h6000, "first carve-out address (Y7, not Y3)");
        check(16'h6001, "inside carve-out");
        check(16'h607F, "middle of carve-out");
        check(16'h60FF, "last carve-out address (Y7)");
        check(16'h6100, "first address after carve-out (back to Y3)");
        check(16'h6101, "just past carve-out");
        check(16'h7FFF, "top of region 3 (Y3)");

        $display("--- Case group 3: transitions across boundaries (single-step) ---");
        check_transition(16'h5FFF, 16'h6000, "region 2 -> carve-out");
        check_transition(16'h60FF, 16'h6100, "carve-out -> region 3 proper");
        check_transition(16'h6100, 16'h60FF, "region 3 proper -> carve-out (reverse)");
        check_transition(16'h7FFF, 16'h8000, "region 3 -> region 4");
        check_transition(16'hDFFF, 16'hE000, "region 6 -> region 7");
        check_transition(16'hFFFF, 16'h0000, "wrap: region 7 -> region 0");
        check_transition(16'h1FFF, 16'h2000, "region 0 -> region 1");

        $display("--- Case group 4: A12..A8 sensitivity inside region 3 ---");
        // Any one of A12..A8 set moves the address out of the carve-out.
        check(16'h6000 | 16'h0100, "region 3 with A8 set -> Y3");
        check(16'h6000 | 16'h0200, "region 3 with A9 set -> Y3");
        check(16'h6000 | 16'h0400, "region 3 with A10 set -> Y3");
        check(16'h6000 | 16'h0800, "region 3 with A11 set -> Y3");
        check(16'h6000 | 16'h1000, "region 3 with A12 set -> Y3");
        // A7..A0 are don't-cares for the carve-out decode.
        check(16'h6000 | 16'h00AA, "carve-out is insensitive to A7..A0 (0xAA)");
        check(16'h6000 | 16'h0055, "carve-out is insensitive to A7..A0 (0x55)");

        $display("--- Case group 5: carve-out pattern does NOT leak into other regions ---");
        check(16'h0000, "same low bits, region 0 -> Y0");
        check(16'h2000, "same low bits, region 1 -> Y1");
        check(16'h4000, "same low bits, region 2 -> Y2");
        check(16'h8000, "same low bits, region 4 -> Y4");
        check(16'hA000, "same low bits, region 5 -> Y5");
        check(16'hC000, "same low bits, region 6 -> Y6");
        check(16'hE000, "same low bits, region 7 -> Y7");

        $display("--- Case group 6: one-hot activity at critical addresses ---");
        check_one_hot_low(16'h0000, "all-zero address");
        check_one_hot_low(16'hFFFF, "all-ones address");
        check_one_hot_low(16'h5FFF, "below carve-out");
        check_one_hot_low(16'h6000, "carve-out base");
        check_one_hot_low(16'h60FF, "carve-out top");
        check_one_hot_low(16'h6100, "above carve-out");
        check_one_hot_low(16'h7FFF, "region 3 top");
        check_one_hot_low(16'hE000, "region 7 base");

        $display("=== summary: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
