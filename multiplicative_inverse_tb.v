`timescale 1ns/1ps
module multiplicative_inverse_tb;
  parameter W=24, FRAC=14;

  reg               clk, rst, start;
  reg  [W-2:0]      den_mag;
  wire [W-2:0]      q_mag;
  wire              rdy;

  multiplicative_inverse #(.W(W),.FRAC(FRAC)) DUT(
    .clk(clk), .rst(rst), .start(start),
    .den_mag(den_mag), .q_mag(q_mag), .rdy(rdy)
  );

  // Clock
  initial clk=0; always #5 clk=~clk;

  // Module-scope temps
  integer i, k, errors, tests;
  reg [2*FRAC+W:0] N, qtmp;

  task kick_and_check;
    input [W-2:0] dmag;
    reg   [W-2:0] exp;
    begin
      // clamp zero to tiny nonzero (caller responsibility per paper)
      den_mag = (dmag=={(W-1){1'b0}}) ? {{(W-2){1'b0}},1'b1} : dmag;

      // golden: floor((1<<(2*FRAC))/den_mag)
      N    = {{(W-1){1'b0}}, 1'b1, {(2*FRAC){1'b0}}};
      qtmp = N / { {(W-1){1'b0}}, den_mag };
      exp  = qtmp[W-2:0];

      // fire
      start=1'b1; @(posedge clk); start=1'b0;

      // wait with watchdog
      k=0;
      while (!rdy && k<3*W) begin @(posedge clk); k=k+1; end
      #1; tests=tests+1;

      if (!rdy) begin
        $display("TIMEOUT for den_mag=%h", den_mag); errors=errors+1;
      end else if (q_mag !== exp) begin
        $display("INV mismatch den=%h exp=%h got=%h", den_mag, exp, q_mag); errors=errors+1;
      end
    end
  endtask

  initial begin
    // reset per paper
    rst=1; start=0; den_mag=0; errors=0; tests=0;
    repeat(2) @(posedge clk);
    rst=0;
    repeat(1) @(posedge clk);

    // directed
    kick_and_check(24'd1);
    kick_and_check(24'd2);
    kick_and_check(24'd3);
    kick_and_check(24'd10);

    // a few random magnitudes (small-ish)
    for (i=0;i<10;i=i+1) begin
      kick_and_check($random & 16'h3FFF);
    end

    if (errors==0) $display("multiplicative_inverse_tb: PASS (%0d tests)", tests);
    else           $display("multiplicative_inverse_tb: %0d ERRORS / %0d tests", errors, tests);
    $finish;
  end
endmodule
