`timescale 1ns/1ps
`default_nettype none

module sn5446a_tb_extra;
    reg A;
    reg B;
    reg C;
    reg D;
    reg LT_n;
    reg RBI_n;
    reg BI_n;

    wire a;
    wire b;
    wire c;
    wire d;
    wire e;
    wire f;
    wire g;
    wire RBO_n;

    integer failures;

    bcd_to_7seg_sn5446a dut (
        .A(A),
        .B(B),
        .C(C),
        .D(D),
        .LT_n(LT_n),
        .RBI_n(RBI_n),
        .BI_n(BI_n),
        .a(a),
        .b(b),
        .c(c),
        .d(d),
        .e(e),
        .f(f),
        .g(g),
        .RBO_n(RBO_n)
    );

    task set_inputs;
        input [3:0] code;
        input lt_n;
        input rbi_n;
        input bi_n;
        begin
            {D, C, B, A} = code;
            LT_n = lt_n;
            RBI_n = rbi_n;
            BI_n = bi_n;
            #1;
        end
    endtask

    task check_case;
        input [8*64-1:0] case_name;
        input [6:0] expected_segments;
        input expected_rbo_n;
        begin
            if (({a, b, c, d, e, f, g} === expected_segments) &&
                (RBO_n === expected_rbo_n)) begin
                $display("PASS: %0s", case_name);
            end else begin
                failures = failures + 1;
                $display(
                    "FAIL: %0s expected segments=%b RBO_n=%b, got segments=%b RBO_n=%b",
                    case_name,
                    expected_segments,
                    expected_rbo_n,
                    {a, b, c, d, e, f, g},
                    RBO_n
                );
            end
        end
    endtask

    initial begin
        failures = 0;

        set_inputs(4'd0, 1'b1, 1'b1, 1'b1);
        check_case("zero displayed before ripple blanking", 7'b0000001, 1'b1);

        RBI_n = 1'b0;
        #1;
        check_case("RBI assertion blanks zero and lowers RBO", 7'b1111111, 1'b0);

        {D, C, B, A} = 4'd1;
        #1;
        check_case("zero-to-one transition releases ripple blanking", 7'b1001111, 1'b1);

        set_inputs(4'd9, 1'b1, 1'b0, 1'b1);
        check_case("RBI low does not blank nonzero digit nine", 7'b0001100, 1'b1);

        {D, C, B, A} = 4'd10;
        #1;
        check_case("nine-to-ten transition enters non-BCD decode", 7'b1110010, 1'b1);

        {D, C, B, A} = 4'd14;
        #1;
        check_case("upper non-BCD boundary code fourteen", 7'b1110000, 1'b1);

        {D, C, B, A} = 4'd15;
        #1;
        check_case("fourteen-to-fifteen transition turns segments off", 7'b1111111, 1'b1);

        LT_n = 1'b0;
        #1;
        check_case("lamp test overrides all-off code fifteen", 7'b0000000, 1'b1);

        BI_n = 1'b0;
        #1;
        check_case("blanking input overrides active lamp test", 7'b1111111, 1'b0);

        BI_n = 1'b1;
        #1;
        check_case("releasing blanking restores active lamp test", 7'b0000000, 1'b1);

        LT_n = 1'b1;
        #1;
        check_case("releasing lamp test restores code fifteen", 7'b1111111, 1'b1);

        if (failures == 0)
            $display("PASS: all supplementary edge cases");
        else
            $display("FAIL: %0d supplementary edge case(s)", failures);

        $finish;
    end
endmodule

`default_nettype wire
