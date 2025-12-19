// Created by ihdl
module router_a ( DATA_IN, result, ctl_a, ctl_b, DIR, WRITE, READY, sel_data, 
        sel_dira, sel_dirb, sel_write, data, dira, dirb, write );
  input [23:0] DATA_IN;
  input [23:0] result;
  input [4:0] ctl_a;
  input [4:0] ctl_b;
  input [4:0] DIR;
  input [1:0] sel_data;
  input [1:0] sel_write;
  output [23:0] data;
  output [4:0] dira;
  output [4:0] dirb;
  input WRITE, READY, sel_dira, sel_dirb;
  output write;
  wire   WRITE;
  assign dira[4] = ctl_a[4];
  assign dira[3] = ctl_a[3];
  assign dira[2] = ctl_a[2];
  assign dira[1] = ctl_a[1];
  assign dira[0] = ctl_a[0];
  assign dirb[4] = ctl_b[4];
  assign dirb[3] = ctl_b[3];
  assign dirb[2] = ctl_b[2];
  assign dirb[1] = ctl_b[1];
  assign dirb[0] = ctl_b[0];
  assign write = WRITE;

  MUX2D0 U3 ( .I0(DATA_IN[23]), .I1(result[23]), .S(sel_data[0]), .Z(data[23])
         );
  MUX2D0 U4 ( .I0(DATA_IN[21]), .I1(result[21]), .S(sel_data[0]), .Z(data[21])
         );
  MUX2D0 U5 ( .I0(DATA_IN[19]), .I1(result[19]), .S(sel_data[0]), .Z(data[19])
         );
  MUX2D0 U6 ( .I0(DATA_IN[17]), .I1(result[17]), .S(sel_data[0]), .Z(data[17])
         );
  MUX2D0 U7 ( .I0(DATA_IN[15]), .I1(result[15]), .S(sel_data[0]), .Z(data[15])
         );
  MUX2D0 U8 ( .I0(DATA_IN[13]), .I1(result[13]), .S(sel_data[0]), .Z(data[13])
         );
  MUX2D0 U9 ( .I0(DATA_IN[11]), .I1(result[11]), .S(sel_data[0]), .Z(data[11])
         );
  MUX2D0 U10 ( .I0(DATA_IN[9]), .I1(result[9]), .S(sel_data[0]), .Z(data[9])
         );
  MUX2D0 U11 ( .I0(DATA_IN[7]), .I1(result[7]), .S(sel_data[0]), .Z(data[7])
         );
  MUX2D0 U12 ( .I0(DATA_IN[5]), .I1(result[5]), .S(sel_data[0]), .Z(data[5])
         );
  MUX2D0 U13 ( .I0(DATA_IN[3]), .I1(result[3]), .S(sel_data[0]), .Z(data[3])
         );
  MUX2D0 U14 ( .I0(DATA_IN[2]), .I1(result[2]), .S(sel_data[0]), .Z(data[2])
         );
  MUX2D0 U15 ( .I0(DATA_IN[1]), .I1(result[1]), .S(sel_data[0]), .Z(data[1])
         );
  MUX2D0 U16 ( .I0(DATA_IN[0]), .I1(result[0]), .S(sel_data[0]), .Z(data[0])
         );
  MUX2D0 U17 ( .I0(DATA_IN[4]), .I1(result[4]), .S(sel_data[0]), .Z(data[4])
         );
  MUX2D0 U18 ( .I0(DATA_IN[6]), .I1(result[6]), .S(sel_data[0]), .Z(data[6])
         );
  MUX2D0 U19 ( .I0(DATA_IN[8]), .I1(result[8]), .S(sel_data[0]), .Z(data[8])
         );
  MUX2D0 U20 ( .I0(DATA_IN[10]), .I1(result[10]), .S(sel_data[0]), .Z(data[10]) );
  MUX2D0 U21 ( .I0(DATA_IN[12]), .I1(result[12]), .S(sel_data[0]), .Z(data[12]) );
  MUX2D0 U22 ( .I0(DATA_IN[14]), .I1(result[14]), .S(sel_data[0]), .Z(data[14]) );
  MUX2D0 U23 ( .I0(DATA_IN[16]), .I1(result[16]), .S(sel_data[0]), .Z(data[16]) );
  MUX2D0 U24 ( .I0(DATA_IN[18]), .I1(result[18]), .S(sel_data[0]), .Z(data[18]) );
  MUX2D0 U25 ( .I0(DATA_IN[20]), .I1(result[20]), .S(sel_data[0]), .Z(data[20]) );
  MUX2D0 U26 ( .I0(DATA_IN[22]), .I1(result[22]), .S(sel_data[0]), .Z(data[22]) );
endmodule
