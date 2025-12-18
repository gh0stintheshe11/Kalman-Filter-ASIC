#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Thu Dec 18 04:34:43 2025                
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
set init_lef_file /nfs/vrg/cmc/cmc/kits/tsmc_65nm_libs/OA_libs/tcbn65gplus/tcbn65gplus_200a/TSMCHOME/digital/Back_End/lef/tcbn65gplus_200a/lef/tcbn65gplus_9lmT2.lef
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
floorPlan -site core -r 1 0.7 0.0 0.0 0.0 0.0
uiSetTool select
getIoFlowFlag
fit
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -edge 0 -layer 3 -spreadType side -pin {{DATA_IN[0]} {DATA_IN[1]} {DATA_IN[2]} {DATA_IN[3]} {DATA_IN[4]} {DATA_IN[5]} {DATA_IN[6]} {DATA_IN[7]} {DATA_IN[8]} {DATA_IN[9]} {DATA_IN[10]} {DATA_IN[11]} {DATA_IN[12]} {DATA_IN[13]} {DATA_IN[14]} {DATA_IN[15]} {DATA_IN[16]} {DATA_IN[17]} {DATA_IN[18]} {DATA_IN[19]} {DATA_IN[20]} {DATA_IN[21]} {DATA_IN[22]} {DATA_IN[23]} {DIR[0]} {DIR[1]} {DIR[2]} {DIR[3]} {DIR[4]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -edge 2 -layer 3 -spreadType side -pin {{DATA_OUT[0]} {DATA_OUT[1]} {DATA_OUT[2]} {DATA_OUT[3]} {DATA_OUT[4]} {DATA_OUT[5]} {DATA_OUT[6]} {DATA_OUT[7]} {DATA_OUT[8]} {DATA_OUT[9]} {DATA_OUT[10]} {DATA_OUT[11]} {DATA_OUT[12]} {DATA_OUT[13]} {DATA_OUT[14]} {DATA_OUT[15]} {DATA_OUT[16]} {DATA_OUT[17]} {DATA_OUT[18]} {DATA_OUT[19]} {DATA_OUT[20]} {DATA_OUT[21]} {DATA_OUT[22]} {DATA_OUT[23]} READY}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -edge 3 -layer 3 -spreadType side -pin {{rom_waddr[0]} {rom_waddr[1]} {rom_waddr[2]} {rom_waddr[3]} {rom_waddr[4]} {rom_waddr[5]} {rom_waddr[6]} {rom_waddr[7]} {rom_wdata[0]} {rom_wdata[1]} {rom_wdata[2]} {rom_wdata[3]} {rom_wdata[4]} {rom_wdata[5]} {rom_wdata[6]} {rom_wdata[7]} {rom_wdata[8]} {rom_wdata[9]} {rom_wdata[10]} {rom_wdata[11]} {rom_wdata[12]} {rom_wdata[13]} {rom_wdata[14]} {rom_wdata[15]} rom_we}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -side Top -layer 3 -assign 0.0 0.0 -pin {WRITE START rst_n clk {loop_addr[0]} {loop_addr[1]} {loop_addr[2]} {loop_addr[3]} {loop_addr[4]} {loop_addr[5]} {loop_addr[6]} {loop_addr[7]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -side Top -layer 3 -assign 0.7 320.4 -pin {WRITE START rst_n clk {loop_addr[0]} {loop_addr[1]} {loop_addr[2]} {loop_addr[3]} {loop_addr[4]} {loop_addr[5]} {loop_addr[6]} {loop_addr[7]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -side Top -layer 3 -assign 0.0 0.0 -pin {clk {loop_addr[0]} {loop_addr[1]} {loop_addr[2]} {loop_addr[3]} {loop_addr[4]} {loop_addr[5]} {loop_addr[6]} {loop_addr[7]} START rst_n WRITE}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -edge 1 -layer 3 -spreadType side -pin {clk {loop_addr[0]} {loop_addr[1]} {loop_addr[2]} {loop_addr[3]} {loop_addr[4]} {loop_addr[5]} {loop_addr[6]} {loop_addr[7]} START rst_n WRITE}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -edge 1 -layer 3 -spreadType side -pin {clk {loop_addr[0]} {loop_addr[1]} {loop_addr[2]} {loop_addr[3]} {loop_addr[4]} {loop_addr[5]} {loop_addr[6]} {loop_addr[7]} START rst_n WRITE}
setPinAssignMode -pinEditInBatch false
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
setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false -rows_without_stripes_only false -extend_to_closest_target none -stop_at_last_wire_for_area false -partial_set_thru_domain false -ignore_nondefault_domains false -trim_antenna_back_to_shape none -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size false -split_vias false -orthogonal_only true -allow_jog { padcore_ring  block_ring } -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape   }
addStripe -nets {VDD VSS} -layer M4 -direction vertical -width 1 -spacing 1 -set_to_set_distance 4 -start_from left -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit AP -padcore_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid None
setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false -rows_without_stripes_only false -extend_to_closest_target none -stop_at_last_wire_for_area false -partial_set_thru_domain false -ignore_nondefault_domains false -trim_antenna_back_to_shape none -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size false -split_vias false -orthogonal_only true -allow_jog { padcore_ring  block_ring } -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape   }
addStripe -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 1 -set_to_set_distance 4 -start_from bottom -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit AP -padcore_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid None
setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false -rows_without_stripes_only false -extend_to_closest_target none -stop_at_last_wire_for_area false -partial_set_thru_domain false -ignore_nondefault_domains false -trim_antenna_back_to_shape none -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width -stacked_via_top_layer AP -stacked_via_bottom_layer M1 -via_using_exact_crossover_size false -split_vias false -orthogonal_only true -allow_jog { padcore_ring  block_ring } -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape   }
addStripe -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 1 -set_to_set_distance 4 -start_from bottom -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit AP -padcore_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid None
setPlaceMode -fp false
place_design
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -edge 0 -layer 3 -spreadType side -pin {{DATA_IN[0]} {DATA_IN[1]} {DATA_IN[2]} {DATA_IN[3]} {DATA_IN[4]} {DATA_IN[5]} {DATA_IN[6]} {DATA_IN[7]} {DATA_IN[8]} {DATA_IN[9]} {DATA_IN[10]} {DATA_IN[11]} {DATA_IN[12]} {DATA_IN[13]} {DATA_IN[14]} {DATA_IN[15]} {DATA_IN[16]} {DATA_IN[17]} {DATA_IN[18]} {DATA_IN[19]} {DATA_IN[20]} {DATA_IN[21]} {DATA_IN[22]} {DATA_IN[23]} {DIR[0]} {DIR[1]} {DIR[2]} {DIR[3]} {DIR[4]}}
setPinAssignMode -pinEditInBatch false
zoomBox -6.077 6.370 5.119 -4.410
selectObject IO_Pin {DATA_IN[0]}
deselectAll
selectObject IO_Pin VSS
deselectAll
fit
setSrouteMode -viaConnectToShape { stripe }
sroute -connect { blockPin padPin padRing corePin floatingStripe } -layerChangeRange { M1(1) AP(10) } -blockPinTarget { nearestTarget } -padPinPortConnect { allPort oneGeom } -padPinTarget { nearestTarget } -corePinTarget { firstAfterRowEnd } -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } -allowJogging 1 -crossoverViaLayerRange { M1(1) AP(10) } -allowLayerChange 1 -blockPin useLef -targetViaLayerRange { M1(1) AP(10) }
setNanoRouteMode -quiet -timingEngine {}
setNanoRouteMode -quiet -routeTopRoutingLayer default
setNanoRouteMode -quiet -routeBottomRoutingLayer default
setNanoRouteMode -quiet -drouteEndIteration default
setNanoRouteMode -quiet -routeWithTimingDriven false
setNanoRouteMode -quiet -routeWithSiDriven false
routeDesign -globalDetail
setVerifyGeometryMode -area { 0 0 0 0 } -minWidth true -minSpacing true -minArea true -sameNet true -short true -overlap true -offRGrid false -offMGrid true -mergedMGridCheck true -minHole true -implantCheck true -minimumCut true -minStep true -viaEnclosure true -antenna false -insuffMetalOverlap true -pinInBlkg false -diffCellViol true -sameCellViol false -padFillerCellsOverlap true -routingBlkgPinOverlap true -routingCellBlkgOverlap true -regRoutingOnly false -stackedViasOnRegNet false -wireExt true -useNonDefaultSpacing false -maxWidth true -maxNonPrefLength -1 -error 1000
verifyGeometry
setVerifyGeometryMode -area { 0 0 0 0 }
saveDesign -cellview {tcbn65gplus kf_top layout}
saveDesign kf_top
editSplit
editSplit
saveDesign kf_top
