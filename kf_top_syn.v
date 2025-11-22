/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : N-2017.09
// Date      : Fri Nov 21 07:54:45 2025
/////////////////////////////////////////////////////////////


module sequencer ( clk, rst_n, start, continue_i, rom_we, rom_waddr, rom_wdata, 
        ctl_a, ctl_b, ctl_c, ctl_d, ctl_e, ready, pc_dbg );
  input [7:0] rom_waddr;
  input [15:0] rom_wdata;
  output [4:0] ctl_a;
  output [4:0] ctl_b;
  output [1:0] ctl_c;
  output [1:0] ctl_d;
  output [1:0] ctl_e;
  output [7:0] pc_dbg;
  input clk, rst_n, start, continue_i, rom_we;
  output ready;
  wire   n1, n2;

  DFQD1 ready_reg ( .D(n2), .CP(clk), .Q(ready) );
  INVD0 U23 ( .I(ready), .ZN(n1) );
  OAI21D0 U24 ( .A1(start), .A2(n1), .B(rst_n), .ZN(n2) );
endmodule


module kf_top ( clk, rst_n, start, data_in, ready, result_out, au_done );
  input [23:0] data_in;
  output [23:0] result_out;
  input clk, rst_n, start;
  output ready, au_done;
  wire   au_done, net74097, net74098, net74099, net74100, net74101, net74102,
         net74103, net74104, net74105, net74106, net74107, net74108, net74109,
         net74110, net74111, net74112, net74113, net74114, net74115, net74116,
         net74117, net74118, net74119, net74120, net74121;
  assign result_out[23] = au_done;
  assign result_out[22] = au_done;
  assign result_out[21] = au_done;
  assign result_out[20] = au_done;
  assign result_out[19] = au_done;
  assign result_out[18] = au_done;
  assign result_out[17] = au_done;
  assign result_out[16] = au_done;
  assign result_out[15] = au_done;
  assign result_out[14] = au_done;
  assign result_out[13] = au_done;
  assign result_out[12] = au_done;
  assign result_out[11] = au_done;
  assign result_out[10] = au_done;
  assign result_out[9] = au_done;
  assign result_out[8] = au_done;
  assign result_out[7] = au_done;
  assign result_out[6] = au_done;
  assign result_out[5] = au_done;
  assign result_out[4] = au_done;
  assign result_out[3] = au_done;
  assign result_out[2] = au_done;
  assign result_out[1] = au_done;
  assign result_out[0] = au_done;

  sequencer Sequencer ( .clk(clk), .rst_n(rst_n), .start(start), .continue_i(
        au_done), .rom_we(net74097), .rom_waddr({net74098, net74099, net74100, 
        net74101, net74102, net74103, net74104, net74105}), .rom_wdata({
        net74106, net74107, net74108, net74109, net74110, net74111, net74112, 
        net74113, net74114, net74115, net74116, net74117, net74118, net74119, 
        net74120, net74121}), .ready(ready) );
  TIEL U531 ( .ZN(au_done) );
endmodule

