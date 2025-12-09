# define standard cell libraries
set search_path {. /CMC/kits/tsmc_65nm_libs/tcbn65gplus/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b}
set link_library {tcbn65gpluswc.db}
set target_library {tcbn65gpluswc.db}
set symbol_library {tcbn65gpluswc.db}

# read Verilog RTL - read all module files
read_file -format verilog {mem_reg.v router_b.v au.v sequencer.v kf_top.v}

# Set top-level design
current_design kf_top
link

# Set don't touch on sub-modules to preserve hierarchy
set_dont_touch [get_designs Memory_Registers]
set_dont_touch [get_designs Router_B]
set_dont_touch [get_designs AU]
set_dont_touch [get_designs Sequencer]

# synthesize/compile design
compile_ultra

# reports
report_timing
report_area
report_timing > ./syn_report_timing.txt
report_area > ./syn_report_area.txt

# export files for next step: place & route
write -hierarchy -format verilog -output kf_top_syn.v
write_sdc kf_top_syn.sdc
