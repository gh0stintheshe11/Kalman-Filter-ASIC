// -----------------------------------------------------------------------------
// mem_reg_tb.v
// Testbench for Memory Registers Block (per paper Figure 3)
// Tests: Data Bank read/write, RQ/RD accumulators, write-through forwarding
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module mem_reg_tb;

  // Parameters for testbench (not passed to DUT for post-syn compatibility)
  parameter W     = 24;
  parameter NR    = 32;       // Per paper: 32 registers for 2-state KF
  parameter ADDRW = 5;        // Per paper: 5-bit address for 32 registers

  // DUT I/O (matching mem_reg.v port names per paper Figure 3)
  reg                 clk;

  // Data Bank interface (per paper naming)
  reg                 write;        // Write enable (from Router A)
  reg  [ADDRW-1:0]    dira;         // Address A (read/write)
  reg  [ADDRW-1:0]    dirb;         // Address B (read only)
  reg  [W-1:0]        data;         // Write data (from Router A)
  wire [W-1:0]        A;            // Read data port A (to Router B)
  wire [W-1:0]        B;            // Read data port B (to Router B)

  // RQ / RD interface
  reg                 rq_we, rd_we;
  reg  [W-1:0]        rq_d, rd_d;
  wire [W-1:0]        RQ, RD;       // Per paper naming

  // Temp address regs (declare at module scope)
  reg  [ADDRW-1:0]    ai, bi;

  // Loop counters / bookkeeping
  integer i, errors, checks;

  // DUT instantiation - no parameter override for post-syn compatibility
  mem_reg DUT (
    .clk    (clk),
    // Data Bank interface
    .write  (write),
    .dira   (dira),
    .dirb   (dirb),
    .data   (data),
    .A      (A),
    .B      (B),
    // RQ/RD interface
    .rq_we  (rq_we),
    .rq_d   (rq_d),
    .RQ     (RQ),
    .rd_we  (rd_we),
    .rd_d   (rd_d),
    .RD     (RD)
  );

  // Clock generation (100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // Pattern helper - creates unique pattern for each address
  function [W-1:0] patt;
    input integer i;
    begin
      patt = {8'hA5, i[7:0], 8'h5A};
    end
  endfunction

  // Task: Write to Data Bank
  task db_write;
    input [ADDRW-1:0] addr;
    input [W-1:0]     wdata;
    begin
      @(negedge clk);
      dira  <= addr;
      data  <= wdata;
      write <= 1'b1;
      @(posedge clk);   // write occurs on this edge
      @(negedge clk);
      write <= 1'b0;
    end
  endtask

  // Task: Read from Data Bank and check both ports
  task db_read_check;
    input [ADDRW-1:0] addr_a;
    input [ADDRW-1:0] addr_b;
    input [W-1:0]     exp_a;
    input [W-1:0]     exp_b;
    begin
      dira <= addr_a;
      dirb <= addr_b;
      #1;
      checks = checks + 2;
      if (A !== exp_a) begin
        $display("ERR DB A: addr=%0d exp=%h got=%h", addr_a, exp_a, A);
        errors = errors + 1;
      end
      if (B !== exp_b) begin
        $display("ERR DB B: addr=%0d exp=%h got=%h", addr_b, exp_b, B);
        errors = errors + 1;
      end
    end
  endtask

  // Task: Write to RQ and verify
  task rq_write_check;
    input [W-1:0] wdata;
    begin
      rq_d  <= wdata;
      rq_we <= 1'b1;
      @(posedge clk);
      rq_we <= 1'b0;
      #1;
      checks = checks + 1;
      if (RQ !== wdata) begin
        $display("ERR RQ: exp=%h got=%h", wdata, RQ);
        errors = errors + 1;
      end
    end
  endtask

  // Task: Write to RD and verify
  task rd_write_check;
    input [W-1:0] wdata;
    begin
      rd_d  <= wdata;
      rd_we <= 1'b1;
      @(posedge clk);
      rd_we <= 1'b0;
      #1;
      checks = checks + 1;
      if (RD !== wdata) begin
        $display("ERR RD: exp=%h got=%h", wdata, RD);
        errors = errors + 1;
      end
    end
  endtask

  // Main test stimulus
  initial begin
    // Initialize all signals
    write = 0;
    dira  = 0;
    dirb  = 0;
    data  = 0;
    rq_we = 0;
    rq_d  = 0;
    rd_we = 0;
    rd_d  = 0;
    errors = 0;
    checks = 0;

    $display("========================================");
    $display("Testing Memory Registers (per paper Figure 3)");
    $display("Data Bank: %0d x %0d-bit registers", NR, W);
    $display("========================================");

    // 1) Write patterns into all Data Bank locations
    $display("\n--- Writing patterns to all %0d registers ---", NR);
    for (i = 0; i < NR; i = i + 1) begin
      ai = i[ADDRW-1:0];
      db_write(ai, patt(i));
    end

    // 2) Read them back via both ports A and B
    $display("\n--- Reading back via both ports ---");
    for (i = 0; i < NR; i = i + 1) begin
      ai = i[ADDRW-1:0];
      bi = (NR - 1 - i);
      db_read_check(ai, bi[ADDRW-1:0], patt(i), patt(NR - 1 - i));
    end

    // 3) Test read-during-write hazard (write-through forwarding on Port B)
    // Note: Port A does NOT forward (to avoid read-modify-write hazards)
    //       Port B DOES forward when FORWARD=1 and dirb==dira
    $display("\n--- Testing write-through forwarding (Port B only) ---");
    @(negedge clk);
      dira  <= 5'd3;            // Write to address 3
      data  <= 24'hDE_ADBE;
      write <= 1'b1;
      dirb  <= 5'd3;            // Read from same address (3) on port B
    #1;
    checks = checks + 2;
    // Port A: NO forwarding - reads old value from mem[3] = patt(3)
    if (A !== patt(3)) begin
      $display("ERR Port A (no fwd): expected %h got %h", patt(3), A);
      errors = errors + 1;
    end
    // Port B: WITH forwarding - should get new write data immediately
    if (B !== 24'hDE_ADBE) begin
      $display("ERR Port B (fwd): expected %h got %h", 24'hDE_ADBE, B);
      errors = errors + 1;
    end
    @(posedge clk);
    @(negedge clk);
    write <= 1'b0;

    // 4) Test RQ accumulator (per paper: "registers RQ and RD are used as accumulators")
    $display("\n--- Testing RQ accumulator ---");
    rq_write_check(24'h00_1111);
    rq_write_check(24'hAA_BBCC);

    // 5) Test RD accumulator
    $display("\n--- Testing RD accumulator ---");
    rd_write_check(24'h22_3333);
    rd_write_check(24'hCC_DDEE);

    // 6) Ensure RQ/RD hold their values when WE=0
    $display("\n--- Testing RQ/RD hold when WE=0 ---");
    rq_d <= 24'h99_9999;
    rd_d <= 24'h88_8888;
    @(posedge clk);
    #1;
    checks = checks + 2;
    if (RQ !== 24'hAA_BBCC) begin
      $display("ERR RQ hold: exp=%h got=%h", 24'hAA_BBCC, RQ);
      errors = errors + 1;
    end
    if (RD !== 24'hCC_DDEE) begin
      $display("ERR RD hold: exp=%h got=%h", 24'hCC_DDEE, RD);
      errors = errors + 1;
    end

    // Summary
    $display("\n========================================");
    if (errors == 0)
      $display("mem_reg_tb: PASS (%0d checks)", checks);
    else
      $display("mem_reg_tb: %0d ERRORS / %0d checks", errors, checks);
    $display("========================================");
    $finish;
  end

endmodule
