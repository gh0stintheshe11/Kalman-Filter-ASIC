# kf_chip timing constraints (place & route and signoff STA).
#
# One clock, from the clk pad's core-side pin.  The SPI pins, START and the
# reset are asynchronous to it and pass through two-flop synchronizers
# (rtl/kf_spi.v, the reset synchronizers in kf_chip and kf_top), so their
# input paths are false paths; MISO and READY are sampled by the outside
# world asynchronously (f_SCLK <= f_CLK / 10), so their output paths are
# only bounded in delay.  Everything inside follows the core's constraints
# (flow/ihp-sg13g2/kf_top.sdc), with the core under u_core.

set period $::env(CLOCK_PERIOD)
create_clock [get_pins clk_pad/p2c] -name clk -period $period
set_propagated_clock [all_clocks]
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# On-chip variation: +/-5 % derate on late/early paths
set_timing_derate -early 0.95
set_timing_derate -late  1.05

# ---- I/O ---------------------------------------------------------------------
# Asynchronous inputs into synchronizers.
set_false_path -from [get_ports {rst_n_PAD sclk_PAD cs_n_PAD mosi_PAD start_PAD}]
# Outputs: 16 mA pads, 1.8 pF board load.  The IHP pad models are
# characterized up to ~2.1-2.2 pF at the slow corner, including the pad's
# own ~0.25 pF (max_capacitance on the pad pin; 4 mA pads only 0.66 pF).
# A real board (~10 pF) only makes the off-chip edges slower (the tables
# give ~4.4 ns delay and ~3.8 ns edges at 10 pF, slow corner), which does
# not matter for SPI at f_CLK / 10.  At most 12 ns from the launching clock
# edge to the pad.
set_load 1.8 [get_ports {miso_PAD ready_PAD}]
set_max_delay -ignore_clock_latency 12.0 -to [get_ports {miso_PAD ready_PAD}]
# MISO's output enable follows CS_N (synchronized) and changes only between
# frames, at least 4 core clock periods before the master samples MISO, so
# its enable/disable arcs are not timed against the core clock.  (The
# pad's three_state_disable arc is characterized with a constant 2.1-2.7 ns
# transition, above the I/O library's 1.2 ns limit at any load.)
set_disable_timing -from c2p_en -to pad [get_cells miso_pad]
# Input transition at the pads.
set_input_transition 1.0 [get_ports {clk_PAD rst_n_PAD sclk_PAD cs_n_PAD mosi_PAD start_PAD}]

# ---- core ----------------------------------------------------------------------
# Register file -> operand registers: hold paths are false (see
# flow/ihp-sg13g2/kf_top.sdc for the reasoning; forwarding guarantees that
# an operand register never captures a register on the edge that writes
# it).
set rf_flops [get_cells -quiet -of_objects [get_pins -quiet -filter "direction == output" \
    -of_objects [get_nets -quiet {u_core.u_rf.g_reg*.r*}]]]
set opnd_flops [get_cells -quiet -of_objects [get_pins -quiet -filter "direction == output" \
    -of_objects [get_nets -quiet {u_core.ma[*] u_core.mb[*] u_core.md[*] u_core.me[*]
                                  u_core.ms1 u_core.ms2 u_core.xc[*]}]]]
if {[llength $rf_flops] > 0 && [llength $opnd_flops] > 0} {
    set_false_path -hold -from $rf_flops -to $opnd_flops
}

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
