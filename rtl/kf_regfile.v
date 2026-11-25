// kf_regfile.v -- data bank: N x W registers, 1 write + 2 asynchronous reads
//
// Port A's address is also the write address (paper Fig. 3, "dira").  There
// is deliberately no write-to-read forwarding: the original design forwarded
// the write data to port B, which formed a combinational loop through the
// arithmetic unit.  Registers have no reset; the host initializes them.
`default_nettype none

module kf_regfile #(
    parameter integer W  = 24,
    parameter integer N  = 32,
    parameter integer AW = 5
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr_a,    // read port A and write address
    input  wire [W-1:0]  wdata,
    input  wire [AW-1:0] addr_b,    // read port B
    output wire [W-1:0]  rdata_a,
    output wire [W-1:0]  rdata_b
);
    reg [W-1:0] mem [0:N-1];

    always @(posedge clk)
        if (we) mem[addr_a] <= wdata;

    assign rdata_a = mem[addr_a];
    assign rdata_b = mem[addr_b];

endmodule

`default_nettype wire
