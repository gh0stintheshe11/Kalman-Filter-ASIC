// kf_top.v -- Kalman filter processor, 2 states / 1 measurement / 1 input.
//
// A microcoded multiply-accumulate machine derived from the architecture of
// Chavez-Bracamontes et al., IEICE ELEX 13(6), 2016:
//
//   S1  PC -> ROM -> decode -> register (or RINV) read   -> operand registers
//   EX  multiply, or add / subtract / load               -> XR
//   WB  ACC <- XR or ACC +/- XR, optional register write
//   kf_rcp computes RINV = 1/S in the background (8 cycles).
//
// Read-after-write hazards and RINV use are interlocked in S1; the exact
// timing is modelled by kfasic/iss.py and the microcode is scheduled so that
// the interlocks rarely fire.
//
// Host protocol, all signals synchronous to clk, inputs registered once:
//   * READY = 1 (idle) two cycles after rst_n is released, and after HALT
//   * a request (write or start) is accepted only if READY = 1 in its cycle
//   * write: DB[dir] <= data_in
//   * data_out = DB[dir], valid one cycle after dir is presented (0 while busy)
//   * start: run the microcode; READY drops on the next clock edge and rises
//     again once HALT has completed
//
// Low power: every register group is clock-gated (kf_clkgate), the
// multiplier and the adder have separate operand registers so only the unit
// in use sees new data, and nothing but the host input registers is clocked
// while idle.
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
    localparam [3:0] OP_HALT = 4'd1, OP_MUL = 4'd2, OP_MAC = 4'd3, OP_MSB = 4'd4,
                     OP_ADD  = 4'd5, OP_SUB = 4'd6, OP_LDA = 4'd7, OP_RCP = 4'd8;

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
    reg        running;
    reg        start_q, write_q;
    reg [4:0]  dir_q;
    reg [23:0] data_in_q;

    assign ready = rst_n_i & ~(running | start_q);

    always @(posedge clk or negedge rst_n_i)
        if (!rst_n_i) begin
            start_q <= 1'b0;
            write_q <= 1'b0;
        end else begin
            start_q <= start & ready;
            write_q <= write & ready;
        end

    always @(posedge clk)
        dir_q <= dir;

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

    // ---- S1: fetch, decode, interlock -------------------------------------
    reg  [7:0]  pc;
    wire [20:0] ir;
    kf_rom u_rom (.addr(pc), .data(ir));

    wire [3:0] s1_op  = ir[20:17];
    wire       s1_wr  = ir[16];
    wire [4:0] s1_dst = ir[15:11];
    wire [4:0] s1_a   = ir[10:6];
    wire [4:0] s1_b   = ir[5:1];
    wire       s1_bi  = ir[0];

    wire s1_mul  = (s1_op == OP_MUL) | (s1_op == OP_MAC) | (s1_op == OP_MSB);
    wire s1_alu  = (s1_op == OP_ADD) | (s1_op == OP_SUB) | (s1_op == OP_LDA);
    wire s1_two  = s1_mul | (s1_op == OP_ADD) | (s1_op == OP_SUB);
    wire s1_rcp  = (s1_op == OP_RCP);
    wire s1_halt = (s1_op == OP_HALT);
    wire s1_ra   = s1_two | (s1_op == OP_LDA);        // reads register a
    wire s1_rb   = (s1_two & ~s1_bi) | s1_rcp;        // reads register b
    wire s1_ri   = s1_two & s1_bi;                    // reads RINV

    reg       ex_v, ex_wr, wb_v, wb_wr;
    reg [3:0] ex_op, wb_op;
    reg [4:0] ex_dst, wb_dst;
    wire      rcp_busy;

    wire ex_w  = ex_v & ex_wr;
    wire wb_w  = wb_v & wb_wr;
    wire hz_a  = s1_ra & ((ex_w & (ex_dst == s1_a)) | (wb_w & (wb_dst == s1_a)));
    wire hz_b  = s1_rb & ((ex_w & (ex_dst == s1_b)) | (wb_w & (wb_dst == s1_b)));
    wire stall = hz_a | hz_b | ((s1_ri | s1_rcp) & rcp_busy);
    wire issue = running & ~s1_halt & ~stall;
    // HALT completes once EX and the reciprocal unit are empty; an
    // instruction still in WB commits on the same clock edge.
    wire done  = running & s1_halt & ~ex_v & ~rcp_busy;

    // sequencer and pipeline control (clocked only while running)
    wire g_ctl;
    kf_clkgate cg_ctl (.clk(cclk), .en(running | start_q), .gclk(g_ctl));
    always @(posedge g_ctl or negedge rst_n_i)
        if (!rst_n_i) begin
            running <= 1'b0;
            pc      <= 8'd0;
            ex_v    <= 1'b0;
            ex_wr   <= 1'b0;
            ex_op   <= 4'd0;
            ex_dst  <= 5'd0;
            wb_v    <= 1'b0;
            wb_wr   <= 1'b0;
            wb_op   <= 4'd0;
            wb_dst  <= 5'd0;
        end else begin
            if (!running) begin
                running <= 1'b1;                      // start_q is set
                pc      <= 8'd0;
            end else begin
                if (done)  running <= 1'b0;
                if (issue) pc <= pc + 8'd1;
            end
            ex_v   <= issue & (s1_mul | s1_alu);
            ex_wr  <= s1_wr;
            ex_op  <= s1_op;
            ex_dst <= s1_dst;
            wb_v   <= ex_v;
            wb_wr  <= ex_wr;
            wb_op  <= ex_op;
            wb_dst <= ex_dst;
        end

    // ---- register file ----------------------------------------------------
    wire [23:0] rd_a, rd_b, rinv;
    wire [23:0] acc_next;
    wire        rf_we    = running ? wb_w     : write_q;
    wire [4:0]  rf_waddr = running ? wb_dst   : dir_q;
    wire [23:0] rf_wdata = running ? acc_next : data_in_q;

    kf_regfile u_rf (
        .clk     (cclk),
        .we      (rf_we),
        .waddr   (rf_waddr),
        .wdata   (rf_wdata),
        .raddr_a (running ? s1_a : dir_q),
        .raddr_b (s1_b),
        .rdata_a (rd_a),
        .rdata_b (rd_b)
    );

    assign data_out = running ? 24'd0 : rd_a;

    // ---- S1 -> EX operand registers (separate, so only one unit toggles) --
    wire [23:0] opnd_b = s1_bi ? rinv : rd_b;
    reg  [23:0] ma, mb;                               // multiplier operands
    reg  [23:0] aa, ab;                               // adder operands
    wire        g_mop, g_aop;
    kf_clkgate cg_mop (.clk(cclk), .en(issue & s1_mul), .gclk(g_mop));
    kf_clkgate cg_aop (.clk(cclk), .en(issue & s1_alu), .gclk(g_aop));
    always @(posedge g_mop) begin
        ma <= rd_a;
        mb <= opnd_b;
    end
    always @(posedge g_aop) begin
        aa <= rd_a;
        ab <= opnd_b;
    end

    // ---- EX ---------------------------------------------------------------
    wire [23:0] mul_y, alu_y;
    kf_mul    u_mul (.a(ma), .b(mb), .y(mul_y));
    kf_addsub u_alu (.a(aa), .b(ab), .sub(ex_op == OP_SUB), .y(alu_y));

    wire        ex_mul = (ex_op == OP_MUL) | (ex_op == OP_MAC) | (ex_op == OP_MSB);
    wire [23:0] ex_y   = ex_mul ? mul_y : (ex_op == OP_LDA) ? aa : alu_y;

    reg  [23:0] xr;
    wire        g_xr;
    kf_clkgate cg_xr (.clk(cclk), .en(ex_v), .gclk(g_xr));
    always @(posedge g_xr)
        xr <= ex_y;

    // ---- WB ---------------------------------------------------------------
    reg  [23:0] acc;
    wire [23:0] acc_sum;
    kf_addsub u_acc (.a(acc), .b(xr), .sub(wb_op == OP_MSB), .y(acc_sum));
    assign acc_next = ((wb_op == OP_MAC) | (wb_op == OP_MSB)) ? acc_sum : xr;

    wire g_acc;
    kf_clkgate cg_acc (.clk(cclk), .en(wb_v), .gclk(g_acc));
    always @(posedge g_acc)
        acc <= acc_next;

    // ---- reciprocal unit --------------------------------------------------
    kf_rcp u_rcp (
        .clk   (cclk),
        .rst_n (rst_n_i),
        .start (issue & s1_rcp),
        .s     (rd_b),
        .busy  (rcp_busy),
        .rinv  (rinv)
    );

endmodule

`default_nettype wire
