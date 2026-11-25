// kf_top_sdf.v -- top level for gate-level simulation with back-annotated
// delays: the routed kf_top netlist, annotated with the SDF file `KF_SDF
// (compile with -gspecify -ginterconnect).  Same ports as kf_top, so the
// black-box tests drive it unchanged.
`default_nettype none

module kf_top_sdf (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        write,
    input  wire [4:0]  dir,
    input  wire [23:0] data_in,
    output wire        ready,
    output wire [23:0] data_out
);
    kf_top dut (
        .clk(clk), .rst_n(rst_n), .start(start), .write(write), .dir(dir),
        .data_in(data_in), .ready(ready), .data_out(data_out)
    );

    initial $sdf_annotate(`KF_SDF, dut);
endmodule

`default_nettype wire
