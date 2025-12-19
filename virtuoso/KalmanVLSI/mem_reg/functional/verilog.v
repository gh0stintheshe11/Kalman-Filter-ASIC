// Created by ihdl
module mem_reg ( clk, write, dira, dirb, data, A, B, rq_we, rq_d, RQ, rd_we, 
        rd_d, RD );
  input [4:0] dira;
  input [4:0] dirb;
  input [23:0] data;
  output [23:0] A;
  output [23:0] B;
  input [23:0] rq_d;
  output [23:0] RQ;
  input [23:0] rd_d;
  output [23:0] RD;
  input clk, write, rq_we, rd_we;


  Data_Bank Data_Bank_inst ( .clk(clk), .write(write), .dira(dira), .data(data), .A(A), .dirb(dirb), .B(B) );
endmodule
