// kf_rdport.v -- one register-file read port: one-hot decode, AND-OR.
//
// sel = onehot(addr); data = OR over i of (sel[i] & q[i]), as a balanced
// binary OR tree (N must be a power of two).  When addr changes, only the
// old and the new select line toggle, and only the two corresponding
// branches of the tree can change; a binary multiplexer tree would instead
// toggle select lines that drive every bit's multiplexers.
//
// Behavioral model, used for simulation.  Synthesis would turn this back
// into multiplexers, so the IHP flow uses flow/ihp-sg13g2/kf_rdport_ihp.v,
// the same function built from AOI22, NAND2, NOR2 and OR2 cells.
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
    // heap-ordered tree: node k = node 2k | node 2k+1, leaves N..2N-1
    // (split_var: each node its own signal for Verilator, see kf_prefix.v)
    wire [W-1:0] node [1:2*N-1] /* verilator split_var */;
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_leaf
            localparam [AW-1:0] IDX = i;
            assign node[N + i] = {W{addr == IDX}} & q[i*W +: W];
        end
        for (i = 1; i < N; i = i + 1) begin : g_or
            assign node[i] = node[2*i] | node[2*i + 1];
        end
    endgenerate
    assign data = node[1];
endmodule

`default_nettype wire
