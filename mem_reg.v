// ============================================================================
// mem_reg.v
// Memory Registers Block - matches paper's architecture
// Contains three modules:
//   - Data_Bank : 32-register dual-read, single-write register file (5-bit addr)
//   - RQ        : 24-bit register with write-enable (Q matrix element storage)
//   - RD        : 24-bit register with write-enable (R matrix element storage)
//   - mem_reg   : top-level wrapper exposing DB + RQ + RD
// ----------------------------------------------------------------------------
// Notes:
// - All widths are parameterized; default W=24 (paper).
// - ADDRW must be big enough for DEPTH (set manually).
// - Reads are asynchronous; writes are synchronous on clk.
// - FORWARD=1 enables write-through on read-during-write same address.
// ============================================================================

`timescale 1ns/1ps
// RQ Register Module - 24-bit register with write-enable, NO reset
module RQ #(parameter W=24)(
  input clk, input we, input [W-1:0] d, output reg [W-1:0] q
);
  always @(posedge clk) if (we) q <= d;
endmodule

// RD Register Module - 24-bit register with write-enable, NO reset
module RD #(parameter W=24)(
  input clk, input we, input [W-1:0] d, output reg [W-1:0] q
);
  always @(posedge clk) if (we) q <= d;
endmodule

// Data_Bank Module - Dual-read / single-write register file, NO reset
module Data_Bank
#(parameter W=24, parameter DEPTH=32, parameter ADDRW=5, parameter FORWARD=1)
(
  input clk,
  input we, input [ADDRW-1:0] waddr, input [W-1:0] wdata,
  input [ADDRW-1:0] raddr_a, input [ADDRW-1:0] raddr_b,
  output reg [W-1:0] rdata_a, output reg [W-1:0] rdata_b
);
  reg [W-1:0] mem [0:DEPTH-1];
  always @(posedge clk) if (we) mem[waddr] <= wdata;
  always @* begin
    rdata_a = mem[raddr_a];
    if (FORWARD && we && (raddr_a == waddr)) rdata_a = wdata;
  end
  always @* begin
    rdata_b = mem[raddr_b];
    if (FORWARD && we && (raddr_b == waddr)) rdata_b = wdata;
  end
endmodule

// Wrapper: Data Bank + RQ + RD
module mem_reg
#(parameter W=24, parameter DEPTH=32, parameter ADDRW=5, parameter FORWARD=1)
(
  input clk,
  // Data Bank
  input db_we, input [ADDRW-1:0] db_waddr, input [W-1:0] db_wdata,
  input [ADDRW-1:0] db_raddr_a, input [ADDRW-1:0] db_raddr_b,
  output [W-1:0] db_rdata_a, output [W-1:0] db_rdata_b,
  // RQ / RD
  input rq_we, input [W-1:0] rq_d, output [W-1:0] rq_q,
  input rd_we, input [W-1:0] rd_d, output [W-1:0] rd_q
);
  Data_Bank #(.W(W), .DEPTH(DEPTH), .ADDRW(ADDRW), .FORWARD(FORWARD)) Data_Bank_inst (
    .clk(clk), .we(db_we), .waddr(db_waddr), .wdata(db_wdata),
    .raddr_a(db_raddr_a), .raddr_b(db_raddr_b),
    .rdata_a(db_rdata_a), .rdata_b(db_rdata_b)
  );
  RQ #(.W(W)) RQ_inst (.clk(clk), .we(rq_we), .d(rq_d), .q(rq_q));
  RD #(.W(W)) RD_inst (.clk(clk), .we(rd_we), .d(rd_d), .q(rd_q));
endmodule