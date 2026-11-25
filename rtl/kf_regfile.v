// kf_regfile.v -- data bank: N x W registers, one write port, three
// asynchronous read ports (operands A and B for the datapath, H for the
// host).
//
// Each register has its own clock gate, so a write clocks only the 24
// flip-flops being written and the bank draws no clock power otherwise (this
// also replaces the per-bit enable multiplexers).  No reset: the host
// initializes the registers it uses.
//
// The read ports (kf_rdport) decode their address to one-hot selects and
// AND-OR the registers: when the address changes, only the select lines of
// the old and the new register toggle.
`default_nettype none

module kf_regfile #(
    parameter integer W  = 24,
    parameter integer N  = 32,
    parameter integer AW = 5
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [W-1:0]  wdata,
    input  wire [AW-1:0] raddr_a,
    input  wire [AW-1:0] raddr_b,
    input  wire [AW-1:0] raddr_h,
    output wire [W-1:0]  rdata_a,
    output wire [W-1:0]  rdata_b,
    output wire [W-1:0]  rdata_h
);
    wire [W*N-1:0] q;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_reg
            localparam [AW-1:0] IDX = i;
            wire        gclk;
            reg [W-1:0] r;
            kf_clkgate u_cg (.clk(clk), .en(we & (waddr == IDX)), .gclk(gclk));
            always @(posedge gclk) r <= wdata;
            assign q[i*W +: W] = r;
        end
    endgenerate

    kf_rdport #(.W(W), .N(N), .AW(AW)) u_rd_a (.addr(raddr_a), .q(q), .data(rdata_a));
    kf_rdport #(.W(W), .N(N), .AW(AW)) u_rd_b (.addr(raddr_b), .q(q), .data(rdata_b));
    kf_rdport #(.W(W), .N(N), .AW(AW)) u_rd_h (.addr(raddr_h), .q(q), .data(rdata_h));

endmodule

`default_nettype wire
