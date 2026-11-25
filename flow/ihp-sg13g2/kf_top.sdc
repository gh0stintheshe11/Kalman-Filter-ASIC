# kf_top timing constraints (used for place & route and for signoff STA).
#
# Values follow LibreLane's generic block constraints with the IHP SG13G2
# defaults, written out explicitly.  The clock period comes from
# CLOCK_PERIOD in config.yaml.

set period $::env(CLOCK_PERIOD)
create_clock [get_ports clk] -name clk -period $period
set_propagated_clock [all_clocks]
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# On-chip variation: +/-5 % derate on late/early paths
set_timing_derate -early 0.95
set_timing_derate -late  1.05

# I/O: 20 % of the period is budgeted outside the block for the inputs
# (all except clk and rst_n are registered right at the boundary) and for
# READY.  data_out is read combinationally from the register file and in
# the chip goes straight into a register of the SPI slave (rtl/kf_spi.v),
# so it gets the whole period.
set io_delay [expr {0.2 * $period}]
set data_inputs [get_ports {start write dir[*] data_in[*]}]
set_input_delay  $io_delay -clock clk $data_inputs
set_output_delay $io_delay -clock clk [get_ports ready]
set_output_delay 0 -clock clk [get_ports {data_out[*]}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin X $data_inputs
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [get_ports {clk rst_n}]
set_load 0.006 [all_outputs]

# rst_n is asserted asynchronously and only feeds the two-flop reset
# synchronizer, whose output drives all other asynchronous resets (those
# recovery/removal checks remain timed).
set_false_path -from [get_ports rst_n]

# Register file -> operand registers: hold paths are false.  An operand
# register (ma, mb, md, me, ms1, ms2 in S1, the base register xc in EX)
# captures data from the register file only when an instruction issues or
# enters EX.  If that instruction reads the register that is being written on
# the same clock edge, the forwarding multiplexer selects the value being
# written (acc_next), not the register; for any other register the AND-OR
# read port blocks it (select 0).  So a register-file flip-flop that
# changes on an edge never reaches an operand register on that edge, and
# hold repair need not delay these paths -- it would put delay cells into
# the read ports, on the setup-critical operand paths.  Paths from the
# instruction register, the select logic and the forwarding controls keep
# their hold checks, and all setup paths are kept.  Gate-level simulation
# with fast-corner delays (make gls SDF=1 SDF_CORNER=nom_fast_1p32V_m40C)
# exercises these paths at speed.
set rf_flops [get_cells -quiet -of_objects [get_pins -quiet -filter "direction == output" \
    -of_objects [get_nets -quiet {u_rf.g_reg*.r*}]]]
set opnd_flops [get_cells -quiet -of_objects [get_pins -quiet -filter "direction == output" \
    -of_objects [get_nets -quiet {ma[*] mb[*] md[*] me[*] ms1 ms2 xc[*]}]]]
if {[llength $rf_flops] > 0 && [llength $opnd_flops] > 0} {
    set_false_path -hold -from $rf_flops -to $opnd_flops
}

# Fanout guideline (LibreLane's MAX_FANOUT_CONSTRAINT, the target of design
# repair).  The signoff check also applies the IHP library's
# default_max_fanout of 8.
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
