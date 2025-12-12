# define standard cell libraries
set search_path {. /CMC/kits/tsmc_65nm_libs/tcbn65gplus/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b}
set link_library {tcbn65gpluswc.db}
set target_library {tcbn65gpluswc.db}
set symbol_library {tcbn65gpluswc.db}

# read Verilog RTL - read all module files
read_file -format verilog {../src/router_a.v ../src/mem_reg.v ../src/router_b.v ../src/au.v ../src/sequencer.v ../src/kf_top.v}

# Set top-level design
current_design kf_top
link

# Uniquify the design to avoid conflicts
uniquify

# Preserve hierarchy by preventing ungrouping of sub-designs
# This is different from set_dont_touch - it allows technology mapping
# but prevents the modules from being merged together
set_ungroup [get_designs router_a] false
set_ungroup [get_designs mem_reg] false
set_ungroup [get_designs router_b] false
set_ungroup [get_designs au] false
set_ungroup [get_designs sequencer] false
set_ungroup [get_designs mult_inv] false
set_ungroup [get_designs rom_256x16] false
set_ungroup [get_designs Data_Bank] false
set_ungroup [get_designs RQ] false
set_ungroup [get_designs RD] false

# synthesize/compile design
compile_ultra

# reports
report_timing
report_area
report_timing > ./syn_report_timing_kf_top.txt
report_area > ./syn_report_area_kf_top.txt

# export files for next step: place & route
write -hierarchy -format verilog -output kf_top_syn.v
write_sdc kf_top_syn.sdc
write -hierarchy -format ddc -output kf_top_syn.ddc
