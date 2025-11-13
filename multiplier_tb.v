`timescale 1ns/1ps
module multiplier_tb;
  parameter W=24, FRAC=14;

  reg  [W-1:0] X, Y;
  wire [W-1:0] M;

  multiplier #(.W(W), .FRAC(FRAC)) DUT (
    .X_sm(X), .Y_sm(Y), .M_sm(M)
  );

  // ---- helpers (SM <-> signed) ----
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

  // integer -> SM in Q(FRAC)
  function [W-1:0] q_of_int; input integer k;
    reg signed [W-1:0] t, a;
    reg sign;
    begin
      t    = k <<< FRAC;     // fixed-point shift
      sign = t[W-1];
      a    = sign ? -t : t;  // abs
      q_of_int = {sign, a[W-2:0]};
    end
  endfunction

  // golden multiply in Q(FRAC)
  function [W-1:0] gold_mul; input [W-1:0] A,B;
    reg s; reg [W-2:0] am,bm,sc,sat; reg [2*(W-1)-1:0] p,pr;
    begin
      s  = A[W-1] ^ B[W-1];
      am = A[W-2:0];
      bm = B[W-2:0];
      p  = am * bm;
      pr = p + {{(2*(W-1)-FRAC-1){1'b0}}, 1'b1, {FRAC{1'b0}}}; // +0.5 LSB
      sc = pr[2*(W-1)-1:FRAC];
      sat= (sc > {(W-1){1'b1}}) ? {(W-1){1'b1}} : sc;
      gold_mul = {s, sat};
    end
  endfunction

  integer i, errors, tests;
  integer a, b;  // declare at module scope (no init here)

  initial begin
    errors=0; tests=0;

    // directed: (-2) * 3 = -6
    X = q_of_int(-2);
    Y = q_of_int(3);
    #1; tests=tests+1;
    if (M !== gold_mul(X,Y)) begin
      $display("MUL dir mismatch exp=%h got=%h", gold_mul(X,Y), M);
      errors=errors+1;
    end

    // random small ints
    for (i=0; i<50; i=i+1) begin
      a = ($random % 8) - 4;   // -4..+3
      b = ($random % 8) - 4;
      X = q_of_int(a);
      Y = q_of_int(b);
      #1; tests=tests+1;
      if (M !== gold_mul(X,Y)) begin
        $display("MUL rnd mismatch a=%0d b=%0d exp=%h got=%h", a, b, gold_mul(X,Y), M);
        errors=errors+1;
      end
    end

    if (errors==0) $display("multiplier_tb: PASS (%0d tests)", tests);
    else           $display("multiplier_tb: %0d ERRORS / %0d tests", errors, tests);
    $finish;
  end
endmodule
