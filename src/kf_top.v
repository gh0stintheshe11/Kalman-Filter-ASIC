// -----------------------------------------------------------------------------
// kf_top.v
// Complete Kalman Filter ASIC top-level
// Integrates: Sequencer + Router A + Memory Registers + Router B + AU
// Based on the paper's architecture diagram
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_top
#(parameter W=24, parameter FRAC=14, parameter NR=32, parameter ADDRW=5)
(
  input              clk,
  input              rst_n,
  
  // External interface
  input              start,           // Start processing
  input  [W-1:0]     data_in,         // External data input
  output             ready,           // System ready for new operation
  
  // Optional observability outputs for debugging
  output [W-1:0]     result_out,      // AU result
  output             au_done
);

  // ========== Sequencer Signals ==========
  wire [4:0]  ctl_a;      // Router A address/control
  wire [4:0]  ctl_b;      // Router B address/control  
  wire [1:0]  ctl_c;      // Sequencer control (increment/wait/halt)
  wire [1:0]  ctl_d;      // AU operation control
  wire [1:0]  ctl_e;      // Additional control
  wire        continue_i; // AU done signal to sequencer
  
  sequencer Sequencer (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .continue_i (continue_i),
    .ready      (ready),
    .ctl_a      (ctl_a),
    .ctl_b      (ctl_b),
    .ctl_c      (ctl_c),
    .ctl_d      (ctl_d),
    .ctl_e      (ctl_e),
    .rom_we     (1'b0),        // ROM write disabled in normal operation
    .rom_waddr  (8'h00),       // Not used
    .rom_wdata  (16'h0000),    // Not used
    .pc_dbg     ()             // Debug output not connected
  );
  
  // ========== Decode Control Signals ==========
  // Instruction format: [a4 a3 a2 a1 a0 | b4 b3 b2 b1 b0 | c1 c0 | d1 d0 | e1 e0]
  // See INSTRUCTION_FORMAT.md for detailed encoding
  //
  // Field A (bits 15-11): Data source and address for write
  //   a4-a3: sel_data (00=DATA_IN, 01=RESULT, 10=ZERO)
  //   a2-a0: memory address for read/write
  //
  // Field B (bits 10-6): Operand selection
  //   b4-b3: sel_R (00=port A, 01=RQ, 10=0, 11=all 1s)
  //   b2-b1: sel_S (00=port B, 01=RD, 10=0, 11=all 1s)
  //   b0: address mode (0=use addr_a for both, 1=separate)
  //
  // Field C (bits 5-4): Sequencer control
  //   00=INC, 01=WAIT, 10=HALT
  //
  // Field D (bits 3-2): AU operation
  //   00=ADD, 01=SUB, 10=MUL, 11=DIV
  //
  // Field E (bits 1-0): Execution control
  //   e1=au_start, e0=write_en
  //   Special: e1e0=11 means write to RQ (from port A)
  //            e1e0=01 with sel_data=10 means write to RD (from port A)
  
  wire [1:0]  sel_data   = ctl_a[4:3];
  wire [ADDRW-1:0] addr_a = {{(ADDRW-3){1'b0}}, ctl_a[2:0]};
  
  wire [1:0]  sel_R      = ctl_b[4:3];
  wire [1:0]  sel_S      = ctl_b[2:1];
  wire        addr_mode  = ctl_b[0];
  
  // Address decoding:
  // - addr_a always comes from ctl_a[2:0]
  // - addr_b = addr_a+1 when addr_mode=1, otherwise addr_b = addr_a
  wire [ADDRW-1:0] addr_b = addr_mode ? 
                            (addr_a + 1'b1) : 
                            addr_a;
  
  wire        inv_R      = 1'b0;  // Not used in basic implementation
  wire        inv_S      = 1'b0;
  wire [1:0]  sel_I      = 2'b00; // Immediate = 0
  
  wire [1:0]  op_sel     = ctl_d[1:0];
  wire [1:0]  mul_y_sel  = 2'b00; // Y = S (could be extended)
  
  // RQ/RD write control
  // Write to RQ when e1e0=11 (reuse invalid AU+WR combination)
  // Write to RD when sel_data=10 (ZERO source) and write_en=1 and not writing to RQ
  wire        rq_we      = (ctl_e == 2'b11);
  wire        rd_we      = (sel_data == 2'b10) && ctl_e[0] && !rq_we;
  
  // AU and write enables - disable when writing to RQ/RD
  wire        au_start   = ctl_e[1] && !rq_we && !rd_we;
  wire        write_en   = ctl_e[0] && !rq_we && !rd_we;
  
  // ========== Router A ==========
  wire [W-1:0]        ra_data;
  wire [ADDRW-1:0]    ra_dira, ra_dirb;
  wire                ra_we;
  wire [W-1:0]        au_result;
  
  // Router A control signals (simplified - can be extended based on needs)
  wire [ADDRW-1:0] dir_ext = {ADDRW{1'b0}};  // External DIR not used in basic mode
  wire       sel_dira = 1'b0;   // Use CTL_A for dira
  wire       sel_dirb = 1'b0;   // Use CTL_B for dirb  
  wire [1:0] sel_write = 2'b00; // Direct write control
  
  router_a #(.W(W), .ADDRW(ADDRW)) Router_A (
    .DATA_IN    (data_in),
    .RESULT     (au_result),
    .CTL_A      (addr_a),
    .CTL_B      (addr_b),
    .DIR_EXT    (dir_ext),
    .WRITE_REQ  (write_en),
    .READY      (ready),
    .sel_data   (sel_data),
    .sel_dira   (sel_dira),
    .sel_dirb   (sel_dirb),
    .sel_write  (sel_write),
    .db_data    (ra_data),
    .db_dira    (ra_dira),
    .db_dirb    (ra_dirb),
    .db_write   (ra_we)
  );
  
  // ========== Memory Registers ==========
  wire [W-1:0] db_rdata_a, db_rdata_b;
  wire [W-1:0] rq_q, rd_q;
  
  mem_reg #(.W(W), .DEPTH(NR), .ADDRW(ADDRW), .FORWARD(1)) Memory_Registers (
    .clk        (clk),
    // Data Bank
    .db_we      (ra_we && !rq_we && !rd_we),  // Only write to DB if not writing to RQ/RD
    .db_waddr   (ra_dira),    // Write address from Router A
    .db_wdata   (ra_data),    // Write data from Router A
    .db_raddr_a (ra_dira),    // Read port A address from Router A
    .db_raddr_b (ra_dirb),    // Read port B address from Router A
    .db_rdata_a (db_rdata_a),
    .db_rdata_b (db_rdata_b),
    // RQ/RD registers - loaded from data bank port A
    .rq_we      (rq_we),
    .rq_d       (db_rdata_a),  // RQ gets data from port A
    .rq_q       (rq_q),
    .rd_we      (rd_we),
    .rd_d       (db_rdata_a),  // RD gets data from port A
    .rd_q       (rd_q)
  );
  
  // ========== Router B ==========
  wire [W-1:0] R_bus, S_bus, I_bus;
  
  router_b #(.W(W)) Router_B (
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
    .msb_R  (),  // Not used
    .msb_S  ()
  );
  
  // ========== Arithmetic Unit ==========
  wire au_busy;
  
  au #(.W(W), .FRAC(FRAC)) AU (
    .clk       (clk),
    .rst_n     (rst_n),
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
  
  // Connect AU done back to sequencer
  assign continue_i = au_done;
  
  // Observability outputs
  assign result_out = au_result;

endmodule
