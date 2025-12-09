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

# Set don't touch on sub-modules to preserve hierarchy (use actual instance names)
# Note: Verilog is case-sensitive for module/instance names
set_dont_touch [get_cells Router_A]
set_dont_touch [get_cells Memory_Registers]
set_dont_touch [get_cells Router_B]
set_dont_touch [get_cells AU]
set_dont_touch [get_cells Sequencer]

# Also preserve sub-sub-modules if needed
set_dont_touch [get_cells AU/Mult_Inv]
set_dont_touch [get_cells Sequencer/ROM]
set_dont_touch [get_cells Memory_Registers/Data_Bank_inst]
set_dont_touch [get_cells Memory_Registers/RQ_inst]
set_dont_touch [get_cells Memory_Registers/RD_inst]

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
