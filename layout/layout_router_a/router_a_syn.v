/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : N-2017.09
// Date      : Thu Dec 11 20:39:43 2025
/////////////////////////////////////////////////////////////


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
  wire   n53, n54, n55, n56, n57, n58, n59, n60, n61, n62, n63, n64, n65, n66,
         n67, n68, n69, n70, n71, n72, n73, n74, n75, n76, n77, n78, n79, n80;

  INVD0 U66 ( .I(sel_write[0]), .ZN(n79) );
  AOI22D0 U67 ( .A1(sel_data[0]), .A2(result[0]), .B1(n76), .B2(DATA_IN[0]), 
        .ZN(n78) );
  AOI22D0 U68 ( .A1(sel_data[0]), .A2(result[10]), .B1(n76), .B2(DATA_IN[10]), 
        .ZN(n65) );
  CKND2D0 U69 ( .A1(n78), .A2(n77), .ZN(data[0]) );
  CKND2D0 U70 ( .A1(n66), .A2(n77), .ZN(data[9]) );
  MUX2D0 U71 ( .I0(ctl_a[4]), .I1(DIR[4]), .S(sel_dira), .Z(dira[4]) );
  MUX2D0 U72 ( .I0(ctl_a[3]), .I1(DIR[3]), .S(sel_dira), .Z(dira[3]) );
  MUX2D0 U73 ( .I0(ctl_a[2]), .I1(DIR[2]), .S(sel_dira), .Z(dira[2]) );
  MUX2D0 U74 ( .I0(ctl_a[1]), .I1(DIR[1]), .S(sel_dira), .Z(dira[1]) );
  MUX2D0 U75 ( .I0(ctl_a[0]), .I1(DIR[0]), .S(sel_dira), .Z(dira[0]) );
  MUX2D0 U76 ( .I0(ctl_b[4]), .I1(DIR[4]), .S(sel_dirb), .Z(dirb[4]) );
  MUX2D0 U77 ( .I0(ctl_b[3]), .I1(DIR[3]), .S(sel_dirb), .Z(dirb[3]) );
  MUX2D0 U78 ( .I0(ctl_b[2]), .I1(DIR[2]), .S(sel_dirb), .Z(dirb[2]) );
  MUX2D0 U79 ( .I0(ctl_b[1]), .I1(DIR[1]), .S(sel_dirb), .Z(dirb[1]) );
  MUX2D0 U80 ( .I0(ctl_b[0]), .I1(DIR[0]), .S(sel_dirb), .Z(dirb[0]) );
  NR2D0 U81 ( .A1(sel_data[0]), .A2(sel_data[1]), .ZN(n76) );
  AOI22D0 U82 ( .A1(sel_data[0]), .A2(result[22]), .B1(n76), .B2(DATA_IN[22]), 
        .ZN(n53) );
  CKND2D0 U83 ( .A1(sel_data[0]), .A2(sel_data[1]), .ZN(n77) );
  CKND2D0 U84 ( .A1(n53), .A2(n77), .ZN(data[22]) );
  AOI22D0 U85 ( .A1(sel_data[0]), .A2(result[21]), .B1(n76), .B2(DATA_IN[21]), 
        .ZN(n54) );
  CKND2D0 U86 ( .A1(n54), .A2(n77), .ZN(data[21]) );
  AOI22D0 U87 ( .A1(sel_data[0]), .A2(result[20]), .B1(n76), .B2(DATA_IN[20]), 
        .ZN(n55) );
  CKND2D0 U88 ( .A1(n55), .A2(n77), .ZN(data[20]) );
  AOI22D0 U89 ( .A1(sel_data[0]), .A2(result[19]), .B1(n76), .B2(DATA_IN[19]), 
        .ZN(n56) );
  CKND2D0 U90 ( .A1(n56), .A2(n77), .ZN(data[19]) );
  AOI22D0 U91 ( .A1(sel_data[0]), .A2(result[18]), .B1(n76), .B2(DATA_IN[18]), 
        .ZN(n57) );
  CKND2D0 U92 ( .A1(n57), .A2(n77), .ZN(data[18]) );
  AOI22D0 U93 ( .A1(sel_data[0]), .A2(result[17]), .B1(n76), .B2(DATA_IN[17]), 
        .ZN(n58) );
  CKND2D0 U94 ( .A1(n58), .A2(n77), .ZN(data[17]) );
  AOI22D0 U95 ( .A1(sel_data[0]), .A2(result[16]), .B1(n76), .B2(DATA_IN[16]), 
        .ZN(n59) );
  CKND2D0 U96 ( .A1(n59), .A2(n77), .ZN(data[16]) );
  AOI22D0 U97 ( .A1(sel_data[0]), .A2(result[15]), .B1(n76), .B2(DATA_IN[15]), 
        .ZN(n60) );
  CKND2D0 U98 ( .A1(n60), .A2(n77), .ZN(data[15]) );
  AOI22D0 U99 ( .A1(sel_data[0]), .A2(result[14]), .B1(n76), .B2(DATA_IN[14]), 
        .ZN(n61) );
  CKND2D0 U100 ( .A1(n61), .A2(n77), .ZN(data[14]) );
  AOI22D0 U101 ( .A1(sel_data[0]), .A2(result[13]), .B1(n76), .B2(DATA_IN[13]), 
        .ZN(n62) );
  CKND2D0 U102 ( .A1(n62), .A2(n77), .ZN(data[13]) );
  AOI22D0 U103 ( .A1(sel_data[0]), .A2(result[12]), .B1(n76), .B2(DATA_IN[12]), 
        .ZN(n63) );
  CKND2D0 U104 ( .A1(n63), .A2(n77), .ZN(data[12]) );
  AOI22D0 U105 ( .A1(sel_data[0]), .A2(result[11]), .B1(n76), .B2(DATA_IN[11]), 
        .ZN(n64) );
  CKND2D0 U106 ( .A1(n64), .A2(n77), .ZN(data[11]) );
  CKND2D0 U107 ( .A1(n65), .A2(n77), .ZN(data[10]) );
  AOI22D0 U108 ( .A1(sel_data[0]), .A2(result[9]), .B1(n76), .B2(DATA_IN[9]), 
        .ZN(n66) );
  AOI22D0 U109 ( .A1(sel_data[0]), .A2(result[8]), .B1(n76), .B2(DATA_IN[8]), 
        .ZN(n67) );
  CKND2D0 U110 ( .A1(n67), .A2(n77), .ZN(data[8]) );
  AOI22D0 U111 ( .A1(sel_data[0]), .A2(result[7]), .B1(n76), .B2(DATA_IN[7]), 
        .ZN(n68) );
  CKND2D0 U112 ( .A1(n68), .A2(n77), .ZN(data[7]) );
  AOI22D0 U113 ( .A1(sel_data[0]), .A2(result[6]), .B1(n76), .B2(DATA_IN[6]), 
        .ZN(n69) );
  CKND2D0 U114 ( .A1(n69), .A2(n77), .ZN(data[6]) );
  AOI22D0 U115 ( .A1(sel_data[0]), .A2(result[23]), .B1(n76), .B2(DATA_IN[23]), 
        .ZN(n70) );
  CKND2D0 U116 ( .A1(n70), .A2(n77), .ZN(data[23]) );
  AOI22D0 U117 ( .A1(sel_data[0]), .A2(result[5]), .B1(n76), .B2(DATA_IN[5]), 
        .ZN(n71) );
  CKND2D0 U118 ( .A1(n71), .A2(n77), .ZN(data[5]) );
  AOI22D0 U119 ( .A1(sel_data[0]), .A2(result[4]), .B1(n76), .B2(DATA_IN[4]), 
        .ZN(n72) );
  CKND2D0 U120 ( .A1(n72), .A2(n77), .ZN(data[4]) );
  AOI22D0 U121 ( .A1(sel_data[0]), .A2(result[3]), .B1(n76), .B2(DATA_IN[3]), 
        .ZN(n73) );
  CKND2D0 U122 ( .A1(n73), .A2(n77), .ZN(data[3]) );
  AOI22D0 U123 ( .A1(sel_data[0]), .A2(result[2]), .B1(n76), .B2(DATA_IN[2]), 
        .ZN(n74) );
  CKND2D0 U124 ( .A1(n74), .A2(n77), .ZN(data[2]) );
  AOI22D0 U125 ( .A1(sel_data[0]), .A2(result[1]), .B1(n76), .B2(DATA_IN[1]), 
        .ZN(n75) );
  CKND2D0 U126 ( .A1(n75), .A2(n77), .ZN(data[1]) );
  OAI21D0 U127 ( .A1(n79), .A2(READY), .B(WRITE), .ZN(n80) );
  MUX2ND0 U128 ( .I0(n80), .I1(n79), .S(sel_write[1]), .ZN(write) );
endmodule

