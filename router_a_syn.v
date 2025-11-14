/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : N-2017.09
// Date      : Fri Nov 14 00:47:36 2025
/////////////////////////////////////////////////////////////


module router_a ( DATA_IN, RESULT, CTL_A, CTL_B, DIR_EXT, WRITE_REQ, READY, 
        sel_data, sel_dira, sel_dirb, sel_write, db_data, db_dira, db_dirb, 
        db_write );
  input [23:0] DATA_IN;
  input [23:0] RESULT;
  input [4:0] CTL_A;
  input [4:0] CTL_B;
  input [4:0] DIR_EXT;
  input [1:0] sel_data;
  input [1:0] sel_write;
  output [23:0] db_data;
  output [4:0] db_dira;
  output [4:0] db_dirb;
  input WRITE_REQ, READY, sel_dira, sel_dirb;
  output db_write;
  wire   n28, n29, n30;

  INVD0 U41 ( .I(sel_write[0]), .ZN(n29) );
  NR2XD0 U42 ( .A1(sel_data[1]), .A2(sel_data[0]), .ZN(n28) );
  AO22D0 U43 ( .A1(sel_data[0]), .A2(RESULT[22]), .B1(n28), .B2(DATA_IN[22]), 
        .Z(db_data[22]) );
  AO22D0 U44 ( .A1(sel_data[0]), .A2(RESULT[21]), .B1(n28), .B2(DATA_IN[21]), 
        .Z(db_data[21]) );
  AO22D0 U45 ( .A1(sel_data[0]), .A2(RESULT[20]), .B1(n28), .B2(DATA_IN[20]), 
        .Z(db_data[20]) );
  AO22D0 U46 ( .A1(sel_data[0]), .A2(RESULT[19]), .B1(n28), .B2(DATA_IN[19]), 
        .Z(db_data[19]) );
  AO22D0 U47 ( .A1(sel_data[0]), .A2(RESULT[18]), .B1(n28), .B2(DATA_IN[18]), 
        .Z(db_data[18]) );
  AO22D0 U48 ( .A1(sel_data[0]), .A2(RESULT[17]), .B1(n28), .B2(DATA_IN[17]), 
        .Z(db_data[17]) );
  AO22D0 U49 ( .A1(sel_data[0]), .A2(RESULT[16]), .B1(n28), .B2(DATA_IN[16]), 
        .Z(db_data[16]) );
  AO22D0 U50 ( .A1(sel_data[0]), .A2(RESULT[15]), .B1(n28), .B2(DATA_IN[15]), 
        .Z(db_data[15]) );
  AO22D0 U51 ( .A1(sel_data[0]), .A2(RESULT[14]), .B1(n28), .B2(DATA_IN[14]), 
        .Z(db_data[14]) );
  AO22D0 U52 ( .A1(sel_data[0]), .A2(RESULT[13]), .B1(n28), .B2(DATA_IN[13]), 
        .Z(db_data[13]) );
  AO22D0 U53 ( .A1(sel_data[0]), .A2(RESULT[12]), .B1(n28), .B2(DATA_IN[12]), 
        .Z(db_data[12]) );
  AO22D0 U54 ( .A1(sel_data[0]), .A2(RESULT[11]), .B1(n28), .B2(DATA_IN[11]), 
        .Z(db_data[11]) );
  AO22D0 U55 ( .A1(sel_data[0]), .A2(RESULT[10]), .B1(n28), .B2(DATA_IN[10]), 
        .Z(db_data[10]) );
  AO22D0 U56 ( .A1(sel_data[0]), .A2(RESULT[9]), .B1(n28), .B2(DATA_IN[9]), 
        .Z(db_data[9]) );
  AO22D0 U57 ( .A1(sel_data[0]), .A2(RESULT[8]), .B1(n28), .B2(DATA_IN[8]), 
        .Z(db_data[8]) );
  AO22D0 U58 ( .A1(sel_data[0]), .A2(RESULT[7]), .B1(n28), .B2(DATA_IN[7]), 
        .Z(db_data[7]) );
  AO22D0 U59 ( .A1(sel_data[0]), .A2(RESULT[6]), .B1(n28), .B2(DATA_IN[6]), 
        .Z(db_data[6]) );
  AO22D0 U60 ( .A1(sel_data[0]), .A2(RESULT[23]), .B1(n28), .B2(DATA_IN[23]), 
        .Z(db_data[23]) );
  AO22D0 U61 ( .A1(sel_data[0]), .A2(RESULT[5]), .B1(n28), .B2(DATA_IN[5]), 
        .Z(db_data[5]) );
  AO22D0 U62 ( .A1(sel_data[0]), .A2(RESULT[4]), .B1(n28), .B2(DATA_IN[4]), 
        .Z(db_data[4]) );
  AO22D0 U63 ( .A1(sel_data[0]), .A2(RESULT[3]), .B1(n28), .B2(DATA_IN[3]), 
        .Z(db_data[3]) );
  AO22D0 U64 ( .A1(sel_data[0]), .A2(RESULT[2]), .B1(n28), .B2(DATA_IN[2]), 
        .Z(db_data[2]) );
  AO22D0 U65 ( .A1(sel_data[0]), .A2(RESULT[1]), .B1(n28), .B2(DATA_IN[1]), 
        .Z(db_data[1]) );
  AO22D0 U66 ( .A1(sel_data[0]), .A2(RESULT[0]), .B1(n28), .B2(DATA_IN[0]), 
        .Z(db_data[0]) );
  MUX2D0 U67 ( .I0(CTL_A[4]), .I1(DIR_EXT[4]), .S(sel_dira), .Z(db_dira[4]) );
  MUX2D0 U68 ( .I0(CTL_A[3]), .I1(DIR_EXT[3]), .S(sel_dira), .Z(db_dira[3]) );
  MUX2D0 U69 ( .I0(CTL_A[2]), .I1(DIR_EXT[2]), .S(sel_dira), .Z(db_dira[2]) );
  MUX2D0 U70 ( .I0(CTL_A[1]), .I1(DIR_EXT[1]), .S(sel_dira), .Z(db_dira[1]) );
  MUX2D0 U71 ( .I0(CTL_A[0]), .I1(DIR_EXT[0]), .S(sel_dira), .Z(db_dira[0]) );
  MUX2D0 U72 ( .I0(CTL_B[4]), .I1(DIR_EXT[4]), .S(sel_dirb), .Z(db_dirb[4]) );
  MUX2D0 U73 ( .I0(CTL_B[3]), .I1(DIR_EXT[3]), .S(sel_dirb), .Z(db_dirb[3]) );
  MUX2D0 U74 ( .I0(CTL_B[2]), .I1(DIR_EXT[2]), .S(sel_dirb), .Z(db_dirb[2]) );
  MUX2D0 U75 ( .I0(CTL_B[1]), .I1(DIR_EXT[1]), .S(sel_dirb), .Z(db_dirb[1]) );
  MUX2D0 U76 ( .I0(CTL_B[0]), .I1(DIR_EXT[0]), .S(sel_dirb), .Z(db_dirb[0]) );
  OAI21D0 U77 ( .A1(n29), .A2(READY), .B(WRITE_REQ), .ZN(n30) );
  MUX2ND0 U78 ( .I0(n30), .I1(n29), .S(sel_write[1]), .ZN(db_write) );
endmodule

