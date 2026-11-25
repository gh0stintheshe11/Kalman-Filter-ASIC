// kf_add.v -- N-bit adder y = a + b + cin with carry out, on the
// Kogge-Stone network kf_prefix.
`default_nettype none

module kf_add #(
    parameter integer N = 26
) (
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    input  wire         cin,
    output wire [N-1:0] y,
    output wire         cout
);
    wire [N-1:0] p = a ^ b;
    wire [N-1:0] gg, pp;
    kf_prefix #(.N(N)) u_ks (.g(a & b), .p(p), .gg(gg), .pp(pp));
    wire [N-1:0] c = gg | (pp & {N{cin}});       // carry out of bit k
    assign y    = p ^ {c[N-2:0], cin};
    assign cout = c[N-1];
endmodule

`default_nettype wire
