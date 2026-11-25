// kf_units_tb.v -- wrapper that exposes the arithmetic units to cocotb.
`default_nettype none

module kf_units_tb (
    input  wire        clk,
    input  wire        rst_n,
    // kf_booth + kf_mul: floor(a * b / 2^14) of two magnitudes
    input  wire [22:0] mul_a,
    input  wire [22:0] mul_b,
    output wire [31:0] mul_p,
    // kf_dot
    input  wire [23:0] dot_base,
    input  wire [31:0] dot_x1,
    input  wire        dot_s1,
    input  wire [31:0] dot_x2,
    input  wire        dot_s2,
    input  wire        dot_m2,
    output wire [23:0] dot_y,
    // kf_rcp
    input  wire        rcp_start,
    input  wire [23:0] rcp_s,
    output wire        rcp_busy,
    output wire        rcp_last,
    output wire [23:0] rcp_rinv_next,
    output wire [23:0] rcp_rinv
);
    wire [35:0] bd;
    kf_booth u_booth (.b(mul_b), .bd(bd));
    kf_mul   u_mul   (.a(mul_a), .bd(bd), .p(mul_p));
    // kf_dot takes whether each product is subtracted from |base|
    kf_dot   u_dot   (.base(dot_base), .x1(dot_x1), .e1(dot_s1 ^ dot_base[23]), .x2(dot_x2),
                      .e2((dot_s2 ^ dot_base[23]) & dot_m2), .m2(dot_m2), .y(dot_y));
    kf_rcp   u_rcp   (.clk(clk), .rst_n(rst_n), .start(rcp_start), .s(rcp_s), .busy(rcp_busy),
                      .last(rcp_last), .rinv_next(rcp_rinv_next), .rinv(rcp_rinv));
endmodule

`default_nettype wire
