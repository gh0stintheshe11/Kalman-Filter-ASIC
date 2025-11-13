// ============================================================================
// mem_reg.v
// Aggregates:
//   - data_bank : dual-read, single-write register file (flop-based, no reset)
//   - reg_we    : 24-bit register with write-enable (no reset) for RQ and RD
//   - mem_reg   : wrapper exposing DB + RQ + RD
// ----------------------------------------------------------------------------
// Notes:
// - All widths are parameterized; default W=24 (paper).
// - ADDRW must be big enough for DEPTH (set manually).
// - Reads are asynchronous; writes are synchronous on clk.
// - FORWARD=1 enables write-through on read-during-write same address.
// ============================================================================

`timescale 1ns/1ps

// 24-bit register with write-enable, NO reset (matches the paper)
module reg_we
#(parameter W=24)
(
  input               clk,
  input               we,
  input  [W-1:0]      d,
  output reg [W-1:0]  q
);
  always @(posedge clk) begin
    if (we) q <= d; // otherwise hold previous (power-up value is don't-care)
  end
endmodule

// Dual-read / single-write Data Bank (flop-based), NO reset
module data_bank
#(
  parameter W      = 24,
  parameter DEPTH  = 40,  // e.g., ~37..40 regs for n=2,m=2
  parameter ADDRW  = 6,   // enough bits for DEPTH (<=64 -> 6)
  parameter FORWARD= 1    // 1=write-through on read/write same addr
)(
  input                  clk,
  // write port
  input                  we,
  input  [ADDRW-1:0]     waddr,
  input  [W-1:0]         wdata,
  // read ports
  input  [ADDRW-1:0]     raddr_a,
  input  [ADDRW-1:0]     raddr_b,
  output reg [W-1:0]     rdata_a,
  output reg [W-1:0]     rdata_b
);
  reg [W-1:0] mem [0:DEPTH-1];

  // synchronous write
  always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
  end

  // asynchronous reads + optional write-through
  always @* begin
    rdata_a = mem[raddr_a];
    if (FORWARD && we && (raddr_a == waddr))
      rdata_a = wdata;
  end

  always @* begin
    rdata_b = mem[raddr_b];
    if (FORWARD && we && (raddr_b == waddr))
      rdata_b = wdata;
  end
endmodule

// Wrapper: Data Bank + RQ + RD (NO reset ports)
module mem_reg
#(
  parameter W      = 24,
  parameter DEPTH  = 40,
  parameter ADDRW  = 6,
  parameter FORWARD= 1
)(
  input                  clk,

  // ---- Data Bank interface (from Router A / decoder) ----
  input                  db_we,          // write enable
  input  [ADDRW-1:0]     db_waddr,       // write address
  input  [W-1:0]         db_wdata,       // write data
  input  [ADDRW-1:0]     db_raddr_a,     // read address A
  input  [ADDRW-1:0]     db_raddr_b,     // read address B
  output [W-1:0]         db_rdata_a,     // read data A
  output [W-1:0]         db_rdata_b,     // read data B

  // ---- RQ accumulator ----
  input                  rq_we,
  input  [W-1:0]         rq_d,
  output [W-1:0]         rq_q,

  // ---- RD accumulator ----
  input                  rd_we,
  input  [W-1:0]         rd_d,
  output [W-1:0]         rd_q
);

  // Data Bank instance
  data_bank #(.W(W), .DEPTH(DEPTH), .ADDRW(ADDRW), .FORWARD(FORWARD)) u_db (
    .clk     (clk),
    .we      (db_we),
    .waddr   (db_waddr),
    .wdata   (db_wdata),
    .raddr_a (db_raddr_a),
    .raddr_b (db_raddr_b),
    .rdata_a (db_rdata_a),
    .rdata_b (db_rdata_b)
  );

  // RQ, RD registers (no reset)
  reg_we #(.W(W)) u_rq (.clk(clk), .we(rq_we), .d(rq_d), .q(rq_q));
  reg_we #(.W(W)) u_rd (.clk(clk), .we(rd_we), .d(rd_d), .q(rd_q));

endmodule
