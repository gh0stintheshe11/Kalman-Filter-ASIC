// kf_clkgate.v -- integrated clock gate, behavioral model.
//
// The enable is latched while clk is low, so gclk = clk & en_latched cannot
// glitch.  This model is used for RTL simulation; the physical flow replaces
// this file with a wrapper around the PDK cell
// (flow/ihp-sg13g2/kf_clkgate_ihp.v, sg13g2_lgcp_1).
`default_nettype none

module kf_clkgate (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    reg en_l;
    /* verilator lint_off LATCH */
    always @(*)
        if (!clk) en_l = en;
    /* verilator lint_on LATCH */
    assign gclk = clk & en_l;
endmodule

`default_nettype wire
