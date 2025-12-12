// -----------------------------------------------------------------------------
// au_tb.v - Comprehensive Arithmetic Unit Testbench
// -----------------------------------------------------------------------------
// Combines tests for all AU operations per paper Section 4:
//   - ADD (1 cycle) - Addition
//   - SUB (1 cycle) - Subtraction
//   - MUL (1 cycle) - Multiplication
//   - DIV (24 cycles) - Multiplicative Inverse (R/S = R * (1/S))
//
// Tests cover:
//   1. Basic integer operations
//   2. Fractional (fixed-point) operations
//   3. Signed number handling
//   4. Combinational result path (single-cycle ops)
//   5. Multi-cycle DIV with successive approximation
//   6. Edge cases (saturation, small values)
//
// Fixed-point format (per paper Section 3):
//   Sign-magnitude Q9.14: 1 sign + 9 integer + 14 fractional = 24 bits
//
// Compatible with: RTL, post-synthesis, post-layout simulation
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module au_tb();
  parameter W = 24;
  parameter FRAC = 14;

  // DUT signals
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

  // Test counters
  integer pass_count, fail_count, test_num;

  // Instantiate AU
  // Use +define+POST_SYN for post-synthesis simulation (no parameters)
  `ifdef POST_SYN
  au dut (
  `else
  au #(.W(W), .FRAC(FRAC)) dut (
  `endif
    .clk              (clk),
    .rst_n            (rst_n),
    .start            (start),
    .R                (R),
    .S                (S),
    .I                (I),
    .ctl_d            (ctl_d),
    .result_comb      (result_comb),
    .result_comb_valid(result_comb_valid),
    .result           (result),
    .done             (done),
    .busy             (busy)
  );

  // Clock generation (10ns period = 100MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // =========================================================================
  // Helper Functions
  // =========================================================================

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

  // Compare with tolerance (handles +0/-0 and small errors)
  function check_result;
    input real got, expected, tolerance;
    real diff;
    begin
      diff = (got > expected) ? (got - expected) : (expected - got);
      check_result = (diff <= tolerance);
    end
  endfunction

  // =========================================================================
  // Test Tasks
  // =========================================================================

  // Task: Test single-cycle operation (ADD/SUB/MUL) with integer values
  task test_single_cycle_int;
    input [1:0] op;
    input integer r_val, s_val;
    real expected, got, tolerance;
    reg [15:0] op_name;
    begin
      test_num = test_num + 1;

      case (op)
        2'b00: begin op_name = "ADD"; expected = r_val + s_val; end
        2'b01: begin op_name = "SUB"; expected = r_val - s_val; end
        2'b10: begin op_name = "MUL"; expected = r_val * s_val; end
        default: begin op_name = "???"; expected = 0; end
      endcase

      R = int_to_sm(r_val);
      S = int_to_sm(s_val);
      I = 0;
      ctl_d = op;
      start = 1;

      // Result should be available combinationally
      #1;
      got = sm_to_real(result_comb);
      tolerance = 0.001;  // Allow small fixed-point error

      if (check_result(got, expected, tolerance) && result_comb_valid) begin
        $display("  [%0d] PASS: %0d %s %0d = %.4f (expected %.4f)",
                 test_num, r_val, op_name, s_val, got, expected);
        pass_count = pass_count + 1;
      end else begin
        $display("  [%0d] FAIL: %0d %s %0d = %.4f (expected %.4f), valid=%b",
                 test_num, r_val, op_name, s_val, got, expected, result_comb_valid);
        fail_count = fail_count + 1;
      end

      @(posedge clk);
      start = 0;
      @(posedge clk);
    end
  endtask

  // Task: Test single-cycle operation with real (fractional) values
  task test_single_cycle_real;
    input [1:0] op;
    input real r_val, s_val;
    real expected, got, tolerance;
    reg [15:0] op_name;
    begin
      test_num = test_num + 1;

      case (op)
        2'b00: begin op_name = "ADD"; expected = r_val + s_val; end
        2'b01: begin op_name = "SUB"; expected = r_val - s_val; end
        2'b10: begin op_name = "MUL"; expected = r_val * s_val; end
        default: begin op_name = "???"; expected = 0; end
      endcase

      R = real_to_sm(r_val);
      S = real_to_sm(s_val);
      I = 0;
      ctl_d = op;
      start = 1;

      #1;
      got = sm_to_real(result_comb);
      // Tolerance: 0.1% of expected or 0.001, whichever is larger
      tolerance = (expected > 0.0 ? expected : -expected) * 0.001;
      if (tolerance < 0.001) tolerance = 0.001;

      if (check_result(got, expected, tolerance) && result_comb_valid) begin
        $display("  [%0d] PASS: %.4f %s %.4f = %.6f (expected %.6f)",
                 test_num, r_val, op_name, s_val, got, expected);
        pass_count = pass_count + 1;
      end else begin
        $display("  [%0d] FAIL: %.4f %s %.4f = %.6f (expected %.6f), valid=%b",
                 test_num, r_val, op_name, s_val, got, expected, result_comb_valid);
        fail_count = fail_count + 1;
      end

      @(posedge clk);
      start = 0;
      @(posedge clk);
    end
  endtask

  // Task: Test DIV operation (24 cycles) with integer values
  task test_div_int;
    input integer r_val, s_val;
    real expected, got, error_pct;
    integer cycles;
    begin
      test_num = test_num + 1;

      R = int_to_sm(r_val);
      S = int_to_sm(s_val);
      I = 0;
      ctl_d = 2'b11;  // DIV

      start = 1;
      @(posedge clk);
      start = 0;

      // Wait for completion (should be ~24-26 cycles)
      cycles = 0;
      while (!done && cycles < 50) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      @(posedge clk);  // One more for result to stabilize

      expected = (1.0 * r_val) / s_val;
      got = sm_to_real(result);
      error_pct = (expected != 0.0) ? ((got - expected) / expected) * 100.0 : 0.0;

      if (error_pct > -1.0 && error_pct < 1.0) begin
        $display("  [%0d] PASS: %0d / %0d = %.6f (expected %.6f), %0d cycles",
                 test_num, r_val, s_val, got, expected, cycles);
        pass_count = pass_count + 1;
      end else begin
        $display("  [%0d] FAIL: %0d / %0d = %.6f (expected %.6f), error=%.2f%%, %0d cycles",
                 test_num, r_val, s_val, got, expected, error_pct, cycles);
        fail_count = fail_count + 1;
      end

      @(posedge clk);
    end
  endtask

  // Task: Test DIV operation with real (fractional) values
  task test_div_real;
    input real r_val, s_val;
    real expected, got, error_pct;
    integer cycles;
    begin
      test_num = test_num + 1;

      R = real_to_sm(r_val);
      S = real_to_sm(s_val);
      I = 0;
      ctl_d = 2'b11;  // DIV

      start = 1;
      @(posedge clk);
      start = 0;

      cycles = 0;
      while (!done && cycles < 50) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      @(posedge clk);

      expected = r_val / s_val;
      got = sm_to_real(result);
      error_pct = (expected != 0.0) ? ((got - expected) / expected) * 100.0 : 0.0;

      if (error_pct > -1.0 && error_pct < 1.0) begin
        $display("  [%0d] PASS: %.4f / %.4f = %.6f (expected %.6f), %0d cycles",
                 test_num, r_val, s_val, got, expected, cycles);
        pass_count = pass_count + 1;
      end else begin
        $display("  [%0d] FAIL: %.4f / %.4f = %.6f (expected %.6f), error=%.2f%%, %0d cycles",
                 test_num, r_val, s_val, got, expected, error_pct, cycles);
        fail_count = fail_count + 1;
      end

      @(posedge clk);
    end
  endtask

  // Task: Verify combinational timing (result available before clock edge)
  task test_comb_timing;
    input [1:0] op;
    input real r_val, s_val;
    reg valid_before_clk;
    begin
      test_num = test_num + 1;

      R = real_to_sm(r_val);
      S = real_to_sm(s_val);
      I = 0;
      ctl_d = op;
      start = 1;

      // Check result_comb_valid immediately (combinational)
      #1;
      valid_before_clk = result_comb_valid;

      @(posedge clk);
      start = 0;

      if (valid_before_clk && (op != 2'b11)) begin
        $display("  [%0d] PASS: Combinational result valid before clock edge (op=%b)",
                 test_num, op);
        pass_count = pass_count + 1;
      end else if (!valid_before_clk && (op == 2'b11)) begin
        $display("  [%0d] PASS: DIV correctly reports comb_valid=0 (multi-cycle)",
                 test_num);
        pass_count = pass_count + 1;
      end else begin
        $display("  [%0d] FAIL: Unexpected comb_valid=%b for op=%b",
                 test_num, valid_before_clk, op);
        fail_count = fail_count + 1;
      end

      @(posedge clk);
    end
  endtask

  // =========================================================================
  // Main Test Sequence
  // =========================================================================
  initial begin
    // Initialize
    rst_n = 0;
    start = 0;
    R = 0;
    S = 0;
    I = 0;
    ctl_d = 2'b00;
    pass_count = 0;
    fail_count = 0;
    test_num = 0;

    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("================================================================");
    $display("AU Comprehensive Testbench");
    $display("Per paper Section 4: ADD/SUB/MUL (1 cycle), DIV (24 cycles)");
    $display("Format: Q9.14 sign-magnitude (1 sign + 9 int + 14 frac = 24 bits)");
    $display("================================================================");

    // -----------------------------------------------------------------------
    // Section 1: ADD Tests
    // -----------------------------------------------------------------------
    $display("\n--- Section 1: ADD Tests (ctl_d=00, 1 cycle) ---");
    test_single_cycle_int(2'b00, 2, 3);       // 2 + 3 = 5
    test_single_cycle_int(2'b00, -2, 3);      // -2 + 3 = 1
    test_single_cycle_int(2'b00, -2, -3);     // -2 + -3 = -5
    test_single_cycle_int(2'b00, 0, 5);       // 0 + 5 = 5
    test_single_cycle_real(2'b00, 1.5, 2.25); // 1.5 + 2.25 = 3.75
    test_single_cycle_real(2'b00, -1.5, 0.5); // -1.5 + 0.5 = -1.0

    // -----------------------------------------------------------------------
    // Section 2: SUB Tests
    // -----------------------------------------------------------------------
    $display("\n--- Section 2: SUB Tests (ctl_d=01, 1 cycle) ---");
    test_single_cycle_int(2'b01, 5, 3);       // 5 - 3 = 2
    test_single_cycle_int(2'b01, 3, 5);       // 3 - 5 = -2
    test_single_cycle_int(2'b01, -2, 3);      // -2 - 3 = -5
    test_single_cycle_int(2'b01, -2, -3);     // -2 - (-3) = 1
    test_single_cycle_real(2'b01, 5.5, 2.25); // 5.5 - 2.25 = 3.25
    test_single_cycle_real(2'b01, 0.5, 1.5);  // 0.5 - 1.5 = -1.0

    // -----------------------------------------------------------------------
    // Section 3: MUL Tests
    // -----------------------------------------------------------------------
    $display("\n--- Section 3: MUL Tests (ctl_d=10, 1 cycle) ---");
    test_single_cycle_int(2'b10, 2, 3);       // 2 * 3 = 6
    test_single_cycle_int(2'b10, -2, 3);      // -2 * 3 = -6
    test_single_cycle_int(2'b10, -2, -3);     // -2 * -3 = 6
    test_single_cycle_int(2'b10, 0, 5);       // 0 * 5 = 0
    test_single_cycle_real(2'b10, 1.5, 2.0);  // 1.5 * 2.0 = 3.0
    test_single_cycle_real(2'b10, 0.5, 0.5);  // 0.5 * 0.5 = 0.25
    test_single_cycle_real(2'b10, -1.5, 2.5); // -1.5 * 2.5 = -3.75

    // -----------------------------------------------------------------------
    // Section 4: DIV Tests (24 cycles per paper)
    // -----------------------------------------------------------------------
    $display("\n--- Section 4: DIV Tests (ctl_d=11, 24 cycles) ---");
    test_div_int(1, 1);       // 1/1 = 1.0
    test_div_int(1, 2);       // 1/2 = 0.5
    test_div_int(1, 4);       // 1/4 = 0.25
    test_div_int(2, 4);       // 2/4 = 0.5
    test_div_int(3, 2);       // 3/2 = 1.5
    test_div_int(6, 3);       // 6/3 = 2.0
    test_div_int(1, -2);      // 1/-2 = -0.5
    test_div_int(-1, 2);      // -1/2 = -0.5
    test_div_int(-4, 2);      // -4/2 = -2.0
    test_div_int(-4, -2);     // -4/-2 = 2.0

    // Fractional divisions (critical for Kalman gain calculation)
    $display("\n--- Section 5: Fractional DIV (Kalman gain scenarios) ---");
    test_div_real(1.01, 1.11);   // ~0.9099 (typical P/(P+R))
    test_div_real(0.5, 1.5);     // 0.333...
    test_div_real(2.5, 3.0);     // 0.833...
    test_div_real(0.1, 0.2);     // 0.5

    // -----------------------------------------------------------------------
    // Section 6: Combinational Timing Verification
    // -----------------------------------------------------------------------
    $display("\n--- Section 6: Combinational Timing Tests ---");
    test_comb_timing(2'b00, 1.0, 2.0);  // ADD should be comb valid
    test_comb_timing(2'b01, 3.0, 1.0);  // SUB should be comb valid
    test_comb_timing(2'b10, 2.0, 3.0);  // MUL should be comb valid
    test_comb_timing(2'b11, 4.0, 2.0);  // DIV should NOT be comb valid

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("\n================================================================");
    $display("Test Summary");
    $display("================================================================");
    $display("  Total:  %0d", pass_count + fail_count);
    $display("  Passed: %0d", pass_count);
    $display("  Failed: %0d", fail_count);
    $display("----------------------------------------------------------------");
    if (fail_count == 0)
      $display("  ALL TESTS PASSED!");
    else
      $display("  SOME TESTS FAILED!");
    $display("================================================================\n");

    $finish;
  end

endmodule
