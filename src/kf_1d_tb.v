// -----------------------------------------------------------------------------
// kf_1d_tb.v
// Simple 1D Kalman Filter Algorithm Test (per paper Section 3)
//
// 1D KF equations (scalar):
//   Time Update:    x⁻ = Φ·x,  P⁻ = Φ·P·Φ + Q
//   Measurement:    K = P⁻/(P⁻+R)
//                   x̂ = x⁻ + K·(y-x⁻)
//                   P = (1-K)·P⁻
//
// Memory Layout:
//   DB[0] = x   (state estimate)
//   DB[1] = P   (error covariance)
//   DB[2] = Φ   (state transition, constant = 1.0)
//   DB[3] = Q   (process noise, constant = 0.01)
//   DB[4] = R   (measurement noise, constant = 0.1)
//   DB[5] = y   (measurement, updated each iteration)
//   DB[6] = temp for calculations
//   DB[7] = temp for calculations
//
// This test will:
// 1. Initialize constants (Φ=1.0, Q=0.01, R=0.1)
// 2. Initialize x=0, P=1.0
// 3. Provide measurement y
// 4. Execute one KF iteration
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_1d_tb();
  parameter W = 24;
  parameter FRAC = 14;
  parameter NR = 32;
  parameter ADDRW = 5;

  // DUT signals (matching kf_top.v port names per paper Figure 3)
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

  // Instantiate DUT with paper's port names
  kf_top #(.W(W), .FRAC(FRAC), .NR(NR), .ADDRW(ADDRW)) dut (
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

  // Helper function: convert real to sign-magnitude S9.14
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

  // Helper function: convert sign-magnitude to real
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

  // Helper: pack fields -> 16-bit instruction per paper format
  // {a[15:11], b[10:6], c[5:4], d[3:2], e[1], f[0]}
  function [15:0] INSTR;
    input [4:0] a, b;      // Address fields (5 bits each)
    input [1:0] c, d;      // Control fields (2 bits each)
    input       e, f;      // Single-bit fields (AU start, write enable)
    begin
      INSTR = {a, b, c, d, e, f};
    end
  endfunction

  // ROM write task
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

  // ROM programming task
  task program_rom;
    begin
      $display("[ROM] Programming 1D Kalman Filter...");

      // ==== INITIALIZATION PHASE ====
      // Load constants and initial values via DATA_IN

      // PC=0: Load Φ=1.0 to DB[2] (Field A=2, F=1 for write)
      rom_wr(8'd0, INSTR(5'd2, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=1: Load Q=0.01 to DB[3]
      rom_wr(8'd1, INSTR(5'd3, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=2: Load R=0.1 to DB[4]
      rom_wr(8'd2, INSTR(5'd4, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=3: Load x=0 to DB[0]
      rom_wr(8'd3, INSTR(5'd0, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=4: Load P=1.0 to DB[1]
      rom_wr(8'd4, INSTR(5'd1, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=5: Load measurement y to DB[5]
      rom_wr(8'd5, INSTR(5'd5, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // ==== KALMAN FILTER ALGORITHM ====
      // Time Update: P⁻ = P + Q (since Φ=1)

      // PC=6: ADD DB[1] + DB[3] (P + Q), start AU
      // Field A=1 (addr for P), Field B=3 (addr for Q), d=00(ADD), e=1(start)
      rom_wr(8'd6, INSTR(5'd1, 5'd3, 2'b00, 2'b00, 1'b1, 1'b0));

      // PC=7: WAIT for AU done
      rom_wr(8'd7, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=8: Write P⁻ to DB[6] (temp)
      rom_wr(8'd8, INSTR(5'd6, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // Measurement Update: K = P⁻/(P⁻+R)
      // First compute P⁻+R

      // PC=9: ADD DB[6] + DB[4] (P⁻ + R), start AU
      rom_wr(8'd9, INSTR(5'd6, 5'd4, 2'b00, 2'b00, 1'b1, 1'b0));

      // PC=10: WAIT
      rom_wr(8'd10, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=11: Write P⁻+R to DB[7] (temp)
      rom_wr(8'd11, INSTR(5'd7, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=12: DIV DB[6] / DB[7] (K = P⁻/(P⁻+R)), start AU
      // d=11(DIV)
      rom_wr(8'd12, INSTR(5'd6, 5'd7, 2'b00, 2'b11, 1'b1, 1'b0));

      // PC=13: WAIT for DIV (24 cycles per paper)
      rom_wr(8'd13, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=14: Write K to DB[6] (reuse temp)
      rom_wr(8'd14, INSTR(5'd6, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // Innovation: (y - x) since x⁻=x for Φ=1

      // PC=15: SUB DB[5] - DB[0] (y - x), start AU
      // d=01(SUB)
      rom_wr(8'd15, INSTR(5'd5, 5'd0, 2'b00, 2'b01, 1'b1, 1'b0));

      // PC=16: WAIT
      rom_wr(8'd16, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=17: Write innovation to DB[7]
      rom_wr(8'd17, INSTR(5'd7, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // x̂ = x + K·(y-x)
      // First: K·(y-x) = DB[6]·DB[7]

      // PC=18: MUL DB[6] × DB[7], start AU
      // d=10(MUL)
      rom_wr(8'd18, INSTR(5'd6, 5'd7, 2'b00, 2'b10, 1'b1, 1'b0));

      // PC=19: WAIT
      rom_wr(8'd19, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=20: Write K·innovation to DB[7]
      rom_wr(8'd20, INSTR(5'd7, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=21: ADD DB[0] + DB[7] (x + K·innovation), start AU
      rom_wr(8'd21, INSTR(5'd0, 5'd7, 2'b00, 2'b00, 1'b1, 1'b0));

      // PC=22: WAIT
      rom_wr(8'd22, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

      // PC=23: Write x̂ to DB[0] (update state)
      rom_wr(8'd23, INSTR(5'd0, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

      // PC=24: HALT
      rom_wr(8'd24, INSTR(5'd0, 5'd0, 2'b10, 2'b00, 1'b0, 1'b0));

      $display("[ROM] Programmed 25 instructions for 1D Kalman Filter");
    end
  endtask

  // Main test
  initial begin
    $display("========================================");
    $display("1D Kalman Filter Algorithm Test");
    $display("Per paper Section 3: KF equations");
    $display("========================================");

    // Initialize
    rst_n = 0;
    START = 0;
    DATA_IN = 0;
    DIR = 0;
    WRITE = 0;
    rom_we = 0;
    rom_waddr = 0;
    rom_wdata = 0;

    // Reset
    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Program ROM
    program_rom();

    // Load constants via DATA_IN (timing synchronized with instruction execution)
    $display("\n--- Loading KF parameters ---");

    // Φ = 1.0
    DATA_IN = real_to_sm(1.0);
    $display("  Φ = 1.0 (0x%06h)", DATA_IN);

    // Start execution
    START = 1;
    @(posedge clk);
    #1;
    START = 0;

    // Q = 0.01
    @(posedge clk);
    DATA_IN = real_to_sm(0.01);
    $display("  Q = 0.01 (0x%06h)", DATA_IN);

    // R = 0.1
    @(posedge clk);
    DATA_IN = real_to_sm(0.1);
    $display("  R = 0.1 (0x%06h)", DATA_IN);

    // x = 0.0
    @(posedge clk);
    DATA_IN = real_to_sm(0.0);
    $display("  x₀ = 0.0 (0x%06h)", DATA_IN);

    // P = 1.0
    @(posedge clk);
    DATA_IN = real_to_sm(1.0);
    $display("  P₀ = 1.0 (0x%06h)", DATA_IN);

    // y = 2.5 (measurement)
    @(posedge clk);
    DATA_IN = real_to_sm(2.5);
    $display("  y = 2.5 (0x%06h)", DATA_IN);

    // Clear DATA_IN
    @(posedge clk);
    DATA_IN = 0;

    // Wait for completion
    $display("\n--- Executing Kalman Filter ---");
    $display("Waiting for computation to complete...");

    // Monitor execution with timeout
    begin : wait_loop
      integer i;
      for (i = 0; i < 200; i = i + 1) begin
        @(posedge clk);
        #1;
        if (i % 10 == 0) begin
          $display("  Cycle %3d: PC=%2d, READY=%b", i, dut.Sequencer.pc, READY);
        end
        if (READY == 1'b1 && i > 10) begin
          $display("  KF computation completed at cycle %d", i);
          disable wait_loop;
        end
      end
      $display("  WARNING: Reached max cycles");
    end

    // Display results
    #20;
    $display("\n========================================");
    $display("Results");
    $display("========================================");
    $display("  x̂  (DB[0]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]),
             dut.Memory_Registers.Data_Bank_inst.mem[0]);
    $display("  P  (DB[1]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[1]),
             dut.Memory_Registers.Data_Bank_inst.mem[1]);
    $display("  Φ  (DB[2]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[2]),
             dut.Memory_Registers.Data_Bank_inst.mem[2]);
    $display("  Q  (DB[3]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[3]),
             dut.Memory_Registers.Data_Bank_inst.mem[3]);
    $display("  R  (DB[4]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[4]),
             dut.Memory_Registers.Data_Bank_inst.mem[4]);
    $display("  y  (DB[5]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[5]),
             dut.Memory_Registers.Data_Bank_inst.mem[5]);
    $display("  P⁻ (DB[6]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[6]),
             dut.Memory_Registers.Data_Bank_inst.mem[6]);
    $display("  tmp(DB[7]) = %.6f (0x%06h)",
             sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[7]),
             dut.Memory_Registers.Data_Bank_inst.mem[7]);

    // Expected result for first iteration:
    // x⁻ = 0, P⁻ = 1.01
    // K = 1.01/(1.01+0.1) = 1.01/1.11 ≈ 0.9099
    // x̂ = 0 + 0.9099×(2.5-0) ≈ 2.275
    $display("\n========================================");
    $display("Expected (manual calculation)");
    $display("========================================");
    $display("  P⁻ = P+Q = 1.0+0.01 = 1.01");
    $display("  K = P⁻/(P⁻+R) = 1.01/1.11 ≈ 0.9099");
    $display("  x̂ = x + K(y-x) = 0 + 0.9099×2.5 ≈ 2.275");

    $display("\n========================================");
    $display("1D Kalman Filter Test Complete");
    $display("========================================\n");
    $finish;
  end

  // Timeout watchdog
  initial begin
    #100000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
