// kf_mul.v -- sign-magnitude Q9.14 multiplier: |a|*|b| >> 14, truncated,
// saturated, sign a^b, zero normalized to +0 (kfasic.fixed.mul).
`default_nettype none

module kf_mul #(
    parameter integer W    = 24,
    parameter integer FRAC = 14
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] y
);
    localparam integer M = W - 1;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [2*M-1:0] p = a[M-1:0] * b[M-1:0];      // Q18.28; low bits truncated
    /* verilator lint_on UNUSEDSIGNAL */
    wire           ovf = |p[2*M-1:M+FRAC];
    wire [M-1:0]   mag = ovf ? {M{1'b1}} : p[M+FRAC-1:FRAC];

    assign y = {(a[W-1] ^ b[W-1]) & (|mag), mag};
endmodule

`default_nettype wire
