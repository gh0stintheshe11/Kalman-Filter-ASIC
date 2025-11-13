// Kalman Filter Test Program
// Implements 1D Kalman Filter iteration
//
// Memory Allocation:
// DB[0] = x_prev     (previous state estimate)
// DB[1] = P_prev     (previous error covariance)
// DB[2] = Q          (process noise)
// DB[3] = R          (measurement noise)
// DB[4] = z          (measurement)
// DB[5] = x_pred     (predicted state)
// DB[6] = P_pred     (predicted covariance)
// DB[7] = K          (Kalman gain)
// DB[8] = innovation (z - x_pred)
// DB[9] = x_new      (updated state)
// DB[10] = P_new     (updated covariance)
// DB[11] = temp1     (temporary storage)
// DB[12] = temp2     (temporary storage)
// DB[13] = ONE       (constant 1.0)

// 1D Kalman Filter Equations:
// Prediction:
//   x_pred = x_prev  (assuming A=1, no control input)
//   P_pred = P_prev + Q
//
// Update:
//   K = P_pred / (P_pred + R)
//   innovation = z - x_pred
//   x_new = x_pred + K * innovation
//   P_new = (1 - K) * P_pred

`timescale 1ns/1ps

module kf_1d_tb;
  parameter W = 24;
  parameter FRAC = 14;
  parameter ADDRW = 6;
  
  // DUT signals
  reg clk, rst_n;
  reg start;
  reg [W-1:0] data_in;
  wire ready;
  wire [W-1:0] result_out;
  wire au_done;
  
  // Test tracking
  integer errors = 0;
  integer checks = 0;
  
  // DUT instantiation
  kf_top #(.W(W), .FRAC(FRAC), .ADDRW(ADDRW)) DUT (
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
  
  // Create Q format value from integer
  function [W-1:0] q_of_int;
    input integer k;
    reg signed [W-1:0] tc;
    begin
      tc = k <<< FRAC;
      q_of_int = tc_to_sm(tc);
    end
  endfunction
  
  // Create Q format value from real (for small fractional values)
  function [W-1:0] q_of_real;
    input real r;
    reg signed [W-1:0] tc;
    begin
      tc = $rtoi(r * (1 << FRAC));
      q_of_real = tc_to_sm(tc);
    end
  endfunction
  
  // Display sign-magnitude value
  task display_sm;
    input [W-1:0] val;
    input [80*8-1:0] label;
    reg signed [W-1:0] tc;
    real decimal;
    begin
      tc = sm_to_tc(val);
      decimal = $itor(tc) / (1 << FRAC);
      $display("%80s: sm=%06h tc=%06h decimal=%f", label, val, tc, decimal);
    end
  endtask
  
  // Load value to memory via ROM program
  task load_value;
    input [ADDRW-1:0] addr;
    input [W-1:0] value;
    begin
      // Program sequencer to load value
      // ROM already programmed, just provide data_in at right time
      data_in = value;
      @(posedge clk);
      #1;
    end
  endtask
  
  // Test value registers (declare at module level)
  reg [W-1:0] x_prev, P_prev, Q, R, z, ONE;
  reg [W-1:0] expected_P_pred, expected_K, expected_x_new, expected_P_new;
  
  // Initial test
  initial begin
    $display("\n========================================");
    $display("1D Kalman Filter Test");
    $display("========================================");
    
    // Initialize
    rst_n = 0;
    start = 0;
    data_in = 0;
    
    // Initial conditions
    x_prev = q_of_real(0.0);      // x_prev = 0.0
    P_prev = q_of_real(1.0);      // P_prev = 1.0
    Q = q_of_real(0.1);           // Q = 0.1 (process noise)
    R = q_of_real(0.5);           // R = 0.5 (measurement noise)
    z = q_of_real(1.5);           // z = 1.5 (measurement)
    ONE = q_of_real(1.0);         // constant 1.0
    
    // Expected results (pre-calculated)
    expected_P_pred = q_of_real(1.1);      // P_pred = 1.0 + 0.1 = 1.1
    expected_K = q_of_real(0.6875);        // K = 1.1 / 1.6 = 0.6875
    expected_x_new = q_of_real(1.03125);   // x = 0 + 0.6875*1.5 = 1.03125
    expected_P_new = q_of_real(0.34375);   // P = 0.3125*1.1 = 0.34375
    
    $display("\nTest inputs:");
    display_sm(x_prev, "x_prev (initial state)");
    display_sm(P_prev, "P_prev (initial covariance)");
    display_sm(Q, "Q (process noise)");
    display_sm(R, "R (measurement noise)");
    display_sm(z, "z (measurement)");
    
    $display("\nExpected outputs:");
    display_sm(expected_P_pred, "P_pred");
    display_sm(expected_K, "K (Kalman gain)");
    display_sm(expected_x_new, "x_new");
    display_sm(expected_P_new, "P_new");
    
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
    
    // TODO: Need to program ROM with Kalman Filter algorithm
    // For now, this is a placeholder showing what needs to be implemented
    
    $display("\n========================================");
    $display("NOTE: Full Kalman Filter program needs to be");
    $display("implemented in sequencer ROM. Current test only");
    $display("shows the framework.");
    $display("========================================");
    
    $display("\nNext steps:");
    $display("1. Program ROM with KF prediction equations");
    $display("2. Program ROM with KF update equations");
    $display("3. Test DIV operation (for Kalman gain K = P/(P+R))");
    $display("4. Verify all intermediate results");
    
    #100;
    $finish;
  end
  
  // Timeout watchdog
  initial begin
    #10000;
    $display("\nERROR: Simulation timeout!");
    $finish;
  end

endmodule
