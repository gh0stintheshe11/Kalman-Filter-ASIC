// kf_chip_sdf.v -- top level for gate-level simulation of the chip with
// back-annotated delays: the routed kf_chip netlist (pads included),
// annotated with the SDF file `KF_SDF (compile with -gspecify
// -ginterconnect).  Same ports as kf_chip, so tb/test_chip.py drives it
// unchanged.
`default_nettype none

module kf_chip_sdf (
    inout wire clk_PAD,
    inout wire rst_n_PAD,
    inout wire sclk_PAD,
    inout wire cs_n_PAD,
    inout wire mosi_PAD,
    inout wire start_PAD,
    inout wire miso_PAD,
    inout wire ready_PAD
);
    kf_chip dut (
        .clk_PAD(clk_PAD), .rst_n_PAD(rst_n_PAD), .sclk_PAD(sclk_PAD), .cs_n_PAD(cs_n_PAD),
        .mosi_PAD(mosi_PAD), .start_PAD(start_PAD), .miso_PAD(miso_PAD), .ready_PAD(ready_PAD)
    );

    initial $sdf_annotate(`KF_SDF, dut);
endmodule

`default_nettype wire
