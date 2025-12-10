// -----------------------------------------------------------------------------
// sequencer_tb.v
// Testbench for Sequencer - PC + ROM + instruction decode (per paper Section 4)
// Tests: ROM programming, PC control (INC/WAIT/HALT), instruction field decode
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// Note: ROM programming via rom_we port works for RTL. For post-syn, the ROM
//       content must be pre-loaded or use a synthesis-friendly ROM init.
// -----------------------------------------------------------------------------
// Per paper instruction format:
//   "a4 a3 a2 a1 a0 b4 b3 b2 b1 b0 c1 c0 d1 d0 e f"
//   Field A [15:11] - Address A (5 bits)
//   Field B [10:6]  - Address B (5 bits)
//   Field C [5:4]   - PC control (00=INC, 01=WAIT, 10=HALT)
//   Field D [3:2]   - AU operation (00=ADD, 01=SUB, 10=MUL, 11=DIV)
//   Field E [1]     - AU start (1 bit)
//   Field F [0]     - Write enable (1 bit)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module sequencer_tb;

  reg         clk, rst_n, start, continue_i;
  reg         rom_we;
  reg  [7:0]  rom_waddr;
  reg  [15:0] rom_wdata;

  // Outputs (per paper's instruction format)
  wire [4:0]  ctl_a, ctl_b;   // 5-bit addresses
  wire [1:0]  ctl_c, ctl_d;   // 2-bit control fields
  wire        ctl_e;          // 1-bit AU start (Field E)
  wire        ctl_f;          // 1-bit write enable (Field F)
  wire        ready;
  wire [7:0]  pc_dbg;

  // Instantiate DUT
  sequencer DUT (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .continue_i (continue_i),
    .rom_we     (rom_we),
    .rom_waddr  (rom_waddr),
    .rom_wdata  (rom_wdata),
    .ctl_a      (ctl_a),
    .ctl_b      (ctl_b),
    .ctl_c      (ctl_c),
    .ctl_d      (ctl_d),
    .ctl_e      (ctl_e),
    .ctl_f      (ctl_f),
    .ready      (ready),
    .pc_dbg     (pc_dbg)
  );

  // Clock generation (100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // Helper: pack fields -> 16-bit instruction per paper format
  // {a[15:11], b[10:6], c[5:4], d[3:2], e[1], f[0]}
  function [15:0] INSTR;
    input [4:0] a, b;      // Address fields (5 bits each)
    input [1:0] c, d;      // Control fields (2 bits each)
    input       e, f;      // Single-bit fields
    begin
      INSTR = {a, b, c, d, e, f};
    end
  endfunction

  integer errors, checks;

  // Task: Write instruction to ROM
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

  // Task: Verify decoded fields match expected values
  task expect_fields;
    input [4:0] ea, eb;    // Expected addresses
    input [1:0] ec, ed;    // Expected ctl_c, ctl_d
    input       ee, ef;    // Expected ctl_e, ctl_f
    begin
      #1;
      checks = checks + 6;
      if (ctl_a !== ea) begin
        $display("ERR ctl_a: exp=%0d got=%0d (PC=%0d)", ea, ctl_a, pc_dbg);
        errors = errors + 1;
      end
      if (ctl_b !== eb) begin
        $display("ERR ctl_b: exp=%0d got=%0d (PC=%0d)", eb, ctl_b, pc_dbg);
        errors = errors + 1;
      end
      if (ctl_c !== ec) begin
        $display("ERR ctl_c: exp=%0d got=%0d (PC=%0d)", ec, ctl_c, pc_dbg);
        errors = errors + 1;
      end
      if (ctl_d !== ed) begin
        $display("ERR ctl_d: exp=%0d got=%0d (PC=%0d)", ed, ctl_d, pc_dbg);
        errors = errors + 1;
      end
      if (ctl_e !== ee) begin
        $display("ERR ctl_e: exp=%0d got=%0d (PC=%0d)", ee, ctl_e, pc_dbg);
        errors = errors + 1;
      end
      if (ctl_f !== ef) begin
        $display("ERR ctl_f: exp=%0d got=%0d (PC=%0d)", ef, ctl_f, pc_dbg);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    // Initialize signals
    rst_n      = 0;
    start      = 0;
    continue_i = 0;
    rom_we     = 0;
    rom_waddr  = 0;
    rom_wdata  = 0;
    errors     = 0;
    checks     = 0;

    $display("========================================");
    $display("Testing Sequencer (per paper Section 4)");
    $display("Instruction format: a4-a0 b4-b0 c1c0 d1d0 e f");
    $display("========================================");

    // Program a small test microprogram:
    // PC=0: Normal step (ctl_c=00), ADD op, AU start, write enable
    //       a=1, b=2, c=00(INC), d=00(ADD), e=1, f=1
    // PC=1: WAIT for continue (ctl_c=01), MUL op, AU start
    //       a=3, b=4, c=01(WAIT), d=10(MUL), e=1, f=0
    // PC=2: Normal step (ctl_c=00), SUB op
    //       a=5, b=6, c=00(INC), d=01(SUB), e=1, f=1
    // PC=3: HALT (ctl_c=10)
    //       a=7, b=8, c=10(HALT), d=11(DIV), e=0, f=0

    rom_wr(8'd0, INSTR(5'd1, 5'd2, 2'b00, 2'b00, 1'b1, 1'b1));  // ADD, INC
    rom_wr(8'd1, INSTR(5'd3, 5'd4, 2'b01, 2'b10, 1'b1, 1'b0));  // MUL, WAIT
    rom_wr(8'd2, INSTR(5'd5, 5'd6, 2'b00, 2'b01, 1'b1, 1'b1));  // SUB, INC
    rom_wr(8'd3, INSTR(5'd7, 5'd8, 2'b10, 2'b11, 1'b0, 1'b0));  // DIV, HALT

    // Release reset
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // Test 1: READY should be high while idle
    $display("\n--- Test 1: Check READY when idle ---");
    #1;
    checks = checks + 1;
    if (!ready) begin
      $display("ERR: ready should be 1 when idle");
      errors = errors + 1;
    end else begin
      $display("PASS: ready=1 when idle");
    end

    // Test 2: Start execution
    $display("\n--- Test 2: Start execution ---");
    start = 1;
    @(posedge clk);
    #1;
    start = 0;

    // PC=0: Should decode first instruction (INC mode)
    $display("\n--- PC=0: Normal step (INC) ---");
    expect_fields(5'd1, 5'd2, 2'b00, 2'b00, 1'b1, 1'b1);
    @(posedge clk);
    #1;
    checks = checks + 2;
    if (pc_dbg !== 8'd1) begin
      $display("ERR: PC step exp=1 got=%0d", pc_dbg);
      errors = errors + 1;
    end
    if (ready) begin
      $display("ERR: ready should be 0 while running");
      errors = errors + 1;
    end

    // PC=1: WAIT mode - should stall until continue_i=1
    $display("\n--- PC=1: WAIT mode (stall test) ---");
    expect_fields(5'd3, 5'd4, 2'b01, 2'b10, 1'b1, 1'b0);

    // Hold for a few cycles with continue_i=0 - PC should stay at 1
    repeat(3) @(posedge clk);
    #1;
    checks = checks + 1;
    if (pc_dbg !== 8'd1) begin
      $display("ERR: WAIT did not stall at PC=1, got PC=%0d", pc_dbg);
      errors = errors + 1;
    end else begin
      $display("PASS: PC stalled at 1 during WAIT");
    end

    // Release wait with continue_i pulse
    $display("\n--- Releasing WAIT with continue_i ---");
    continue_i = 1;
    @(posedge clk);
    #1;
    continue_i = 0;

    // PC should advance to 2
    $display("\n--- PC=2: Normal step after WAIT ---");
    expect_fields(5'd5, 5'd6, 2'b00, 2'b01, 1'b1, 1'b1);
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (pc_dbg !== 8'd3) begin
      $display("ERR: PC step to 3 failed, got PC=%0d", pc_dbg);
      errors = errors + 1;
    end

    // PC=3: HALT - should stop and set READY=1
    $display("\n--- PC=3: HALT ---");
    expect_fields(5'd7, 5'd8, 2'b10, 2'b11, 1'b0, 1'b0);
    @(posedge clk);  // Apply HALT this cycle
    #1;
    checks = checks + 2;
    if (!ready) begin
      $display("ERR: ready should be 1 after HALT");
      errors = errors + 1;
    end else begin
      $display("PASS: ready=1 after HALT");
    end
    if (pc_dbg !== 8'd3) begin
      $display("ERR: PC should stay at 3 after HALT, got %0d", pc_dbg);
      errors = errors + 1;
    end

    // Summary
    $display("\n========================================");
    if (errors == 0)
      $display("sequencer_tb: PASS (%0d checks)", checks);
    else
      $display("sequencer_tb: %0d ERRORS / %0d checks", errors, checks);
    $display("========================================");
    $finish;
  end

endmodule
