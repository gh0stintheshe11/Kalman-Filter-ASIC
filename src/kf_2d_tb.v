// -----------------------------------------------------------------------------
// kf_2d_tb.v
// 2-State 1-Measurement Kalman Filter Testbench (per paper Section 3 & 5)
// -----------------------------------------------------------------------------
// This is the EXACT implementation from the paper:
//   - n = 2 states (e.g., position and velocity for inertial navigation)
//   - r = 1 measurement
//   - m = 1 control input
//
// Paper equations (Section 3):
//   Time Update (Predict):
//     x^-_k = Phi * x^+_{k-1} + G * u_{k-1}           (Eq. 3)
//     P^-_k = Phi * P^+_{k-1} * Phi^T + Q_{k-1}       (Eq. 4)
//
//   Measurement Update (Correct):
//     K_k = P^-_k * H^T * (H * P^-_k * H^T + R_k)^-1  (Eq. 5)
//     x^+_k = x^-_k + K_k * (y_k - H * x^-_k)         (Eq. 6)
//     P^+_k = (I - K_k * H) * P^-_k                   (Eq. 7)
//
// For 2-state, 1-measurement system:
//   x = [x1; x2]  (2x1 state vector)
//   Phi = [phi11 phi12; phi21 phi22]  (2x2 state transition)
//   P = [p11 p12; p21 p22]  (2x2 covariance)
//   H = [h1 h2]  (1x2 measurement matrix)
//   K = [k1; k2]  (2x1 Kalman gain)
//   Q = [q11 q12; q21 q22]  (2x2 process noise covariance)
//   R = r  (scalar measurement noise variance)
//   G = [g1; g2]  (2x1 control input matrix)
//   u = scalar control input
//   y = scalar measurement
//
// Memory Layout (32 registers per paper Eq. 10 for n=2, r=1, m=1):
//   DB[0]  = x1     (state 1)
//   DB[1]  = x2     (state 2)
//   DB[2]  = p11    (covariance element)
//   DB[3]  = p12    (covariance element)
//   DB[4]  = p21    (covariance element)
//   DB[5]  = p22    (covariance element)
//   DB[6]  = phi11  (state transition)
//   DB[7]  = phi12  (state transition)
//   DB[8]  = phi21  (state transition)
//   DB[9]  = phi22  (state transition)
//   DB[10] = q11    (process noise covariance)
//   DB[11] = q12    (process noise covariance)
//   DB[12] = q21    (process noise covariance)
//   DB[13] = q22    (process noise covariance)
//   DB[14] = h1     (measurement matrix element)
//   DB[15] = h2     (measurement matrix element)
//   DB[16] = r      (measurement noise variance)
//   DB[17] = g1     (control input matrix)
//   DB[18] = g2     (control input matrix)
//   DB[19] = u      (control input)
//   DB[20] = y      (measurement)
//   DB[21-31] = temp storage for intermediate calculations
//
// Per paper Table III: 2-state 1-measurement KF requires 113 clock cycles
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_2d_tb();
  parameter W = 24;
  parameter FRAC = 14;
  parameter NR = 32;
  parameter ADDRW = 5;

  // DUT signals
  reg              clk;
  reg              rst_n;
  reg              START;
  reg  [W-1:0]     DATA_IN;
  reg  [ADDRW-1:0] DIR;
  reg              WRITE;
  wire             READY;
  wire [W-1:0]     DATA_OUT;

  // ROM programming signals
  reg              rom_we;
  reg  [7:0]       rom_waddr;
  reg  [15:0]      rom_wdata;

  // Test tracking
  integer test_iter;
  integer pass_count, fail_count;

  // ROM program counter (module-level for task access)
  integer rom_pc;

  // Instantiate DUT
  kf_top dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .START      (START),
    .DATA_IN    (DATA_IN),
    .DIR        (DIR),
    .WRITE      (WRITE),
    .READY      (READY),
    .DATA_OUT   (DATA_OUT),
    .rom_we     (rom_we),
    .rom_waddr  (rom_waddr),
    .rom_wdata  (rom_wdata)
  );

  // Clock generation (100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // =========================================================================
  // Helper Functions
  // =========================================================================

  // Convert real to sign-magnitude Q9.14 format
  function [W-1:0] real_to_sm;
    input real x;
    reg sign;
    integer mag_int;
    reg [W-2:0] mag;
    begin
      sign = (x < 0.0);
      mag_int = (sign ? -x : x) * (1 << FRAC);
      mag = mag_int[W-2:0];
      real_to_sm = {sign, mag};
    end
  endfunction

  // Convert sign-magnitude to real
  function real sm_to_real;
    input [W-1:0] sm;
    reg sign;
    reg [W-2:0] mag;
    real val;
    begin
      sign = sm[W-1];
      mag = sm[W-2:0];
      val = $itor(mag) / (1 << FRAC);
      sm_to_real = sign ? -val : val;
    end
  endfunction

  // Pack instruction: {a[15:11], b[10:6], c[5:4], d[3:2], e[1], f[0]}
  function [15:0] INSTR;
    input [4:0] a, b;      // Address fields
    input [1:0] c, d;      // Control fields (c=PC control, d=AU op)
    input       e, f;      // e=AU start, f=write enable
    begin
      INSTR = {a, b, c, d, e, f};
    end
  endfunction

  // =========================================================================
  // ROM Write Task
  // =========================================================================
  task rom_wr;
    input [7:0]  addr;
    input [15:0] data;
    begin
      @(negedge clk);
      rom_waddr <= addr;
      rom_wdata <= data;
      rom_we    <= 1'b1;
      @(posedge clk);
      rom_we    <= 1'b0;
    end
  endtask

  // =========================================================================
  // ROM Programming Task - 2D Kalman Filter Algorithm
  // Per paper Section 3 equations and Table I operations
  // =========================================================================
  // 2-Instruction Pattern for AU operations:
  //   Instr N:   a=src_a, b=src_b, c=01 (WAIT), d=OP, e=1, f=0  // Compute & wait
  //   Instr N+1: a=dest,  b=X,     c=00 (INC),  d=X,  e=0, f=1  // Store result
  // =========================================================================
  task program_rom_2d_kf;
    begin
      $display("[ROM] Programming 2D Kalman Filter (n=2, r=1, m=1)...");
      rom_pc = 0;

      // =====================================================================
      // INITIALIZATION PHASE: Load all parameters via DATA_IN
      // These instructions store external data to Data Bank registers
      // =====================================================================

      // Load state vector x = [x1; x2]
      rom_wr(rom_pc, INSTR(5'd0,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x1 -> DB[0]
      rom_wr(rom_pc, INSTR(5'd1,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x2 -> DB[1]

      // Load covariance P = [p11 p12; p21 p22]
      rom_wr(rom_pc, INSTR(5'd2,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // p11 -> DB[2]
      rom_wr(rom_pc, INSTR(5'd3,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // p12 -> DB[3]
      rom_wr(rom_pc, INSTR(5'd4,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // p21 -> DB[4]
      rom_wr(rom_pc, INSTR(5'd5,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // p22 -> DB[5]

      // Load state transition Phi = [phi11 phi12; phi21 phi22]
      rom_wr(rom_pc, INSTR(5'd6,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // phi11 -> DB[6]
      rom_wr(rom_pc, INSTR(5'd7,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // phi12 -> DB[7]
      rom_wr(rom_pc, INSTR(5'd8,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // phi21 -> DB[8]
      rom_wr(rom_pc, INSTR(5'd9,  5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // phi22 -> DB[9]

      // Load process noise Q = [q11 q12; q21 q22]
      rom_wr(rom_pc, INSTR(5'd10, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // q11 -> DB[10]
      rom_wr(rom_pc, INSTR(5'd11, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // q12 -> DB[11]
      rom_wr(rom_pc, INSTR(5'd12, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // q21 -> DB[12]
      rom_wr(rom_pc, INSTR(5'd13, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // q22 -> DB[13]

      // Load measurement matrix H = [h1 h2]
      rom_wr(rom_pc, INSTR(5'd14, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // h1 -> DB[14]
      rom_wr(rom_pc, INSTR(5'd15, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // h2 -> DB[15]

      // Load measurement noise R (scalar)
      rom_wr(rom_pc, INSTR(5'd16, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // R -> DB[16]

      // Load control input matrix G = [g1; g2]
      rom_wr(rom_pc, INSTR(5'd17, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // g1 -> DB[17]
      rom_wr(rom_pc, INSTR(5'd18, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // g2 -> DB[18]

      // Load control input u and measurement y
      rom_wr(rom_pc, INSTR(5'd19, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // u -> DB[19]
      rom_wr(rom_pc, INSTR(5'd20, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // y -> DB[20]

      // =====================================================================
      // TIME UPDATE (PREDICT) - Eq. 3 & 4
      // =====================================================================
      // Use c=01 (WAIT) for AU operations so PC waits for au_done

      // ----- Eq. 3: x^-_k = Phi * x^+_{k-1} + G * u_{k-1} -----
      // x1^- = phi11*x1 + phi12*x2 + g1*u
      // x2^- = phi21*x1 + phi22*x2 + g2*u

      // phi11 * x1 -> DB[21]
      rom_wr(rom_pc, INSTR(5'd6,  5'd0,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd21, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // phi12 * x2 -> DB[22]
      rom_wr(rom_pc, INSTR(5'd7,  5'd1,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd22, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // phi11*x1 + phi12*x2 -> DB[21]
      rom_wr(rom_pc, INSTR(5'd21, 5'd22, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // ADD + WAIT
      rom_wr(rom_pc, INSTR(5'd21, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // g1 * u -> DB[22]
      rom_wr(rom_pc, INSTR(5'd17, 5'd19, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd22, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // x1^- = (phi11*x1 + phi12*x2) + g1*u -> DB[21]
      rom_wr(rom_pc, INSTR(5'd21, 5'd22, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // ADD + WAIT
      rom_wr(rom_pc, INSTR(5'd21, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x1^- stored

      // phi21 * x1 -> DB[22]
      rom_wr(rom_pc, INSTR(5'd8,  5'd0,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd22, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // phi22 * x2 -> DB[23]
      rom_wr(rom_pc, INSTR(5'd9,  5'd1,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd23, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // phi21*x1 + phi22*x2 -> DB[22]
      rom_wr(rom_pc, INSTR(5'd22, 5'd23, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // ADD + WAIT
      rom_wr(rom_pc, INSTR(5'd22, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // g2 * u -> DB[23]
      rom_wr(rom_pc, INSTR(5'd18, 5'd19, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // MUL + WAIT
      rom_wr(rom_pc, INSTR(5'd23, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // Store result

      // x2^- = (phi21*x1 + phi22*x2) + g2*u -> DB[22]
      rom_wr(rom_pc, INSTR(5'd22, 5'd23, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // ADD + WAIT
      rom_wr(rom_pc, INSTR(5'd22, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x2^- stored

      // x^- is now in DB[21] (x1^-) and DB[22] (x2^-)

      // ----- Eq. 4: P^-_k = Phi * P^+_{k-1} * Phi^T + Q_{k-1} -----
      // First compute Phi * P (2x2 * 2x2)

      // (Phi*P)_11 = phi11*p11 + phi12*p21 -> DB[23]
      rom_wr(rom_pc, INSTR(5'd6,  5'd2,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // phi11*p11
      rom_wr(rom_pc, INSTR(5'd23, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd7,  5'd4,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // phi12*p21
      rom_wr(rom_pc, INSTR(5'd24, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd23, 5'd24, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // ADD
      rom_wr(rom_pc, INSTR(5'd23, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (Phi*P)_11 -> DB[23]

      // (Phi*P)_12 = phi11*p12 + phi12*p22 -> DB[24]
      rom_wr(rom_pc, INSTR(5'd6,  5'd3,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd24, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd7,  5'd5,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd24, 5'd25, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd24, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (Phi*P)_12 -> DB[24]

      // (Phi*P)_21 = phi21*p11 + phi22*p21 -> DB[25]
      rom_wr(rom_pc, INSTR(5'd8,  5'd2,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd9,  5'd4,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd25, 5'd26, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (Phi*P)_21 -> DB[25]

      // (Phi*P)_22 = phi21*p12 + phi22*p22 -> DB[26]
      rom_wr(rom_pc, INSTR(5'd8,  5'd3,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd9,  5'd5,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd27, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (Phi*P)_22 -> DB[26]

      // (Phi*P) is now in DB[23,24,25,26]
      // Now compute (Phi*P) * Phi^T + Q
      // Phi^T = [phi11 phi21; phi12 phi22]

      // P^-_11 = (Phi*P)_11*phi11 + (Phi*P)_12*phi12 + q11 -> DB[2]
      rom_wr(rom_pc, INSTR(5'd23, 5'd6,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd24, 5'd7,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd28, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd10, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // + q11
      rom_wr(rom_pc, INSTR(5'd2,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^-_11 -> DB[2]

      // P^-_12 = (Phi*P)_11*phi21 + (Phi*P)_12*phi22 + q12 -> DB[3]
      rom_wr(rom_pc, INSTR(5'd23, 5'd8,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd24, 5'd9,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd28, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd11, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // + q12
      rom_wr(rom_pc, INSTR(5'd3,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^-_12 -> DB[3]

      // P^-_21 = (Phi*P)_21*phi11 + (Phi*P)_22*phi12 + q21 -> DB[4]
      rom_wr(rom_pc, INSTR(5'd25, 5'd6,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd7,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd28, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd12, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // + q21
      rom_wr(rom_pc, INSTR(5'd4,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^-_21 -> DB[4]

      // P^-_22 = (Phi*P)_21*phi21 + (Phi*P)_22*phi22 + q22 -> DB[5]
      rom_wr(rom_pc, INSTR(5'd25, 5'd8,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd9,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd28, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd13, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // + q22
      rom_wr(rom_pc, INSTR(5'd5,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^-_22 -> DB[5]

      // P^- is now in DB[2,3,4,5], x^- is in DB[21,22]

      // =====================================================================
      // MEASUREMENT UPDATE (CORRECT) - Eq. 5, 6, 7
      // =====================================================================

      // ----- Eq. 5: K = P^- * H^T / (H * P^- * H^T + R) -----
      // For r=1: H*P^-*H^T is scalar

      // (P^-*H^T)_1 = p11*h1 + p12*h2 -> DB[27]
      rom_wr(rom_pc, INSTR(5'd2,  5'd14, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd3,  5'd15, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd28, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (P^-*H^T)_1 -> DB[27]

      // (P^-*H^T)_2 = p21*h1 + p22*h2 -> DB[28]
      rom_wr(rom_pc, INSTR(5'd4,  5'd14, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd5,  5'd15, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd29, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // (P^-*H^T)_2 -> DB[28]

      // S = H * (P^-*H^T) + R = h1*(P^-*H^T)_1 + h2*(P^-*H^T)_2 + R -> DB[29]
      rom_wr(rom_pc, INSTR(5'd14, 5'd27, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd15, 5'd28, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd30, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd30, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd16, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // + R
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // S -> DB[29]

      // K1 = (P^-*H^T)_1 / S (DIV takes ~24 cycles) -> DB[23]
      rom_wr(rom_pc, INSTR(5'd27, 5'd29, 2'b01, 2'b11, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // DIV with WAIT
      rom_wr(rom_pc, INSTR(5'd23, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // K1 -> DB[23]

      // K2 = (P^-*H^T)_2 / S -> DB[24]
      rom_wr(rom_pc, INSTR(5'd28, 5'd29, 2'b01, 2'b11, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // DIV with WAIT
      rom_wr(rom_pc, INSTR(5'd24, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // K2 -> DB[24]

      // K = [K1; K2] in DB[23,24]

      // ----- Eq. 6: x^+ = x^- + K * (y - H*x^-) -----
      // innovation = y - H*x^- = y - (h1*x1^- + h2*x2^-) -> DB[25]

      rom_wr(rom_pc, INSTR(5'd14, 5'd21, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // h1*x1^-
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd15, 5'd22, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // h2*x2^-
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd25, 5'd26, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // H*x^-
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd20, 5'd25, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // y - H*x^-
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // innov -> DB[25]

      // x1^+ = x1^- + K1 * innovation -> DB[0]
      rom_wr(rom_pc, INSTR(5'd23, 5'd25, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K1*innov
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd21, 5'd26, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // x1^- + K1*innov
      rom_wr(rom_pc, INSTR(5'd0,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x1^+ -> DB[0]

      // x2^+ = x2^- + K2 * innovation -> DB[1]
      rom_wr(rom_pc, INSTR(5'd24, 5'd25, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K2*innov
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd22, 5'd26, 2'b01, 2'b00, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // x2^- + K2*innov
      rom_wr(rom_pc, INSTR(5'd1,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // x2^+ -> DB[1]

      // ----- Eq. 7: P^+ = (I - K*H) * P^- -----
      // Compute K*H elements first
      rom_wr(rom_pc, INSTR(5'd23, 5'd14, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K1*h1
      rom_wr(rom_pc, INSTR(5'd25, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // -> DB[25]

      rom_wr(rom_pc, INSTR(5'd23, 5'd15, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K1*h2
      rom_wr(rom_pc, INSTR(5'd26, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // -> DB[26]

      rom_wr(rom_pc, INSTR(5'd24, 5'd14, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K2*h1
      rom_wr(rom_pc, INSTR(5'd27, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // -> DB[27]

      rom_wr(rom_pc, INSTR(5'd24, 5'd15, 2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K2*h2
      rom_wr(rom_pc, INSTR(5'd28, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // -> DB[28]

      // P^+_11 = p11 - K1*h1*p11 - K1*h2*p21 -> DB[2]
      rom_wr(rom_pc, INSTR(5'd25, 5'd2,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K1*h1*p11
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd4,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // K1*h2*p21
      rom_wr(rom_pc, INSTR(5'd30, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd2,  5'd29, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // p11 - K1*h1*p11
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd30, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;  // - K1*h2*p21
      rom_wr(rom_pc, INSTR(5'd2,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^+_11 -> DB[2]

      // P^+_12 = p12 - K1*h1*p12 - K1*h2*p22 -> DB[3]
      rom_wr(rom_pc, INSTR(5'd25, 5'd3,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd26, 5'd5,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd30, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd3,  5'd29, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd30, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd3,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^+_12 -> DB[3]

      // P^+_21 = p21 - K2*h1*p11 - K2*h2*p21 -> DB[4]
      rom_wr(rom_pc, INSTR(5'd27, 5'd2,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd4,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd30, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd4,  5'd29, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd30, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd4,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^+_21 -> DB[4]

      // P^+_22 = p22 - K2*h1*p12 - K2*h2*p22 -> DB[5]
      rom_wr(rom_pc, INSTR(5'd27, 5'd3,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd28, 5'd5,  2'b01, 2'b10, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd30, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd5,  5'd29, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd29, 5'd30, 2'b01, 2'b01, 1'b1, 1'b0)); rom_pc = rom_pc + 1;
      rom_wr(rom_pc, INSTR(5'd5,  5'd0,  2'b00, 2'b00, 1'b0, 1'b1)); rom_pc = rom_pc + 1;  // P^+_22 -> DB[5]

      // =====================================================================
      // HALT
      // =====================================================================
      rom_wr(rom_pc, INSTR(5'd0, 5'd0, 2'b10, 2'b00, 1'b0, 1'b0)); rom_pc = rom_pc + 1;

      $display("[ROM] Programmed %0d instructions for 2D Kalman Filter", rom_pc);
    end
  endtask

  // =========================================================================
  // Data Loading Task
  // =========================================================================
  // Data must be present on DATA_IN BEFORE the clock edge when the write
  // instruction executes. The sequence is:
  //   1. Set DATA_IN value
  //   2. Wait for clock edge (write happens here)
  //   3. Repeat for next value
  // =========================================================================
  task load_kf_data;
    input real x1_init, x2_init;
    input real p11_init, p12_init, p21_init, p22_init;
    input real phi11, phi12, phi21, phi22;
    input real q11, q12, q21, q22;
    input real h1, h2;
    input real r_noise;
    input real g1, g2;
    input real u_ctrl;
    input real y_meas;
    begin
      // State vector - DATA_IN must be set BEFORE the instruction executes
      DATA_IN = real_to_sm(x1_init);  @(posedge clk);
      DATA_IN = real_to_sm(x2_init);  @(posedge clk);

      // Covariance matrix
      DATA_IN = real_to_sm(p11_init); @(posedge clk);
      DATA_IN = real_to_sm(p12_init); @(posedge clk);
      DATA_IN = real_to_sm(p21_init); @(posedge clk);
      DATA_IN = real_to_sm(p22_init); @(posedge clk);

      // State transition matrix
      DATA_IN = real_to_sm(phi11);    @(posedge clk);
      DATA_IN = real_to_sm(phi12);    @(posedge clk);
      DATA_IN = real_to_sm(phi21);    @(posedge clk);
      DATA_IN = real_to_sm(phi22);    @(posedge clk);

      // Process noise covariance
      DATA_IN = real_to_sm(q11);      @(posedge clk);
      DATA_IN = real_to_sm(q12);      @(posedge clk);
      DATA_IN = real_to_sm(q21);      @(posedge clk);
      DATA_IN = real_to_sm(q22);      @(posedge clk);

      // Measurement matrix
      DATA_IN = real_to_sm(h1);       @(posedge clk);
      DATA_IN = real_to_sm(h2);       @(posedge clk);

      // Measurement noise
      DATA_IN = real_to_sm(r_noise);  @(posedge clk);

      // Control input matrix
      DATA_IN = real_to_sm(g1);       @(posedge clk);
      DATA_IN = real_to_sm(g2);       @(posedge clk);

      // Control input and measurement
      DATA_IN = real_to_sm(u_ctrl);   @(posedge clk);
      DATA_IN = real_to_sm(y_meas);   @(posedge clk);

      DATA_IN = 0;
    end
  endtask

  // =========================================================================
  // Main Test
  // =========================================================================
  initial begin
    $display("================================================================");
    $display("2D Kalman Filter Test (per paper Section 3 & 5)");
    $display("n=2 states, r=1 measurement, m=1 control input");
    $display("Per paper Table III: 113 clock cycles per iteration");
    $display("================================================================");

    // Initialize signals
    rst_n = 0;
    START = 0;
    DATA_IN = 0;
    DIR = 0;
    WRITE = 0;
    rom_we = 0;
    rom_waddr = 0;
    rom_wdata = 0;
    pass_count = 0;
    fail_count = 0;

    // Reset
    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Program ROM with 2D KF algorithm
    program_rom_2d_kf;

    // =====================================================================
    // Test Case: Inertial Navigation Example (per paper application)
    // State: [position; velocity]
    // Phi: discrete-time state transition for dt=0.1s
    //   position_new = position + dt*velocity
    //   velocity_new = velocity
    //   Phi = [1 dt; 0 1] = [1 0.1; 0 1]
    // H: measure position only -> H = [1 0]
    // =====================================================================
    $display("\n--- Test: Inertial Navigation (position/velocity) ---");
    $display("State: [position; velocity]");
    $display("Phi = [1 0.1; 0 1] (dt=0.1s)");
    $display("H = [1 0] (measure position)");
    $display("Initial: x=[0; 1], P=I, Q=0.01*I, R=0.1");
    $display("Measurement: y=0.5");

    // Pre-load first data value BEFORE START (so it's ready when first instruction writes)
    DATA_IN = real_to_sm(0.0);  // x1 = 0.0

    // Start execution - at next posedge, PC=0, instruction 0 fetched
    START = 1;
    @(posedge clk);
    START = 0;

    // Now sequencer is running, PC=0 -> instruction 0 will write DATA_IN to DB[0] on next posedge
    // Load remaining data synchronized with instruction execution
    // Each data value must be present BEFORE the posedge when its instruction executes
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // x2 = 1.0 -> DB[1]
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // p11 = 1.0 -> DB[2]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // p12 = 0.0 -> DB[3]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // p21 = 0.0 -> DB[4]
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // p22 = 1.0 -> DB[5]
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // phi11 = 1.0 -> DB[6]
    DATA_IN = real_to_sm(0.1);   @(posedge clk);  // phi12 = 0.1 -> DB[7]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // phi21 = 0.0 -> DB[8]
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // phi22 = 1.0 -> DB[9]
    DATA_IN = real_to_sm(0.01);  @(posedge clk);  // q11 = 0.01 -> DB[10]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // q12 = 0.0 -> DB[11]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // q21 = 0.0 -> DB[12]
    DATA_IN = real_to_sm(0.01);  @(posedge clk);  // q22 = 0.01 -> DB[13]
    DATA_IN = real_to_sm(1.0);   @(posedge clk);  // h1 = 1.0 -> DB[14]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // h2 = 0.0 -> DB[15]
    DATA_IN = real_to_sm(0.1);   @(posedge clk);  // R = 0.1 -> DB[16]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // g1 = 0.0 -> DB[17]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // g2 = 0.0 -> DB[18]
    DATA_IN = real_to_sm(0.0);   @(posedge clk);  // u = 0.0 -> DB[19]
    DATA_IN = real_to_sm(0.5);   @(posedge clk);  // y = 0.5 -> DB[20]
    DATA_IN = 0;

    // Debug: Check loaded data
    #10;
    $display("\n--- Debug: Loaded Initial Values ---");
    $display("  x1 (DB[0])  = %.6f (0x%06h)", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]), dut.Memory_Registers.Data_Bank_inst.mem[0]);
    $display("  x2 (DB[1])  = %.6f (0x%06h)", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[1]), dut.Memory_Registers.Data_Bank_inst.mem[1]);
    $display("  phi11 (DB[6]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[6]));
    $display("  phi12 (DB[7]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[7]));
    $display("  h1 (DB[14]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[14]));
    $display("  R (DB[16]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[16]));
    $display("  y (DB[20]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[20]));

    // Wait for completion
    $display("\n--- Executing 2D Kalman Filter ---");
    begin : wait_loop
      integer i;
      for (i = 0; i < 500; i = i + 1) begin
        @(posedge clk);
        #1;
`ifndef SIM_POST_SYN
        // Debug first few computation cycles
        if (i >= 0 && i <= 25) begin
          $display("  Cycle %3d: PC=%3d, state=%d, rv=%b, done=%b, e=%b, f=%b, c=%b, result=%h",
                   i, dut.Sequencer.pc, dut.AU.state, dut.result_valid, dut.au_done,
                   dut.ctl_e, dut.ctl_f, dut.ctl_c, dut.au_result);
          $display("           dira=%d, dirb=%d, A=%h, B=%h, ra_data=%h, ra_write=%b",
                   dut.ra_dira, dut.ra_dirb, dut.db_A, dut.db_B, dut.ra_data, dut.ra_write);
        end
        if (i % 40 == 0 && i > 10) begin
          $display("  Cycle %3d: PC=%3d, READY=%b",
                   i, dut.Sequencer.pc, READY);
        end
`else
        if (i % 50 == 0) begin
          $display("  Cycle %3d: READY=%b", i, READY);
        end
`endif
        if (READY == 1'b1 && i > 25) begin
          $display("  KF computation completed at cycle %0d", i);
          disable wait_loop;
        end
      end
      $display("  WARNING: Reached max cycles without completion");
    end

    // Display results
    #20;
    $display("\n================================================================");
    $display("Results");
    $display("================================================================");

`ifndef SIM_POST_SYN
    $display("  x1 (position) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]),
             dut.Memory_Registers.Data_Bank_inst.mem[0]);
    $display("  x2 (velocity) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[1]),
             dut.Memory_Registers.Data_Bank_inst.mem[1]);
    $display("  P11 = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[2]),
             dut.Memory_Registers.Data_Bank_inst.mem[2]);
    $display("  P12 = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[3]),
             dut.Memory_Registers.Data_Bank_inst.mem[3]);
    $display("  P21 = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[4]),
             dut.Memory_Registers.Data_Bank_inst.mem[4]);
    $display("  P22 = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[5]),
             dut.Memory_Registers.Data_Bank_inst.mem[5]);
    $display("\n--- Intermediate values ---");
    $display("  x1^- (DB[21]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[21]));
    $display("  x2^- (DB[22]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[22]));
    $display("  K1 (DB[23]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[23]));
    $display("  K2 (DB[24]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[24]));
    $display("  innov (DB[25]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[25]));
`else
    $display("  Post-synthesis mode: internal signals not accessible");
    $display("  DATA_OUT = 0x%06h (%.6f)", DATA_OUT, sm_to_real(DATA_OUT));
`endif

    // Expected results (manual calculation):
    // Time Update:
    //   x^- = Phi*x = [1 0.1; 0 1]*[0; 1] = [0.1; 1]
    //   P^- = Phi*P*Phi^T + Q = [1.02 0.1; 0.1 1.01]
    // Measurement Update:
    //   S = H*P^-*H^T + R = 1.02 + 0.1 = 1.12
    //   K = P^-*H^T / S = [1.02; 0.1] / 1.12 = [0.911; 0.089]
    //   innovation = y - H*x^- = 0.5 - 0.1 = 0.4
    //   x^+ = x^- + K*innovation = [0.1; 1] + [0.911; 0.089]*0.4
    //       = [0.1 + 0.364; 1 + 0.036] = [0.464; 1.036]
    //   P^+ = (I - K*H)*P^- (simplified)

    $display("\n================================================================");
    $display("Expected (manual calculation)");
    $display("================================================================");
    $display("  Time Update:");
    $display("    x^- = Phi*x = [0.1; 1.0]");
    $display("    P^- = Phi*P*Phi^T + Q = [1.02 0.1; 0.1 1.01]");
    $display("  Measurement Update:");
    $display("    S = H*P^-*H^T + R = 1.02 + 0.1 = 1.12");
    $display("    K = [0.911; 0.089]");
    $display("    innovation = y - H*x^- = 0.5 - 0.1 = 0.4");
    $display("    x^+ = [0.464; 1.036]");

    $display("\n================================================================");
    $display("2D Kalman Filter Test Complete");
    $display("================================================================\n");

    $finish;
  end

  // Timeout watchdog
  initial begin
    #200000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
