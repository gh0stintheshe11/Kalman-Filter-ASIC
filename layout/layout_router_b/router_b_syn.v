/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : N-2017.09
// Date      : Thu Dec 11 20:40:43 2025
/////////////////////////////////////////////////////////////


module router_b ( A, B, RQ, RD, sel_R, sel_S, inv_R, inv_S, sel_I, R, S, I, 
        msb_R, msb_S );
  input [23:0] A;
  input [23:0] B;
  input [23:0] RQ;
  input [23:0] RD;
  input [1:0] sel_R;
  input [1:0] sel_S;
  input [1:0] sel_I;
  output [23:0] R;
  output [23:0] S;
  output [23:0] I;
  input inv_R, inv_S;
  output msb_R, msb_S;
  wire   \I[23] , n105, n106, n107, n108, n109, n110, n111, n112, n113, n114,
         n115, n116, n117, n118, n119, n120, n121, n122, n123, n124, n125,
         n126, n127, n128, n129, n130, n131, n132, n133, n134, n135, n136,
         n137, n138, n139, n140, n141, n142, n143, n144, n145, n146, n147,
         n148, n149, n150, n151, n152, n153, n154, n155, n156, n157, n158,
         n159, n160, n161, n162, n163, n164, n165, n166, n167, n168, n169,
         n170, n171, n172, n173, n174, n175, n176, n177, n178, n179, n180,
         n181, n182, n183, n184, n185, n186, n187, n188, n189, n190, n191,
         n192, n193, n194, n195, n196, n197, n198, n199, n200, n201, n202,
         n203, n204, n205, n206, n207;
  assign msb_R = R[23];
  assign msb_S = S[23];
  assign I[1] = \I[23] ;
  assign I[2] = \I[23] ;
  assign I[3] = \I[23] ;
  assign I[4] = \I[23] ;
  assign I[5] = \I[23] ;
  assign I[6] = \I[23] ;
  assign I[7] = \I[23] ;
  assign I[8] = \I[23] ;
  assign I[9] = \I[23] ;
  assign I[10] = \I[23] ;
  assign I[11] = \I[23] ;
  assign I[12] = \I[23] ;
  assign I[13] = \I[23] ;
  assign I[14] = \I[23] ;
  assign I[15] = \I[23] ;
  assign I[16] = \I[23] ;
  assign I[17] = \I[23] ;
  assign I[18] = \I[23] ;
  assign I[19] = \I[23] ;
  assign I[20] = \I[23] ;
  assign I[21] = \I[23] ;
  assign I[22] = \I[23] ;
  assign I[23] = \I[23] ;

  NR2D0 U156 ( .A1(sel_I[0]), .A2(n105), .ZN(\I[23] ) );
  AOI22D0 U157 ( .A1(sel_S[0]), .A2(RD[0]), .B1(n152), .B2(B[0]), .ZN(n106) );
  AOI22D0 U158 ( .A1(sel_S[0]), .A2(RD[5]), .B1(n152), .B2(B[5]), .ZN(n116) );
  AOI22D0 U159 ( .A1(sel_S[0]), .A2(RD[20]), .B1(n152), .B2(B[20]), .ZN(n146)
         );
  AOI22D0 U160 ( .A1(sel_R[0]), .A2(RQ[10]), .B1(n203), .B2(A[10]), .ZN(n177)
         );
  INVD0 U161 ( .I(sel_I[1]), .ZN(n105) );
  CKND2D0 U162 ( .A1(n120), .A2(n153), .ZN(n121) );
  CKND2D0 U163 ( .A1(n150), .A2(n153), .ZN(n151) );
  CKND2D0 U164 ( .A1(n179), .A2(n204), .ZN(n180) );
  AO21D0 U165 ( .A1(sel_I[0]), .A2(n105), .B(\I[23] ), .Z(I[0]) );
  INVD0 U166 ( .I(inv_S), .ZN(n156) );
  NR2D0 U167 ( .A1(sel_S[0]), .A2(sel_S[1]), .ZN(n152) );
  CKND2D0 U168 ( .A1(sel_S[0]), .A2(sel_S[1]), .ZN(n153) );
  CKND2D0 U169 ( .A1(n106), .A2(n153), .ZN(n107) );
  MUX2ND0 U170 ( .I0(n156), .I1(inv_S), .S(n107), .ZN(S[0]) );
  AOI22D0 U171 ( .A1(sel_S[0]), .A2(RD[1]), .B1(n152), .B2(B[1]), .ZN(n108) );
  CKND2D0 U172 ( .A1(n108), .A2(n153), .ZN(n109) );
  MUX2ND0 U173 ( .I0(n156), .I1(inv_S), .S(n109), .ZN(S[1]) );
  AOI22D0 U174 ( .A1(sel_S[0]), .A2(RD[2]), .B1(n152), .B2(B[2]), .ZN(n110) );
  CKND2D0 U175 ( .A1(n110), .A2(n153), .ZN(n111) );
  MUX2ND0 U176 ( .I0(n156), .I1(inv_S), .S(n111), .ZN(S[2]) );
  AOI22D0 U177 ( .A1(sel_S[0]), .A2(RD[3]), .B1(n152), .B2(B[3]), .ZN(n112) );
  CKND2D0 U178 ( .A1(n112), .A2(n153), .ZN(n113) );
  MUX2ND0 U179 ( .I0(n156), .I1(inv_S), .S(n113), .ZN(S[3]) );
  AOI22D0 U180 ( .A1(sel_S[0]), .A2(RD[4]), .B1(n152), .B2(B[4]), .ZN(n114) );
  CKND2D0 U181 ( .A1(n114), .A2(n153), .ZN(n115) );
  MUX2ND0 U182 ( .I0(n156), .I1(inv_S), .S(n115), .ZN(S[4]) );
  CKND2D0 U183 ( .A1(n116), .A2(n153), .ZN(n117) );
  MUX2ND0 U184 ( .I0(n156), .I1(inv_S), .S(n117), .ZN(S[5]) );
  AOI22D0 U185 ( .A1(sel_S[0]), .A2(RD[6]), .B1(n152), .B2(B[6]), .ZN(n118) );
  CKND2D0 U186 ( .A1(n118), .A2(n153), .ZN(n119) );
  MUX2ND0 U187 ( .I0(n156), .I1(inv_S), .S(n119), .ZN(S[6]) );
  AOI22D0 U188 ( .A1(sel_S[0]), .A2(RD[7]), .B1(n152), .B2(B[7]), .ZN(n120) );
  MUX2ND0 U189 ( .I0(n156), .I1(inv_S), .S(n121), .ZN(S[7]) );
  AOI22D0 U190 ( .A1(sel_S[0]), .A2(RD[8]), .B1(n152), .B2(B[8]), .ZN(n122) );
  CKND2D0 U191 ( .A1(n122), .A2(n153), .ZN(n123) );
  MUX2ND0 U192 ( .I0(n156), .I1(inv_S), .S(n123), .ZN(S[8]) );
  AOI22D0 U193 ( .A1(sel_S[0]), .A2(RD[9]), .B1(n152), .B2(B[9]), .ZN(n124) );
  CKND2D0 U194 ( .A1(n124), .A2(n153), .ZN(n125) );
  MUX2ND0 U195 ( .I0(n156), .I1(inv_S), .S(n125), .ZN(S[9]) );
  AOI22D0 U196 ( .A1(sel_S[0]), .A2(RD[10]), .B1(n152), .B2(B[10]), .ZN(n126)
         );
  CKND2D0 U197 ( .A1(n126), .A2(n153), .ZN(n127) );
  MUX2ND0 U198 ( .I0(n156), .I1(inv_S), .S(n127), .ZN(S[10]) );
  AOI22D0 U199 ( .A1(sel_S[0]), .A2(RD[11]), .B1(n152), .B2(B[11]), .ZN(n128)
         );
  CKND2D0 U200 ( .A1(n128), .A2(n153), .ZN(n129) );
  MUX2ND0 U201 ( .I0(n156), .I1(inv_S), .S(n129), .ZN(S[11]) );
  AOI22D0 U202 ( .A1(sel_S[0]), .A2(RD[12]), .B1(n152), .B2(B[12]), .ZN(n130)
         );
  CKND2D0 U203 ( .A1(n130), .A2(n153), .ZN(n131) );
  MUX2ND0 U204 ( .I0(n156), .I1(inv_S), .S(n131), .ZN(S[12]) );
  AOI22D0 U205 ( .A1(sel_S[0]), .A2(RD[13]), .B1(n152), .B2(B[13]), .ZN(n132)
         );
  CKND2D0 U206 ( .A1(n132), .A2(n153), .ZN(n133) );
  MUX2ND0 U207 ( .I0(n156), .I1(inv_S), .S(n133), .ZN(S[13]) );
  AOI22D0 U208 ( .A1(sel_S[0]), .A2(RD[14]), .B1(n152), .B2(B[14]), .ZN(n134)
         );
  CKND2D0 U209 ( .A1(n134), .A2(n153), .ZN(n135) );
  MUX2ND0 U210 ( .I0(n156), .I1(inv_S), .S(n135), .ZN(S[14]) );
  AOI22D0 U211 ( .A1(sel_S[0]), .A2(RD[15]), .B1(n152), .B2(B[15]), .ZN(n136)
         );
  CKND2D0 U212 ( .A1(n136), .A2(n153), .ZN(n137) );
  MUX2ND0 U213 ( .I0(n156), .I1(inv_S), .S(n137), .ZN(S[15]) );
  AOI22D0 U214 ( .A1(sel_S[0]), .A2(RD[16]), .B1(n152), .B2(B[16]), .ZN(n138)
         );
  CKND2D0 U215 ( .A1(n138), .A2(n153), .ZN(n139) );
  MUX2ND0 U216 ( .I0(n156), .I1(inv_S), .S(n139), .ZN(S[16]) );
  AOI22D0 U217 ( .A1(sel_S[0]), .A2(RD[17]), .B1(n152), .B2(B[17]), .ZN(n140)
         );
  CKND2D0 U218 ( .A1(n140), .A2(n153), .ZN(n141) );
  MUX2ND0 U219 ( .I0(n156), .I1(inv_S), .S(n141), .ZN(S[17]) );
  AOI22D0 U220 ( .A1(sel_S[0]), .A2(RD[18]), .B1(n152), .B2(B[18]), .ZN(n142)
         );
  CKND2D0 U221 ( .A1(n142), .A2(n153), .ZN(n143) );
  MUX2ND0 U222 ( .I0(n156), .I1(inv_S), .S(n143), .ZN(S[18]) );
  AOI22D0 U223 ( .A1(sel_S[0]), .A2(RD[19]), .B1(n152), .B2(B[19]), .ZN(n144)
         );
  CKND2D0 U224 ( .A1(n144), .A2(n153), .ZN(n145) );
  MUX2ND0 U225 ( .I0(n156), .I1(inv_S), .S(n145), .ZN(S[19]) );
  CKND2D0 U226 ( .A1(n146), .A2(n153), .ZN(n147) );
  MUX2ND0 U227 ( .I0(n156), .I1(inv_S), .S(n147), .ZN(S[20]) );
  AOI22D0 U228 ( .A1(sel_S[0]), .A2(RD[21]), .B1(n152), .B2(B[21]), .ZN(n148)
         );
  CKND2D0 U229 ( .A1(n148), .A2(n153), .ZN(n149) );
  MUX2ND0 U230 ( .I0(n156), .I1(inv_S), .S(n149), .ZN(S[21]) );
  AOI22D0 U231 ( .A1(sel_S[0]), .A2(RD[22]), .B1(n152), .B2(B[22]), .ZN(n150)
         );
  MUX2ND0 U232 ( .I0(n156), .I1(inv_S), .S(n151), .ZN(S[22]) );
  AOI22D0 U233 ( .A1(sel_S[0]), .A2(RD[23]), .B1(n152), .B2(B[23]), .ZN(n154)
         );
  CKND2D0 U234 ( .A1(n154), .A2(n153), .ZN(n155) );
  MUX2ND0 U235 ( .I0(n156), .I1(inv_S), .S(n155), .ZN(S[23]) );
  INVD0 U236 ( .I(inv_R), .ZN(n207) );
  NR2D0 U237 ( .A1(sel_R[0]), .A2(sel_R[1]), .ZN(n203) );
  AOI22D0 U238 ( .A1(sel_R[0]), .A2(RQ[0]), .B1(n203), .B2(A[0]), .ZN(n157) );
  CKND2D0 U239 ( .A1(sel_R[0]), .A2(sel_R[1]), .ZN(n204) );
  CKND2D0 U240 ( .A1(n157), .A2(n204), .ZN(n158) );
  MUX2ND0 U241 ( .I0(n207), .I1(inv_R), .S(n158), .ZN(R[0]) );
  AOI22D0 U242 ( .A1(sel_R[0]), .A2(RQ[1]), .B1(n203), .B2(A[1]), .ZN(n159) );
  CKND2D0 U243 ( .A1(n159), .A2(n204), .ZN(n160) );
  MUX2ND0 U244 ( .I0(n207), .I1(inv_R), .S(n160), .ZN(R[1]) );
  AOI22D0 U245 ( .A1(sel_R[0]), .A2(RQ[2]), .B1(n203), .B2(A[2]), .ZN(n161) );
  CKND2D0 U246 ( .A1(n161), .A2(n204), .ZN(n162) );
  MUX2ND0 U247 ( .I0(n207), .I1(inv_R), .S(n162), .ZN(R[2]) );
  AOI22D0 U248 ( .A1(sel_R[0]), .A2(RQ[3]), .B1(n203), .B2(A[3]), .ZN(n163) );
  CKND2D0 U249 ( .A1(n163), .A2(n204), .ZN(n164) );
  MUX2ND0 U250 ( .I0(n207), .I1(inv_R), .S(n164), .ZN(R[3]) );
  AOI22D0 U251 ( .A1(sel_R[0]), .A2(RQ[4]), .B1(n203), .B2(A[4]), .ZN(n165) );
  CKND2D0 U252 ( .A1(n165), .A2(n204), .ZN(n166) );
  MUX2ND0 U253 ( .I0(n207), .I1(inv_R), .S(n166), .ZN(R[4]) );
  AOI22D0 U254 ( .A1(sel_R[0]), .A2(RQ[5]), .B1(n203), .B2(A[5]), .ZN(n167) );
  CKND2D0 U255 ( .A1(n167), .A2(n204), .ZN(n168) );
  MUX2ND0 U256 ( .I0(n207), .I1(inv_R), .S(n168), .ZN(R[5]) );
  AOI22D0 U257 ( .A1(sel_R[0]), .A2(RQ[6]), .B1(n203), .B2(A[6]), .ZN(n169) );
  CKND2D0 U258 ( .A1(n169), .A2(n204), .ZN(n170) );
  MUX2ND0 U259 ( .I0(n207), .I1(inv_R), .S(n170), .ZN(R[6]) );
  AOI22D0 U260 ( .A1(sel_R[0]), .A2(RQ[7]), .B1(n203), .B2(A[7]), .ZN(n171) );
  CKND2D0 U261 ( .A1(n171), .A2(n204), .ZN(n172) );
  MUX2ND0 U262 ( .I0(n207), .I1(inv_R), .S(n172), .ZN(R[7]) );
  AOI22D0 U263 ( .A1(sel_R[0]), .A2(RQ[8]), .B1(n203), .B2(A[8]), .ZN(n173) );
  CKND2D0 U264 ( .A1(n173), .A2(n204), .ZN(n174) );
  MUX2ND0 U265 ( .I0(n207), .I1(inv_R), .S(n174), .ZN(R[8]) );
  AOI22D0 U266 ( .A1(sel_R[0]), .A2(RQ[9]), .B1(n203), .B2(A[9]), .ZN(n175) );
  CKND2D0 U267 ( .A1(n175), .A2(n204), .ZN(n176) );
  MUX2ND0 U268 ( .I0(n207), .I1(inv_R), .S(n176), .ZN(R[9]) );
  CKND2D0 U269 ( .A1(n177), .A2(n204), .ZN(n178) );
  MUX2ND0 U270 ( .I0(n207), .I1(inv_R), .S(n178), .ZN(R[10]) );
  AOI22D0 U271 ( .A1(sel_R[0]), .A2(RQ[11]), .B1(n203), .B2(A[11]), .ZN(n179)
         );
  MUX2ND0 U272 ( .I0(n207), .I1(inv_R), .S(n180), .ZN(R[11]) );
  AOI22D0 U273 ( .A1(sel_R[0]), .A2(RQ[12]), .B1(n203), .B2(A[12]), .ZN(n181)
         );
  CKND2D0 U274 ( .A1(n181), .A2(n204), .ZN(n182) );
  MUX2ND0 U275 ( .I0(n207), .I1(inv_R), .S(n182), .ZN(R[12]) );
  AOI22D0 U276 ( .A1(sel_R[0]), .A2(RQ[13]), .B1(n203), .B2(A[13]), .ZN(n183)
         );
  CKND2D0 U277 ( .A1(n183), .A2(n204), .ZN(n184) );
  MUX2ND0 U278 ( .I0(n207), .I1(inv_R), .S(n184), .ZN(R[13]) );
  AOI22D0 U279 ( .A1(sel_R[0]), .A2(RQ[14]), .B1(n203), .B2(A[14]), .ZN(n185)
         );
  CKND2D0 U280 ( .A1(n185), .A2(n204), .ZN(n186) );
  MUX2ND0 U281 ( .I0(n207), .I1(inv_R), .S(n186), .ZN(R[14]) );
  AOI22D0 U282 ( .A1(sel_R[0]), .A2(RQ[15]), .B1(n203), .B2(A[15]), .ZN(n187)
         );
  CKND2D0 U283 ( .A1(n187), .A2(n204), .ZN(n188) );
  MUX2ND0 U284 ( .I0(n207), .I1(inv_R), .S(n188), .ZN(R[15]) );
  AOI22D0 U285 ( .A1(sel_R[0]), .A2(RQ[16]), .B1(n203), .B2(A[16]), .ZN(n189)
         );
  CKND2D0 U286 ( .A1(n189), .A2(n204), .ZN(n190) );
  MUX2ND0 U287 ( .I0(n207), .I1(inv_R), .S(n190), .ZN(R[16]) );
  AOI22D0 U288 ( .A1(sel_R[0]), .A2(RQ[17]), .B1(n203), .B2(A[17]), .ZN(n191)
         );
  CKND2D0 U289 ( .A1(n191), .A2(n204), .ZN(n192) );
  MUX2ND0 U290 ( .I0(n207), .I1(inv_R), .S(n192), .ZN(R[17]) );
  AOI22D0 U291 ( .A1(sel_R[0]), .A2(RQ[18]), .B1(n203), .B2(A[18]), .ZN(n193)
         );
  CKND2D0 U292 ( .A1(n193), .A2(n204), .ZN(n194) );
  MUX2ND0 U293 ( .I0(n207), .I1(inv_R), .S(n194), .ZN(R[18]) );
  AOI22D0 U294 ( .A1(sel_R[0]), .A2(RQ[19]), .B1(n203), .B2(A[19]), .ZN(n195)
         );
  CKND2D0 U295 ( .A1(n195), .A2(n204), .ZN(n196) );
  MUX2ND0 U296 ( .I0(n207), .I1(inv_R), .S(n196), .ZN(R[19]) );
  AOI22D0 U297 ( .A1(sel_R[0]), .A2(RQ[20]), .B1(n203), .B2(A[20]), .ZN(n197)
         );
  CKND2D0 U298 ( .A1(n197), .A2(n204), .ZN(n198) );
  MUX2ND0 U299 ( .I0(n207), .I1(inv_R), .S(n198), .ZN(R[20]) );
  AOI22D0 U300 ( .A1(sel_R[0]), .A2(RQ[21]), .B1(n203), .B2(A[21]), .ZN(n199)
         );
  CKND2D0 U301 ( .A1(n199), .A2(n204), .ZN(n200) );
  MUX2ND0 U302 ( .I0(n207), .I1(inv_R), .S(n200), .ZN(R[21]) );
  AOI22D0 U303 ( .A1(sel_R[0]), .A2(RQ[22]), .B1(n203), .B2(A[22]), .ZN(n201)
         );
  CKND2D0 U304 ( .A1(n201), .A2(n204), .ZN(n202) );
  MUX2ND0 U305 ( .I0(n207), .I1(inv_R), .S(n202), .ZN(R[22]) );
  AOI22D0 U306 ( .A1(sel_R[0]), .A2(RQ[23]), .B1(n203), .B2(A[23]), .ZN(n205)
         );
  CKND2D0 U307 ( .A1(n205), .A2(n204), .ZN(n206) );
  MUX2ND0 U308 ( .I0(n207), .I1(inv_R), .S(n206), .ZN(R[23]) );
endmodule

