// -----------------------------------------------------------------------------
// router_a_tb.v
// Testbench for Router A - Data input multiplexer and address routing
// Tests per paper Figure 3: Data mux, address mux, write enable control
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module router_a_tb;
  // Parameters for testbench (not passed to DUT for post-syn compatibility)
  parameter W=24, ADDRW=5;

  // Inputs (matching router_a.v port names)
  reg  [W-1:0]      DATA_IN, result;
  reg  [ADDRW-1:0]  ctl_a, ctl_b, DIR;
  reg               WRITE, READY;
  reg  [1:0]        sel_data, sel_write;
  reg               sel_dira, sel_dirb;

  // Outputs (matching router_a.v port names)
  wire [W-1:0]      data;
  wire [ADDRW-1:0]  dira, dirb;
  wire              write;

  // Instantiate DUT - no parameter override for post-syn compatibility
  router_a DUT (
    .DATA_IN   (DATA_IN),
    .result    (result),
    .ctl_a     (ctl_a),
    .ctl_b     (ctl_b),
    .DIR       (DIR),
    .WRITE     (WRITE),
    .READY     (READY),
    .sel_data  (sel_data),
    .sel_dira  (sel_dira),
    .sel_dirb  (sel_dirb),
    .sel_write (sel_write),
    .data      (data),
    .dira      (dira),
    .dirb      (dirb),
    .write     (write)
  );

  // Distinct test patterns
  localparam [W-1:0]      DIN  = 24'h123456;  // DATA_IN pattern
  localparam [W-1:0]      RES  = 24'hC0FFEE;  // result pattern
  localparam [ADDRW-1:0]  ASEL = 5'h03;       // ctl_a pattern
  localparam [ADDRW-1:0]  BSEL = 5'h1C;       // ctl_b pattern
  localparam [ADDRW-1:0]  DEXT = 5'h12;       // DIR pattern

  integer sd, sda, sdb, sw, wr, rdy, tests, errors;

  // Expected data output based on sel_data
  function [W-1:0] exp_data;
    input [1:0] sd;
    begin
      case(sd)
        2'd0:    exp_data = DIN;          // DATA_IN
        2'd1:    exp_data = RES;          // result
        2'd2:    exp_data = {W{1'b0}};    // Zero
        default: exp_data = {W{1'b1}};    // All ones
      endcase
    end
  endfunction

  // Expected dira based on sel_dira
  function [ADDRW-1:0] exp_dira;
    input sel;
    begin
      exp_dira = sel ? DEXT : ASEL;  // 1=DIR, 0=ctl_a
    end
  endfunction

  // Expected dirb based on sel_dirb
  function [ADDRW-1:0] exp_dirb;
    input sel;
    begin
      exp_dirb = sel ? DEXT : BSEL;  // 1=DIR, 0=ctl_b
    end
  endfunction

  // Expected write output based on sel_write
  function exp_write;
    input [1:0] sw;
    input wr, ready;
    begin
      case(sw)
        2'd0:    exp_write = wr;            // Direct WRITE
        2'd1:    exp_write = wr & ready;    // WRITE & READY
        2'd2:    exp_write = 1'b0;          // Disabled
        default: exp_write = 1'b1;          // Always enabled
      endcase
    end
  endfunction

  initial begin
    // Initialize inputs with test patterns
    DATA_IN = DIN;
    result  = RES;
    ctl_a   = ASEL;
    ctl_b   = BSEL;
    DIR     = DEXT;
    tests   = 0;
    errors  = 0;

    $display("========================================");
    $display("Testing Router A (per paper Figure 3)");
    $display("========================================");

    // Exhaustive test of all control combinations
    for (sd = 0; sd < 4; sd = sd + 1)
    for (sda = 0; sda < 2; sda = sda + 1)
    for (sdb = 0; sdb < 2; sdb = sdb + 1)
    for (sw = 0; sw < 4; sw = sw + 1)
    for (wr = 0; wr < 2; wr = wr + 1)
    for (rdy = 0; rdy < 2; rdy = rdy + 1) begin
      sel_data  = sd[1:0];
      sel_dira  = sda[0:0];
      sel_dirb  = sdb[0:0];
      sel_write = sw[1:0];
      WRITE     = wr[0:0];
      READY     = rdy[0:0];
      #1;
      tests = tests + 1;

      // Check data output
      if (data !== exp_data(sel_data)) begin
        $display("ERR data: sel_data=%0d exp=%h got=%h",
                  sel_data, exp_data(sel_data), data);
        errors = errors + 1;
      end

      // Check dira output
      if (dira !== exp_dira(sel_dira)) begin
        $display("ERR dira: sel_dira=%0d exp=%0d got=%0d",
                 sel_dira, exp_dira(sel_dira), dira);
        errors = errors + 1;
      end

      // Check dirb output
      if (dirb !== exp_dirb(sel_dirb)) begin
        $display("ERR dirb: sel_dirb=%0d exp=%0d got=%0d",
                 sel_dirb, exp_dirb(sel_dirb), dirb);
        errors = errors + 1;
      end

      // Check write output
      if (write !== exp_write(sel_write, WRITE, READY)) begin
        $display("ERR write: sel_write=%0d WRITE=%0d READY=%0d exp=%0d got=%0d",
                 sel_write, WRITE, READY,
                 exp_write(sel_write, WRITE, READY), write);
        errors = errors + 1;
      end
    end

    $display("========================================");
    if (errors == 0)
      $display("Router A: %0d tests PASSED", tests);
    else
      $display("Router A: %0d tests, %0d ERRORS", tests, errors);
    $display("========================================");
    $finish;
  end
endmodule
