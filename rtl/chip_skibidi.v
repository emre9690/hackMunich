module bcd_7seg_7447a (
    A,
    B,
    C,
    D,
    LT_n,
    RBI_n,
    BI_n,
    a_n,
    b_n,
    c_n,
    d_n,
    e_n,
    f_n,
    g_n,
    RBO_n
);
    input A;
    input B;
    input C;
    input D;
    input LT_n;
    input RBI_n;
    input BI_n;

    output reg a_n;
    output reg b_n;
    output reg c_n;
    output reg d_n;
    output reg e_n;
    output reg f_n;
    output reg g_n;
    output reg RBO_n;

    always @* begin
        if (!BI_n) begin
            {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1111111;
            RBO_n = 1'b0;
        end else if (!LT_n) begin
            {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0000000;
            RBO_n = 1'b1;
        end else if (!RBI_n && !D && !C && !B && !A) begin
            {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1111111;
            RBO_n = 1'b0;
        end else begin
            RBO_n = 1'b1;
            case ({D, C, B, A})
                4'h0: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0000001;
                4'h1: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1001111;
                4'h2: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0010010;
                4'h3: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0000110;
                4'h4: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1001100;
                4'h5: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0100100;
                4'h6: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1100000;
                4'h7: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0001111;
                4'h8: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0000000;
                4'h9: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0001100;
                4'hA: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1110010;
                4'hB: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1100110;
                4'hC: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1011100;
                4'hD: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b0110100;
                4'hE: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1110000;
                4'hF: {a_n, b_n, c_n, d_n, e_n, f_n, g_n} = 7'b1111111;
            endcase
        end
    end
endmodule
