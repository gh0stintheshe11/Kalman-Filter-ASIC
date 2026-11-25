// kf_top.v -- Kalman filter processor, 2 states / 1 measurement / 1 input.
//
// A microcoded multiply-accumulate machine derived from the architecture of
// Chavez-Bracamontes et al., IEICE ELEX 13(6), 2016:
//
//   F   ROM[PC]                                          -> IR (prefetched)
//   S1  IR -> decode -> read A and B (register, RINV or 1.0) -> operand registers
//   EX  A * B -> XR;  read the addend C of MAD/MSD          -> XC
//   WB  ACC <- XR, ACC +/- XR or XC +/- XR, optional register write
//   kf_rcp computes RINV = 1/S in the background (7 cycles).
//
// The WB result is forwarded to the operand reads in S1 and EX, so only an
// operand A or B written by the instruction just ahead stalls (one cycle);
// RINV use waits for the reciprocal unit.  The exact timing is modelled by
// kfasic/iss.py and the microcode is scheduled so that the interlocks rarely
// fire.
//
// Host protocol, all signals synchronous to clk, inputs registered once:
//   * READY = 1 (idle) two cycles after rst_n is released, and after HALT
//   * a request (write or start) is accepted only if READY = 1 in its cycle
//   * write: DB[dir] <= data_in
//   * data_out = DB[dir], valid one cycle after dir is presented (0 while busy)
//   * start: run the microcode; READY drops on the next clock edge and rises
//     again once HALT has completed
//
// Low power: every register group is clock-gated (kf_clkgate) behind a core
// clock gate, so nothing but the host input registers is clocked while
// idle; register-file reads are decoded one-hot (kf_rdport); the
// instruction register keeps the ROM's glitches out of the datapath.
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
    // opcodes (OP_MAC = 3 needs no decoding of its own)
    localparam [2:0] OP_HALT = 3'd1, OP_MUL = 3'd2, OP_MSB = 3'd4,
                     OP_MAD  = 3'd5, OP_MSD = 3'd6, OP_RCP = 3'd7;
    localparam [23:0] ONE = 24'h004000;               // 1.0 in Q9.14

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
    // address while idle, and during a run the addend register of the
    // instruction that enters EX.
    wire [4:0] s1_c;
    always @(posedge clk)
        dir_q <= busy_next ? s1_c : dir;

    // ---- core clock: everything below runs only while there is work ------
    // (a run, or a host write).  While idle, only the reset synchronizer and
    // the host input registers above are clocked.
    wire cclk;
    kf_clkgate cg_core (.clk(clk), .en(running | start_q | write_q | (write & ready)),
                        .gclk(cclk));

    wire g_din;
    kf_clkgate cg_din (.clk(cclk), .en(write & ready), .gclk(g_din));
    always @(posedge g_din)
        data_in_q <= data_in;

    // ---- fetch: ROM[pc] -> IR ------------------------------------------------
    // The instruction register keeps the ROM's switching (and its glitches)
    // away from the decode logic and the register-file read ports.  pc is
    // the address of the next instruction; it returns to 0 when a run ends,
    // so the edge that starts a run loads ROM[0] and no cycle is lost.
    reg  [7:0]  pc;
    reg  [25:0] ir;
    wire [25:0] rom_q;
    kf_rom u_rom (.addr(pc), .data(rom_q));

    // ---- S1: decode, interlock, operand read ----------------------------------
    wire [2:0] s1_op  = ir[25:23];
    wire       s1_wr  = ir[22];
    wire [4:0] s1_dst = ir[21:17];
    wire [4:0] s1_a   = ir[16:12];
    wire [4:0] s1_b   = ir[11:7];
    wire [1:0] s1_bs  = ir[6:5];                      // B: register, RINV, 1.0
    assign     s1_c   = ir[4:0];

    wire s1_acc  = (s1_op != 3'd0) & (s1_op != OP_HALT) & (s1_op != OP_RCP);
    wire s1_rcp  = (s1_op == OP_RCP);
    wire s1_halt = (s1_op == OP_HALT);
    wire s1_rb   = (s1_acc & (s1_bs == 2'd0)) | s1_rcp;   // reads register b
    wire s1_ri   = s1_acc & (s1_bs == 2'd1);              // reads RINV

    reg       ex_v, ex_wr, wb_v, wb_wr;
    reg [2:0] ex_op, wb_op;
    reg [4:0] ex_dst, wb_dst;
    wire      rcp_busy;

    wire ex_w  = ex_v & ex_wr;
    wire wb_w  = wb_v & wb_wr;
    // only the instruction in EX can still owe a register to S1; one in WB
    // forwards its result
    wire hz_a  = s1_acc & ex_w & (ex_dst == s1_a);
    wire hz_b  = s1_rb  & ex_w & (ex_dst == s1_b);
    wire stall = hz_a | hz_b | ((s1_ri | s1_rcp) & rcp_busy);
    wire issue = running & ~s1_halt & ~stall;
    // HALT completes once EX and the reciprocal unit are empty; an
    // instruction still in WB commits on the same clock edge.
    assign done = running & s1_halt & ~ex_v & ~rcp_busy;

    // instruction register: loaded when the run starts and on every issue
    wire g_ir;
    kf_clkgate cg_ir (.clk(cclk), .en(start_q | issue), .gclk(g_ir));
    always @(posedge g_ir or negedge rst_n_i)
        if (!rst_n_i)
            ir <= 26'd0;                              // NOP
        else
            ir <= rom_q;

    // sequencer and pipeline control (clocked only while running)
    wire g_ctl;
    kf_clkgate cg_ctl (.clk(cclk), .en(running | start_q), .gclk(g_ctl));
    always @(posedge g_ctl or negedge rst_n_i)
        if (!rst_n_i) begin
            running <= 1'b0;
            pc      <= 8'd0;
            ex_v    <= 1'b0;
            ex_wr   <= 1'b0;
            ex_op   <= 3'd0;
            ex_dst  <= 5'd0;
            wb_v    <= 1'b0;
            wb_wr   <= 1'b0;
            wb_op   <= 3'd0;
            wb_dst  <= 5'd0;
        end else begin
            if (!running) begin
                running <= 1'b1;                      // start_q is set, pc is 0
                pc      <= 8'd1;
            end else if (done) begin
                running <= 1'b0;
                pc      <= 8'd0;
            end else if (issue) begin
                pc      <= pc + 8'd1;
            end
            ex_v   <= issue & s1_acc;
            ex_wr  <= s1_wr;
            ex_op  <= s1_op;
            ex_dst <= s1_dst;
            wb_v   <= ex_v;
            wb_wr  <= ex_wr;
            wb_op  <= ex_op;
            wb_dst <= ex_dst;
        end

    // ---- register file ----------------------------------------------------
    // Ports A and B serve S1.  Port H serves the host while idle and reads
    // the addend C in EX while running (dir_q holds its address); data_out
    // is forced to 0 then.
    wire [23:0] rd_a, rd_b, rd_h, rinv;
    wire [23:0] acc_next;
    wire        rf_we    = running ? wb_w     : write_q;
    wire [4:0]  rf_waddr = running ? wb_dst   : dir_q;
    wire [23:0] rf_wdata = running ? acc_next : data_in_q;

    kf_regfile u_rf (
        .clk     (cclk),
        .we      (rf_we),
        .waddr   (rf_waddr),
        .wdata   (rf_wdata),
        .raddr_a (s1_a),
        .raddr_b (s1_b),
        .raddr_h (dir_q),
        .rdata_a (rd_a),
        .rdata_b (rd_b),
        .rdata_h (rd_h)
    );

    assign data_out = rd_h & {24{~busy}};

    // ---- S1 -> EX operand registers -------------------------------------
    wire [23:0] opnd_a = (wb_w & (wb_dst == s1_a)) ? acc_next : rd_a;
    wire [23:0] reg_b  = (wb_w & (wb_dst == s1_b)) ? acc_next : rd_b;
    wire [23:0] opnd_b = s1_bs[1] ? ONE : s1_bs[0] ? rinv : reg_b;
    reg  [23:0] ma, mb;
    wire        g_mop;
    kf_clkgate cg_mop (.clk(cclk), .en(issue & s1_acc), .gclk(g_mop));
    always @(posedge g_mop) begin
        ma <= opnd_a;
        mb <= opnd_b;
    end

    // ---- EX ---------------------------------------------------------------
    wire [23:0] mul_y;
    kf_mul u_mul (.a(ma), .b(mb), .y(mul_y));

    reg  [23:0] xr;
    wire        g_xr;
    kf_clkgate cg_xr (.clk(cclk), .en(ex_v), .gclk(g_xr));
    always @(posedge g_xr)
        xr <= mul_y;

    wire        ex_addend = (ex_op == OP_MAD) | (ex_op == OP_MSD);
    reg  [23:0] xc;
    wire        g_xc;
    kf_clkgate cg_xc (.clk(cclk), .en(ex_v & ex_addend), .gclk(g_xc));
    always @(posedge g_xc)
        xc <= (wb_w & (wb_dst == dir_q)) ? acc_next : rd_h;

    // ---- WB ---------------------------------------------------------------
    reg  [23:0] acc;
    wire [23:0] acc_sum;
    wire        wb_addend = (wb_op == OP_MAD) | (wb_op == OP_MSD);
    kf_addsub u_acc (.a(wb_addend ? xc : acc), .b(xr),
                     .sub((wb_op == OP_MSB) | (wb_op == OP_MSD)), .y(acc_sum));
    assign acc_next = (wb_op == OP_MUL) ? xr : acc_sum;

    wire g_acc;
    kf_clkgate cg_acc (.clk(cclk), .en(wb_v), .gclk(g_acc));
    always @(posedge g_acc)
        acc <= acc_next;

    // ---- reciprocal unit --------------------------------------------------
    kf_rcp u_rcp (
        .clk   (cclk),
        .rst_n (rst_n_i),
        .start (issue & s1_rcp),
        .s     (reg_b),
        .busy  (rcp_busy),
        .rinv  (rinv)
    );

endmodule

`default_nettype wire
