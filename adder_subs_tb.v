`timescale 1ns/1ps
module adder_subs_tb;
  parameter W=24;

  reg  [W-1:0] X, Y;
  reg          op_add;
  wire [W-1:0] SR;

  adder_subs #(.W(W)) DUT(.X_sm(X), .Y_sm(Y), .op_add(op_add), .SR_sm(SR));

  // ----- helpers (SM <-> signed) -----
  function [W:0] sm_to_tc; input [W-1:0] sm;
    begin
      sm_to_tc = sm[W-1] ? -{{1'b0}, sm[W-2:0]} : {{1'b0}, sm[W-2:0]};
    end
  endfunction

  function [W-1:0] tc_to_sm_sat; input signed [W:0] v;
    reg sign; reg signed [W:0] a; reg [W-2:0] mag;
    begin
      sign = (v < 0);
      a    = sign ? -v : v;
      mag  = (a[W-1:0] > {(W-1){1'b1}}) ? {(W-1){1'b1}} : a[W-1:0];
      tc_to_sm_sat = {sign, mag};
    end
  endfunction

  // int -> sign-magnitude (no Q scaling needed for add/sub TB)
  function [W-1:0] sm_of_int; input integer k;
    reg signed [W-1:0] t, a;
    reg sign;
    begin
      t    = k;
      sign = t[W-1];
      a    = sign ? -t : t;                 // abs(t)
      sm_of_int = {sign, a[W-2:0]};         // {sign, magnitude}
    end
  endfunction

  integer i, errors, tests;
  integer a, b;   // declare at module scope (no init here)

  initial begin
    errors=0; tests=0;

    // directed: 2 + 3 = 5
    X=sm_of_int(2); Y=sm_of_int(3); op_add=1; #1; tests=tests+1;
    if (SR !== tc_to_sm_sat(sm_to_tc(X)+sm_to_tc(Y))) begin
      $display("ADD dir mismatch exp=%h got=%h",
               tc_to_sm_sat(sm_to_tc(X)+sm_to_tc(Y)), SR);
      errors=errors+1;
    end

    // directed: 5 - 7 = -2
    X=sm_of_int(5); Y=sm_of_int(7); op_add=0; #1; tests=tests+1;
    if (SR !== tc_to_sm_sat(sm_to_tc(X)-sm_to_tc(Y))) begin
      $display("SUB dir mismatch exp=%h got=%h",
               tc_to_sm_sat(sm_to_tc(X)-sm_to_tc(Y)), SR);
      errors=errors+1;
    end

    // random small range (-16..+15)
    for (i=0;i<50;i=i+1) begin
      a = ($random % 32) - 16;
      b = ($random % 32) - 16;
      X = sm_of_int(a);
      Y = sm_of_int(b);
      op_add = $random;
      #1; tests=tests+1;
      if (SR !== tc_to_sm_sat(op_add ? (sm_to_tc(X)+sm_to_tc(Y))
                                     : (sm_to_tc(X)-sm_to_tc(Y)))) begin
        $display("RAND mismatch a=%0d b=%0d add=%0d exp=%h got=%h",
                 a, b, op_add,
                 tc_to_sm_sat(op_add ? (sm_to_tc(X)+sm_to_tc(Y))
                                     : (sm_to_tc(X)-sm_to_tc(Y))),
                 SR);
        errors=errors+1;
      end
    end

    if (errors==0) $display("adder_subs_tb: PASS (%0d tests)", tests);
    else           $display("adder_subs_tb: %0d ERRORS / %0d tests", errors, tests);
    $finish;
  end
endmodule
