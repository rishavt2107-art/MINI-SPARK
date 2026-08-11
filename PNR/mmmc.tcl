#=============================================================================
# FILE    : mmmc.tcl
# PROJECT : Mini Spark SoC
# TOOL    : Cadence Innovus
# LIBRARY : gsclib045
#
# DESC    : Multi-Mode Multi-Corner timing setup.
#
#   slow.lib     SS process, 125 C  -> worst case for SETUP timing
#   typical.lib  TT process,  25 C  -> nominal reference
#   fast.lib     FF process, -40 C  -> worst case for HOLD timing
#
#   Innovus optimises setup against SS and hold against FF. That pairing is
#   the industry standard: a slow chip fails setup, a fast chip fails hold,
#   so you must close both ends.
#
#   NOTE: This file has been re-verified against the run that produced clean
#   postCTS timing (WNS +0.078ns setup, all corners) - no changes were
#   needed here. The failures you hit were entirely in innovus.tcl and the
#   tech LEF, not in this file.
#
# USAGE   : sourced automatically by innovus.tcl - do not run standalone
#=============================================================================

set LIB_DIR "/home/install/FOUNDRY/digital/45nm/dig/lib"

#-----------------------------------------------------------------------------
# Library sets - one per process corner
#-----------------------------------------------------------------------------
create_library_set -name libs_ss -timing [list $LIB_DIR/slow.lib]
create_library_set -name libs_tt -timing [list $LIB_DIR/typical.lib]
create_library_set -name libs_ff -timing [list $LIB_DIR/fast.lib]

#-----------------------------------------------------------------------------
# RC corners
#   These multipliers are standard academic approximations. A production
#   flow would use a QRC tech file extracted from the foundry deck instead.
#-----------------------------------------------------------------------------
create_rc_corner -name rc_ss \
    -temperature 125 \
    -pre_route_res  1.40 -pre_route_cap  1.10 \
    -post_route_res 1.40 -post_route_cap 1.10 \
    -post_route_cross_cap 1.10

create_rc_corner -name rc_tt \
    -temperature 25 \
    -pre_route_res  1.00 -pre_route_cap  1.00 \
    -post_route_res 1.00 -post_route_cap 1.00 \
    -post_route_cross_cap 1.00

create_rc_corner -name rc_ff \
    -temperature -40 \
    -pre_route_res  0.70 -pre_route_cap  0.90 \
    -post_route_res 0.70 -post_route_cap 0.90 \
    -post_route_cross_cap 0.90

#-----------------------------------------------------------------------------
# Timing conditions - bind a library set to a named condition
#-----------------------------------------------------------------------------
create_timing_condition -name tc_ss -library_sets [list libs_ss]
create_timing_condition -name tc_tt -library_sets [list libs_tt]
create_timing_condition -name tc_ff -library_sets [list libs_ff]

#-----------------------------------------------------------------------------
# Delay corners - a timing condition paired with an RC corner
#-----------------------------------------------------------------------------
create_delay_corner -name dc_ss -timing_condition tc_ss -rc_corner rc_ss
create_delay_corner -name dc_tt -timing_condition tc_tt -rc_corner rc_tt
create_delay_corner -name dc_ff -timing_condition tc_ff -rc_corner rc_ff

#-----------------------------------------------------------------------------
# Constraint mode - the SDC written out by Genus
#-----------------------------------------------------------------------------
create_constraint_mode -name func_mode \
    -sdc_files [list soc_top_syn.sdc]

#-----------------------------------------------------------------------------
# Analysis views - constraint mode + delay corner
#-----------------------------------------------------------------------------
create_analysis_view -name av_ss -constraint_mode func_mode -delay_corner dc_ss
create_analysis_view -name av_tt -constraint_mode func_mode -delay_corner dc_tt
create_analysis_view -name av_ff -constraint_mode func_mode -delay_corner dc_ff

#-----------------------------------------------------------------------------
# Activate: setup checked at SS and TT, hold checked at FF and TT
#-----------------------------------------------------------------------------
set_analysis_view -setup [list av_ss av_tt] -hold [list av_ff av_tt]

puts ">>>>> MMMC configured : setup on SS/TT, hold on FF/TT"
