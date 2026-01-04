#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Sun Jan  4 16:17:03 2026                
#                                                     
#######################################################

#@(#)CDS: Innovus v18.10-p002_1 (64bit) 05/29/2018 19:19 (Linux 2.6.18-194.el5)
#@(#)CDS: NanoRoute 18.10-p002_1 NR180522-1057/18_10-UB (database version 2.30, 418.7.1) {superthreading v1.46}
#@(#)CDS: AAE 18.10-p004 (64bit) 05/29/2018 (Linux 2.6.18-194.el5)
#@(#)CDS: CTE 18.10-p003_1 () May 15 2018 10:23:07 ( )
#@(#)CDS: SYNTECH 18.10-a012_1 () Apr 19 2018 01:27:21 ( )
#@(#)CDS: CPE v18.10-p005
#@(#)CDS: IQRC/TQRC 18.1.1-s118 (64bit) Fri Mar 23 17:23:45 PDT 2018 (Linux 2.6.18-194.el5)

set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
getVersion
win
set ::TimeLib::tsgMarkCellLatchConstructFlag 1
set defHierChar /
set delaycal_input_transition_delay 0.1ps
set distributed_client_message_echo 1
set distributed_mmmc_disable_reports_auto_redirection 0
set enc_enable_print_mode_command_reset_options 1
set floorplan_default_site core
set fpIsMaxIoHeight 0
set init_gnd_net VSS
set init_lef_file {/nfs/vrg/cmc/cmc/kits/tsmc_65nm_libs/OA_libs/tcbn65gplus/tcbn65gplus_200a/TSMCHOME/digital/Back_End/lef/tcbn65gplus_200a/lef/tcbn65gplus_9lmT2.lef /nfs/vrg/cmc/cmc/kits/tsmc_65nm_libs/OA_libs/tpan65gpgv2od3/tpan65gpgv2od3_200b/TSMCHOME/digital/Back_End/lef/tpan65gpgv2od3_200a/mt/9lm/lef/tpan65gpgv2od3_9lm.lef}
set init_mmmc_file kf_top.view
set init_oa_search_lib {}
set init_original_verilog_files kf_top_syn.v
set init_pwr_net VDD
set init_verilog kf_top_syn.v
set latch_time_borrow_mode max_borrow
set pegDefaultResScaleFactor 1
set pegDetailResScaleFactor 1
set report_inactive_arcs_format {from to when arc_type sense reason}
set soft_stack_size_limit 128
init_design
getIoFlowFlag
setIoFlowFlag 0
floorPlan -site core -r 1 0.7 240 240 240 240
uiSetTool select
getIoFlowFlag
fit
createIoRow -site pad -beginOffset 240 -endOffset 240
createIoRow -site corner -corner BL
createIoRow -site corner -corner BR
createIoRow -site corner -corner TR
createIoRow -site corner -corner TL
createIoRow -site corner -corner TL
gui_select -rect {-18.586 810.382 835.959 -24.483}
deselectAll
createIoRow -site corner -side N -beginOffset 240 -endOffset 240
createIoRow -site corner -side W -beginOffset 240 -endOffset 240
createIoRow -site corner -side S -beginOffset 240 -endOffset 240
createIoRow -site corner -side E -beginOffset 240 -endOffset 240
createIoRow -site corner -side E -beginOffset 240 -endOffset 240
gui_select -rect {-21.693 817.632 816.279 -17.232}
deselectAll
selectObject StdRow (480000,1220800,860000,1600800)
deleteSelectedFromFPlan
selectObject StdRow (0,480000,380000,860000)
deleteSelectedFromFPlan
selectObject StdRow (480000,0,860000,380000)
deleteSelectedFromFPlan
selectObject StdRow (1221600,480000,1601600,860000)
deleteSelectedFromFPlan
selectObject StdRow (1221600,480000,1601600,860000)
deleteSelectedFromFPlan
createIoRow -site pad -beginOffset 240 -endOffset 240
gui_select -rect {377.094 742.018 72.566 797.952}
createIoRow -site pad -side N -beginOffset 240 -endOffset 240
createIoRow -site pad -side W -beginOffset 240 -endOffset 240
createIoRow -site pad -side S -beginOffset 240 -endOffset 240
createIoRow -site pad -side E -beginOffset 240 -endOffset 240
createIoRow -site pad -side E -beginOffset 240 -endOffset 240
selectObject StdRow (0,480000,380000,1120800)
deselectAll
selectObject StdRow (480000,1220800,1121600,1600800)
deselectAll
selectObject StdRow (1221600,480000,1601600,1120800)
deselectAll
selectObject StdRow (480000,0,1121600,380000)
deselectAll
selectObject StdRow (0,0,380000,380000)
deselectAll
selectObject StdRow (480000,0,1121600,380000)
deselectAll
selectObject StdRow (0,1220800,380000,1600800)
deselectAll
selectObject StdRow (1221600,1220800,1601600,1600800)
deselectAll
selectObject StdRow (1221600,480000,1601600,1120800)
deselectAll
selectObject StdRow (480000,1220800,1121600,1600800)
deselectAll
gui_select -rect {-22.729 823.847 853.567 -9.982}
deselectAll
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {} -type core_rings -follow core -layer {top M5 bottom M5 left M4 right M4} -width {top 20 bottom 20 left 20 right 201} -spacing {top 2 bottom 2 left 2 right 2} -offset {top 2 bottom 2 left 2 right 2} -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top M5 bottom M5 left M4 right M4} -width {top 20 bottom 20 left 20 right 201} -spacing {top 2 bottom 2 left 2 right 2} -offset {top 2 bottom 2 left 2 right 2} -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top M5 bottom M5 left M4 right M4} -width {top 20 bottom 20 left 20 right 20} -spacing {top 2 bottom 2 left 2 right 2} -offset {top 2 bottom 2 left 2 right 2} -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
gui_select -rect {-24.800 822.811 840.102 -14.125}
deselectAll
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top M5 bottom M5 left M4 right M4} -width {top 12 bottom 12 left 12 right 12} -spacing {top 2 bottom 2 left 2 right 2} -offset {top 2 bottom 2 left 2 right 2} -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top M5 bottom M5 left M4 right M4} -width {top 12 bottom 12 left 12 right 12} -spacing {top 2 bottom 2 left 2 right 2} -offset {top 2 bottom 2 left 2 right 2} -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
