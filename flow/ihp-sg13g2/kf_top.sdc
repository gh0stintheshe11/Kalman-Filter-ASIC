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

# I/O: 20 % of the period is budgeted outside the block on both sides.
# All inputs except clk and rst_n are registered right at the boundary.
set io_delay [expr {0.2 * $period}]
set data_inputs [get_ports {start write dir[*] data_in[*]}]
set_input_delay  $io_delay -clock clk $data_inputs
set_output_delay $io_delay -clock clk [all_outputs]
set_driving_cell -lib_cell sg13g2_buf_4 -pin X $data_inputs
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [get_ports {clk rst_n}]
set_load 0.006 [all_outputs]

# rst_n is asserted asynchronously and only feeds the two-flop reset
# synchronizer, whose output drives all other asynchronous resets (those
# recovery/removal checks remain timed).
set_false_path -from [get_ports rst_n]

set_max_fanout 10 [current_design]
