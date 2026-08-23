module bcd_to_7seg_sn5446a (
    input A,
    input B,
    input C,
    input D,
    input LT_n,
    input RBI_n,
    input BI_n,
    output reg a,
    output reg b,
    output reg c,
    output reg d,
    output reg e,
    output reg f,
    output reg g,
    output reg RBO_n
);

always @* begin
    if (!BI_n) begin
        {a, b, c, d, e, f, g} = 7'b1111111;
        RBO_n = 1'b0;
    end else if (!LT_n) begin
        {a, b, c, d, e, f, g} = 7'b0000000;
        RBO_n = 1'b1;
    end else if (!RBI_n && !A && !B && !C && !D) begin
        {a, b, c, d, e, f, g} = 7'b1111111;
        RBO_n = 1'b0;
    end else begin
        RBO_n = 1'b1;
        case ({D, C, B, A})
            4'h0: {a, b, c, d, e, f, g} = 7'b0000001;
            4'h1: {a, b, c, d, e, f, g} = 7'b1001111;
            4'h2: {a, b, c, d, e, f, g} = 7'b0010010;
            4'h3: {a, b, c, d, e, f, g} = 7'b0000110;
            4'h4: {a, b, c, d, e, f, g} = 7'b1001100;
            4'h5: {a, b, c, d, e, f, g} = 7'b0100100;
            4'h6: {a, b, c, d, e, f, g} = 7'b1100000;
            4'h7: {a, b, c, d, e, f, g} = 7'b0001111;
            4'h8: {a, b, c, d, e, f, g} = 7'b0000000;
            4'h9: {a, b, c, d, e, f, g} = 7'b0001100;
            4'ha: {a, b, c, d, e, f, g} = 7'b1110010;
            4'hb: {a, b, c, d, e, f, g} = 7'b1100110;
            4'hc: {a, b, c, d, e, f, g} = 7'b1011100;
            4'hd: {a, b, c, d, e, f, g} = 7'b0110100;
            4'he: {a, b, c, d, e, f, g} = 7'b1110000;
            4'hf: {a, b, c, d, e, f, g} = 7'b1111111;
        endcase
    end
end

endmodule
