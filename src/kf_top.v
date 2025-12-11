// -----------------------------------------------------------------------------
// kf_top.v
// Kalman Filter ASIC Top-Level (per paper Figure 3)
// -----------------------------------------------------------------------------
// Integrates all components per paper's architecture:
//   Sequencer   - PC + ROM (256x16) + instruction decode
//   Router A    - Data input mux and address routing
//   Data Bank   - NR x 24-bit register file + RQ/RD accumulators
//   Router B    - Operand selection for AU
//   AU          - Arithmetic Unit (Adder/Sub, Multiplier, Mult. Inverse)
//
// External Interface (per paper Figure 3):
//   DATA_IN     - 24-bit external data input
//   DATA_OUT    - 24-bit output (AU result)
//   DIR         - 5-bit external address
//   WRITE       - External write control
//   READY       - System ready status
//   START       - Start execution
//   RESET       - System reset (active low in this implementation)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_top
#(parameter W=24, parameter FRAC=14, parameter NR=32, parameter ADDRW=5)
(
  input              clk,
  input              rst_n,          // Active-low reset (paper uses active-high RESET)

  // External interface (per paper Figure 3)
  input              START,          // Start execution
  input  [W-1:0]     DATA_IN,        // External data input
  input  [ADDRW-1:0] DIR,            // External address input
  input              WRITE,          // External write request
  output             READY,          // System ready status
  output [W-1:0]     DATA_OUT,       // Output (AU result)

  // ROM programming interface (for testbench)
  input              rom_we,
  input  [7:0]       rom_waddr,
  input  [15:0]      rom_wdata
);

  // ========== Forward declarations ==========
  wire au_done;               // AU done signal (connects sequencer <-> AU)
  wire [W-1:0] au_result;     // AU result (connects AU -> Router A)

  // ========== Sequencer ==========
  // Instruction format per paper: "a4 a3 a2 a1 a0 b4 b3 b2 b1 b0 c1 c0 d1 d0 e f"
  wire [4:0]  ctl_a;      // Field A [15:11]: Address A - 5 bits
  wire [4:0]  ctl_b;      // Field B [10:6]:  Address B - 5 bits
  wire [1:0]  ctl_c;      // Field C [5:4]:   PC control
  wire [1:0]  ctl_d;      // Field D [3:2]:   AU operation
  wire        ctl_e;      // Field E [1]:     AU start
  wire        ctl_f;      // Field F [0]:     Write enable

  sequencer Sequencer (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (START),
    .continue_i (au_done),     // AU done signal (forward declared)
    .ready      (READY),
    .ctl_a      (ctl_a),
    .ctl_b      (ctl_b),
    .ctl_c      (ctl_c),
    .ctl_d      (ctl_d),
    .ctl_e      (ctl_e),
    .ctl_f      (ctl_f),
    .rom_we     (rom_we),
    .rom_waddr  (rom_waddr),
    .rom_wdata  (rom_wdata),
    .pc_dbg     ()
  );

  // ========== Result Valid Tracking ==========
  // Track when AU result is valid and should be used for next write.
  //
  // Per paper timing: 1-cycle operations (ADD/SUB/MUL) complete in the cycle
  // after they start. The STORE instruction executes the same cycle au_done=1.
  //
  // Two cases for selecting AU result vs DATA_IN:
  // 1. au_done=1 this cycle: AU just completed, result register is valid
  // 2. result_valid=1: AU completed previously, result not yet consumed
  //
  // The `result_valid` register tracks case 2 for multi-cycle scenarios
  // where the store might not immediately follow the operation.
  reg result_valid;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result_valid <= 1'b0;
    end else if (au_done) begin
      result_valid <= 1'b1;      // AU completed, result is valid
    end else if (ctl_f && result_valid) begin
      result_valid <= 1'b0;      // Result consumed by write
    end
  end

  // ========== Router A ==========
  // Connects: DATA_IN, AU result -> Data Bank
  wire [W-1:0]     ra_data;       // Data to Data Bank
  wire [ADDRW-1:0] ra_dira;       // Address A to Data Bank
  wire [ADDRW-1:0] ra_dirb;       // Address B to Data Bank
  wire             ra_write;      // Write enable to Data Bank

  // Data source selection: write AU result when au_done OR result_valid
  // au_done: AU just completed THIS cycle (1-cycle ops with immediate store)
  // result_valid: AU completed in a previous cycle, result waiting to be consumed
  wire [1:0] sel_data = (au_done || result_valid) ? 2'b01 : 2'b00;  // 00=DATA_IN, 01=result

  router_a #(.W(W), .ADDRW(ADDRW)) Router_A (
    // Inputs
    .DATA_IN    (DATA_IN),
    .result     (au_result),
    .ctl_a      (ctl_a),
    .ctl_b      (ctl_b),
    .DIR        (DIR),
    .WRITE      (ctl_f),          // Write enable from Field F
    .READY      (READY),
    // Control
    .sel_data   (sel_data),
    .sel_dira   (1'b0),           // Use ctl_a (not external DIR)
    .sel_dirb   (1'b0),           // Use ctl_b (not external DIR)
    .sel_write  (2'b00),          // Direct write control
    // Outputs to Data Bank
    .data       (ra_data),
    .dira       (ra_dira),
    .dirb       (ra_dirb),
    .write      (ra_write)
  );

  // ========== Memory Registers (Data Bank + RQ + RD) ==========
  wire [W-1:0] db_A, db_B;        // Data Bank outputs (to Router B)
  wire [W-1:0] RQ_out, RD_out;    // RQ/RD outputs (to Router B)

  mem_reg #(.W(W), .NR(NR), .ADDRW(ADDRW), .FORWARD(1)) Memory_Registers (
    .clk    (clk),
    // Data Bank interface (per paper naming)
    .write  (ra_write),
    .dira   (ra_dira),
    .dirb   (ra_dirb),
    .data   (ra_data),
    .A      (db_A),
    .B      (db_B),
    // RQ/RD interface (disabled for now - paper doesn't specify encoding)
    .rq_we  (1'b0),
    .rq_d   (db_A),
    .RQ     (RQ_out),
    .rd_we  (1'b0),
    .rd_d   (db_A),
    .RD     (RD_out)
  );

  // ========== Router B ==========
  // Connects: Data Bank outputs, RQ, RD -> AU operands R, S
  wire [W-1:0] R_bus, S_bus, I_bus;

  // Operand selection - default to Data Bank outputs
  // (Paper doesn't specify encoding for RQ/RD selection)
  wire [1:0] sel_R = 2'b00;       // 00 = A (Data Bank port A)
  wire [1:0] sel_S = 2'b00;       // 00 = B (Data Bank port B)

  router_b #(.W(W)) Router_B (
    // Inputs from Data Bank
    .A      (db_A),
    .B      (db_B),
    // Inputs from accumulators
    .RQ     (RQ_out),
    .RD     (RD_out),
    // Control
    .sel_R  (sel_R),
    .sel_S  (sel_S),
    .inv_R  (1'b0),
    .inv_S  (1'b0),
    .sel_I  (2'b00),
    // Outputs to AU
    .R      (R_bus),
    .S      (S_bus),
    .I      (I_bus),
    .msb_R  (),
    .msb_S  ()
  );

  // ========== Arithmetic Unit ==========
  wire au_busy;

  au #(.W(W), .FRAC(FRAC)) AU (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (ctl_e),              // AU start from Field E
    // Operands from Router B
    .R      (R_bus),
    .S      (S_bus),
    .I      (I_bus),
    // Control from sequencer
    .ctl_d  (ctl_d),
    // Outputs
    .result (au_result),
    .done   (au_done),
    .busy   (au_busy)
  );

  // ========== Output ==========
  assign DATA_OUT = au_result;

endmodule
