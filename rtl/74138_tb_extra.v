`timescale 1ns/1ps
`default_nettype none

module decoder_74138_tb_extra;
    reg A0;
    reg A1;
    reg A2;
    reg G1;
    reg G2A_n;
    reg G2B_n;

    wire Y0;
    wire Y1;
    wire Y2;
    wire Y3;
    wire Y4;
    wire Y5;
    wire Y6;
    wire Y7;
    wire [7:0] outputs;

    integer case_count;
    integer failure_count;

    assign outputs = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};

    decoder_74138 dut (
        .A0(A0),
        .A1(A1),
        .A2(A2),
        .G1(G1),
        .G2A_n(G2A_n),
        .G2B_n(G2B_n),
        .Y0(Y0),
        .Y1(Y1),
        .Y2(Y2),
        .Y3(Y3),
        .Y4(Y4),
        .Y5(Y5),
        .Y6(Y6),
        .Y7(Y7)
    );

    task run_case;
        input [8*64-1:0] description;
        input [2:0] select_bits;
        input enable_high;
        input enable_a_low;
        input enable_b_low;
        input [7:0] expected_outputs;
        begin
            {A2, A1, A0} = select_bits;
            G1 = enable_high;
            G2A_n = enable_a_low;
            G2B_n = enable_b_low;
            #1;

            case_count = case_count + 1;
            if (outputs === expected_outputs) begin
                $display("PASS: %0s (outputs=%b)", description, outputs);
            end else begin
                failure_count = failure_count + 1;
                $display(
                    "FAIL: %0s (expected=%b, actual=%b)",
                    description,
                    expected_outputs,
                    outputs
                );
            end
        end
    endtask

    initial begin
        case_count = 0;
        failure_count = 0;

        // Disabled boundary selections must leave every active-low output high.
        run_case("G1 low at select 0", 3'b000, 1'b0, 1'b0, 1'b0, 8'b11111111);
        run_case("G1 low at select 7", 3'b111, 1'b0, 1'b0, 1'b0, 8'b11111111);
        run_case("G2A_n high blocks select 0", 3'b000, 1'b1, 1'b1, 1'b0, 8'b11111111);
        run_case("G2B_n high blocks select 7", 3'b111, 1'b1, 1'b0, 1'b1, 8'b11111111);

        // Enable and disable transitions at the lowest selection boundary.
        run_case("enable select 0", 3'b000, 1'b1, 1'b0, 1'b0, 8'b11111110);
        run_case("disable select 0 through G2A_n", 3'b000, 1'b1, 1'b1, 1'b0, 8'b11111111);
        run_case("re-enable select 0", 3'b000, 1'b1, 1'b0, 1'b0, 8'b11111110);

        // Selection transitions cross the middle and both endpoint boundaries.
        run_case("select 3 before middle transition", 3'b011, 1'b1, 1'b0, 1'b0, 8'b11110111);
        run_case("select 4 after middle transition", 3'b100, 1'b1, 1'b0, 1'b0, 8'b11101111);
        run_case("select upper boundary 7", 3'b111, 1'b1, 1'b0, 1'b0, 8'b01111111);
        run_case("wrap transition from 7 to 0", 3'b000, 1'b1, 1'b0, 1'b0, 8'b11111110);

        if (failure_count == 0) begin
            $display("PASS: all %0d supplementary edge cases", case_count);
        end else begin
            $display(
                "FAIL: %0d of %0d supplementary edge cases",
                failure_count,
                case_count
            );
        end

        $finish;
    end
endmodule

`default_nettype wire
