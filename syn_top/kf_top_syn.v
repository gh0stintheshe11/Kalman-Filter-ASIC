/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : N-2017.09
// Date      : Tue Dec  9 18:44:28 2025
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
  wire   n17, n36;

  DFQD1 ready_reg ( .D(n17), .CP(clk), .Q(ready) );
  INVD0 U3 ( .I(start), .ZN(n36) );
  IOA21D0 U4 ( .A1(ready), .A2(n36), .B(rst_n), .ZN(n17) );
endmodule


module kf_top ( clk, rst_n, start, data_in, ready, result_out, au_done );
  input [23:0] data_in;
  output [23:0] result_out;
  input clk, rst_n, start;
  output ready, au_done;
  wire   \result_out[22] , net56442, net56443, net56444, net56445, net56446,
         net56447, net56448, net56449, net56450, net56451, net56452, net56453,
         net56454, net56455, net56456, net56457, net56458, net56459, net56460,
         net56461, net56462, net56463, net56464, net56465, net56466;
  assign result_out[23] = \result_out[22] ;
  assign result_out[0] = \result_out[22] ;
  assign result_out[1] = \result_out[22] ;
  assign result_out[2] = \result_out[22] ;
  assign result_out[3] = \result_out[22] ;
  assign result_out[4] = \result_out[22] ;
  assign result_out[5] = \result_out[22] ;
  assign result_out[6] = \result_out[22] ;
  assign result_out[7] = \result_out[22] ;
  assign result_out[8] = \result_out[22] ;
  assign result_out[9] = \result_out[22] ;
  assign result_out[10] = \result_out[22] ;
  assign result_out[11] = \result_out[22] ;
  assign result_out[12] = \result_out[22] ;
  assign result_out[13] = \result_out[22] ;
  assign result_out[14] = \result_out[22] ;
  assign result_out[15] = \result_out[22] ;
  assign result_out[16] = \result_out[22] ;
  assign result_out[17] = \result_out[22] ;
  assign result_out[18] = \result_out[22] ;
  assign result_out[19] = \result_out[22] ;
  assign result_out[20] = \result_out[22] ;
  assign result_out[21] = \result_out[22] ;
  assign result_out[22] = \result_out[22] ;

  sequencer Sequencer ( .clk(clk), .rst_n(rst_n), .start(start), .continue_i(
        au_done), .rom_we(net56442), .rom_waddr({net56443, net56444, net56445, 
        net56446, net56447, net56448, net56449, net56450}), .rom_wdata({
        net56451, net56452, net56453, net56454, net56455, net56456, net56457, 
        net56458, net56459, net56460, net56461, net56462, net56463, net56464, 
        net56465, net56466}), .ready(ready) );
  TIEL U17 ( .ZN(au_done) );
  TIEH U18 ( .Z(\result_out[22] ) );
endmodule

