#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Thu Dec 18 03:43:22 2025                
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
set init_mmmc_file mem_reg.view
set init_oa_search_lib {}
set init_original_verilog_files mem_reg_syn.v
set init_pwr_net VDD
set init_verilog mem_reg_syn.v
set latch_time_borrow_mode max_borrow
set pegDefaultResScaleFactor 1
set pegDetailResScaleFactor 1
set report_inactive_arcs_format {from to when arc_type sense reason}
set soft_stack_size_limit 128
init_design
fit
getIoFlowFlag
setIoFlowFlag 0
floorPlan -site core -r 0.972200158856 0.699995 0.0 0.0 0.0 0.0
uiSetTool select
getIoFlowFlag
fit
setIoFlowFlag 0
floorPlan -site core -r 1 0.7 0.0 0.0 0.0 0.0
uiSetTool select
getIoFlowFlag
fit
setIoFlowFlag 0
floorPlan -site core -r 0.971428571429 0.69944 0.0 0.0 0.0 0.0
uiSetTool select
getIoFlowFlag
fit
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -side Right -layer 3 -spreadType side -pin {{A[0]} {A[1]} {A[2]} {A[3]} {A[4]} {A[5]} {A[6]} {A[7]} {A[8]} {A[9]} {A[10]} {A[11]} {A[12]} {A[13]} {A[14]} {A[15]} {A[16]} {A[17]} {A[18]} {A[19]} {A[20]} {A[21]} {A[22]} {A[23]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -side Right -layer 2 -spreadType side -pin {{B[0]} {B[1]} {B[2]} {B[3]} {B[4]} {B[5]} {B[6]} {B[7]} {B[8]} {B[9]} {B[10]} {B[11]} {B[12]} {B[13]} {B[14]} {B[15]} {B[16]} {B[17]} {B[18]} {B[19]} {B[20]} {B[21]} {B[22]} {B[23]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -side Right -layer 2 -spreadType side -pin {{B[0]} {B[1]} {B[2]} {B[3]} {B[4]} {B[5]} {B[6]} {B[7]} {B[8]} {B[9]} {B[10]} {B[11]} {B[12]} {B[13]} {B[14]} {B[15]} {B[16]} {B[17]} {B[18]} {B[19]} {B[20]} {B[21]} {B[22]} {B[23]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -side Right -layer 3 -spreadType side -pin {{B[0]} {B[1]} {B[2]} {B[3]} {B[4]} {B[5]} {B[6]} {B[7]} {B[8]} {B[9]} {B[10]} {B[11]} {B[12]} {B[13]} {B[14]} {B[15]} {B[16]} {B[17]} {B[18]} {B[19]} {B[20]} {B[21]} {B[22]} {B[23]} {A[0]} {A[1]} {A[2]} {A[3]} {A[4]} {A[5]} {A[6]} {A[7]} {A[8]} {A[9]} {A[10]} {A[11]} {A[12]} {A[13]} {A[14]} {A[15]} {A[16]} {A[17]} {A[18]} {A[19]} {A[20]} {A[21]} {A[22]} {A[23]}}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -side Bottom -layer 3 -spreadType side -pin {{RD[0]} {RD[1]} {RD[2]} {RD[3]} {RD[4]} {RD[5]} {RD[6]} {RD[7]} {RD[8]} {RD[9]} {RD[10]} {RD[11]} {RD[12]} {RD[13]} {RD[14]} {RD[15]} {RD[16]} {RD[17]} {RD[18]} {RD[19]} {RD[20]} {RD[21]} {RD[22]} {RD[23]} {RQ[0]} {RQ[1]} {RQ[2]} {RQ[3]} {RQ[4]} {RQ[5]} {RQ[6]} {RQ[7]} {RQ[8]} {RQ[9]} {RQ[10]} {RQ[11]} {RQ[12]} {RQ[13]} {RQ[14]} {RQ[15]} {RQ[16]} {RQ[17]} {RQ[18]} {RQ[19]} {RQ[20]} {RQ[21]} {RQ[22]} {RQ[23]} {rd_d[0]} {rd_d[1]} {rd_d[2]} {rd_d[3]} {rd_d[4]} {rd_d[5]} {rd_d[6]} {rd_d[7]} {rd_d[8]} {rd_d[9]} {rd_d[10]} {rd_d[11]} {rd_d[12]} {rd_d[13]} {rd_d[14]} {rd_d[15]} {rd_d[16]} {rd_d[17]} {rd_d[18]} {rd_d[19]} {rd_d[20]} {rd_d[21]} {rd_d[22]} {rd_d[23]} rd_we {rq_d[0]} {rq_d[1]} {rq_d[2]} {rq_d[3]} {rq_d[4]} {rq_d[5]} {rq_d[6]} {rq_d[7]} {rq_d[8]} {rq_d[9]} {rq_d[10]} {rq_d[11]} {rq_d[12]} {rq_d[13]} {rq_d[14]} {rq_d[15]} {rq_d[16]} {rq_d[17]} {rq_d[18]} {rq_d[19]} {rq_d[20]} {rq_d[21]} {rq_d[22]} {rq_d[23]} rq_we}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -side Top -layer 3 -spreadType side -pin {{RQ[0]} {RQ[1]} {RQ[2]} {RQ[3]} {RQ[4]} {RQ[5]} {RQ[6]} {RQ[7]} {RQ[8]} {RQ[9]} {RQ[10]} {RQ[11]} {RQ[12]} {RQ[13]} {RQ[14]} {RQ[15]} {RQ[16]} {RQ[17]} {RQ[18]} {RQ[19]} {RQ[20]} {RQ[21]} {RQ[22]} {RQ[23]} {rq_d[0]} {rq_d[1]} {rq_d[2]} {rq_d[3]} {rq_d[4]} {rq_d[5]} {rq_d[6]} {rq_d[7]} {rq_d[8]} {rq_d[9]} {rq_d[10]} {rq_d[11]} {rq_d[12]} {rq_d[13]} {rq_d[14]} {rq_d[15]} {rq_d[16]} {rq_d[17]} {rq_d[18]} {rq_d[19]} {rq_d[20]} {rq_d[21]} {rq_d[22]} {rq_d[23]} rq_we}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -fixOverlap 1 -spreadDirection clockwise -side Left -layer 3 -spreadType side -pin {{dira[0]} {dira[1]} {dira[2]} {dira[3]} {dira[4]} {dirb[0]} {dirb[1]} {dirb[2]} {dirb[3]} {dirb[4]} write {data[0]} {data[1]} {data[2]} {data[3]} {data[4]} {data[5]} {data[6]} {data[7]} {data[8]} {data[9]} {data[10]} {data[11]} {data[12]} {data[13]} {data[14]} {data[15]} {data[16]} {data[17]} {data[18]} {data[19]} {data[20]} {data[21]} {data[22]} {data[23]} clk}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -side Bottom -layer 3 -spreadType side -pin {{RD[0]} {RD[1]} {RD[2]} {RD[3]} {RD[4]} {RD[5]} {RD[6]} {RD[7]} {RD[8]} {RD[9]} {RD[10]} {RD[11]} {RD[12]} {RD[13]} {RD[14]} {RD[15]} {RD[16]} {RD[17]} {RD[18]} {RD[19]} {RD[20]} {RD[21]} {RD[22]} {RD[23]} {rd_d[0]} {rd_d[1]} {rd_d[2]} {rd_d[3]} {rd_d[4]} {rd_d[5]} {rd_d[6]} {rd_d[7]} {rd_d[8]} {rd_d[9]} {rd_d[10]} {rd_d[11]} {rd_d[12]} {rd_d[13]} {rd_d[14]} {rd_d[15]} {rd_d[16]} {rd_d[17]} {rd_d[18]} {rd_d[19]} {rd_d[20]} {rd_d[21]} {rd_d[22]} {rd_d[23]} rd_we}
setPinAssignMode -pinEditInBatch false
getPinAssignMode -pinEditInBatch -quiet
setPinAssignMode -pinEditInBatch true
editPin -pinWidth 0.1 -pinDepth 0.52 -fixOverlap 1 -spreadDirection clockwise -side Bottom -layer 3 -spreadType side -pin {{RD[0]} {RD[1]} {RD[2]} {RD[3]} {RD[4]} {RD[5]} {RD[6]} {RD[7]} {RD[8]} {RD[9]} {RD[10]} {RD[11]} {RD[12]} {RD[13]} {RD[14]} {RD[15]} {RD[16]} {RD[17]} {RD[18]} {RD[19]} {RD[20]} {RD[21]} {RD[22]} {RD[23]} {rd_d[0]} {rd_d[1]} {rd_d[2]} {rd_d[3]} {rd_d[4]} {rd_d[5]} {rd_d[6]} {rd_d[7]} {rd_d[8]} {rd_d[9]} {rd_d[10]} {rd_d[11]} {rd_d[12]} {rd_d[13]} {rd_d[14]} {rd_d[15]} {rd_d[16]} {rd_d[17]} {rd_d[18]} {rd_d[19]} {rd_d[20]} {rd_d[21]} {rd_d[22]} {rd_d[23]} rd_we}
setPinAssignMode -pinEditInBatch false
setPlaceMode -fp false
place_design
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
saveDesign mem_reg
