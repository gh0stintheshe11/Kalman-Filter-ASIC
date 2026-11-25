// kf_regfile.v -- data bank: N x W registers, one write port, two
// asynchronous read ports.
//
// Each register has its own clock gate, so a write clocks only the 24
// flip-flops being written and the bank draws no clock power otherwise (this
// also replaces the per-bit enable multiplexers).  No reset: the host
// initializes the registers it uses.
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
    output wire [W-1:0]  rdata_a,
    output wire [W-1:0]  rdata_b
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

    assign rdata_a = q[raddr_a*W +: W];
    assign rdata_b = q[raddr_b*W +: W];

endmodule

`default_nettype wire
