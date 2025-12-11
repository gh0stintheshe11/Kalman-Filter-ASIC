// -----------------------------------------------------------------------------
// au_inv_tb.v
// Testbench for AU Multiplicative Inverse (DIV operation)
// -----------------------------------------------------------------------------
// Per paper Section 4:
//   "The multiplicative-inverse follows a successive approximation technique
//    using the multiplier block and an internal numeric comparator to determine
//    the result bit by bit, requiring 24 clock cycles to finish the task."
//
// Operation: R / S = R × (1/S)
//   - First computes 1/S using successive approximation (23 cycles)
//   - Then multiplies R × (1/S) to get final result (1 cycle)
//   - Total: ~24-26 cycles including FSM overhead
//
// Fixed-point format: Q9.14 sign-magnitude (1 sign + 9 int + 14 frac = 24 bits)
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// Define SIM_POST_SYN for post-synthesis simulation
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module au_inv_tb();
  parameter W = 24;
  parameter FRAC = 14;

  reg              clk;
  reg              rst_n;
  reg  [W-1:0]     R, S, I;
  reg  [1:0]       ctl_d;
  reg              start;
  wire [W-1:0]     result;
  wire             done, busy;

  // Test counters
  integer pass_count, fail_count;

  // Instantiate AU
  au dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (start),
    .R      (R),
    .S      (S),
    .I      (I),
    .ctl_d  (ctl_d),
    .result (result),
    .done   (done),
    .busy   (busy)
  );

  // Clock generation (10ns period = 100MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // Convert integer to sign-magnitude Q9.14 format
  function [W-1:0] int_to_sm;
    input integer val;
    reg sign_bit;
    reg [W-2:0] magnitude;
    begin
      sign_bit = (val < 0);
      if (val < 0) val = -val;
      magnitude = val << FRAC;
      int_to_sm = {sign_bit, magnitude};
    end
  endfunction

  // Convert real to sign-magnitude Q9.14 format
  function [W-1:0] real_to_sm;
    input real val;
    reg sign_bit;
    integer mag_int;
    begin
      sign_bit = (val < 0.0);
      mag_int = (sign_bit ? -val : val) * (1 << FRAC);
      real_to_sm = {sign_bit, mag_int[W-2:0]};
    end
  endfunction

  // Convert sign-magnitude Q9.14 to real
  function real sm_to_real;
    input [W-1:0] sm;
    integer signed_mag;
    begin
      signed_mag = sm[W-2:0];
      sm_to_real = (sm[W-1]) ? -($itor(signed_mag) / 16384.0)
                             :  ($itor(signed_mag) / 16384.0);
    end
  endfunction

  // Task: Test division with integer values
  task test_div_int;
    input integer r_val, s_val;
    real expected, got, error_pct;
    integer cycles;
    begin
      $display("\nTest: %0d / %0d", r_val, s_val);

      R = int_to_sm(r_val);
      S = int_to_sm(s_val);
      I = 0;
      ctl_d = 2'b11;  // DIV (INV)

      start = 1;
      @(posedge clk);
      start = 0;

      // Wait for completion
      cycles = 0;
      while (!done && cycles < 50) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      @(posedge clk);

      expected = (1.0 * r_val) / s_val;
      got = sm_to_real(result);
      error_pct = (expected != 0.0) ? ((got - expected) / expected) * 100.0 : got * 100.0;

      $display("  Expected: %.6f", expected);
      $display("  Got:      %.6f (0x%06h)", got, result);
      $display("  Error:    %.2f%%, Cycles: %0d", error_pct, cycles);

      if (error_pct > -1.0 && error_pct < 1.0) begin
        $display("  PASS");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL");
        fail_count = fail_count + 1;
      end
    end
  endtask

  // Task: Test division with real (fractional) values
  task test_div_real;
    input real r_val, s_val;
    real expected, got, error_pct;
    integer cycles;
    begin
      $display("\nTest: %.4f / %.4f", r_val, s_val);

      R = real_to_sm(r_val);
      S = real_to_sm(s_val);
      I = 0;
      ctl_d = 2'b11;  // DIV (INV)

      start = 1;
      @(posedge clk);
      start = 0;

      // Wait for completion
      cycles = 0;
      while (!done && cycles < 50) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      @(posedge clk);

      expected = r_val / s_val;
      got = sm_to_real(result);
      error_pct = (expected != 0.0) ? ((got - expected) / expected) * 100.0 : got * 100.0;

      $display("  Expected: %.6f", expected);
      $display("  Got:      %.6f (0x%06h)", got, result);
      $display("  Error:    %.2f%%, Cycles: %0d", error_pct, cycles);

      if (error_pct > -1.0 && error_pct < 1.0) begin
        $display("  PASS");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL");
        fail_count = fail_count + 1;
      end
    end
  endtask

  initial begin
    // Initialize
    start = 0;
    rst_n = 0;
    I = 0;
    pass_count = 0;
    fail_count = 0;

    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("========================================");
    $display("AU Multiplicative Inverse (DIV) Test");
    $display("Per paper: ~24 clock cycles per inverse");
    $display("Format: Q9.14 sign-magnitude");
    $display("========================================");

    // ---- Integer divisions ----
    $display("\n--- Integer Divisions ---");
    test_div_int(1, 1);     // 1/1 = 1.0
    test_div_int(1, 2);     // 1/2 = 0.5
    test_div_int(1, 4);     // 1/4 = 0.25
    test_div_int(2, 4);     // 2/4 = 0.5
    test_div_int(3, 2);     // 3/2 = 1.5

    // ---- Signed divisions ----
    $display("\n--- Signed Divisions ---");
    test_div_int(1, -2);    // 1/-2 = -0.5
    test_div_int(-1, 2);    // -1/2 = -0.5
    test_div_int(-4, 2);    // -4/2 = -2.0

    // ---- Fractional divisions (critical for Kalman Filter) ----
    $display("\n--- Fractional Divisions (KF-critical) ---");
    test_div_real(1.01, 1.11);   // Kalman gain: P_pred/(P_pred+R) ≈ 0.9099
    test_div_real(0.5, 1.5);     // 0.333...
    test_div_real(2.5, 3.0);     // 0.833...

    // ---- Summary ----
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("  Passed: %0d", pass_count);
    $display("  Failed: %0d", fail_count);
    if (fail_count == 0)
      $display("  ALL TESTS PASSED!");
    else
      $display("  SOME TESTS FAILED!");
    $display("========================================\n");

    $finish;
  end

endmodule
