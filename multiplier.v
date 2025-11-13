`timescale 1ns/1ps
module multiplier #(parameter W=24, parameter FRAC=14)(
  input  [W-1:0] X_sm,   // sign-magnitude
  input  [W-1:0] Y_sm,   // sign-magnitude
  output [W-1:0] M_sm    // saturated sign-magnitude
);
  localparam [W-2:0] MAG_MAX={(W-1){1'b1}};

  wire sign = X_sm[W-1] ^ Y_sm[W-1];
  wire [W-2:0] xm = X_sm[W-2:0];
  wire [W-2:0] ym = Y_sm[W-2:0];

  wire [2*(W-1)-1:0] p  = xm * ym;
  wire [2*(W-1)-1:0] pr = p + {{(2*(W-1)-FRAC-1){1'b0}},1'b1,{FRAC{1'b0}}}; // +0.5 LSB
  wire [W-2:0]       sc = pr[2*(W-1)-1:FRAC];
  wire [W-2:0]       sat= (sc > MAG_MAX) ? MAG_MAX : sc;

  assign M_sm = {sign, sat};
endmodule
