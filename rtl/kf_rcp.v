// kf_rcp.v -- reciprocal unit: rinv <- 1/S (kfasic.fixed.rcp).
//
// Radix-8 restoring division of 2^28 by |S|: 24 quotient bits in eight
// digits, two per cycle.  start loads |S| and its multiples 3|S|, 5|S|,
// 7|S| (the result of the instruction that starts the unit, at the end of
// its WB cycle); the unit is busy for the next four cycles and writes rinv
// at the end of the last.  In that
// last cycle (last = 1) the new value is already on rinv_next, so an
// instruction reading RINV can issue then.  Exact: rinv = floor(2^28 / |S|),
// saturated to the largest magnitude for |S| <= 32 LSB (where 1/S would
// exceed the range), with the sign of S.  It runs in parallel with the main
// datapath.
`default_nettype none

module kf_rcp #(
    parameter integer W = 24
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,     // load s (one cycle)
    input  wire [W-1:0] s,
    output wire         busy,
    output wire         last,      // last busy cycle: rinv_next is the result
    output wire [W-1:0] rinv_next,
    output reg  [W-1:0] rinv
);
    localparam integer M = W - 1;                 // magnitude bits
    localparam integer N = M + 3;                 // 8 * remainder, k * |S|
    localparam [M-1:0] MAG_MAX = {M{1'b1}};

    reg  [M-1:0] d;                               // |S|
    reg          sgn, sat;
    reg  [M-1:0] r;                               // partial remainder, < d
    reg  [M-6:0] q;                               // quotient digits so far (6 x 3 bits)
    reg  [2:0]   cnt;

    assign busy = (cnt != 3'd0);
    assign last = (cnt == 3'd1);

    // ---- multiples of |S|, k = 1..7: computed at load, registered ----------
    wire [M-1:0] s_mag = s[M-1:0];
    wire [N-1:0] s3, s5, s7;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [2:0]   sk_cout;                         // 7|S| < 2^N: no carry out
    /* verilator lint_on UNUSEDSIGNAL */
    kf_add #(.N(N)) u_s3 (.a({3'b000, s_mag}), .b({2'b00, s_mag, 1'b0}), .cin(1'b0),
                          .y(s3), .cout(sk_cout[0]));
    kf_add #(.N(N)) u_s5 (.a({3'b000, s_mag}), .b({1'b0, s_mag, 2'b00}), .cin(1'b0),
                          .y(s5), .cout(sk_cout[1]));
    kf_add #(.N(N)) u_s7 (.a({s_mag, 3'b000}), .b(~{3'b000, s_mag}), .cin(1'b1),
                          .y(s7), .cout(sk_cout[2]));
    reg  [N-1:0] d3, d5, d7;

    wire [N-1:0] dk [1:7];
    assign dk[1] = {3'b000, d};
    assign dk[2] = {2'b00, d, 1'b0};
    assign dk[3] = d3;
    assign dk[4] = {1'b0, d, 2'b00};
    assign dk[5] = d5;
    assign dk[6] = {d3[N-2:0], 1'b0};
    assign dk[7] = d7;

    // ---- two radix-8 steps: digit = largest k in 0..7 with k*d <= 8r ------
    // The comparisons are monotonic in k (ge[k] implies ge[k-1]), so the
    // digit is the thermometer count of ge and the new remainder is
    // 8r - digit*d, selected one-hot.
    wire [M-1:0] rs [0:2];                        // remainder before each step
    wire [2:0]   qs [0:1];                        // the two digits
    assign rs[0] = r;

    genvar j, k;
    generate
        for (j = 0; j < 2; j = j + 1) begin : g_step
            wire [N-1:0] r8 = {rs[j], 3'b000};
            wire [N-1:0] t [1:7];                 // 8r - k*d
            wire [7:1]   ge;                      // 8r >= k*d
            for (k = 1; k <= 7; k = k + 1) begin : g_cmp
                kf_add #(.N(N)) u_sub (.a(r8), .b(~dk[k]), .cin(1'b1), .y(t[k]), .cout(ge[k]));
            end
            assign qs[j] = {ge[4],
                            (ge[2] & ~ge[4]) | ge[6],
                            (ge[1] & ~ge[2]) | (ge[3] & ~ge[4]) | (ge[5] & ~ge[6]) | ge[7]};
            assign rs[j + 1] = ({M{~ge[1]}}         & r8[M-1:0])
                             | ({M{ge[1] & ~ge[2]}} & t[1][M-1:0])
                             | ({M{ge[2] & ~ge[3]}} & t[2][M-1:0])
                             | ({M{ge[3] & ~ge[4]}} & t[3][M-1:0])
                             | ({M{ge[4] & ~ge[5]}} & t[4][M-1:0])
                             | ({M{ge[5] & ~ge[6]}} & t[5][M-1:0])
                             | ({M{ge[6] & ~ge[7]}} & t[6][M-1:0])
                             | ({M{ge[7]}}          & t[7][M-1:0]);
        end
    endgenerate
    wire [2:0] qa = qs[0];
    wire [2:0] qb = qs[1];

    // 24-bit quotient after the last step; bit 23 is 0 for |S| > 32
    /* verilator lint_off UNUSEDSIGNAL */
    wire [M:0] q_final = {q, qa, qb};
    /* verilator lint_on UNUSEDSIGNAL */
    assign rinv_next = {sgn, sat ? MAG_MAX : q_final[M-1:0]};

    // ---- registers (clock-gated) ------------------------------------------
    wire g_ld, g_it, g_out;
    kf_clkgate cg_ld  (.clk(clk), .en(start),        .gclk(g_ld));
    kf_clkgate cg_it  (.clk(clk), .en(start | busy), .gclk(g_it));
    kf_clkgate cg_out (.clk(clk), .en(last),         .gclk(g_out));

    always @(posedge g_ld) begin
        d   <= s_mag;
        d3  <= s3;
        d5  <= s5;
        d7  <= s7;
        sgn <= s[W-1];
        sat <= (s_mag <= 32);
    end

    always @(posedge g_it or negedge rst_n)
        if (!rst_n)
            cnt <= 3'd0;
        else if (start)
            cnt <= 3'd4;
        else
            cnt <= cnt - 3'd1;

    // 2^28 = 16 * 8^8: the remainder starts at 16, so the first step
    // compares 128 with k * d
    always @(posedge g_it) begin
        if (start) begin
            r <= {{(M - 5){1'b0}}, 5'd16};
            q <= {(M - 5){1'b0}};
        end else begin
            r <= rs[2];
            q <= {q[M-12:0], qa, qb};
        end
    end

    always @(posedge g_out)
        rinv <= rinv_next;

endmodule

`default_nettype wire
