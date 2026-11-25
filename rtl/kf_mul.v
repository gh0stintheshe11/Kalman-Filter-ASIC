// kf_mul.v -- unsigned multiplier, truncated: p = floor(a * b / 2^FRAC).
//
// b arrives radix-4 Booth recoded (kf_booth: {neg, two, one} per digit), so
// the partial products are selected straight from registers.  The 12
// partial-product rows (two's complement, with the usual sign-extension
// constants folded in) are reduced to two by a Wallace tree of carry-save
// adders and added by a Kogge-Stone adder (kf_prefix).  Everything is
// written out so that synthesis keeps the logarithmic structure; the low
// FRAC bits of the sum only produce the carry into bit FRAC.
`default_nettype none

module kf_mul #(
    parameter integer M    = 23,
    parameter integer FRAC = 14,
    parameter integer R    = (M + 2) / 2         // Booth digits of b
) (
    input  wire [M-1:0]        a,
    input  wire [3*R-1:0]      bd,
    output wire [2*M-FRAC-1:0] p
);
    localparam integer N = 2 * R + M + 1;        // width of the rows

    // ---- partial products ----------------------------------------------------
    // row i = digit_i * a * 4^i: |digit| * a inverted if negative, bits
    // M+1.. carry the sign-extension constants (row 0: neg, neg, ~neg; the
    // others: ~neg, 1), and the +1 of a negated row goes to bit 2i of row i+1.
    wire [R-1:0] neg;
    wire [N-1:0] pp [0:R-1];

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : g_pp
            wire one = bd[3 * i];
            wire two = bd[3 * i + 1];
            assign neg[i] = bd[3 * i + 2];
            wire [M:0] mag = ({(M + 1){one}} & {1'b0, a}) | ({(M + 1){two}} & {a, 1'b0});
            wire [M:0] row = mag ^ {(M + 1){neg[i]}};
            if (i == 0) begin : g_first
                assign pp[i] = {{(N - M - 4){1'b0}}, ~neg[i], neg[i], neg[i], row};
            end else begin : g_next
                wire [N-1:0] body = {{(N - M - 3){1'b0}}, 1'b1, ~neg[i], row};
                wire [N-1:0] cin  = {{(N - 1){1'b0}}, neg[i - 1]};
                assign pp[i] = (body << (2 * i)) | (cin << (2 * i - 2));
            end
        end
    endgenerate

    // ---- Wallace tree: 12 rows -> 2 in five carry-save levels --------------
    function [2*N-1:0] csa;                       // {carry, sum}
        input [N-1:0] x, y, z;
        csa = {((x & y) | (x & z) | (y & z)) << 1, x ^ y ^ z};
    endfunction

    wire [N-1:0] s1a, c1a, s1b, c1b, s1c, c1c, s1d, c1d;
    assign {c1a, s1a} = csa(pp[0], pp[1], pp[2]);
    assign {c1b, s1b} = csa(pp[3], pp[4], pp[5]);
    assign {c1c, s1c} = csa(pp[6], pp[7], pp[8]);
    assign {c1d, s1d} = csa(pp[9], pp[10], pp[11]);
    wire [N-1:0] s2a, c2a, s2b, c2b;
    assign {c2a, s2a} = csa(s1a, c1a, s1b);
    assign {c2b, s2b} = csa(c1b, s1c, c1c);
    wire [N-1:0] s3a, c3a, s3b, c3b;
    assign {c3a, s3a} = csa(s2a, c2a, s2b);
    assign {c3b, s3b} = csa(c2b, s1d, c1d);
    wire [N-1:0] s4, c4;
    assign {c4, s4} = csa(s3a, c3a, s3b);
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N-1:0] x, y;                           // bits 2M.. are beyond the product
    /* verilator lint_on UNUSEDSIGNAL */
    assign {y, x} = csa(s4, c4, c3b);

    // ---- carry-propagate adder ---------------------------------------------
    localparam integer W = 2 * M;                // the product's bits
    /* verilator lint_off UNUSEDSIGNAL */
    wire [W-1:0] gg, pp_unused;
    wire [W-1:0] sum = (x[W-1:0] ^ y[W-1:0]) ^ {gg[W-2:0], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */
    kf_prefix #(.N(W)) u_ks (.g(x[W-1:0] & y[W-1:0]), .p(x[W-1:0] ^ y[W-1:0]),
                             .gg(gg), .pp(pp_unused));
    assign p = sum[W-1:FRAC];
endmodule

`default_nettype wire
