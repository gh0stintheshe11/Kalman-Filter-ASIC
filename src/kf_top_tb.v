// -----------------------------------------------------------------------------
// kf_top_tb.v
// Unified Kalman Filter ASIC Testbench
// -----------------------------------------------------------------------------
// Supports both 1D and 2D Kalman Filter tests via ROM_FILE parameter.
// Uses $readmemh to load instruction ROM from .mem files.
//
// Usage:
//   For 1D KF test: ncverilog +define+TEST_1D ...
//   For 2D KF test: ncverilog ... (default)
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// For post-syn: define SIM_POST_SYN to disable internal signal access
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_top_tb();

  // =========================================================================
  // Parameters - Change ROM_FILE to select test case
  // =========================================================================
`ifdef TEST_1D
  parameter ROM_FILE = "kf_1d.mem";
  parameter TEST_MODE = "1D";
`else
  parameter ROM_FILE = "kf_2d.mem";
  parameter TEST_MODE = "2D";
`endif

  parameter W = 24;
  parameter FRAC = 14;
  parameter NR = 32;
  parameter ADDRW = 5;

  // =========================================================================
  // DUT Signals
  // =========================================================================
  reg              clk;
  reg              rst_n;
  reg              START;
  reg  [W-1:0]     DATA_IN;
  reg  [ADDRW-1:0] DIR;
  reg              WRITE;
  wire             READY;
  wire [W-1:0]     DATA_OUT;

  // ROM programming signals (kept for backward compatibility)
  reg              rom_we;
  reg  [7:0]       rom_waddr;
  reg  [15:0]      rom_wdata;

  // Loop control
  reg  [7:0]       loop_addr;

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  kf_top #(
    .W(W),
    .FRAC(FRAC),
    .NR(NR),
    .ADDRW(ADDRW),
    .ROM_FILE(ROM_FILE)
  ) dut (
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
    .rom_wdata  (rom_wdata),
    .loop_addr  (loop_addr)
  );

  // =========================================================================
  // Clock Generation (100 MHz)
  // =========================================================================
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
    begin
      sign = (x < 0.0);
      mag_int = (sign ? -x : x) * (1 << FRAC);
      real_to_sm = {sign, mag_int[W-2:0]};
    end
  endfunction

  // Convert sign-magnitude to real
  function real sm_to_real;
    input [W-1:0] sm;
    real val;
    begin
      val = $itor(sm[W-2:0]) / (1 << FRAC);
      sm_to_real = sm[W-1] ? -val : val;
    end
  endfunction

  // =========================================================================
  // Test Sequences
  // =========================================================================

  // 1D Kalman Filter Test
  task test_1d_kf;
    begin
      $display("\n========================================");
      $display("1D Kalman Filter Test");
      $display("ROM File: %s", ROM_FILE);
      $display("========================================");
      $display("Parameters: Phi=1.0, Q=0.01, R=0.1, x0=0, P0=1.0, y=2.5");
      $display("Expected result: x_hat ~= 2.275");

      // Pre-load first data value BEFORE START
      DATA_IN = real_to_sm(1.0);  // Phi = 1.0

      // Start execution
      START = 1;
      @(posedge clk);
      START = 0;

      // Load parameters (must be present BEFORE clock edge when instruction writes)
      DATA_IN = real_to_sm(0.01);  @(posedge clk);  // Q = 0.01 -> DB[3]
      DATA_IN = real_to_sm(0.1);   @(posedge clk);  // R = 0.1 -> DB[4]
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // x = 0.0 -> DB[0]
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // P = 1.0 -> DB[1]
      DATA_IN = real_to_sm(2.5);   @(posedge clk);  // y = 2.5 -> DB[5]
      DATA_IN = 0;

      // Wait for completion
      wait_for_ready(200);

      // Display results
      #20;
      $display("\n--- Results ---");
`ifndef SIM_POST_SYN
      $display("  x_hat (DB[0]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]));
      $display("  K     (DB[6]) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[6]));
`else
      $display("  Post-synthesis mode: internal signals not accessible");
      $display("  DATA_OUT = %.6f", sm_to_real(DATA_OUT));
`endif
      $display("  Expected: x_hat = 2.275 (K = 0.9099)");
    end
  endtask

  // 2D Kalman Filter Test - Continuous Operation
  task test_2d_kf;
    integer iter;
    integer cycle_count;
    real measurements [0:4];  // Test with 5 measurements
    begin
      $display("\n========================================");
      $display("2D Kalman Filter Test - CONTINUOUS MODE");
      $display("ROM File: %s", ROM_FILE);
      $display("========================================");
      $display("Inertial Navigation: State=[position; velocity]");
      $display("Phi=[1 0.1; 0 1], H=[1 0], Q=0.01*I, R=0.1");
      $display("Initial: x=[0; 1], P=I");
      $display("Testing 5 iterations with different measurements");

      // Define test measurements (simulating a moving target)
      measurements[0] = 0.5;
      measurements[1] = 0.7;
      measurements[2] = 0.9;
      measurements[3] = 1.2;
      measurements[4] = 1.5;

      // Set loop_addr to PC=20 (reload y from DATA_IN, then run KF iteration)
      // PC=20 is "Load -> DB[20] (y)" instruction
      loop_addr = 8'd20;

      // Pre-load first data value
      DATA_IN = real_to_sm(0.0);  // x1 = 0.0

      START = 1;
      @(posedge clk);
      START = 0;

      // Load all 20 remaining parameters (21 total)
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // x2 = 1.0
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // p11 = 1.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // p12 = 0.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // p21 = 0.0
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // p22 = 1.0
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // phi11 = 1.0
      DATA_IN = real_to_sm(0.1);   @(posedge clk);  // phi12 = 0.1
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // phi21 = 0.0
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // phi22 = 1.0
      DATA_IN = real_to_sm(0.01);  @(posedge clk);  // q11 = 0.01
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // q12 = 0.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // q21 = 0.0
      DATA_IN = real_to_sm(0.01);  @(posedge clk);  // q22 = 0.01
      DATA_IN = real_to_sm(1.0);   @(posedge clk);  // h1 = 1.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // h2 = 0.0
      DATA_IN = real_to_sm(0.1);   @(posedge clk);  // R = 0.1
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // g1 = 0.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // g2 = 0.0
      DATA_IN = real_to_sm(0.0);   @(posedge clk);  // u = 0.0
      DATA_IN = real_to_sm(measurements[0]);  @(posedge clk);  // y = first measurement
      DATA_IN = 0;

      $display("\n--- Running %0d KF iterations ---", 5);

      // Run multiple iterations
      for (iter = 0; iter < 5; iter = iter + 1) begin
        $display("\n=== Iteration %0d (y = %.2f) ===", iter + 1, measurements[iter]);

        // Wait for this iteration to complete (PC reaches LOOP at 160)
        cycle_count = 0;
        begin : wait_loop
          forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
`ifndef SIM_POST_SYN
            // Detect when PC reaches LOOP instruction (PC=160 for kf_2d.mem)
            // At this point, update DATA_IN for next iteration BEFORE the loop executes
            if (dut.Sequencer.pc == 8'd160 && cycle_count > 20) begin
              // Prepare next measurement BEFORE the LOOP executes
              if (iter < 4) begin
                DATA_IN = real_to_sm(measurements[iter + 1]);
              end
              // Wait one more cycle for the LOOP to execute and PC to jump to 20
              @(posedge clk);
              cycle_count = cycle_count + 1;
              disable wait_loop;
            end
`endif
            // Timeout per iteration
            if (cycle_count > 300) begin
              $display("  WARNING: Iteration timeout at PC=%0d", dut.Sequencer.pc);
              disable wait_loop;
            end
          end
        end

        // Display results for this iteration
`ifndef SIM_POST_SYN
        $display("  Cycles: %0d", cycle_count);
        $display("  x1 (position) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]));
        $display("  x2 (velocity) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[1]));
        $display("  y  (loaded)   = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[20]));
        $display("  P11 = %.6f, P12 = %.6f",
                 sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[2]),
                 sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[3]));
        $display("  P21 = %.6f, P22 = %.6f",
                 sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[4]),
                 sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[5]));
`endif
      end

      // Final results
      $display("\n--- Final Results after 5 iterations ---");
`ifndef SIM_POST_SYN
      $display("  x1 (position) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[0]));
      $display("  x2 (velocity) = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[1]));
      $display("  P11 = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[2]));
      $display("  P12 = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[3]));
      $display("  P21 = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[4]));
      $display("  P22 = %.6f", sm_to_real(dut.Memory_Registers.Data_Bank_inst.mem[5]));
`else
      $display("  Post-synthesis mode: internal signals not accessible");
      $display("  DATA_OUT = %.6f", sm_to_real(DATA_OUT));
`endif
    end
  endtask

  // Wait for READY with timeout
  task wait_for_ready;
    input integer max_cycles;
    integer i;
    reg done;
    begin
      $display("\n--- Executing Kalman Filter ---");
      done = 0;
      for (i = 0; i < max_cycles && !done; i = i + 1) begin
        @(posedge clk);
        #1;
`ifndef SIM_POST_SYN
        // Debug output (first 30 cycles and every 50 after)
        if (i < 30 || i % 50 == 0) begin
          $display("  Cycle %3d: PC=%3d, READY=%b, e=%b, f=%b",
                   i, dut.Sequencer.pc, READY, dut.ctl_e, dut.ctl_f);
        end
`else
        if (i % 50 == 0) begin
          $display("  Cycle %3d: READY=%b", i, READY);
        end
`endif
        if (READY == 1'b1 && i > 10) begin
          $display("  KF computation completed at cycle %d", i);
          done = 1;
        end
      end
      if (!done) begin
        $display("  WARNING: Timeout after %d cycles", max_cycles);
      end
    end
  endtask

  // =========================================================================
  // Main Test
  // =========================================================================
  initial begin
    $display("================================================================");
    $display("Kalman Filter ASIC Unified Testbench");
    $display("Test Mode: %s", TEST_MODE);
    $display("ROM File: %s", ROM_FILE);
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
    loop_addr = 8'd0;

    // Reset sequence
    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Run appropriate test based on ROM file
`ifdef TEST_1D
    test_1d_kf;
`else
    test_2d_kf;
`endif

    $display("\n================================================================");
    $display("Kalman Filter Test Complete");
    $display("================================================================\n");

    $finish;
  end

  // =========================================================================
  // Timeout Watchdog
  // =========================================================================
  initial begin
    #200000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
