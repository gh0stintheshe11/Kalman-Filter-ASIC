// kf_booth.v -- radix-4 Booth recoding of an unsigned multiplier operand.
//
// b (M bits, zero-extended) = sum over i of digit_i * 4^i with digit_i =
// -2 b[2i+1] + b[2i] + b[2i-1] in {-2..2}.  Each digit is delivered as
// {neg, two, one}: |digit| = 1 (one), 2 (two), negative (neg; never set
// for digit 0).  The datapath recodes operands B and E before the operand
// registers, so the multipliers start from registered digits.
`default_nettype none

module kf_booth #(
    parameter integer M = 23,
    parameter integer R = (M + 2) / 2            // digits
) (
    input  wire [M-1:0]   b,
    output wire [3*R-1:0] bd
);
    wire [2*R:0] bx = {{(2 * R - M){1'b0}}, b, 1'b0};

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : g_digit
            wire x0 = bx[2 * i];
            wire x1 = bx[2 * i + 1];
            wire x2 = bx[2 * i + 2];
            assign bd[3 * i]     = x1 ^ x0;
            assign bd[3 * i + 1] = (x2 & ~x1 & ~x0) | (~x2 & x1 & x0);
            assign bd[3 * i + 2] = x2 & ~(x1 & x0);
        end
    endgenerate
endmodule

`default_nettype wire
