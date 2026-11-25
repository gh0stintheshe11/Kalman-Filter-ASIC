// kf_rdport_ihp.v -- kf_rdport (rtl/kf_rdport.v) for IHP SG13G2.
//
// The one-hot decoder is left to synthesis; the AND-OR is instantiated
// from cells so that synthesis cannot turn it into a multiplexer tree.
// Per bit, with sel/q pairs reduced level by level:
//   AOI22  ~(sel[2k] & q[2k] | sel[2k+1] & q[2k+1])   16 cells,  2 registers
//   NAND2  OR of 4 registers                           8 cells
//   NOR2   NOR of 8                                    4 cells
//   NAND2  OR of 16                                    2 cells
//   OR2    OR of 32                                    1 cell
// Two-input gates are used after the AOI22 because the library's NAND4 and
// OR4 come only in weak sizes; these can be upsized and buffered by timing
// repair.  Same ports and function as rtl/kf_rdport.v; only N = 32.
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
            wire [15:0] t1;     // active low, 2 registers each
            wire [7:0]  t2;     // active high, 4
            wire [3:0]  t3;     // active low, 8
            wire [1:0]  t4;     // active high, 16
            for (i = 0; i < 16; i = i + 1) begin : g_aoi
                sg13g2_a22oi_1 u_aoi (.A1(sel[2*i]),     .A2(q[(2*i)*W + b]),
                                      .B1(sel[2*i + 1]), .B2(q[(2*i + 1)*W + b]),
                                      .Y(t1[i]));
            end
            for (i = 0; i < 8; i = i + 1) begin : g_l2
                sg13g2_nand2_1 u_nand (.A(t1[2*i]), .B(t1[2*i + 1]), .Y(t2[i]));
            end
            for (i = 0; i < 4; i = i + 1) begin : g_l3
                sg13g2_nor2_1 u_nor (.A(t2[2*i]), .B(t2[2*i + 1]), .Y(t3[i]));
            end
            for (i = 0; i < 2; i = i + 1) begin : g_l4
                sg13g2_nand2_1 u_nand (.A(t3[2*i]), .B(t3[2*i + 1]), .Y(t4[i]));
            end
            sg13g2_or2_1 u_or (.A(t4[0]), .B(t4[1]), .X(data[b]));
        end
    endgenerate
endmodule

`default_nettype wire
