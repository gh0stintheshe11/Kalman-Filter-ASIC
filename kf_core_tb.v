`timescale 1ns/1ps
module kf_core_tb;

  // Match the core parameters
  parameter W=24;
  parameter FRAC=14;
  parameter DEPTH=8;   // small for TB
  parameter ADDRW=3;

  reg                 clk;

  // ------ Control/observe wires to DUT ------
  reg  [W-1:0]        DATA_IN;
  reg  [ADDRW-1:0]    CTL_A, CTL_B, DIR_EXT;
  reg                 WRITE_REQ, READY_G;
  reg  [1:0]          sel_data, sel_write;
  reg                 sel_dira, sel_dirb;
  reg  [ADDRW-1:0]    DB_WADDR;

  reg  [1:0]          sel_R, sel_S, sel_I;
  reg                 inv_R, inv_S;

  reg                 au_start;
  reg  [1:0]          op_sel, mul_y_sel;

  wire                au_done, au_busy;
  wire [W-1:0]        result_out;
  wire [W-1:0]        db_rdata_a, db_rdata_b;

  // DUT
  kf_core #(.W(W), .FRAC(FRAC), .DEPTH(DEPTH), .ADDRW(ADDRW)) DUT (
    .clk(clk),
    .DATA_IN(DATA_IN), .CTL_A(CTL_A), .CTL_B(CTL_B), .DIR_EXT(DIR_EXT),
    .WRITE_REQ(WRITE_REQ), .READY_G(READY_G),
    .sel_data(sel_data), .sel_dira(sel_dira), .sel_dirb(sel_dirb),
    .sel_write(sel_write), .DB_WADDR(DB_WADDR),
    .sel_R(sel_R), .sel_S(sel_S), .inv_R(inv_R), .inv_S(inv_S), .sel_I(sel_I),
    .au_start(au_start), .op_sel(op_sel), .mul_y_sel(mul_y_sel),
    .au_done(au_done), .au_busy(au_busy),
    .result_out(result_out),
    .db_rdata_a(db_rdata_a), .db_rdata_b(db_rdata_b)
  );

  // Clock
  initial clk=0;
  always #5 clk=~clk;

  // =========== Helpers: sign-magnitude / golden math ===========

  function [W-1:0] tc_to_sm; input signed [W-1:0] v;
    reg sign; reg signed [W-1:0] a;
    begin
      sign=(v<0); a=sign? -v : v;
      if (a[W-2:0] > {(W-1){1'b1}}) a[W-2:0] = {(W-1){1'b1}};
      tc_to_sm = {sign, a[W-2:0]};
    end
  endfunction

  function signed [W-1:0] sm_to_tc; input [W-1:0] sm;
    begin
      sm_to_tc = sm[W-1] ? -$signed({1'b0,sm[W-2:0]}) : $signed({1'b0,sm[W-2:0]});
    end
  endfunction

  function [W-1:0] q_of_int; input integer k;
    reg signed [W-1:0] tc;
    begin tc = k <<< FRAC; q_of_int = tc_to_sm(tc); end
  endfunction

  function [W-1:0] gold_add; input [W-1:0] a,b; reg signed [W:0] t;
    begin
      t = sm_to_tc(a)+sm_to_tc(b);
      if (t >  $signed({1'b0,{(W-1){1'b1}}})) t =  $signed({1'b0,{(W-1){1'b1}}});
      if (t < -$signed({1'b0,{(W-1){1'b1}}})) t = -$signed({1'b0,{(W-1){1'b1}}});
      gold_add = tc_to_sm(t[W-1:0]);
    end
  endfunction

  function [W-1:0] gold_sub; input [W-1:0] a,b; reg signed [W:0] t;
    begin
      t = sm_to_tc(a)-sm_to_tc(b);
      if (t >  $signed({1'b0,{(W-1){1'b1}}})) t =  $signed({1'b0,{(W-1){1'b1}}});
      if (t < -$signed({1'b0,{(W-1){1'b1}}})) t = -$signed({1'b0,{(W-1){1'b1}}});
      gold_sub = tc_to_sm(t[W-1:0]);
    end
  endfunction

  function [W-1:0] gold_mul; input [W-1:0] a,b;
    reg s; reg [W-2:0] am,bm,sc,sat; reg [2*(W-1)-1:0] p,pr;
    begin
      s=a[W-1]^b[W-1]; am=a[W-2:0]; bm=b[W-2:0];
      p = am*bm;
      pr = p + {{(2*(W-1)-FRAC-1){1'b0}},1'b1,{FRAC{1'b0}}}; // +0.5 LSB
      sc = pr[2*(W-1)-1:FRAC];
      sat= sc > {(W-1){1'b1}} ? {(W-1){1'b1}} : sc;
      gold_mul = {s,sat};
    end
  endfunction

  function [W-1:0] gold_div; input [W-1:0] a,b;
    reg s; reg [W-2:0] am,bm,invb,sc,sat; reg [2*(W-1)-1:0] p,pr;
    reg [2*FRAC+W:0] N;
    begin
      s=a[W-1]^b[W-1]; am=a[W-2:0]; bm=b[W-2:0];
      if (bm == {(W-1){1'b0}}) bm = {{(W-2){1'b0}},1'b1}; // tiny
      N = {{(W-1){1'b0}},1'b1,{(2*FRAC){1'b0}}};
      invb = (N / { {(W-1){1'b0}}, bm})[W-2:0];
      p = am * invb;
      pr = p + {{(2*(W-1)-FRAC-1){1'b0}},1'b1,{FRAC{1'b0}}};
      sc = pr[2*(W-1)-1:FRAC];
      sat= sc > {(W-1){1'b1}} ? {(W-1){1'b1}} : sc;
      gold_div = {s,sat};
    end
  endfunction

  // --------------------- Test flow helpers ---------------------
  task db_write; input [ADDRW-1:0] addr; input [W-1:0] data;
    begin
      // Router A: write DATA_IN to DB[addr]
      DATA_IN   <= data;
      sel_data  <= 2'd0;         // DATA_IN
      WRITE_REQ <= 1'b1;
      sel_write <= 2'd0;         // WR (no gating)
      DB_WADDR  <= addr;
      READY_G   <= 1'b0;
      @(negedge clk);
      // one cycle is enough because DB write is on posedge via router_a gating
      @(posedge clk);
      WRITE_REQ <= 1'b0;
    end
  endtask

  task setup_read_addrs; input [ADDRW-1:0] a; input [ADDRW-1:0] b;
    begin
      // Make Router A drive raddr A/B from CTL_A/B
      CTL_A    <= a;
      CTL_B    <= b;
      sel_dira <= 1'b0; // use CTL_A
      sel_dirb <= 1'b0; // use CTL_B
    end
  endtask

  task write_result_to; input [ADDRW-1:0] dst;
    begin
      // Router A: RESULT -> DB[dst], gated by AU done
      sel_data  <= 2'd1;         // RESULT
      WRITE_REQ <= 1'b1;
      sel_write <= 2'd1;         // WR & READY_G
      DB_WADDR  <= dst;
      READY_G   <= 1'b0;         // we'll switch to done when it arrives
      // wait for AU done then gate write
      wait(au_done==1'b1);
      READY_G   <= 1'b1;         // open the gate for this cycle
      @(posedge clk);
      READY_G   <= 1'b0;
      WRITE_REQ <= 1'b0;
    end
  endtask

  task do_op; input [1:0] op; begin
      op_sel    <= op;
      mul_y_sel <= 2'b00; // default Y=S
      au_start  <= 1'b1; @(posedge clk); au_start <= 1'b0;
      if (op==2'b11) begin // DIV -> wait reciprocal internally
        wait(au_done==1'b1);
      end else begin
        @(posedge clk); // result valid next cycle
      end
    end
  endtask

  task do_mul_y; input [1:0] ysel; begin
      op_sel    <= 2'b10; mul_y_sel <= ysel;
      au_start  <= 1'b1; @(posedge clk); au_start <= 1'b0;
      if (ysel==2'b10) wait(au_done==1'b1); // inv(S)
      else @(posedge clk);
    end
  endtask

  // --------------------- Test sequence ---------------------
  integer errors, checks;
  reg [W-1:0] Aop, Bop, expect;

  initial begin
    // defaults
    clk=0;
    DATA_IN=0; CTL_A=0; CTL_B=0; DIR_EXT=0; WRITE_REQ=0; READY_G=0;
    sel_data=0; sel_write=0; sel_dira=0; sel_dirb=0; DB_WADDR=0;
    sel_R=2'b00; sel_S=2'b00; inv_R=0; inv_S=0; sel_I=2'b00;
    au_start=0; op_sel=0; mul_y_sel=0;
    errors=0; checks=0;

    // 1) Load operands into DB[0] and DB[1]
    Aop = q_of_int( 3);  db_write(0, Aop);
    Bop = q_of_int(-2);  db_write(1, Bop);

    // 2) Select DB[0] -> A, DB[1] -> B
    setup_read_addrs(0,1);
    sel_R = 2'b00; // A
    sel_S = 2'b00; // B
    inv_R = 0; inv_S = 0;
    sel_I = 2'b01; // +1 available if needed

    // ---- ADD ----
    do_op(2'b00); // add
    expect = gold_add(Aop,Bop);
    write_result_to(2);
    // read back DB[2] through A port to verify
    setup_read_addrs(2,1); #1; checks=checks+1;
    if (db_rdata_a !== expect) begin
      $display("ADD end-to-end mismatch exp=%h got=%h", expect, db_rdata_a);
      errors=errors+1;
    end

    // ---- SUB ----
    setup_read_addrs(0,1);
    do_op(2'b01);
    expect = gold_sub(Aop,Bop);
    write_result_to(3);
    setup_read_addrs(3,1); #1; checks=checks+1;
    if (db_rdata_a !== expect) begin
      $display("SUB end-to-end mismatch exp=%h got=%h", expect, db_rdata_a);
      errors=errors+1;
    end

    // ---- MUL R*S ----
    setup_read_addrs(0,1);
    do_mul_y(2'b00); // Y=S
    expect = gold_mul(Aop,Bop);
    write_result_to(4);
    setup_read_addrs(4,1); #1; checks=checks+1;
    if (db_rdata_a !== expect) begin
      $display("MUL end-to-end mismatch exp=%h got=%h", expect, db_rdata_a);
      errors=errors+1;
    end

    // ---- DIV R/S ----
    setup_read_addrs(0,1);
    op_sel=2'b11; mul_y_sel=2'b10; au_start=1'b1; @(posedge clk); au_start=1'b0;
    wait(au_done==1'b1);
    expect = gold_div(Aop,Bop);
    write_result_to(5);
    setup_read_addrs(5,1); #1; checks=checks+1;
    if (db_rdata_a !== expect) begin
      $display("DIV end-to-end mismatch exp=%h got=%h", expect, db_rdata_a);
      errors=errors+1;
    end

    if (errors==0) $display("kf_core_tb: PASS (%0d checks)", checks);
    else           $display("kf_core_tb: %0d ERRORS / %0d checks", errors, checks);

    $finish;
  end
endmodule
