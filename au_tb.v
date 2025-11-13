`timescale 1ns/1ps
module au_tb;

  parameter W=24;
  parameter FRAC=14;

  // DUT I/O
  reg               clk, start;
  reg  [W-1:0]      R_in, S_in, Iimm_in;
  reg  [1:0]        op_sel, mul_y_sel;
  wire [W-1:0]      result;
  wire              done, busy;

  au #(.W(W), .FRAC(FRAC)) DUT (
    .clk(clk), .start(start),
    .R_in(R_in), .S_in(S_in), .Iimm_in(Iimm_in),
    .op_sel(op_sel), .mul_y_sel(mul_y_sel),
    .result(result), .done(done), .busy(busy)
  );

  // Clock
  initial clk=0;
  always #5 clk=~clk;

  // Helpers: build sign-magnitude from signed integer (Q format)
  function [W-1:0] tc_to_sm;
    input signed [W-1:0] v; // two's complement
    reg sign;
    reg signed [W-1:0] a;
    begin
      sign = (v < 0);
      a    = sign ? -v : v;
      if (a[W-2:0] > {(W-1){1'b1}}) a[W-2:0] = {(W-1){1'b1}};
      tc_to_sm = {sign, a[W-2:0]};
    end
  endfunction

  function signed [W-1:0] sm_to_tc;
    input [W-1:0] sm;
    begin
      sm_to_tc = sm[W-1] ? -$signed({1'b0,sm[W-2:0]}) : $signed({1'b0,sm[W-2:0]});
    end
  endfunction

  // Golden models (integer arithmetic with Q scaling)
  function [W-1:0] gold_add;
    input [W-1:0] a,b;
    reg signed [W:0] t;
    begin
      t = sm_to_tc(a) + sm_to_tc(b);
      // saturate to sign-magnitude
      if (t > $signed({1'b0,{(W-1){1'b1}}})) t = $signed({1'b0,{(W-1){1'b1}}});
      if (t < -$signed({1'b0,{(W-1){1'b1}}})) t = -$signed({1'b0,{(W-1){1'b1}}});
      gold_add = tc_to_sm(t[W-1:0]);
    end
  endfunction

  function [W-1:0] gold_sub;
    input [W-1:0] a,b;
    reg signed [W:0] t;
    begin
      t = sm_to_tc(a) - sm_to_tc(b);
      if (t > $signed({1'b0,{(W-1){1'b1}}})) t = $signed({1'b0,{(W-1){1'b1}}});
      if (t < -$signed({1'b0,{(W-1){1'b1}}})) t = -$signed({1'b0,{(W-1){1'b1}}});
      gold_sub = tc_to_sm(t[W-1:0]);
    end
  endfunction

  function [W-1:0] gold_mul;
    input [W-1:0] a,b;
    reg sign;
    reg [W-2:0] am,bm;
    reg [2*(W-1)-1:0] p, pr;
    reg [W-2:0] sc, sat;
    begin
      sign = a[W-1]^b[W-1];
      am   = a[W-2:0]; bm = b[W-2:0];
      p    = am * bm;
      pr   = p + {{(2*(W-1)-FRAC-1){1'b0}}, 1'b1, {FRAC{1'b0}}}; // +0.5 LSB
      sc   = pr[2*(W-1)-1:FRAC];
      sat  = sc > {(W-1){1'b1}} ? {(W-1){1'b1}} : sc;
      gold_mul = {sign, sat};
    end
  endfunction

  function [W-1:0] gold_div; // a / b  => a * inv(b)
    input [W-1:0] a,b;
    reg sign;
    reg [W-2:0] am,bm;
    reg [W-2:0] invb;
    reg [2*(W-1)-1:0] p, pr;
    reg [W-2:0] sc, sat;
    reg [2*FRAC+W:0] N;
    begin
      sign = a[W-1]^b[W-1];
      am   = a[W-2:0]; bm = b[W-2:0];
      if (bm == { (W-1){1'b0} }) bm = {{(W-2){1'b0}},1'b1}; // tiny
      N    = {{(W-1){1'b0}}, 1'b1, {(2*FRAC){1'b0}}};      // 1<<(2*FRAC)
      invb = (N / { {(W-1){1'b0}}, bm})[W-2:0];            // trunc
      p    = am * invb;
      pr   = p + {{(2*(W-1)-FRAC-1){1'b0}}, 1'b1, {FRAC{1'b0}}};
      sc   = pr[2*(W-1)-1:FRAC];
      sat  = sc > {(W-1){1'b1}} ? {(W-1){1'b1}} : sc;
      gold_div = {sign, sat};
    end
  endfunction

  // Test sequence
  integer i, errors, tests;
  task kick_simple;
    input [1:0] op;
    begin
      op_sel     = op;
      mul_y_sel  = 2'b00; // S as Y by default
      start      = 1'b1; @(posedge clk);
      start      = 1'b0; @(posedge clk);
      tests = tests + 1;
    end
  endtask

  task kick_mul_y;
    input [1:0] ysel; // 00=S, 01=Iimm, 10=inv(S)
    begin
      op_sel     = 2'b10;
      mul_y_sel  = ysel;
      start      = 1'b1; @(posedge clk);
      start      = 1'b0;
      if (ysel==2'b10) begin
        // wait reciprocal
        while (!done) @(posedge clk);
      end else begin
        @(posedge clk); // simple mul result next cycle
      end
      tests = tests + 1;
    end
  endtask

  // Build some handy constants (Q14)
  function [W-1:0] q_of_int;
    input integer k;
    reg signed [W-1:0] tc;
    begin
      tc = k <<< FRAC; // shift left FRAC
      q_of_int = tc_to_sm(tc);
    end
  endfunction

  initial begin
    clk=0; start=0; op_sel=0; mul_y_sel=0;
    Iimm_in = q_of_int(1); // +1

    errors=0; tests=0;

    // Deterministic checks
    R_in = q_of_int(2); S_in = q_of_int(3);
      kick_simple(2'b00); // ADD
      if (result !== gold_add(R_in,S_in)) begin
        $display("ADD mismatch exp=%h got=%h", gold_add(R_in,S_in), result);
        errors=errors+1;
      end
    R_in = q_of_int(5); S_in = q_of_int(7);
      kick_simple(2'b01); // SUB
      if (result !== gold_sub(R_in,S_in)) begin
        $display("SUB mismatch exp=%h got=%h", gold_sub(R_in,S_in), result);
        errors=errors+1;
      end
    R_in = q_of_int(-2); S_in = q_of_int(3);
      kick_mul_y(2'b00);  // MUL R*S
      if (result !== gold_mul(R_in,S_in)) begin
        $display("MUL mismatch exp=%h got=%h", gold_mul(R_in,S_in), result);
        errors=errors+1;
      end
    R_in = q_of_int(4); S_in = q_of_int(2);
      op_sel=2'b11; mul_y_sel=2'b10; // DIV = R*(1/S)
      start=1'b1; @(posedge clk); start=1'b0;
      while (!done) @(posedge clk);
      if (result !== gold_div(R_in,S_in)) begin
        $display("DIV mismatch exp=%h got=%h", gold_div(R_in,S_in), result);
        errors=errors+1;
      end

    // Randomized small-range tests (avoid tiny denominators)
    for (i=0;i<50;i=i+1) begin
      reg signed [15:0] a, b;
      a = ($random % 8) - 4; // -4..+3
      b = (($random % 7) + 1); // 1..7
      R_in = tc_to_sm(a <<< FRAC);
      S_in = tc_to_sm(b <<< FRAC);

      // ADD
      kick_simple(2'b00);
      if (result !== gold_add(R_in,S_in)) begin
        $display("ADD rnd mismatch exp=%h got=%h", gold_add(R_in,S_in), result);
        errors=errors+1;
      end
      // SUB
      kick_simple(2'b01);
      if (result !== gold_sub(R_in,S_in)) begin
        $display("SUB rnd mismatch exp=%h got=%h", gold_sub(R_in,S_in), result);
        errors=errors+1;
      end
      // MUL
      kick_mul_y(2'b00);
      if (result !== gold_mul(R_in,S_in)) begin
        $display("MUL rnd mismatch exp=%h got=%h", gold_mul(R_in,S_in), result);
        errors=errors+1;
      end
      // DIV
      op_sel=2'b11; mul_y_sel=2'b10;
      start=1'b1; @(posedge clk); start=1'b0; while (!done) @(posedge clk);
      if (result !== gold_div(R_in,S_in)) begin
        $display("DIV rnd mismatch exp=%h got=%h", gold_div(R_in,S_in), result);
        errors=errors+1;
      end
    end

    if (errors==0) $display("au_tb: PASS (%0d checks)", tests);
    else           $display("au_tb: %0d ERRORS (%0d checks)", errors, tests);

    $finish;
  end
endmodule
