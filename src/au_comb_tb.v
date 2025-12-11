// -----------------------------------------------------------------------------
// au_comb_tb.v - Test combinational AU result path
// -----------------------------------------------------------------------------
// Verifies that ADD/SUB/MUL produce results in a single cycle
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module au_comb_tb();
  parameter W = 24;
  parameter FRAC = 14;

  reg              clk;
  reg              rst_n;
  reg              start;
  reg  [W-1:0]     R, S, I;
  reg  [1:0]       ctl_d;

  wire [W-1:0]     result_comb;
  wire             result_comb_valid;
  wire [W-1:0]     result;
  wire             done;
  wire             busy;

  // Instantiate AU
  au #(.W(W), .FRAC(FRAC)) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (start),
    .R      (R),
    .S      (S),
    .I      (I),
    .ctl_d  (ctl_d),
    .result_comb       (result_comb),
    .result_comb_valid (result_comb_valid),
    .result (result),
    .done   (done),
    .busy   (busy)
  );

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Convert real to sign-magnitude Q9.14
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

  initial begin
    $display("=== AU Combinational Result Test ===");

    // Initialize
    rst_n = 0;
    start = 0;
    R = 0;
    S = 0;
    I = 0;
    ctl_d = 2'b00;

    repeat(3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // Test 1: ADD (2.0 + 3.0 = 5.0)
    $display("\n--- Test 1: ADD 2.0 + 3.0 ---");
    R = real_to_sm(2.0);
    S = real_to_sm(3.0);
    ctl_d = 2'b00;  // ADD
    start = 1;

    // Check combinational result BEFORE clock edge
    #1;
    $display("  Before clk: result_comb_valid=%b, result_comb=%h (%.6f)",
             result_comb_valid, result_comb, sm_to_real(result_comb));

    @(posedge clk);
    start = 0;
    #1;
    $display("  After clk:  result_comb_valid=%b, result_comb=%h (%.6f)",
             result_comb_valid, result_comb, sm_to_real(result_comb));

    if (sm_to_real(result_comb) > 4.9 && sm_to_real(result_comb) < 5.1)
      $display("  PASS: ADD result correct");
    else
      $display("  FAIL: Expected ~5.0, got %.6f", sm_to_real(result_comb));

    @(posedge clk);

    // Test 2: SUB (5.0 - 2.0 = 3.0)
    $display("\n--- Test 2: SUB 5.0 - 2.0 ---");
    R = real_to_sm(5.0);
    S = real_to_sm(2.0);
    ctl_d = 2'b01;  // SUB
    start = 1;

    #1;
    $display("  Before clk: result_comb_valid=%b, result_comb=%h (%.6f)",
             result_comb_valid, result_comb, sm_to_real(result_comb));

    @(posedge clk);
    start = 0;
    #1;

    if (sm_to_real(result_comb) > 2.9 && sm_to_real(result_comb) < 3.1)
      $display("  PASS: SUB result correct");
    else
      $display("  FAIL: Expected ~3.0, got %.6f", sm_to_real(result_comb));

    @(posedge clk);

    // Test 3: MUL (2.0 * 3.0 = 6.0)
    $display("\n--- Test 3: MUL 2.0 * 3.0 ---");
    R = real_to_sm(2.0);
    S = real_to_sm(3.0);
    ctl_d = 2'b10;  // MUL
    start = 1;

    #1;
    $display("  Before clk: result_comb_valid=%b, result_comb=%h (%.6f)",
             result_comb_valid, result_comb, sm_to_real(result_comb));

    @(posedge clk);
    start = 0;
    #1;

    if (sm_to_real(result_comb) > 5.9 && sm_to_real(result_comb) < 6.1)
      $display("  PASS: MUL result correct");
    else
      $display("  FAIL: Expected ~6.0, got %.6f", sm_to_real(result_comb));

    @(posedge clk);

    // Test 4: DIV (6.0 / 2.0 = 3.0) - multi-cycle
    $display("\n--- Test 4: DIV 6.0 / 2.0 (multi-cycle) ---");
    R = real_to_sm(6.0);
    S = real_to_sm(2.0);
    ctl_d = 2'b11;  // DIV
    start = 1;

    #1;
    $display("  result_comb_valid should be 0 for DIV: %b", result_comb_valid);

    @(posedge clk);
    start = 0;

    // Wait for DIV to complete
    $display("  Waiting for DIV...");
    begin : wait_div
      integer i;
      for (i = 0; i < 30; i = i + 1) begin
        @(posedge clk);
        if (done) begin
          $display("  DIV done at cycle %0d", i);
          disable wait_div;
        end
      end
    end

    #1;
    $display("  DIV result: %h (%.6f)", result, sm_to_real(result));

    if (sm_to_real(result) > 2.9 && sm_to_real(result) < 3.1)
      $display("  PASS: DIV result correct");
    else
      $display("  FAIL: Expected ~3.0, got %.6f", sm_to_real(result));

    $display("\n=== Test Complete ===");
    $finish;
  end

endmodule
