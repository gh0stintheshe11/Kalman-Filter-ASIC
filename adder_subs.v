`timescale 1ns/1ps
module adder_subs #(parameter W=24)(
  input  [W-1:0] X_sm,     // sign-magnitude
  input  [W-1:0] Y_sm,     // sign-magnitude
  input          op_add,   // 1=add, 0=sub (X ± Y)
  output [W-1:0] SR_sm     // saturated sign-magnitude
);
  localparam [W-2:0] MAG_MAX = {(W-1){1'b1}};

  function [W:0] sm_to_tc; input [W-1:0] sm;
    begin sm_to_tc = sm[W-1] ? -{{1'b0}, sm[W-2:0]} : {{1'b0}, sm[W-2:0]}; end
  endfunction

  function [W-1:0] tc_to_sm_sat; input signed [W:0] v;
    reg sign; reg signed [W:0] a; reg [W-2:0] mag;
    begin
      sign = (v<0); a = sign ? -v : v;
      mag  = (a[W-1:0] > MAG_MAX) ? MAG_MAX : a[W-1:0];
      tc_to_sm_sat = {sign, mag};
    end
  endfunction

  wire signed [W:0] X_tc = sm_to_tc(X_sm);
  wire signed [W:0] Y_tc = sm_to_tc(Y_sm);
  wire signed [W:0] Z_tc = op_add ? (X_tc + Y_tc) : (X_tc - Y_tc);

  assign SR_sm = tc_to_sm_sat(Z_tc);
endmodule
