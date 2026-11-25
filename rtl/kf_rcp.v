// kf_rcp.v -- reciprocal unit: rinv <- 1/S (kfasic.fixed.rcp).
//
// Radix-8 restoring division of 2^28 by |S|: 24 quotient bits, three per
// cycle, so rinv is updated 8 cycles after start and busy is high for those
// 8 cycles.  Exact: rinv = floor(2^28 / |S|), saturated to the largest
// magnitude for |S| <= 32 LSB (where 1/S would exceed the range), with the
// sign of S.  It runs in parallel with the main datapath.
`default_nettype none

module kf_rcp #(
    parameter integer W = 24
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,     // load s and begin (one cycle)
    input  wire [W-1:0] s,
    output wire         busy,
    output reg  [W-1:0] rinv
);
    localparam integer M = W - 1;                 // magnitude bits
    localparam [M-1:0] MAG_MAX = {M{1'b1}};

    reg  [M-1:0] d;                               // |S|
    reg          sgn, sat;
    reg  [M-1:0] r;                               // partial remainder, < d
    reg  [M-3:0] q;                               // quotient digits so far (7 x 3 bits)
    reg  [3:0]   cnt;

    assign busy = (cnt != 4'd0);

    // ---- one radix-8 step: largest k in 0..7 with k*d <= 8r -------------
    wire [M+2:0] r8 = {r, 3'b000};
    wire [M+2:0] d1 = {3'b000, d};
    wire [M+2:0] d2 = {2'b00, d, 1'b0};
    wire [M+2:0] d4 = {1'b0, d, 2'b00};
    wire [M+2:0] dk [1:7];
    assign dk[1] = d1;
    assign dk[2] = d2;
    assign dk[3] = d1 + d2;
    assign dk[4] = d4;
    assign dk[5] = d1 + d4;
    assign dk[6] = d2 + d4;
    assign dk[7] = d1 + d2 + d4;

    wire [M+3:0] t  [1:7];                        // 8r - k*d, MSB = borrow
    wire [7:1]   ge;
    genvar k;
    generate
        for (k = 1; k <= 7; k = k + 1) begin : g_cmp
            assign t[k]  = {1'b0, r8} - {1'b0, dk[k]};
            assign ge[k] = ~t[k][M+3];
        end
    endgenerate

    reg [2:0]   digit;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [M+2:0] r_next;                           // < d, so the top 3 bits are 0
    /* verilator lint_on UNUSEDSIGNAL */
    always @(*) begin
        digit  = 3'd0;
        r_next = r8;
        if (ge[1]) begin digit = 3'd1; r_next = t[1][M+2:0]; end
        if (ge[2]) begin digit = 3'd2; r_next = t[2][M+2:0]; end
        if (ge[3]) begin digit = 3'd3; r_next = t[3][M+2:0]; end
        if (ge[4]) begin digit = 3'd4; r_next = t[4][M+2:0]; end
        if (ge[5]) begin digit = 3'd5; r_next = t[5][M+2:0]; end
        if (ge[6]) begin digit = 3'd6; r_next = t[6][M+2:0]; end
        if (ge[7]) begin digit = 3'd7; r_next = t[7][M+2:0]; end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire [M:0] q_next = {q, digit};               // 24-bit quotient; bit 23 is 0 unless sat
    /* verilator lint_on UNUSEDSIGNAL */

    // ---- registers (clock-gated) ------------------------------------------
    wire g_ld, g_it, g_out;
    kf_clkgate cg_ld  (.clk(clk), .en(start),                    .gclk(g_ld));
    kf_clkgate cg_it  (.clk(clk), .en(start | busy),             .gclk(g_it));
    kf_clkgate cg_out (.clk(clk), .en(busy & (cnt == 4'd1)),     .gclk(g_out));

    always @(posedge g_ld) begin
        d   <= s[M-1:0];
        sgn <= s[W-1];
        sat <= (s[M-1:0] <= 32);
    end

    always @(posedge g_it or negedge rst_n)
        if (!rst_n)
            cnt <= 4'd0;
        else if (start)
            cnt <= 4'd8;
        else
            cnt <= cnt - 4'd1;

    always @(posedge g_it) begin
        if (start) begin
            r <= 16;                              // 2^28 >> 24: the bits above the quotient
            q <= {(M - 2){1'b0}};
        end else begin
            r <= r_next[M-1:0];
            q <= q_next[M-3:0];
        end
    end

    always @(posedge g_out)
        rinv <= {sgn, sat ? MAG_MAX : q_next[M-1:0]};

endmodule

`default_nettype wire
