// Created by ihdl
module sequencer ( clk, rst_n, start, continue_i, loop_addr, rom_we, rom_waddr, 
        rom_wdata, ctl_a, ctl_b, ctl_c, ctl_d, ctl_e, ctl_f, ready, pc_dbg );
  input [7:0] loop_addr;
  input [7:0] rom_waddr;
  input [15:0] rom_wdata;
  output [4:0] ctl_a;
  output [4:0] ctl_b;
  output [1:0] ctl_c;
  output [1:0] ctl_d;
  output [7:0] pc_dbg;
  input clk, rst_n, start, continue_i, rom_we;
  output ctl_e, ctl_f, ready;
  wire   n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n24, n25, n26, n27, n28, n29,
         n30, n31, n32, n11, n12, n13, n14, n15, n16, n17, n18, n19, n20, n21,
         n22, n23, n33, n34, n35, n36, n37, n38, n39, n40, n41, n42, n43, n44,
         n45, n46, n47, n48, n49, n50, n51, n52, n53, n54;

  rom_256x16 ROM ( .clk(clk), .addr({n3, n4, n5, n6, n7, n8, n9, n10}), .dout(
        {ctl_a, ctl_b, n1, n2, ctl_d, ctl_e, ctl_f}), .prog_we(rom_we), 
        .prog_addr(rom_waddr), .prog_data(rom_wdata) );
  DFQD1 \pc_reg[0]  ( .D(n32), .CP(clk), .Q(n10) );
  DFQD1 ready_reg ( .D(n30), .CP(clk), .Q(ready) );
  DFQD1 \pc_reg[7]  ( .D(n31), .CP(clk), .Q(n3) );
  DFQD1 \pc_reg[6]  ( .D(n29), .CP(clk), .Q(n4) );
  DFQD1 \pc_reg[5]  ( .D(n28), .CP(clk), .Q(n5) );
  DFQD1 \pc_reg[4]  ( .D(n27), .CP(clk), .Q(n6) );
  DFQD1 \pc_reg[3]  ( .D(n26), .CP(clk), .Q(n7) );
  DFQD1 \pc_reg[2]  ( .D(n25), .CP(clk), .Q(n8) );
  DFQD1 \pc_reg[1]  ( .D(n24), .CP(clk), .Q(n9) );
  NR2D0 U3 ( .A1(n51), .A2(n17), .ZN(n21) );
  AOI21D0 U4 ( .A1(n39), .A2(n23), .B(n22), .ZN(n36) );
  OAI21D0 U5 ( .A1(n12), .A2(n11), .B(rst_n), .ZN(n30) );
  INVD0 U6 ( .I(n2), .ZN(n13) );
  AOI21D0 U7 ( .A1(n1), .A2(n13), .B(ready), .ZN(n12) );
  CKND2D0 U8 ( .A1(ready), .A2(start), .ZN(n14) );
  INVD0 U9 ( .I(n14), .ZN(n11) );
  CKND2D0 U10 ( .A1(n10), .A2(n9), .ZN(n49) );
  INR2D0 U11 ( .A1(n8), .B1(n49), .ZN(n42) );
  ND3D0 U12 ( .A1(n42), .A2(n7), .A3(n6), .ZN(n17) );
  OAI31D0 U13 ( .A1(n1), .A2(continue_i), .A3(n13), .B(n12), .ZN(n15) );
  IND2D0 U14 ( .A1(n15), .B1(rst_n), .ZN(n16) );
  NR2D0 U15 ( .A1(n16), .A2(n1), .ZN(n39) );
  ND3D0 U16 ( .A1(rst_n), .A2(n15), .A3(n14), .ZN(n50) );
  IOA21D0 U17 ( .A1(n17), .A2(n39), .B(n50), .ZN(n22) );
  INR2D0 U18 ( .A1(n1), .B1(n16), .ZN(n53) );
  INVD0 U19 ( .I(n39), .ZN(n51) );
  INVD0 U20 ( .I(n5), .ZN(n23) );
  AOI22D0 U21 ( .A1(loop_addr[5]), .A2(n53), .B1(n21), .B2(n23), .ZN(n18) );
  IOA21D0 U22 ( .A1(n5), .A2(n22), .B(n18), .ZN(n28) );
  INVD0 U23 ( .I(n10), .ZN(n20) );
  CKND2D0 U24 ( .A1(n53), .A2(loop_addr[0]), .ZN(n19) );
  OAI221D0 U25 ( .A1(n10), .A2(n51), .B1(n20), .B2(n50), .C(n19), .ZN(n32) );
  INVD0 U26 ( .I(n4), .ZN(n37) );
  CKND2D0 U27 ( .A1(n5), .A2(n21), .ZN(n38) );
  OAI21D0 U28 ( .A1(n4), .A2(n51), .B(n36), .ZN(n33) );
  AOI22D0 U29 ( .A1(loop_addr[7]), .A2(n53), .B1(n3), .B2(n33), .ZN(n34) );
  OAI31D0 U30 ( .A1(n3), .A2(n37), .A3(n38), .B(n34), .ZN(n31) );
  CKND2D0 U31 ( .A1(n53), .A2(loop_addr[6]), .ZN(n35) );
  OAI221D0 U32 ( .A1(n4), .A2(n38), .B1(n37), .B2(n36), .C(n35), .ZN(n29) );
  INVD0 U33 ( .I(n7), .ZN(n45) );
  CKND2D0 U34 ( .A1(n39), .A2(n42), .ZN(n46) );
  AOI32D0 U35 ( .A1(n42), .A2(n50), .A3(n7), .B1(n51), .B2(n50), .ZN(n40) );
  AOI22D0 U36 ( .A1(n6), .A2(n40), .B1(n53), .B2(loop_addr[4]), .ZN(n41) );
  OAI31D0 U37 ( .A1(n6), .A2(n45), .A3(n46), .B(n41), .ZN(n27) );
  OA21D0 U38 ( .A1(n42), .A2(n51), .B(n50), .Z(n44) );
  CKND2D0 U39 ( .A1(n53), .A2(loop_addr[3]), .ZN(n43) );
  OAI221D0 U40 ( .A1(n7), .A2(n46), .B1(n45), .B2(n44), .C(n43), .ZN(n26) );
  AOI32D0 U41 ( .A1(n10), .A2(n50), .A3(n9), .B1(n51), .B2(n50), .ZN(n47) );
  AOI22D0 U42 ( .A1(n8), .A2(n47), .B1(n53), .B2(loop_addr[2]), .ZN(n48) );
  OAI31D0 U43 ( .A1(n8), .A2(n51), .A3(n49), .B(n48), .ZN(n25) );
  OAI21D0 U44 ( .A1(n10), .A2(n51), .B(n50), .ZN(n54) );
  NR2D0 U45 ( .A1(n9), .A2(n51), .ZN(n52) );
  AO222D0 U46 ( .A1(n54), .A2(n9), .B1(n53), .B2(loop_addr[1]), .C1(n10), .C2(
        n52), .Z(n24) );
endmodule
