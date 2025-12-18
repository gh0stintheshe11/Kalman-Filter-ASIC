if {![namespace exists ::IMEX]} { namespace eval ::IMEX {} }
set ::IMEX::dataVar [file dirname [file normalize [info script]]]
set ::IMEX::libVar ${::IMEX::dataVar}/libs

create_library_set -name worst\
   -timing\
    [list ${::IMEX::libVar}/lib/typ/tcbn65gpluswc.lib]
create_library_set -name best\
   -timing\
    [list ${::IMEX::libVar}/mmmc/tcbn65gplusbc.lib]
create_library_set -name typical\
   -timing\
    [list ${::IMEX::libVar}/mmmc/tcbn65gplustc.lib]
create_rc_corner -name worst\
   -preRoute_res 1\
   -postRoute_res {1 1 1}\
   -preRoute_cap 1\
   -postRoute_cap {1 1 1}\
   -postRoute_xcap {1 1 1}\
   -preRoute_clkres 1\
   -preRoute_clkcap 1\
   -postRoute_clkcap {1 1 1}\
   -postRoute_clkres {1 1 1}
create_rc_corner -name best\
   -preRoute_res 1\
   -postRoute_res {1 1 1}\
   -preRoute_cap 1\
   -postRoute_cap {1 1 1}\
   -postRoute_xcap {1 1 1}\
   -preRoute_clkres 1\
   -preRoute_clkcap 1\
   -postRoute_clkcap {1 1 1}\
   -postRoute_clkres {1 1 1}
create_rc_corner -name typical\
   -preRoute_res 1\
   -postRoute_res {1 1 1}\
   -preRoute_cap 1\
   -postRoute_cap {1 1 1}\
   -postRoute_xcap {1 1 1}\
   -preRoute_clkres 1\
   -preRoute_clkcap 1\
   -postRoute_clkcap {1 1 1}\
   -postRoute_clkres {1 1 1}
create_delay_corner -name worst_worst\
   -library_set worst\
   -rc_corner worst
create_delay_corner -name typ_typ\
   -library_set typical\
   -rc_corner typical
create_delay_corner -name best_best\
   -library_set best\
   -rc_corner best
create_constraint_mode -name constraints\
   -sdc_files\
    [list ${::IMEX::libVar}/mmmc/sequencer_syn.sdc]
create_analysis_view -name setup_view -constraint_mode constraints -delay_corner worst_worst
create_analysis_view -name typical_view -constraint_mode constraints -delay_corner typ_typ
create_analysis_view -name hold_view -constraint_mode constraints -delay_corner best_best
set_analysis_view -setup [list setup_view] -hold [list hold_view]
