// kf_rdport_ihp.v -- kf_rdport (rtl/kf_rdport.v) for IHP SG13G2.
//
// The one-hot decoder is left to synthesis; the AND-OR is instantiated
// from cells so that synthesis cannot turn it into a multiplexer tree:
//   AOI22  ~(sel[2k] & q[2k] | sel[2k+1] & q[2k+1])     16 per bit
//   NAND4  OR of 8 registers                               4 per bit
//   OR4    OR of 32 registers                              1 per bit
// Same ports and function as rtl/kf_rdport.v; only N = 32 is supported.
`default_nettype none

module kf_rdport #(
    parameter integer W  = 24,
    parameter integer N  = 32,
    parameter integer AW = 5
) (
    input  wire [AW-1:0]  addr,
    input  wire [W*N-1:0] q,
    output wire [W-1:0]   data
);
    wire [N-1:0] sel;
    genvar i, b;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_sel
            localparam [AW-1:0] IDX = i;
            assign sel[i] = (addr == IDX);
        end
        for (b = 0; b < W; b = b + 1) begin : g_bit
            wire [N/2-1:0] t;
            wire [N/8-1:0] u;
            for (i = 0; i < N / 2; i = i + 1) begin : g_aoi
                sg13g2_a22oi_1 u_aoi (.A1(sel[2*i]),     .A2(q[(2*i)*W + b]),
                                      .B1(sel[2*i + 1]), .B2(q[(2*i + 1)*W + b]),
                                      .Y(t[i]));
            end
            for (i = 0; i < N / 8; i = i + 1) begin : g_nand
                sg13g2_nand4_1 u_nand (.A(t[4*i]), .B(t[4*i + 1]), .C(t[4*i + 2]), .D(t[4*i + 3]),
                                       .Y(u[i]));
            end
            sg13g2_or4_1 u_or (.A(u[0]), .B(u[1]), .C(u[2]), .D(u[3]), .X(data[b]));
        end
    endgenerate
endmodule

`default_nettype wire
