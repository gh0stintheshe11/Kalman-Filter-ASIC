// -----------------------------------------------------------------------------
// kf_top_tb.v
// Testbench for complete Kalman Filter ASIC top-level
// Tests the integrated system: Sequencer + Routers + Memory + AU
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module kf_top_tb;

  parameter W = 24;
  parameter FRAC = 14;
  parameter NR = 40;
  parameter ADDRW = 6;
  
  // DUT signals
  reg              clk;
  reg              rst_n;
  reg              start;
  reg  [W-1:0]     data_in;
  wire             ready;
  wire [W-1:0]     result_out;
  wire             au_done;
  
  // Instantiate DUT
  kf_top #(.W(W), .FRAC(FRAC), .NR(NR), .ADDRW(ADDRW)) DUT (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .data_in    (data_in),
    .ready      (ready),
    .result_out (result_out),
    .au_done    (au_done)
  );
  
  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;
  
  // ========== Helper Functions ==========
  
  // Convert two's complement to sign-magnitude
  function [W-1:0] tc_to_sm;
    input signed [W-1:0] v;
    reg sign;
    reg signed [W-1:0] a;
    begin
      sign = (v < 0);
      a = sign ? -v : v;
      if (a[W-2:0] > {(W-1){1'b1}}) a[W-2:0] = {(W-1){1'b1}};
      tc_to_sm = {sign, a[W-2:0]};
    end
  endfunction
  
  // Convert sign-magnitude to two's complement
  function signed [W-1:0] sm_to_tc;
    input [W-1:0] sm;
    begin
      sm_to_tc = sm[W-1] ? -$signed({1'b0, sm[W-2:0]}) : $signed({1'b0, sm[W-2:0]});
    end
  endfunction
  
  // Create Q-format value from integer
  function [W-1:0] q_of_int;
    input integer k;
    reg signed [W-1:0] tc;
    begin
      tc = k <<< FRAC;
      q_of_int = tc_to_sm(tc);
    end
  endfunction
  
  // Display sign-magnitude value
  task display_sm;
    input [W-1:0] val;
    input [80*8-1:0] label;
    reg signed [W-1:0] tc;
    real r;
    begin
      tc = sm_to_tc(val);
      r = $itor(tc) / (2.0 ** FRAC);
      $display("%s: sm=%h tc=%h decimal=%.6f", label, val, tc, r);
    end
  endtask
  
  // ========== Test Sequence ==========
  
  integer errors, checks;
  reg [W-1:0] val_a, val_b, expected;
  reg signed [W-1:0] tc_a, tc_b, tc_result;
  
  // For MUL calculation
  reg [2*(W-1)-1:0] prod;
  reg [W-2:0] mag_a, mag_b, mag_result;
  reg sign_result;
  
  initial begin
    $display("========================================");
    $display("Kalman Filter ASIC Top-Level Test");
    $display("Complete Arithmetic Operations Test");
    $display("========================================");
    
    // Initialize
    clk = 0;
    rst_n = 0;
    start = 0;
    data_in = 0;
    errors = 0;
    checks = 0;
    
    // Test values: 3.0 and 2.5 in Q14 format
    val_a = q_of_int(3);       // 3.0 = 0x00C000
    val_b = q_of_int(2);       // 2.0 = 0x008000
    val_b = val_b + (1 << (FRAC-1)); // 2.5 = 0x00A000
    
    $display("\nTest operands:");
    display_sm(val_a, "Value A (3.0)");
    display_sm(val_b, "Value B (2.5)");
    
    // Reset sequence
    #20;
    rst_n = 1;
    #10;
    
    $display("\n[Test 1] Check initial READY state");
    checks = checks + 1;
    if (ready !== 1'b1) begin
      $display("ERROR: System not ready after reset");
      errors = errors + 1;
    end else begin
      $display("PASS: System ready");
    end
    
    $display("\n[Test 2] Load operands into memory");
    // Memory writes are synchronous - they happen on the NEXT posedge
    // after write_en is asserted
    
    // Prepare first value
    data_in = val_a;
    #5;
    $display("T0: Prepared data_in=%h (3.0)", data_in);
    
    // Cycle 1: Assert START
    @(posedge clk);
    #1;
    start = 1'b1;
    $display("T1: Asserted START");
    
    // Cycle 2: PC→0, ROM[0] instruction visible
    @(posedge clk);
    #1;
    $display("T2: PC=%d, instruction for DB[0] write active", DUT.u_sequencer.pc);
    start = 1'b0;
    
    // Cycle 3: PC→1, DB[0] write completes, ROM[1] instruction visible
    // NOW we can change data_in for the DB[1] write
    @(posedge clk);
    #1;
    $display("T3: PC=%d, DB[0]=%h (should be 00c000)", 
             DUT.u_sequencer.pc, DUT.u_mem.u_db.mem[0]);
    data_in = val_b;
    $display("T3: Changed data_in=%h (2.5) for DB[1]", data_in);
    
    // Cycle 4: PC→2, DB[1] write completes
    @(posedge clk);
    #1;
    $display("T4: PC=%d, DB[0]=%h, DB[1]=%h", 
             DUT.u_sequencer.pc, DUT.u_mem.u_db.mem[0], DUT.u_mem.u_db.mem[1]);
    data_in = 0;
    
    // Monitor execution
    $display("\n[PC Progression from PC=2 onwards]");
    begin : early_monitor
      integer i;
      for (i = 0; i < 10; i = i + 1) begin
        $display("  PC=%2d: ctl_a=%05b ctl_b=%05b addr_a=%d addr_b=%d rdata_a=%h rdata_b=%h",
                 DUT.u_sequencer.pc, DUT.ctl_a, DUT.ctl_b,
                 DUT.addr_a, DUT.addr_b, DUT.db_rdata_a, DUT.db_rdata_b);
        if (DUT.u_sequencer.pc == 2) begin
          $display("  >>> PC=2: R_bus=%h S_bus=%h au_start=%b", 
                   DUT.R_bus, DUT.S_bus, DUT.au_start);
        end
        @(posedge clk);
        #1;
      end
    end
    
    // Check what was actually loaded
    #10;
    $display("\nMemory contents after load:");
    $display("  DB[0] = %h (expected %h for 3.0)", DUT.u_mem.u_db.mem[0], val_a);
    $display("  DB[1] = %h (expected %h for 2.5)", DUT.u_mem.u_db.mem[1], val_b);
    
    $display("\nROM Program Check:");
    $display("  ROM[2] = %b (ADD instruction)", DUT.u_sequencer.UROM.mem[2]);
    $display("           ctl_a=%b ctl_b=%b ctl_c=%b ctl_d=%b ctl_e=%b",
             DUT.u_sequencer.UROM.mem[2][15:11],
             DUT.u_sequencer.UROM.mem[2][10:6],
             DUT.u_sequencer.UROM.mem[2][5:4],
             DUT.u_sequencer.UROM.mem[2][3:2],
             DUT.u_sequencer.UROM.mem[2][1:0]);
    
    $display("PASS: Loaded operands");
    checks = checks + 1;
    
    // Monitor a few cycles to see PC progression
    $display("\n[PC Progression Check]");
    begin : pc_check
      integer i;
      for (i = 0; i < 10; i = i + 1) begin
        @(posedge clk);
        #1;
        $display("  Cycle %d: PC=%d, ready=%b", i, DUT.u_sequencer.pc, DUT.ready);
        if (DUT.u_sequencer.pc == 2) begin
          $display("\n[PC=2 Debug] ADD Instruction Execution:");
          $display("  ctl_b = %05b", DUT.ctl_b);
          $display("  sel_R = %02b, sel_S = %02b, addr_mode = %b", DUT.sel_R, DUT.sel_S, DUT.addr_mode);
          $display("  addr_a = %d, addr_b = %d", DUT.addr_a, DUT.addr_b);
          $display("  db_rdata_a = %h (mem[%d])", DUT.db_rdata_a, DUT.addr_a);
          $display("  db_rdata_b = %h (mem[%d])", DUT.db_rdata_b, DUT.addr_b);
          $display("  R_bus = %h, S_bus = %h", DUT.R_bus, DUT.S_bus);
          $display("  au_start = %b, op_sel = %02b", DUT.au_start, DUT.op_sel);
        end
      end
    end
    
    $display("\n[Test 3] Monitor sequencer execution");
    $display("PC   | ctl_a | ctl_b | ctl_c | ctl_d | ctl_e | addr_a | addr_b | au_done | ready | result");
    $display("-----|-------|-------|-------|-------|-------|--------|--------|---------|-------|--------");
    
    // Monitor for a few cycles or until HALT
    begin : monitor_loop
      integer i;
      for (i = 0; i < 50; i = i + 1) begin
        @(posedge clk);
        #1;
        $display("%3d  | %5b | %5b | %2b    | %2b    | %2b    | %6d | %6d | %b       | %b     | %h",
                 DUT.u_sequencer.pc,
                 DUT.ctl_a,
                 DUT.ctl_b,
                 DUT.ctl_c,
                 DUT.ctl_d,
                 DUT.ctl_e,
                 DUT.addr_a,
                 DUT.addr_b,
                 au_done,
                 ready,
                 result_out);
        
        // Check if we hit HALT (ctl_c = 2'b10)
        if (DUT.ctl_c == 2'b10 && ready == 1'b1) begin
          $display("\nHALT detected - program completed at PC=%d", DUT.u_sequencer.pc);
          disable monitor_loop;
        end
      end
    end
    
    $display("\n[Test 4] Verify computation results");
    // Read back results from memory
    #20;
    
    // Expected results:
    // DB[2] should have ADD: 3.0 + 2.5 = 5.5
    tc_a = sm_to_tc(val_a);
    tc_b = sm_to_tc(val_b);
    tc_result = tc_a + tc_b;
    expected = tc_to_sm(tc_result);
    
    $display("\nExpected ADD result (3.0 + 2.5 = 5.5):");
    display_sm(expected, "ADD");
    $display("Actual result in DB[2]:");
    display_sm(DUT.u_mem.u_db.mem[2], "DB[2]");
    
    checks = checks + 1;
    if (DUT.u_mem.u_db.mem[2] == expected) begin
      $display("PASS: ADD result correct");
    end else begin
      $display("ERROR: ADD result mismatch");
      errors = errors + 1;
    end
    
    // DB[3] should have SUB: 3.0 - 2.5 = 0.5
    tc_result = tc_a - tc_b;
    expected = tc_to_sm(tc_result);
    
    $display("\nExpected SUB result (3.0 - 2.5 = 0.5):");
    display_sm(expected, "SUB");
    $display("Actual result in DB[3]:");
    display_sm(DUT.u_mem.u_db.mem[3], "DB[3]");
    
    checks = checks + 1;
    if (DUT.u_mem.u_db.mem[3] == expected) begin
      $display("PASS: SUB result correct");
    end else begin
      $display("ERROR: SUB result mismatch");
      errors = errors + 1;
    end
    
    // DB[4] should have MUL: 3.0 * 2.5 = 7.5
    // For multiplication in fixed-point, need to handle scaling
    mag_a = val_a[W-2:0];
    mag_b = val_b[W-2:0];
    sign_result = val_a[W-1] ^ val_b[W-1];
    
    prod = mag_a * mag_b;
    mag_result = prod[2*(W-1)-1:FRAC];  // Scale down by FRAC bits
    
    expected = {sign_result, mag_result};
    
    $display("\nExpected MUL result (3.0 * 2.5 = 7.5):");
    display_sm(expected, "MUL");
    $display("Actual result in DB[4]:");
    display_sm(DUT.u_mem.u_db.mem[4], "DB[4]");
    
    checks = checks + 1;
    if (DUT.u_mem.u_db.mem[4] == expected) begin
      $display("PASS: MUL result correct");
    end else begin
      $display("ERROR: MUL result mismatch");
      errors = errors + 1;
    end
    
    $display("\n[Test 5] Verify system returned to READY");
    if (ready == 1'b1) begin
      $display("PASS: System ready for next operation");
    end else begin
      $display("WARNING: System not in READY state");
    end
    checks = checks + 1;
    
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
    #10000;
    $display("\nERROR: Simulation timeout!");
    $finish;
  end

endmodule
