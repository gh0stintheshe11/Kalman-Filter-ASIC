// kf_dot.v -- the accumulation of an arithmetic instruction
// (kfasic.fixed.dot): y = sat(base + p1 + p2), where base is a Q9.14 word
// (sign-magnitude) and p1, p2 are truncated products, given as magnitudes
// x1, x2 and whether they are subtracted from |base| (e1, e2: the sign of
// the product differs from the sign of the base; the datapath registers
// these flags).  p2 only counts if m2 is set (e2 must then be 0 too).  The
// sum is exact (35 bits) and saturated once; a zero result is +0.
//
// So T = |base| +/- x1 +/- x2 and y = (sign of base) * T.  The
// three rows go through one carry-save level into a compound Kogge-Stone
// adder that delivers T0 = S + C and T1 = S + C + 1 from one prefix tree.
// The "+1" of a subtracted product is T1's; with two subtracted products
// the other one goes into the free carry bit 0.  If T is negative,
// |T| = -(T0 + 1) = ~T0, so no second carry chain is needed.  Zero and
// saturation are detected in parallel with the adder.
`default_nettype none

module kf_dot #(
    parameter integer M = 23,                    // magnitude bits of a word
    parameter integer P = 32                     // magnitude bits of a product
) (
    input  wire [M:0]   base,
    input  wire [P-1:0] x1,
    input  wire         e1,                      // subtract x1 from |base|
    input  wire [P-1:0] x2,
    input  wire         e2,                      // subtract x2 (0 if !m2)
    input  wire         m2,                      // p2 present
    output wire [M:0]   y
);
    localparam integer N = P + 3;                // |T| < 2^(P+2)

    wire          sb = base[M];
    wire [N-1:0]  r0 = {{(N - M){1'b0}}, base[M-1:0]};
    wire [N-1:0]  r1 = {3'b000, x1} ^ {N{e1}};
    wire [N-1:0]  r2 = {3'b000, x2 & {P{m2}}} ^ {N{e2}};

    // carry-save level; carry bit 0 takes the second "+1"
    wire [N-1:0]  s  = r0 ^ r1 ^ r2;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N-1:0]  mj = (r0 & r1) | (r0 & r2) | (r1 & r2);   // bit N-1 overflows
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-1:0]  c  = {mj[N-2:0], e1 & e2};

    // compound Kogge-Stone adder over s + c
    wire [N-1:0] q = s ^ c;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N-1:0] gg, pp;                                        // bit N-1 unused
    /* verilator lint_on UNUSEDSIGNAL */
    kf_prefix #(.N(N)) u_ks (.g(s & c), .p(q), .gg(gg), .pp(pp));
    wire [N-1:0] t0 = q ^ {gg[N-2:0], 1'b0};                      // s + c
    wire [N-1:0] t1 = q ^ ({gg[N-2:0], 1'b0} | {pp[N-2:0], 1'b1}); // s + c + 1

    wire          sub  = e1 | e2;                // T = sub ? T1 : T0
    wire          neg  = sub & t1[N-1];
    wire [N-1:0]  tt   = sub ? t1 : t0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N-1:0]  tabs = neg ? ~t0 : tt;                    // high bits: sat
    /* verilator lint_on UNUSEDSIGNAL */
    // zero: T1 = 0 iff s ^ c is all ones; T0 = 0 (no subtraction) iff all
    // rows are 0
    wire          zero = sub ? &q : ~|(s | c);
    wire          sat  = neg ? ~&t0[N-1:M] : |tt[N-1:M];
    wire [M-1:0]  mag  = sat ? {M{1'b1}} : tabs[M-1:0];

    assign y = {(sb ^ neg) & ~zero, mag};
endmodule

`default_nettype wire
