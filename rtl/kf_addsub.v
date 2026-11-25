// kf_addsub.v -- sign-magnitude Q9.14 adder/subtractor: a + b or a - b,
// saturating, zero normalized to +0 (kfasic.fixed.add / sub).
`default_nettype none

module kf_addsub #(
    parameter integer W = 24
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire         sub,
    output wire [W-1:0] y
);
    localparam integer M = W - 1;
    localparam [M-1:0] MAG_MAX = {M{1'b1}};

    wire         a_sgn   = a[W-1];
    wire [M-1:0] a_mag   = a[M-1:0];
    wire         b_sgn   = b[W-1] ^ sub;              // sign of the addend
    wire [M-1:0] b_mag   = b[M-1:0];
    wire         eff_sub = a_sgn ^ b_sgn;             // magnitudes subtract

    wire [M:0]   mag_sum = {1'b0, a_mag} + {1'b0, b_mag};
    wire [M:0]   mag_dif = {1'b0, a_mag} - {1'b0, b_mag};
    wire         borrow  = mag_dif[M];                // |b| > |a|
    wire [M-1:0] dif_abs = borrow ? (~mag_dif[M-1:0] + 1'b1) : mag_dif[M-1:0];

    wire [M-1:0] mag = eff_sub ? dif_abs : (mag_sum[M] ? MAG_MAX : mag_sum[M-1:0]);
    wire         sgn = (eff_sub & borrow) ? b_sgn : a_sgn;

    assign y = {sgn & (|mag), mag};
endmodule

`default_nettype wire
