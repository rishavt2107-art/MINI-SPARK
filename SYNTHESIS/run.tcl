#=============================================================================
# FILE    : run.tcl
# PROJECT : Mini Spark SoC
# TOOL    : Cadence Genus Synthesis Solution  (21.14-s082_1)
# LIBRARY : gsclib045
# TARGET  : 100 MHz  (10 ns clock period)
#
# USAGE   : cd ~/MINISP/SYNTHESIS
#           genus -legacy_ui -f run.tcl
#=============================================================================

set_attribute init_lib_search_path /home/install/FOUNDRY/digital/45nm/dig/lib

set_attribute lef_library {/home/install/FOUNDRY/digital/45nm/dig/lef/gsclib045_tech.lef /home/install/FOUNDRY/digital/45nm/dig/lef/gsclib045_macro.lef}

set_attribute library  slow.lib

set_attribute design_process_node 45
set_attribute information_level 7

file mkdir reports
file mkdir outputs

puts "\n>>>>> SECTION 0 COMPLETE : gsclib045 library loaded\n"


#=============================================================================
# SECTION 1 : READ RTL
#=============================================================================

read_hdl {
    ./alu.v
    ./reg_file.v
    ./control_unit.v
    ./riscv_core.v
    ./pe.v
    ./systolic_array.v
    ./accel_top.v
    ./axi_lite_bus.v
    ./sram_sp_256x32.v
    ./imem_rom.v
    ./soc_top.v
}

puts "\n>>>>> SECTION 1 COMPLETE : 10 RTL files read\n"


#=============================================================================
# SECTION 2 : ELABORATE
#=============================================================================

elaborate soc_top
current_design soc_top

check_design -unresolved  > reports/00_unresolved.rpt
check_design -multidriven > reports/01_multidriven.rpt
check_design -undriven    > reports/02_undriven.rpt

puts "\n>>>>> SECTION 2 COMPLETE : elaborated soc_top"
puts ">>>>> Review reports/00_unresolved.rpt - it MUST be empty\n"


#=============================================================================
# SECTION 3 : TIMING CONSTRAINTS
#=============================================================================

read_sdc ./soc_top.sdc

report_clocks       > reports/03_clocks.rpt
report_timing -lint > reports/04_sdc_lint.rpt

puts "\n>>>>> SECTION 3 COMPLETE : SDC applied, 100 MHz target\n"


#=============================================================================
# SECTION 4 : SYNTHESIS EFFORT
#=============================================================================

set_attribute syn_generic_effort medium
set_attribute syn_map_effort     medium
set_attribute syn_opt_effort     medium


#=============================================================================
# SECTION 5 : GENERIC SYNTHESIS
#=============================================================================

syn_generic

report_area   > reports/10_generic_area.rpt
report_timing > reports/11_generic_timing.rpt

puts "\n>>>>> SECTION 5 COMPLETE : syn_generic\n"


#=============================================================================
# SECTION 6 : TECHNOLOGY MAPPING
#=============================================================================

syn_map

report_area   > reports/20_mapped_area.rpt
report_timing > reports/21_mapped_timing.rpt
report_gates  > reports/22_mapped_gates.rpt

puts "\n>>>>> SECTION 6 COMPLETE : syn_map - now using gsclib045 cells\n"


#=============================================================================
# SECTION 7 : INCREMENTAL OPTIMISATION
#=============================================================================

syn_opt

puts "\n>>>>> SECTION 7 COMPLETE : syn_opt\n"


#=============================================================================
# SECTION 8 : TIMING REPORTS
#   Flags below are the ONLY ones this Genus build (21.14-s082_1) accepts
#   for report_timing, confirmed against its own -help dump:
#     -endpoints -summary -lint -verbose -full_pin_names -physical
#     -user_derate -user_mean_derate -user_sigma_derate -incr_derate
#     -gtd -encounter -gui -num_paths -worst -logic_levels -skip_buf
#     -skip_inv -slack_limit -mode -from -through -to -not_through
#   There is NO -nworst, NO -max_paths, NO -early, NO -unconstrained.
#=============================================================================

report_timing -worst 20 -num_paths 20 > reports/30_timing_setup.rpt
report_timing -summary                > reports/32_timing_summary.rpt


#=============================================================================
# SECTION 9 : AREA, POWER, GATE REPORTS
#=============================================================================

report_area  > reports/40_area.rpt
report_gates > reports/42_gates.rpt
report_power > reports/50_power.rpt


#=============================================================================
# SECTION 10 : DESIGN QUALITY REPORTS
#=============================================================================

report_qor        > reports/60_qor.rpt
report_hierarchy  > reports/61_hierarchy.rpt
report_sequential > reports/66_sequential.rpt


#=============================================================================
# SECTION 11 : WRITE OUTPUTS FOR INNOVUS
#=============================================================================

write_hdl                   > outputs/soc_top_netlist.v
write_sdc                   > outputs/soc_top_syn.sdc
write_sdf -timescale ns     > outputs/soc_top.sdf
write_design -basename outputs/soc_top_genus


#=============================================================================
# SECTION 12 : CONSOLE SUMMARY
#=============================================================================

puts "\n"
puts "============================================================"
puts "   MINI SPARK SOC - SYNTHESIS QoR SUMMARY"
puts "============================================================"
report_qor
puts "\n------------------------------------------------------------"
puts "   WORST 3 TIMING PATHS"
puts "------------------------------------------------------------"
report_timing -worst 3
puts "\n------------------------------------------------------------"
puts "   AREA"
puts "------------------------------------------------------------"
report_area

puts "\n"
puts "============================================================"
puts "   SYNTHESIS COMPLETE"
puts "============================================================"
puts "  Netlist : outputs/soc_top_netlist.v"
puts "  SDC     : outputs/soc_top_syn.sdc"
puts "  SDF     : outputs/soc_top.sdf"
puts ""
puts "  MANDATORY CHECKS BEFORE INNOVUS:"
puts "    1. reports/00_unresolved.rpt   must be EMPTY"
puts "    2. reports/30_timing_setup.rpt slack must be POSITIVE and MET"
puts "============================================================"
puts "\n"


#=============================================================================
# SECTION 13 : GUI  (comment out for pure batch runs)
#=============================================================================

gui_show
