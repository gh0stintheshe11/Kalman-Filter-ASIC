// -----------------------------------------------------------------------------
// kf_top_tb.v
// Testbench for complete Kalman Filter ASIC top-level (per paper Figure 3)
// Tests the integrated system: Sequencer + Routers + Memory + AU
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_top_tb;

  parameter W = 24;
  parameter FRAC = 14;
  parameter NR = 32;
  parameter ADDRW = 5;

  // DUT signals (matching kf_top.v port names per paper)
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
  kf_top #(.W(W), .FRAC(FRAC), .NR(NR), .ADDRW(ADDRW)) DUT (
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

  // ========== Helper Functions ==========

  // Convert integer to sign-magnitude Q9.14 format
  function [W-1:0] to_fixed;
    input integer val;
    reg sign_bit;
    reg [W-2:0] magnitude;
    begin
      sign_bit = (val < 0);
      if (val < 0) val = -val;
      magnitude = val << FRAC;
      to_fixed = {sign_bit, magnitude};
    end
  endfunction

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

  // Convert sign-magnitude Q9.14 to real for display
  function real to_real;
    input [W-1:0] fixed_val;
    integer signed_mag;
    integer signed_val;
    begin
      signed_mag = fixed_val[W-2:0];
      signed_val = (fixed_val[W-1]) ? -signed_mag : signed_mag;
      to_real = signed_val / (16384.0); // 2^14
    end
  endfunction

  // ROM write task - programs ROM via ports
  task rom_write;
    input [7:0]  addr;
    input [15:0] data;
    begin
      @(negedge clk);
      rom_waddr = addr;
      rom_wdata = data;
      rom_we = 1'b1;
      @(posedge clk);
      #1;
      rom_we = 1'b0;
    end
  endtask

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

  // ========== Test Sequence ==========

  integer errors, checks;
  reg [W-1:0] val_a, val_b, expected;

  initial begin
    $display("========================================");
    $display("Kalman Filter ASIC Top-Level Test");
    $display("Per paper Figure 3 architecture");
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
    errors = 0;
    checks = 0;

    // Test values: 3.0 and 2.5 in Q9.14 format
    val_a = to_fixed(3);                      // 3.0 = 0x00C000
    val_b = to_fixed(2) + (1 << (FRAC-1));    // 2.5 = 0x00A000

    $display("\nTest operands:");
    $display("  Value A (3.0) = 0x%06h (%.4f)", val_a, to_real(val_a));
    $display("  Value B (2.5) = 0x%06h (%.4f)", val_b, to_real(val_b));

    // Reset sequence
    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // ========== PROGRAM ROM ==========
    // Simple test program to verify basic operation:
    // PC=0: NOP (just increment PC) - uses field F=0 (no write)
    // PC=1: ADD DB[0]+DB[1], start AU, write result - c=00(INC), d=00(ADD), e=1, f=1
    // PC=2: WAIT for AU done - c=01(WAIT)
    // PC=3: Write result to DB[2] - c=00(INC), f=1
    // PC=4: HALT - c=10(HALT)

    // For now, let's just test that the sequencer runs
    $display("\n--- Programming ROM ---");

    // PC=0: Store DATA_IN to DB[0] (write enable via external interface not instruction)
    //       a=0 (write addr), b=0, c=00(INC), d=00(ADD), e=0(no AU), f=1(write)
    rom_write(8'd0, INSTR(5'd0, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

    // PC=1: Store DATA_IN to DB[1]
    //       a=1 (write addr), b=0, c=00(INC), d=00(ADD), e=0(no AU), f=1(write)
    rom_write(8'd1, INSTR(5'd1, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

    // PC=2: ADD DB[0] + DB[1], start AU
    //       a=0 (operand A addr), b=1 (operand B addr), c=00(INC), d=00(ADD), e=1(AU start), f=0
    rom_write(8'd2, INSTR(5'd0, 5'd1, 2'b00, 2'b00, 1'b1, 1'b0));

    // PC=3: WAIT for AU done
    //       c=01(WAIT) - stays here until continue_i (au_done) is high
    rom_write(8'd3, INSTR(5'd0, 5'd0, 2'b01, 2'b00, 1'b0, 1'b0));

    // PC=4: Write AU result to DB[2]
    //       a=2 (write addr), f=1(write)
    rom_write(8'd4, INSTR(5'd2, 5'd0, 2'b00, 2'b00, 1'b0, 1'b1));

    // PC=5: HALT
    //       c=10(HALT)
    rom_write(8'd5, INSTR(5'd0, 5'd0, 2'b10, 2'b00, 1'b0, 1'b0));

    $display("ROM programmed with 6 instructions");

    // ========== Test 1: Check initial READY state ==========
    $display("\n--- Test 1: Check initial READY state ---");
    checks = checks + 1;
    if (READY !== 1'b1) begin
      $display("ERROR: System not ready after reset");
      errors = errors + 1;
    end else begin
      $display("PASS: System READY=1 after reset");
    end

    // ========== Test 2: Load operands and run program ==========
    $display("\n--- Test 2: Load operands and execute program ---");

    // Provide first operand on DATA_IN
    DATA_IN = val_a;
    $display("DATA_IN = 0x%06h (3.0)", DATA_IN);

    // Start execution
    START = 1;
    @(posedge clk);
    #1;
    START = 0;
    $display("START asserted - execution begins");

    // Wait one cycle, then provide second operand
    @(posedge clk);
    DATA_IN = val_b;
    $display("DATA_IN = 0x%06h (2.5)", DATA_IN);

    // Clear DATA_IN
    @(posedge clk);
    DATA_IN = 0;

    // Monitor execution
    $display("\nMonitoring execution:");
    $display("Cycle | PC | ctl_c | ctl_d | ctl_e | ctl_f | READY | DATA_OUT");
    $display("------|----| ------|-------|-------|-------|-------|----------");

    begin : monitor_loop
      integer i;
      for (i = 0; i < 30; i = i + 1) begin
        @(posedge clk);
        #1;
        $display("%5d | %2d |   %2b  |   %2b  |   %b   |   %b   |   %b   | %06h",
                 i,
                 DUT.Sequencer.pc,
                 DUT.ctl_c,
                 DUT.ctl_d,
                 DUT.ctl_e,
                 DUT.ctl_f,
                 READY,
                 DATA_OUT);

        // Check if we hit HALT
        if (READY == 1'b1 && i > 2) begin
          $display("\nHALT detected - program completed");
          disable monitor_loop;
        end
      end
    end

    // ========== Test 3: Verify results ==========
    $display("\n--- Test 3: Verify computation results ---");

    // Read Data Bank contents
    $display("\nData Bank contents:");
    $display("  DB[0] = 0x%06h (%.4f) - expected 3.0",
             DUT.Memory_Registers.Data_Bank_inst.mem[0],
             to_real(DUT.Memory_Registers.Data_Bank_inst.mem[0]));
    $display("  DB[1] = 0x%06h (%.4f) - expected 2.5",
             DUT.Memory_Registers.Data_Bank_inst.mem[1],
             to_real(DUT.Memory_Registers.Data_Bank_inst.mem[1]));
    $display("  DB[2] = 0x%06h (%.4f) - expected 5.5 (ADD result)",
             DUT.Memory_Registers.Data_Bank_inst.mem[2],
             to_real(DUT.Memory_Registers.Data_Bank_inst.mem[2]));

    // Expected ADD result: 3.0 + 2.5 = 5.5
    expected = to_fixed(5) + (1 << (FRAC-1));  // 5.5 in Q9.14

    checks = checks + 1;
    if (DUT.Memory_Registers.Data_Bank_inst.mem[2] == expected) begin
      $display("\nPASS: ADD result correct (3.0 + 2.5 = 5.5)");
    end else begin
      $display("\nERROR: ADD result mismatch");
      $display("  Expected: 0x%06h (%.4f)", expected, to_real(expected));
      $display("  Got:      0x%06h (%.4f)",
               DUT.Memory_Registers.Data_Bank_inst.mem[2],
               to_real(DUT.Memory_Registers.Data_Bank_inst.mem[2]));
      errors = errors + 1;
    end

    // ========== Test 4: Verify system returned to READY ==========
    $display("\n--- Test 4: Verify system returned to READY ---");
    checks = checks + 1;
    if (READY == 1'b1) begin
      $display("PASS: System READY=1 after HALT");
    end else begin
      $display("ERROR: System not in READY state after HALT");
      errors = errors + 1;
    end

    // Summary
    #50;
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    if (errors == 0) begin
      $display("kf_top_tb: PASS (%0d checks)", checks);
    end else begin
      $display("kf_top_tb: %0d ERRORS / %0d checks", errors, checks);
    end
    $display("========================================\n");

    $finish;
  end

  // Timeout watchdog
  initial begin
    #20000;
    $display("\nERROR: Simulation timeout!");
    $finish;
  end

endmodule
