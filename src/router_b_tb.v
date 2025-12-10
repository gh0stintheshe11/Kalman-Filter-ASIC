// -----------------------------------------------------------------------------
// router_b_tb.v
// Testbench for Router B - Operand selection for AU (per paper Figure 3)
// Tests: R/S mux selection, inversion, immediate values
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module router_b_tb;

  // Parameters for testbench (not passed to DUT for post-syn compatibility)
  parameter W = 24;

  // DUT inputs (matching router_b.v port names per paper Figure 3)
  reg  [W-1:0] A, B, RQ, RD;      // Data Bank outputs and temp registers
  reg  [1:0]   sel_R, sel_S, sel_I;
  reg          inv_R, inv_S;

  // DUT outputs
  wire [W-1:0] R, S, I;
  wire         msb_R, msb_S;

  // Instantiate DUT - no parameter override for post-syn compatibility
  router_b DUT (
    .A      (A),
    .B      (B),
    .RQ     (RQ),
    .RD     (RD),
    .sel_R  (sel_R),
    .sel_S  (sel_S),
    .inv_R  (inv_R),
    .inv_S  (inv_S),
    .sel_I  (sel_I),
    .R      (R),
    .S      (S),
    .I      (I),
    .msb_R  (msb_R),
    .msb_S  (msb_S)
  );

  // Distinct source patterns for testing
  localparam [W-1:0] PA  = 24'h12_3456;   // Pattern for A (Data Bank port A)
  localparam [W-1:0] PB  = 24'hAB_CDEF;   // Pattern for B (Data Bank port B)
  localparam [W-1:0] PRQ = 24'h0F_F00D;   // Pattern for RQ
  localparam [W-1:0] PRD = 24'hC0_FFEE;   // Pattern for RD

  // Loop counters / book-keeping
  integer a, b, c, d, i_sel, tests, errors;

  // Expected value temporaries
  reg [W-1:0] expR, expS, expI;

  // Expected R based on sel_R (per paper: 00=A, 01=RQ, 10=0, 11=all-1s)
  function [W-1:0] pickR;
    input [1:0] sel;
    begin
      case(sel)
        2'b00:   pickR = PA;           // Data Bank port A
        2'b01:   pickR = PRQ;          // Temp register RQ
        2'b10:   pickR = {W{1'b0}};    // Zero
        default: pickR = {W{1'b1}};    // All ones
      endcase
    end
  endfunction

  // Expected S based on sel_S (per paper: 00=B, 01=RD, 10=0, 11=all-1s)
  function [W-1:0] pickS;
    input [1:0] sel;
    begin
      case(sel)
        2'b00:   pickS = PB;           // Data Bank port B
        2'b01:   pickS = PRD;          // Temp register RD
        2'b10:   pickS = {W{1'b0}};    // Zero
        default: pickS = {W{1'b1}};    // All ones
      endcase
    end
  endfunction

  // Expected I based on sel_I
  function [W-1:0] pickI;
    input [1:0] sel;
    begin
      case(sel)
        2'b00:   pickI = {W{1'b0}};                 // 0
        2'b01:   pickI = {{(W-1){1'b0}}, 1'b1};     // +1
        2'b10:   pickI = {W{1'b1}};                 // -1 (all ones)
        default: pickI = {W{1'b0}};                 // 0
      endcase
    end
  endfunction

  initial begin
    // Drive distinct sources (per paper Figure 3 naming)
    A  = PA;
    B  = PB;
    RQ = PRQ;
    RD = PRD;
    tests  = 0;
    errors = 0;

    $display("========================================");
    $display("Testing Router B (per paper Figure 3)");
    $display("Operand selection: R from A/RQ, S from B/RD");
    $display("========================================");

    // Iterate all mux choices + inversion flags + immediates (0,+1,-1)
    for (a = 0; a < 4; a = a + 1)
    for (b = 0; b < 4; b = b + 1)
    for (c = 0; c < 2; c = c + 1)
    for (d = 0; d < 2; d = d + 1) begin
      sel_R = a[1:0];
      sel_S = b[1:0];
      inv_R = c[0:0];
      inv_S = d[0:0];

      for (i_sel = 0; i_sel < 3; i_sel = i_sel + 1) begin
        sel_I = i_sel[1:0];

        #1;
        tests = tests + 1;

        // Compute expected R (with optional inversion)
        expR = pickR(sel_R);
        if (inv_R) expR = ~expR;

        // Compute expected S (with optional inversion)
        expS = pickS(sel_S);
        if (inv_S) expS = ~expS;

        // Compute expected I
        expI = pickI(sel_I);

        // Check R output
        if (R !== expR) begin
          $display("ERR R: sel_R=%0d inv_R=%0d exp=%h got=%h", sel_R, inv_R, expR, R);
          errors = errors + 1;
        end

        // Check S output
        if (S !== expS) begin
          $display("ERR S: sel_S=%0d inv_S=%0d exp=%h got=%h", sel_S, inv_S, expS, S);
          errors = errors + 1;
        end

        // Check I output
        if (I !== expI) begin
          $display("ERR I: sel_I=%0d exp=%h got=%h", sel_I, expI, I);
          errors = errors + 1;
        end

        // Check MSB outputs (sign bits to AU)
        if (msb_R !== R[W-1]) begin
          $display("ERR msb_R: exp=%b got=%b", R[W-1], msb_R);
          errors = errors + 1;
        end
        if (msb_S !== S[W-1]) begin
          $display("ERR msb_S: exp=%b got=%b", S[W-1], msb_S);
          errors = errors + 1;
        end
      end
    end

    $display("========================================");
    if (errors == 0)
      $display("Router B: PASS (%0d tests)", tests);
    else
      $display("Router B: %0d ERRORS / %0d tests", errors, tests);
    $display("========================================");

    $finish;
  end

endmodule
