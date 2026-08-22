// Hand-authored fixture used ONLY to prove the harness itself works
// (Stage 1, before any Devin session is involved). Correct 74138 behavior:
// active-LOW outputs, enabled iff G1=1 & G2A_n=0 & G2B_n=0.
module decoder_74138 (
    input  A0, A1, A2,
    input  G1, G2A_n, G2B_n,
    output reg Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7
);
    wire enabled = G1 & ~G2A_n & ~G2B_n;
    wire [2:0] sel = {A2, A1, A0};

    always @(*) begin
        {Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7} = 8'b1111_1111;
        if (enabled) begin
            case (sel)
                3'd0: Y0 = 1'b0;
                3'd1: Y1 = 1'b0;
                3'd2: Y2 = 1'b0;
                3'd3: Y3 = 1'b0;
                3'd4: Y4 = 1'b0;
                3'd5: Y5 = 1'b0;
                3'd6: Y6 = 1'b0;
                3'd7: Y7 = 1'b0;
            endcase
        end
    end
endmodule
