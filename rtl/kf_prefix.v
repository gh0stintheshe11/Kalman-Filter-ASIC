// kf_prefix.v -- Kogge-Stone parallel-prefix carry network.
//
// From the bit generate g = a & b and propagate p = a ^ b of an addition,
// computes for every k the generate gg[k] and propagate pp[k] of bits k..0,
// in ceil(log2 N) levels.  The carry into bit k+1 is gg[k] | (pp[k] & cin).
// The adders of the datapath (multiplier, accumulator, reciprocal unit) are
// built on it, because the generic adders of synthesis are much slower.
`default_nettype none

module kf_prefix #(
    parameter integer N = 32
) (
    input  wire [N-1:0] g,
    input  wire [N-1:0] p,
    output wire [N-1:0] gg,
    output wire [N-1:0] pp
);
    localparam integer L = $clog2(N);

    wire [N-1:0] gl [0:L];
    wire [N-1:0] pl [0:L];
    assign gl[0] = g;
    assign pl[0] = p;

    genvar l, k;
    generate
        for (l = 0; l < L; l = l + 1) begin : g_level
            for (k = 0; k < N; k = k + 1) begin : g_bit
                if (k >= (1 << l)) begin : g_op
                    assign gl[l + 1][k] = gl[l][k] | (pl[l][k] & gl[l][k - (1 << l)]);
                    assign pl[l + 1][k] = pl[l][k] & pl[l][k - (1 << l)];
                end else begin : g_pass
                    assign gl[l + 1][k] = gl[l][k];
                    assign pl[l + 1][k] = pl[l][k];
                end
            end
        end
    endgenerate

    assign gg = gl[L];
    assign pp = pl[L];
endmodule

`default_nettype wire
