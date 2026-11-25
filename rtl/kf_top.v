// kf_top.v -- Kalman filter processor, 2 states / 1 measurement / 1 input.
//
// A microcoded dot-product machine.  The paper (Chavez-Bracamontes et al.,
// IEICE ELEX 13(6), 2016) uses a single-cycle add/multiply/divide datapath;
// here every instruction is a two-term dot product with an addend,
//
//   ACC <- base +/- A*B +/- D*E,     base = 0, ACC or register C,
//
// on two multipliers, in a three-stage pipeline:
//
//   F   ROM[PC]                                         -> IR (prefetched)
//   S1  IR -> decode -> read A, B, D, E (A, D may be RINV or 1.0); B and E
//       are Booth recoded                               -> operand registers
//   EX  A*B, D*E (truncated, not saturated)             -> XR1, XR2
//       read the base (ACC or register C)               -> XC, and whether
//       each product is subtracted from its magnitude
//   WB  ACC <- sat(XC +/- XR1 +/- XR2), optional register write, optionally
//       start the reciprocal unit with the result
//
// kf_rcp computes RINV = 1/S in the background (4 cycles; the new value is
// forwarded in the last).  The WB result is forwarded to the operand reads
// in S1 and to the base read in EX, so only an operand written by the
// instruction just ahead stalls (one cycle).  The exact timing is modelled
// by kfasic/iss.py.
//
// Host protocol, all signals synchronous to clk, inputs registered once:
//   * READY = 1 (idle) two cycles after rst_n is released, and after HALT
//   * a request (write or start) is accepted only if READY = 1 in its cycle
//   * write: DB[dir] <= data_in
//   * data_out = DB[dir], read combinationally from the registered address:
//     valid by the end of the cycle after dir is presented while READY = 1
//     (0 while busy)
//   * start: run the microcode; READY drops on the next clock edge and rises
//     again with HALT (the last instruction commits on the edge after,
//     before the host can observe it)
//
// Low power: every register group is clock-gated (kf_clkgate) behind a core
// clock gate, so nothing but the host input registers is clocked while
// idle; register-file reads are decoded one-hot (kf_rdport); the
// instruction register keeps the ROM's glitches out of the datapath; the
// second multiplier's operands are only loaded when it is used.
`default_nettype none

module kf_top (
    input  wire        clk,
    input  wire        rst_n,       // asynchronous assert, synchronized release
    input  wire        start,
    input  wire        write,
    input  wire [4:0]  dir,
    input  wire [23:0] data_in,
    output wire        ready,
    output wire [23:0] data_out
);
    localparam [1:0]  OP_HALT  = 2'd1, OP_ALU_RCP = 2'd3;   // ALU ops: op[1] = 1
    localparam [1:0]  BASE_ACC = 2'd1, BASE_C     = 2'd2;
    localparam [1:0]  SRC_RINV = 2'd1;                      // 2: the constant 1.0
    localparam [23:0] ONE      = 24'h004000;                // 1.0 in Q9.14

    // ---- reset synchronizer ----------------------------------------------
    reg rst_meta, rst_n_i;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            rst_meta <= 1'b0;
            rst_n_i  <= 1'b0;
        end else begin
            rst_meta <= 1'b1;
            rst_n_i  <= rst_meta;
        end

    // ---- host input registers --------------------------------------------
    reg        running;            // sequencer running (core clock domain)
    reg        busy;               // equal to running, on the free-running clock
    reg        start_q, write_q;
    reg [4:0]  dir_q;
    reg [23:0] data_in_q;
    wire       done;

    // The host-side outputs and input qualifiers use busy rather than
    // running: its clock does not pass through the core clock gates, so
    // these paths start early in the cycle.
    assign ready = rst_n_i & ~(busy | start_q);
    wire   busy_next = busy ? ~done : start_q;    // next state of running

    always @(posedge clk or negedge rst_n_i)
        if (!rst_n_i) begin
            start_q <= 1'b0;
            write_q <= 1'b0;
            busy    <= 1'b0;
        end else begin
            start_q <= start & ready;
            write_q <= write & ready;
            busy    <= busy_next;
        end

    // dir_q addresses read port H straight from a register: the host's
    // address while idle, and during a run the base register of the
    // instruction that enters EX.
    wire [4:0] s1_c;
    always @(posedge clk)
        dir_q <= busy_next ? s1_c : dir;

    // ---- core clock: everything below runs only while there is work ------
    // (a run, the commit of its last instruction, or a host write).  While
    // idle, only the reset synchronizer and the host input registers above
    // are clocked.
    reg  wb_v;
    wire cclk;
    kf_clkgate cg_core (.clk(clk), .en(running | wb_v | start_q | write_q | (write & ready)),
                        .gclk(cclk));

    wire g_din;
    kf_clkgate cg_din (.clk(cclk), .en(write & ready), .gclk(g_din));
    always @(posedge g_din)
        data_in_q <= data_in;

    // ---- fetch: ROM[pc] -> IR ------------------------------------------------
    // pc is the address of the next instruction; it returns to 0 when a run
    // ends, so the edge that starts a run loads ROM[0] and no cycle is lost.
    reg  [7:0]  pc;
    reg  [41:0] ir;
    wire [41:0] rom_q;
    kf_rom u_rom (.addr(pc), .data(rom_q));

    // ---- S1: decode, interlock, operand read ----------------------------------
    wire [1:0] s1_op   = ir[41:40];
    wire [1:0] s1_base = ir[39:38];
    wire       s1_n1   = ir[37];
    wire       s1_m2   = ir[36];
    wire       s1_n2   = ir[35];
    wire       s1_wr   = ir[34];
    wire [4:0] s1_dst  = ir[33:29];
    wire [4:0] s1_a    = ir[28:24];
    wire [1:0] s1_asrc = ir[23:22];               // A: register, RINV, 1.0
    wire [4:0] s1_b    = ir[21:17];
    wire [4:0] s1_d    = ir[16:12];
    wire [1:0] s1_dsrc = ir[11:10];               // D: register, RINV, 1.0
    wire [4:0] s1_e    = ir[9:5];
    assign     s1_c    = ir[4:0];

    wire s1_alu  = s1_op[1];
    wire s1_rc   = (s1_op == OP_ALU_RCP);
    wire s1_halt = (s1_op == OP_HALT);
    wire s1_p2   = s1_alu & s1_m2;                // second product present
    wire s1_ra   = s1_alu & (s1_asrc == 2'd0);    // reads register a
    wire s1_rd   = s1_p2  & (s1_dsrc == 2'd0);
    wire s1_ri   = (s1_alu & (s1_asrc == SRC_RINV)) | (s1_p2 & (s1_dsrc == SRC_RINV));

    reg       ex_v, ex_wr, ex_rc, ex_m2, wb_wr, wb_rc, wb_m2;
    reg [1:0] ex_base;
    reg [4:0] ex_dst, wb_dst;
    wire      rcp_busy, rcp_last;

    wire ex_w = ex_v & ex_wr;
    wire wb_w = wb_v & wb_wr;
    // only the instruction in EX can still owe an operand to S1; one in WB
    // forwards its result
    wire hz  = ex_w & ((s1_ra  & (ex_dst == s1_a)) | (s1_alu & (ex_dst == s1_b)) |
                       (s1_rd  & (ex_dst == s1_d)) | (s1_p2  & (ex_dst == s1_e)));
    wire rc_pend = (ex_v & ex_rc) | (wb_v & wb_rc);    // a reciprocal is about to start
    wire stall   = hz | (s1_ri & (rc_pend | (rcp_busy & ~rcp_last)))
                      | (s1_rc & (rc_pend | rcp_busy));
    wire advance = running & ~s1_halt & ~stall;   // the instruction leaves S1
    wire issue   = advance & s1_alu;              // ... into EX
    // HALT ends the run once no reciprocal is pending; an instruction in WB
    // commits on the same edge, one in EX on the next.
    assign done = running & s1_halt & ~rc_pend & ~rcp_busy;

    // instruction register: loaded when the run starts and on every advance
    wire g_ir;
    kf_clkgate cg_ir (.clk(cclk), .en(start_q | advance), .gclk(g_ir));
    always @(posedge g_ir or negedge rst_n_i)
        if (!rst_n_i)
            ir <= 42'd0;                          // NOP
        else
            ir <= rom_q;

    // sequencer and pipeline control (clocked while running and while the
    // last instruction commits)
    wire g_ctl;
    kf_clkgate cg_ctl (.clk(cclk), .en(running | wb_v | start_q), .gclk(g_ctl));
    always @(posedge g_ctl or negedge rst_n_i)
        if (!rst_n_i) begin
            running <= 1'b0;
            pc      <= 8'd0;
            ex_v    <= 1'b0;
            ex_wr   <= 1'b0;
            ex_rc   <= 1'b0;
            ex_m2   <= 1'b0;
            ex_base <= 2'd0;
            ex_dst  <= 5'd0;
            wb_v    <= 1'b0;
            wb_wr   <= 1'b0;
            wb_rc   <= 1'b0;
            wb_m2   <= 1'b0;
            wb_dst  <= 5'd0;
        end else begin
            if (!running) begin
                if (start_q) begin
                    running <= 1'b1;              // pc is 0, IR takes ROM[0]
                    pc      <= 8'd1;
                end
            end else if (done) begin
                running <= 1'b0;
                pc      <= 8'd0;
            end else if (advance) begin
                pc      <= pc + 8'd1;
            end
            ex_v    <= issue;
            ex_wr   <= s1_wr;
            ex_rc   <= s1_rc;
            ex_m2   <= s1_m2;
            ex_base <= s1_base;
            ex_dst  <= s1_dst;
            wb_v    <= ex_v;
            wb_wr   <= ex_wr;
            wb_rc   <= ex_rc;
            wb_m2   <= ex_m2;
            wb_dst  <= ex_dst;
        end

    // ---- register file ----------------------------------------------------
    // Ports A, B, D, E serve S1.  Port H serves the host while idle and reads
    // the base register in EX during a run (dir_q holds its address);
    // data_out is forced to 0 then.
    wire [23:0] rd_a, rd_b, rd_d, rd_e, rd_h;
    wire [23:0] acc_next, rinv, rinv_next;
    wire        rf_we    = wb_w | write_q;        // never both
    wire [4:0]  rf_waddr = wb_v ? wb_dst   : dir_q;
    wire [23:0] rf_wdata = wb_v ? acc_next : data_in_q;

    kf_regfile u_rf (
        .clk     (cclk),
        .we      (rf_we),
        .waddr   (rf_waddr),
        .wdata   (rf_wdata),
        .raddr_a (s1_a),
        .raddr_b (s1_b),
        .raddr_d (s1_d),
        .raddr_e (s1_e),
        .raddr_h (dir_q),
        .rdata_a (rd_a),
        .rdata_b (rd_b),
        .rdata_d (rd_d),
        .rdata_e (rd_e),
        .rdata_h (rd_h)
    );

    assign data_out = rd_h & {24{~busy}};

    // ---- S1 -> EX operand registers -------------------------------------
    wire [23:0] reg_a = (wb_w & (wb_dst == s1_a)) ? acc_next : rd_a;
    wire [23:0] reg_b = (wb_w & (wb_dst == s1_b)) ? acc_next : rd_b;
    wire [23:0] reg_d = (wb_w & (wb_dst == s1_d)) ? acc_next : rd_d;
    wire [23:0] reg_e = (wb_w & (wb_dst == s1_e)) ? acc_next : rd_e;
    wire [23:0] rinv_src = rcp_last ? rinv_next : rinv;
    wire [23:0] opnd_a = s1_asrc[1] ? ONE : s1_asrc[0] ? rinv_src : reg_a;
    wire [23:0] opnd_d = s1_dsrc[1] ? ONE : s1_dsrc[0] ? rinv_src : reg_d;
    wire [35:0] bd_b, bd_e;
    kf_booth u_bb (.b(reg_b[22:0]), .bd(bd_b));
    kf_booth u_be (.b(reg_e[22:0]), .bd(bd_e));

    reg  [22:0] ma, md;                           // multiplicands
    reg  [35:0] mb, me;                           // Booth digits of the multipliers
    reg         ms1, ms2;                         // signs of the two terms
    wire        g_op1, g_op2;
    kf_clkgate cg_op1 (.clk(cclk), .en(issue),         .gclk(g_op1));
    kf_clkgate cg_op2 (.clk(cclk), .en(issue & s1_m2), .gclk(g_op2));
    always @(posedge g_op1) begin
        ma  <= opnd_a[22:0];
        mb  <= bd_b;
        ms1 <= opnd_a[23] ^ reg_b[23] ^ s1_n1;
    end
    always @(posedge g_op2) begin
        md  <= opnd_d[22:0];
        me  <= bd_e;
        ms2 <= opnd_d[23] ^ reg_e[23] ^ s1_n2;
    end

    // ---- EX ---------------------------------------------------------------
    wire [31:0] p1, p2;
    kf_mul u_mul1 (.a(ma), .bd(mb), .p(p1));
    kf_mul u_mul2 (.a(md), .bd(me), .p(p2));

    reg  [31:0] xr1, xr2;
    wire        g_xr1, g_xr2;
    kf_clkgate cg_xr1 (.clk(cclk), .en(ex_v),         .gclk(g_xr1));
    kf_clkgate cg_xr2 (.clk(cclk), .en(ex_v & ex_m2), .gclk(g_xr2));
    always @(posedge g_xr1)
        xr1 <= p1;
    always @(posedge g_xr2)
        xr2 <= p2;

    // the base: register C through port H, or ACC, i.e. the result of the
    // instruction ahead (forwarded if it is in WB), or 0; and whether each
    // product is subtracted from its magnitude (sign differs from the base)
    reg  [23:0] acc;
    wire [23:0] base_c   = (wb_w & (wb_dst == dir_q)) ? acc_next : rd_h;
    wire [23:0] base_acc = wb_v ? acc_next : acc;
    wire [23:0] base_val = (ex_base == BASE_C) ? base_c : (ex_base == BASE_ACC) ? base_acc : 24'd0;
    reg  [23:0] xc;
    reg         xe1, xe2;
    wire        g_xc;
    kf_clkgate cg_xc (.clk(cclk), .en(ex_v), .gclk(g_xc));
    always @(posedge g_xc) begin
        xc  <= base_val;
        xe1 <= ms1 ^ base_val[23];
        xe2 <= (ms2 ^ base_val[23]) & ex_m2;
    end

    // ---- WB ---------------------------------------------------------------
    kf_dot u_dot (.base(xc), .x1(xr1), .e1(xe1), .x2(xr2), .e2(xe2), .m2(wb_m2), .y(acc_next));

    wire g_acc;
    kf_clkgate cg_acc (.clk(cclk), .en(wb_v), .gclk(g_acc));
    always @(posedge g_acc)
        acc <= acc_next;

    // ---- reciprocal unit --------------------------------------------------
    kf_rcp u_rcp (
        .clk       (cclk),
        .rst_n     (rst_n_i),
        .start     (wb_v & wb_rc),
        .s         (acc_next),
        .busy      (rcp_busy),
        .last      (rcp_last),
        .rinv_next (rinv_next),
        .rinv      (rinv)
    );

endmodule

`default_nettype wire
