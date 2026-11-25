// kf_units_tb.v -- wrapper that exposes the arithmetic units to cocotb.
`default_nettype none

module kf_units_tb (
    input  wire        clk,
    input  wire        rst_n,
    // kf_mul
    input  wire [23:0] mul_a,
    input  wire [23:0] mul_b,
    output wire [23:0] mul_y,
    // kf_addsub
    input  wire [23:0] as_a,
    input  wire [23:0] as_b,
    input  wire        as_sub,
    output wire [23:0] as_y,
    // kf_rcp
    input  wire        rcp_start,
    input  wire [23:0] rcp_s,
    output wire        rcp_busy,
    output wire [23:0] rcp_rinv
);
    kf_mul    u_mul (.a(mul_a), .b(mul_b), .y(mul_y));
    kf_addsub u_as  (.a(as_a), .b(as_b), .sub(as_sub), .y(as_y));
    kf_rcp    u_rcp (.clk(clk), .rst_n(rst_n), .start(rcp_start), .s(rcp_s),
                     .busy(rcp_busy), .rinv(rcp_rinv));
endmodule

`default_nettype wire
