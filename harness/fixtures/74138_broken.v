// Hand-authored fixture used ONLY to prove the harness catches real bugs
// (Stage 1). Deliberately broken: output polarity is inverted (active HIGH
// instead of active LOW) -- the exact bug class the brief calls out as the
// natural failure surface for this chip.
module decoder_74138 (
    input  A0, A1, A2,
    input  G1, G2A_n, G2B_n,
    output reg Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7
);
    wire enabled = G1 & ~G2A_n & ~G2B_n;
    wire [2:0] sel = {A2, A1, A0};

    always @(*) begin
        {Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7} = 8'b0000_0000;  // BUG: should be all-1 idle
        if (enabled) begin
            case (sel)
                3'd0: Y0 = 1'b1;  // BUG: should drive LOW (0), not HIGH (1)
                3'd1: Y1 = 1'b1;
                3'd2: Y2 = 1'b1;
                3'd3: Y3 = 1'b1;
                3'd4: Y4 = 1'b1;
                3'd5: Y5 = 1'b1;
                3'd6: Y6 = 1'b1;
                3'd7: Y7 = 1'b1;
            endcase
        end
    end
endmodule
