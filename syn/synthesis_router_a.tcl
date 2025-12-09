# define standard cell libraries
set search_path {. /CMC/kits/tsmc_65nm_libs/tcbn65gplus/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b}
set link_library {tcbn65gpluswc.db}
set target_library {tcbn65gpluswc.db}
set symbol_library {tcbn65gpluswc.db}

# read Verilog RTL - read all module files
read_file -format verilog ../src/router_a.v 

# Set top-level design
current_design router_a
link

# synthesize/compile design
compile_ultra

# reports
report_timing
report_area
report_timing > ./syn_report_timing_router_a.txt
report_area > ./syn_report_area_router_a.txt

# export files for next step: place & route
write -hierarchy -format verilog -output router_a_syn.v
write_sdc router_a_syn.sdc
write -hierarchy -format ddc -output router_a_syn.ddc
