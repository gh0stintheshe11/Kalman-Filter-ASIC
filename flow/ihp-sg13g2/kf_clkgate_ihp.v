// kf_clkgate_ihp.v -- kf_clkgate mapped to the IHP SG13G2 integrated clock
// gate (latch-based, positive edge).  Replaces rtl/kf_clkgate.v in the
// physical flow; same ports and behavior.
`default_nettype none

module kf_clkgate (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    sg13g2_lgcp_1 u_icg (.CLK(clk), .GATE(en), .GCLK(gclk));
endmodule

`default_nettype wire
