// -----------------------------------------------------------------------------
// kf_core.v
// Top-level core: Router A + mem_reg + Router B + AU
// Exposes simple control pins so a TB (or a future sequencer/decoder) can drive it.
// Default: 24-bit sign-magnitude, FRAC=14 to match the paper.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_core
#(parameter W=24, parameter FRAC=14, parameter DEPTH=40, parameter ADDRW=6)
(
  input                  clk,

  // ---------------- Router A controls ----------------
  input  [W-1:0]         DATA_IN,         // external data source
  input  [ADDRW-1:0]     CTL_A,           // address field A
  input  [ADDRW-1:0]     CTL_B,           // address field B
  input  [ADDRW-1:0]     DIR_EXT,         // external address (optional)
  input                   WRITE_REQ,      // request to write DB
  input                   READY_G,        // gating (e.g., AU done)
  input  [1:0]            sel_data,       // 0:DATA_IN 1:RESULT 2:ZERO 3:RESV
  input                   sel_dira,       // 0:CTL_A   1:DIR_EXT
  input                   sel_dirb,       // 0:CTL_B   1:DIR_EXT
  input  [1:0]            sel_write,      // 0:WR 1:WR&READY_G 2:0 3:1
  input  [ADDRW-1:0]      DB_WADDR,       // write dest (decoder decision)

  // ---------------- Router B controls ----------------
  input  [1:0]           sel_R,           // 00:A 01:RQ 10:0 11:FFFF
  input  [1:0]           sel_S,           // 00:B 01:RD 10:0 11:FFFF
  input                  inv_R,
  input                  inv_S,
  input  [1:0]           sel_I,           // 00:0 01:+1 10:-1 11:0

  // ---------------- AU controls ----------------
  input                  au_start,        // pulse to start AU op
  input  [1:0]           op_sel,          // 00=ADD 01=SUB 10=MUL 11=DIV(R*1/S)
  input  [1:0]           mul_y_sel,       // 00=S 01=I 10=inv(S)

  // ---------------- Status/observe ----------------
  output                 au_done,
  output                 au_busy,
  output [W-1:0]         result_out,      // AU result (for observation)
  // Useful taps to probe in TB
  output [W-1:0]         db_rdata_a,
  output [W-1:0]         db_rdata_b
);

  // ---------- Router A ----------
  wire [W-1:0]  ra_db_data;
  wire [ADDRW-1:0] ra_dira, ra_dirb;
  wire              ra_db_we;

  // AU result wire back to Router A
  wire [W-1:0] au_result;

  router_a #(.W(W), .ADDRW(ADDRW)) u_router_a (
    .DATA_IN    (DATA_IN),
    .RESULT     (au_result),
    .CTL_A      (CTL_A),
    .CTL_B      (CTL_B),
    .DIR_EXT    (DIR_EXT),
    .WRITE_REQ  (WRITE_REQ),
    .READY      (READY_G),
    .sel_data   (sel_data),
    .sel_dira   (sel_dira),
    .sel_dirb   (sel_dirb),
    .sel_write  (sel_write),
    .db_data    (ra_db_data),
    .db_dira    (ra_dira),
    .db_dirb    (ra_dirb),
    .db_write   (ra_db_we)
  );

  // ---------- Memory registers (Data Bank + RQ/RD) ----------
  wire [W-1:0] rq_q, rd_q;

  mem_reg #(.W(W), .DEPTH(DEPTH), .ADDRW(ADDRW), .FORWARD(1)) u_mem (
    .clk        (clk),
    // Data Bank
    .db_we      (ra_db_we),
    .db_waddr   (DB_WADDR),
    .db_wdata   (ra_db_data),
    .db_raddr_a (ra_dira),
    .db_raddr_b (ra_dirb),
    .db_rdata_a (db_rdata_a),
    .db_rdata_b (db_rdata_b),
    // RQ/RD (here we keep them unused unless your microcode uses them)
    .rq_we      (1'b0), .rq_d({W{1'b0}}), .rq_q(rq_q),
    .rd_we      (1'b0), .rd_d({W{1'b0}}), .rd_q(rd_q)
  );

  // ---------- Router B ----------
  wire [W-1:0] R_bus, S_bus, I_bus;
  wire msb_R, msb_S;  // (not used directly here, but exposed inside AU if needed)

  router_b #(.W(W)) u_router_b (
    .A_data (db_rdata_a),
    .B_data (db_rdata_b),
    .RQ     (rq_q),
    .RD     (rd_q),
    .sel_R  (sel_R),
    .sel_S  (sel_S),
    .inv_R  (inv_R),
    .inv_S  (inv_S),
    .sel_I  (sel_I),
    .R      (R_bus),
    .S      (S_bus),
    .I      (I_bus),
    .msb_R  (/*unused*/),
    .msb_S  (/*unused*/)
  );

  // ---------- Arithmetic Unit ----------
  au #(.W(W), .FRAC(FRAC)) u_au (
    .clk       (clk),
    .start     (au_start),
    .R_in      (R_bus),
    .S_in      (S_bus),
    .Iimm_in   (I_bus),
    .op_sel    (op_sel),
    .mul_y_sel (mul_y_sel),
    .result    (au_result),
    .done      (au_done),
    .busy      (au_busy)
  );

  assign result_out = au_result;

endmodule
