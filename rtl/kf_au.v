// kf_au.v -- arithmetic unit (paper Sec. 4 / Fig. 3)
//
// Operands and result are 24-bit sign-magnitude Q9.14 words; the exact
// arithmetic (truncation, saturation, +0 normalization) is defined by
// kfasic/fixed.py and checked bit for bit by the testbenches.
//
//   ADD, SUB, MUL   combinational, one cycle
//   DIV             R / S = R * (1/S), 25 cycles, using the single multiplier:
//                     cycle 0       setup (Q = 0)
//                     cycles 1..23  successive approximation of 1/|S|:
//                                   keep bit i if (Q | 2^i) * |S| <= 1.0
//                     cycle 24      final product R * Q, done = 1
//                   The sequencer holds the instruction (and therefore R and
//                   S) stable until done.
`default_nettype none

module kf_au #(
    parameter integer W    = 24,
    parameter integer FRAC = 14
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,   // an instruction with e=1 executes this cycle
    input  wire [1:0]   op,      // 00 ADD, 01 SUB, 10 MUL, 11 DIV
    input  wire [W-1:0] r,       // operand R
    input  wire [W-1:0] s,       // operand S
    output wire [W-1:0] y,       // result (for DIV: valid while done = 1)
    output wire         done     // final cycle of a DIV
);
    localparam integer M  = W - 1;              // magnitude bits
    localparam integer BW = $clog2(M);          // bit-position counter width
    localparam [M-1:0]  MAG_MAX = {M{1'b1}};
    localparam [31:0]   TOP32   = M - 1;
    localparam [BW-1:0] TOP_BIT = TOP32[BW-1:0];
    localparam [1:0] OP_SUB = 2'b01, OP_DIV = 2'b11;
    localparam [1:0] S_IDLE = 2'd0, S_APPROX = 2'd1, S_FINAL = 2'd2;

    wire         r_sgn = r[W-1];
    wire [M-1:0] r_mag = r[M-1:0];
    wire         s_sgn = s[W-1];
    wire [M-1:0] s_mag = s[M-1:0];

    // ------------------------------------------------------------------
    // Adder / subtractor: sign-magnitude, saturating
    // ------------------------------------------------------------------
    wire         s_eff   = s_sgn ^ (op == OP_SUB);   // sign of the addend
    wire         eff_sub = r_sgn ^ s_eff;            // magnitudes subtract
    wire [M:0]   mag_sum = {1'b0, r_mag} + {1'b0, s_mag};
    wire [M:0]   mag_dif = {1'b0, r_mag} - {1'b0, s_mag};
    wire         borrow  = mag_dif[M];               // |S| > |R|
    wire [M-1:0] dif_abs = borrow ? (~mag_dif[M-1:0] + 1'b1) : mag_dif[M-1:0];
    wire [M-1:0] as_mag  = eff_sub ? dif_abs : (mag_sum[M] ? MAG_MAX : mag_sum[M-1:0]);
    wire         as_sgn  = (eff_sub & borrow) ? s_eff : r_sgn;
    wire [W-1:0] as_res  = {as_sgn & (|as_mag), as_mag};

    // ------------------------------------------------------------------
    // DIV state machine and the shared multiplier
    // ------------------------------------------------------------------
    reg  [1:0]    state;
    reg  [M-1:0]  q;          // reciprocal under construction
    reg  [BW-1:0] bitpos;     // bit being tested

    wire approx = (state == S_APPROX);
    wire fin    = (state == S_FINAL);

    wire [M-1:0] q_try = q | ({{(M-1){1'b0}}, 1'b1} << bitpos);

    // IDLE: R*S (MUL)   APPROX: q_try*S   FINAL: R*Q
    wire [M-1:0]   mul_x = approx ? q_try : r_mag;
    wire [M-1:0]   mul_y = fin    ? q     : s_mag;
    wire [2*M-1:0] p     = mul_x * mul_y;          // Q18.28

    // Q18.28 -> Q9.14: truncate, saturate on overflow, sign = sign(R)^sign(S)
    wire         p_ovf  = |p[2*M-1:M+FRAC];
    wire [M-1:0] pm_mag = p_ovf ? MAG_MAX : p[M+FRAC-1:FRAC];
    wire [W-1:0] pm_res = {(r_sgn ^ s_sgn) & (|pm_mag), pm_mag};

    // reciprocal test: q_try * |S| <= 1.0, i.e. p <= 2^(2*FRAC)
    wire p_le_one = ~|p[2*M-1:2*FRAC+1] & ~(p[2*FRAC] & |p[2*FRAC-1:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else case (state)
            S_IDLE:   if (start && op == OP_DIV) state <= S_APPROX;
            S_APPROX: if (bitpos == {BW{1'b0}})  state <= S_FINAL;
            default:  state <= S_IDLE;           // S_FINAL
        endcase
    end

    // q/bitpos are (re)initialized whenever no search is running, so they
    // need no reset.
    always @(posedge clk) begin
        if (!approx) begin
            q      <= {M{1'b0}};
            bitpos <= TOP_BIT;
        end else begin
            if (p_le_one) q <= q_try;
            bitpos <= bitpos - 1'b1;
        end
    end

    assign done = fin;
    assign y    = op[1] ? pm_res : as_res;      // MUL and DIV use the product

endmodule

`default_nettype wire
