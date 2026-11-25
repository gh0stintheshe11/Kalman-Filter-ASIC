// kf_top.v -- Kalman filter processor (architecture of Chavez-Bracamontes et
// al., IEICE ELEX 13(6), 2016), 2 states / 1 measurement / 1 control input.
//
// Host protocol (paper Sec. 4), all signals synchronous to clk.  The host
// inputs are registered once, so every request takes effect one cycle after
// it is presented:
//   * READY = 1 (idle) two cycles after rst_n is released
//   * while READY = 1:  write = 1 stores data_in into DB[dir];
//                       data_out shows DB[dir] two cycles after dir is set
//   * start (one-cycle pulse while READY = 1) runs the microcode from PC 0;
//     READY drops on the next clock edge and rises again 189 cycles after
//     that edge (1 input-register cycle + 188 program cycles)
//   * write/dir/data_in/start are ignored while READY = 0
//
// Instruction word: a[15:11] b[10:6] c[5:4] d[3:2] e[1] f[0]
//   e = 1: SR <= AU(op d, DB[a], DB[b])
//   f = 1: DB[a] <= (e ? AU result : SR)
`default_nettype none

module kf_top (
    input  wire        clk,
    input  wire        rst_n,       // asynchronous assert, synchronized release
    input  wire        start,
    input  wire        write,
    input  wire [4:0]  dir,
    input  wire [23:0] data_in,
    output wire        ready,
    output reg  [23:0] data_out
);
    // ---- reset synchronizer --------------------------------------------
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
    // Registering the inputs makes off-chip timing trivial and keeps the
    // (functionally false) path dir -> data bank -> AU -> data bank from
    // starting at a primary input with external delay.
    // A request is accepted only if READY = 1 in the cycle it is presented.
    reg        start_q, write_q;
    reg [4:0]  dir_q;
    reg [23:0] data_in_q;
    always @(posedge clk or negedge rst_n_i)
        if (!rst_n_i) begin
            start_q <= 1'b0;
            write_q <= 1'b0;
        end else begin
            start_q <= start & ready;
            write_q <= write & ready;
        end
    always @(posedge clk) begin
        dir_q     <= dir;
        data_in_q <= data_in;
    end

    // ---- sequencer and instruction decode ------------------------------
    wire        running;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] instr;              // c field [5:4] is decoded in the sequencer
    /* verilator lint_on UNUSEDSIGNAL */
    wire [4:0]  i_a = instr[15:11];
    wire [4:0]  i_b = instr[10:6];
    wire [1:0]  i_d = instr[3:2];
    wire        i_e = instr[1];
    wire        i_f = instr[0];

    wire exec   = running & i_e;
    wire is_div = (i_d == 2'b11);
    wire au_done;
    wire stall  = exec & is_div & ~au_done;

    kf_sequencer u_seq (
        .clk     (clk),
        .rst_n   (rst_n_i),
        .start   (start_q),
        .stall   (stall),
        .running (running),
        .instr   (instr)
    );

    // low during reset (incl. the synchronizer), while busy, and on the
    // cycle after START was captured
    assign ready = rst_n_i & ~(running | start_q);

    // ---- data bank: host owns it while idle, the program while running --
    wire [23:0] rdata_a, rdata_b, au_y;
    reg  [23:0] sr;                                    // result register

    wire [4:0]  addr_a = running ? i_a : dir_q;
    wire        we     = running ? (i_f & ~(i_e & is_div)) : write_q;
    wire [23:0] wdata  = running ? (i_e ? au_y : sr) : data_in_q;

    kf_regfile u_bank (
        .clk     (clk),
        .we      (we),
        .addr_a  (addr_a),
        .wdata   (wdata),
        .addr_b  (i_b),
        .rdata_a (rdata_a),
        .rdata_b (rdata_b)
    );

    // ---- arithmetic unit -------------------------------------------------
    kf_au u_au (
        .clk   (clk),
        .rst_n (rst_n_i),
        .start (exec),
        .op    (i_d),
        .r     (rdata_a),
        .s     (rdata_b),
        .y     (au_y),
        .done  (au_done)
    );

    always @(posedge clk)
        if (exec & (~is_div | au_done)) sr <= au_y;

    // ---- host readback (registered) --------------------------------------
    always @(posedge clk)
        if (!running) data_out <= rdata_a;

endmodule

`default_nettype wire
