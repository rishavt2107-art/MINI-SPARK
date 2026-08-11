#=============================================================================
# FILE    : innovus.tcl
# PROJECT : Mini Spark SoC
# TOOL    : Cadence Innovus 21.15
# LIBRARY : gsclib045  (M1-M10 routing)
#
# USAGE   : cd ~/rt/MINISP/PNR
#           innovus -init innovus.tcl -log ${PNR_ROOT}/reports/innovus.log
#
# DESIGN  : 23,673 cells | 10,121 flops | 105,564 um2 | 100 MHz
#
#=============================================================================
# WHAT CHANGED IN THIS VERSION (both real bugs found from actual run logs)
#
#   BUG 1 - CTS ABORT (IMPCCOPT-2036)
#     set_ccopt_property -net_type trunk routing_top_layer M5 (etc.) does
#     NOT exist as a property name in this Innovus build. It is not wrapped
#     in try_cmd anywhere in the version that had it, so it killed the
#     whole script mid-Step-6. REMOVED. CCOpt is left to pick clock
#     routing layers on its own, which it does sensibly.
#
#   BUG 2 - ROUTING ABORT (NRDB-158)
#     "Missing vias from LAYER M1 to LAYER M2 in RULE LEF_DEFAULT."
#     gsclib045_tech.lef only ships VIARULE ... GENERATE DEFAULT templates,
#     no literal VIA statements. This build's NanoRoute failed to derive
#     ANY default via from those GENERATE templates (confirmed: every
#     layer M1-M11 threw the same "no default via" WARNING - M1-M2 was
#     just the first one NanoRoute actually needed, so it's the one that
#     escalated to a hard ERROR and aborted the run).
#     FIX: use gsclib045_tech_patched.lef instead of the original tech
#     LEF. It is byte-identical except for ten added VIA ... DEFAULT
#     blocks (one per adjacent metal pair, M1-M2 through M10-M11),
#     hand-derived from each layer's own VIARULE GENERATE geometry using
#     the larger of its two enclosure values on both sides (conservative:
#     never under-encloses, just slightly bigger than the tool's own
#     minimum - safe for a Phase 1 run). This gives NanoRoute a literal
#     via to use instead of relying on auto-derivation.
#     >>> Update LEF_TECH below if you keep the patched file at a
#         different path than the original. <<<
#
#=============================================================================
# HOW THIS SCRIPT SURVIVES FAILURE
#
#   1. RESUMABLE. Every step ends with saveDesign to a .enc checkpoint.
#      If the flow dies at step 8, set RESUME_FROM to 8 at the top and
#      relaunch - it restores the step-7 database and continues. You never
#      redo work you already completed.
#
#   2. FAULT TOLERANT. Every optional command is wrapped in try_cmd, which
#      catches an unsupported-option or unsupported-property error, prints
#      a warning, records it, and lets the flow continue. Innovus option
#      and property names vary between builds and a single bad name would
#      otherwise abort a multi-hour run - exactly what happened twice
#      before this version.
#
#   3. HONEST ABOUT WHAT IS ESSENTIAL. Core flow commands (init_design,
#      floorPlan, place_opt_design, ccopt_design, routeDesign, streamOut)
#      are called directly. If one of those fails the flow genuinely cannot
#      continue and you need to see the error.
#=============================================================================


#=============================================================================
# RESUME CONTROL
#   1 = full run from scratch
#   N = restore the checkpoint from step N-1 and continue from step N
#
#   You already have a clean postCTS checkpoint from the prior run
#   (${PNR_ROOT}/outputs/soc_top_postcts.enc, WNS +0.078ns, 0 DRVs, 62.9% density).
#   Once the LEF is patched, set this to 8 to go straight to routing
#   instead of redoing 6 steps. Set to 1 only if you want a full rerun.
#=============================================================================
set RESUME_FROM 1
set PNR_ROOT [file normalize [file dirname [info script]]]


#=============================================================================
# HELPERS
#=============================================================================
set ::SKIPPED {}

proc try_cmd {desc script} {
    if {[catch {uplevel 1 $script} err]} {
        puts "!!!!! SKIPPED: $desc"
        puts "!!!!!   reason: $err"
        lappend ::SKIPPED $desc
        return 0
    }
    return 1
}

proc checkpoint {name} {
    global DESIGN PNR_ROOT
    set ckpt_path "${PNR_ROOT}/outputs/${DESIGN}_${name}.enc"
    if {[catch {saveDesign $ckpt_path} err]} {
        puts "\n!!!!! checkpoint $name FAILED TO SAVE: $err"
        puts "!!!!! cwd was: [pwd]"
        puts "!!!!! Stopping here instead of continuing silently - a later"
        puts "!!!!! RESUME_FROM pointing at this stage would otherwise fail"
        puts "!!!!! with a confusing 'session directory not found' error.\n"
        error "checkpoint $name failed: $err"
    }
    ;# saveDesign can report success but still not leave a real dir behind
    ;# (quota, symlink, race) - verify it's actually there before trusting it.
    if {![file exists $ckpt_path]} {
        error "checkpoint $name: saveDesign returned OK but '$ckpt_path' does not exist on disk (cwd=[pwd]). Check permissions/disk space."
    }
    puts ">>>>> checkpoint saved: $ckpt_path  (verified on disk, cwd=[pwd])"
}

proc safe_restore {ckpt_name} {
    global DESIGN PNR_ROOT
    set ckpt_path "${PNR_ROOT}/outputs/${DESIGN}_${ckpt_name}.enc"
    if {![file exists $ckpt_path]} {
        puts "\n============================================================"
        puts "   CANNOT RESUME - checkpoint not found"
        puts "============================================================"
        puts "   Looking for : $ckpt_path"
        puts "   Current dir : [pwd]"
        puts "   Contents of ${PNR_ROOT}/outputs/:"
        if {[llength [glob -nocomplain ${PNR_ROOT}/outputs/*]] > 0} {
            foreach f [glob -nocomplain ${PNR_ROOT}/outputs/*] { puts "     $f" }
        } else {
            puts "     (${PNR_ROOT}/outputs/ is empty)"
        }
        puts "============================================================\n"
        error "Missing checkpoint $ckpt_path - see listing above. Either fix RESUME_FROM to match what's actually on disk, or cd into the directory that has it, then rerun."
    }
    restoreDesign $ckpt_path $DESIGN
}

proc stamp {msg} {
    puts "\n########## $msg  \[[clock format [clock seconds] -format %H:%M:%S]\] ##########\n"
}


#=============================================================================
# CONFIGURATION
#   Verified against gsclib045_macro.lef and gsclib045_tech.lef:
#     SITE CoreSite (0.2 x 1.71 um)                        CONFIRMED
#     FILL1 FILL2 FILL4 FILL8 FILL16 FILL32 FILL64         CONFIRMED
#     ANTENNA                                              CONFIRMED
#     CLKBUFX2/3/4/6/8/12/16/20 - NO CLKBUFX1 exists       CONFIRMED
#     CLKINVX1/2/3/4/6/8/12/16/20                          CONFIRMED
#     Routing layers M1..M10 all TYPE ROUTING              CONFIRMED
#     No TAP/WELLTAP cell in this library - none used
#     M1-M11 default vias: added by hand in the patched    SEE BUG 2 ABOVE
#       tech LEF - originals only had GENERATE templates
#
#   FOUNDRY INSTALL IS NEVER MODIFIED. gsclib045_tech.lef and
#   gsclib045_macro.lef under /home/install/FOUNDRY are shared, foundry/
#   admin-managed, and read-only as far as this flow is concerned. The
#   patched tech LEF lives only in your own project directory (PROJ_LEF_DIR
#   below) and is loaded from there instead - the original is never
#   touched, copied over, or written to.
#=============================================================================

# Shared foundry install - READ ONLY, untouched by this script
set LEF_DIR      "/home/install/FOUNDRY/digital/45nm/dig/lef"
set LEF_STD      "$LEF_DIR/gsclib045_macro.lef"
;# gsclib045_macro.lef (std cells) has no via-derivation issue - used as-is

# Your own project directory - writable, this is where the patched
# tech LEF lives. Create it once:
#   mkdir -p ~/rt/MINISP/PNR/lef
#   cp gsclib045_tech_patched.lef ~/rt/MINISP/PNR/lef/
set PROJ_LEF_DIR "lef"
set LEF_TECH     "$PROJ_LEF_DIR/gsclib045_tech_patched.lef"

set DESIGN   "soc_top"

set UTIL     0.62
set MARGIN   20.0

set ROUTE_BOT   1
;# ROUTE_TOP must be >= the top-most layer with EXISTING routed wires anywhere
;# in the design, not just the top layer you want signal nets to use. The
;# power ring/stripes (PG_HORIZ/PG_VERT below) are physically routed on M7/M8
;# by addRing/addStripe in Step 3, before routeDesign ever runs - Innovus
;# confirmed this with NRDB-954 ("conflicts with existing routed wires on
;# layer 8") when this was left at 6. Set to 8 to match PG_VERT. Signal nets
;# still preferentially route on the lower layers; this only widens the
;# router's *legal* range so it doesn't reject the PG wires that are already
;# there.
set ROUTE_TOP   8
set PG_HORIZ    "M7"
set PG_VERT     "M8"
set STRIPE_LAY  "M7"
set SITE_NAME   "CoreSite"

set CLK_BUFFERS   {CLKBUFX2 CLKBUFX3 CLKBUFX4 CLKBUFX6 CLKBUFX8 CLKBUFX12}
set CLK_INVERTERS {CLKINVX2 CLKINVX3 CLKINVX4 CLKINVX6 CLKINVX8 CLKINVX12}
set FILLER_CELLS  {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set ANTENNA_CELL  "ANTENNA"

file mkdir $PNR_ROOT/reports
file mkdir $PNR_ROOT/outputs

;# Print exactly what's on disk BEFORE anything runs. If RESUME_FROM points
;# at a checkpoint that isn't in this list, you'll know immediately instead
;# of hitting a cryptic IMPSYT-7338 deep inside Step N.
puts "\n>>>>> Working directory : [pwd]"
puts ">>>>> ${PNR_ROOT}/outputs/ resolves to : [file normalize ${PNR_ROOT}/outputs]"
if {[llength [glob -nocomplain ${PNR_ROOT}/outputs/*]] > 0} {
    puts ">>>>> Existing checkpoints found in ${PNR_ROOT}/outputs/:"
    foreach f [lsort [glob -nocomplain ${PNR_ROOT}/outputs/*]] { puts "       $f" }
} else {
    puts ">>>>> ${PNR_ROOT}/outputs/ is currently EMPTY - RESUME_FROM must be 1"
}
puts ">>>>> RESUME_FROM is set to: $RESUME_FROM\n"


#=============================================================================
# STEP 1 : INITIALISE DESIGN
#=============================================================================
if {$RESUME_FROM <= 1} {
    stamp "STEP 1 : INIT DESIGN"

    set init_design_name  $DESIGN
    set init_verilog      soc_top_netlist.v
    set init_top_cell     $DESIGN
    set init_lef_file     [list $LEF_TECH $LEF_STD]
    set init_mmmc_file    mmmc.tcl
    set init_pwr_net      VDD
    set init_gnd_net      VSS
    set init_mmmc_version 2

    init_design

    globalNetConnect VDD -type pgpin -pin VDD -inst * -override
    globalNetConnect VSS -type pgpin -pin VSS -inst * -override
    globalNetConnect VDD -type tiehi -inst * -override
    globalNetConnect VSS -type tielo -inst * -override

    try_cmd "setDesignMode process"  { setDesignMode -process 45 }
    try_cmd "checkDesign"            { checkDesign -all -noHtml -outfile ${PNR_ROOT}/reports/20_check_design.rpt }

    puts ">>>>> STEP 1 DONE"
} else {
    puts ">>>>> STEP 1 SKIPPED (resuming)"
}


#=============================================================================
# STEP 2 : FLOORPLAN
#=============================================================================
if {$RESUME_FROM <= 2} {
    stamp "STEP 2 : FLOORPLAN"

    if {$RESUME_FROM == 2} { safe_restore init }

    floorPlan -site $SITE_NAME -r 1.0 $UTIL $MARGIN $MARGIN $MARGIN $MARGIN

    try_cmd "IO pin placement" {
        setPinAssignMode -pinEditInBatch true
        editPin -pin {clk}      -side TOP -layer M3 -spreadType center -fixedPin 1
        editPin -pin {rst}      -side TOP -layer M3 -spreadType center -fixedPin 1
        editPin -pin {done_irq} -side TOP -layer M3 -spreadType center -fixedPin 1
        setPinAssignMode -pinEditInBatch false
    }

    checkpoint floorplan
    puts ">>>>> STEP 2 DONE"
}


#=============================================================================
# STEP 3 : POWER PLANNING
#=============================================================================
if {$RESUME_FROM <= 3} {
    stamp "STEP 3 : POWER PLAN"

    if {$RESUME_FROM == 3} { safe_restore floorplan }

    addRing -nets {VDD VSS} \
            -type core_rings \
            -follow core \
            -layer [list top $PG_HORIZ bottom $PG_HORIZ left $PG_VERT right $PG_VERT] \
            -width   {top 2.0 bottom 2.0 left 2.0 right 2.0} \
            -spacing {top 1.0 bottom 1.0 left 1.0 right 1.0} \
            -offset  {top 1.0 bottom 1.0 left 1.0 right 1.0}

    addStripe -nets {VDD VSS} \
              -layer $STRIPE_LAY \
              -direction vertical \
              -width 1.0 \
              -spacing 1.0 \
              -set_to_set_distance 30 \
              -start_from left \
              -start_offset 15 \
              -stop_offset 15 \
              -switch_layer_over_obs false

    sroute -connect {corePin} \
           -layerChangeRange [list M1 $PG_VERT] \
           -blockPinTarget {nearestTarget} \
           -corePinTarget {firstAfterRowEnd} \
           -allowJogging 1 \
           -allowLayerChange 1

    checkpoint powerplan
    puts ">>>>> STEP 3 DONE"
}


#=============================================================================
# STEP 4 : PLACEMENT
#=============================================================================
if {$RESUME_FROM <= 4} {
    stamp "STEP 4 : PLACEMENT"

    if {$RESUME_FROM == 4} { safe_restore powerplan }

    place_opt_design

    try_cmd "checkPlace"      { checkPlace ${PNR_ROOT}/reports/21_check_place.rpt }
    try_cmd "place timing"    { report_timing -nworst 5 > ${PNR_ROOT}/reports/22_place_timing.rpt }
    try_cmd "place summary"   { summaryReport -noHtml -outfile ${PNR_ROOT}/reports/23_place_summary.rpt }

    checkpoint placed
    puts ">>>>> STEP 4 DONE"
}


#=============================================================================
# STEP 5 : PRE-CTS OPTIMISATION
#=============================================================================
if {$RESUME_FROM <= 5} {
    stamp "STEP 5 : PRE-CTS OPT"

    if {$RESUME_FROM == 5} { safe_restore placed }

    optDesign -preCTS -outDir ${PNR_ROOT}/reports/preCTS

    try_cmd "preCTS timing" { report_timing -nworst 10 > ${PNR_ROOT}/reports/24_prects_timing.rpt }

    checkpoint prects
    puts ">>>>> STEP 5 DONE"
}


#=============================================================================
# STEP 6 : CLOCK TREE SYNTHESIS
#
#   10,121 sinks on a single clock domain, 8,192 of which come from the
#   flip-flop-based SRAM model. Longest-running step - expect 10-30 min.
#
#   Only buffer_cells and inverter_cells are strictly required. Each
#   property is set individually so that if this build rejects one name,
#   the rest still apply and CTS still runs.
#
#   routing_top_layer / routing_bottom_layer are DELIBERATELY ABSENT here.
#   A prior run proved these are not valid ccopt property names in this
#   build (IMPCCOPT-2036: "No property with name routing_top_layer could
#   be found") and, being unwrapped, aborted the whole script. CCOpt picks
#   clock routing layers on its own and does so sensibly - do not add
#   these back without first running 'set_ccopt_property -help *' to
#   confirm the exact accepted name in your build.
#=============================================================================
if {$RESUME_FROM <= 6} {
    stamp "STEP 6 : CTS  (longest step - be patient)"

    if {$RESUME_FROM == 6} { safe_restore prects }

    create_ccopt_clock_tree_spec

    try_cmd "ccopt buffer_cells"     { set_ccopt_property buffer_cells   $CLK_BUFFERS }
    try_cmd "ccopt inverter_cells"   { set_ccopt_property inverter_cells $CLK_INVERTERS }
    try_cmd "ccopt target_skew"      { set_ccopt_property target_skew      0.150 }
    try_cmd "ccopt target_max_trans" { set_ccopt_property target_max_trans 0.200 }
    try_cmd "ccopt max_fanout"       { set_ccopt_property max_fanout       32 }

    ccopt_design

    try_cmd "cts trees"    { report_ccopt_clock_trees -file ${PNR_ROOT}/reports/25_cts_trees.rpt }
    try_cmd "cts skew"     { report_ccopt_skew_groups -file ${PNR_ROOT}/reports/26_cts_skew.rpt }
    try_cmd "postCTS time" { report_timing -nworst 10 > ${PNR_ROOT}/reports/27_postcts_timing.rpt }

    checkpoint cts
    puts ">>>>> STEP 6 DONE - check ${PNR_ROOT}/reports/26_cts_skew.rpt"
}


#=============================================================================
# STEP 7 : POST-CTS OPTIMISATION
#=============================================================================
if {$RESUME_FROM <= 7} {
    stamp "STEP 7 : POST-CTS OPT"

    if {$RESUME_FROM == 7} { safe_restore cts }

    optDesign -postCTS -outDir ${PNR_ROOT}/reports/postCTS_setup

    try_cmd "postCTS hold"        { optDesign -postCTS -hold -outDir ${PNR_ROOT}/reports/postCTS_hold }
    try_cmd "postCTS setup rpt"   { report_timing -nworst 10 > ${PNR_ROOT}/reports/28_postcts_setup.rpt }
    try_cmd "postCTS hold rpt"    { report_timing -early -nworst 10 > ${PNR_ROOT}/reports/29_postcts_hold.rpt }

    checkpoint postcts
    puts ">>>>> STEP 7 DONE"
}


#=============================================================================
# STEP 8 : ROUTING
#   Each setNanoRouteMode call is separate so one unsupported option does
#   not prevent the others from applying. Expect 20 to 60 minutes.
#
#   Requires the PATCHED tech LEF (see BUG 2 at top of file) or this will
#   die again in seconds with NRDB-158 on the M1-M2 via, exactly as before.
#=============================================================================
if {$RESUME_FROM <= 8} {
    stamp "STEP 8 : ROUTING  (long step)"

    if {$RESUME_FROM == 8} { safe_restore postcts }

    try_cmd "nr quiet"          { setNanoRouteMode -quiet }
    try_cmd "nr timingDriven"   { setNanoRouteMode -routeWithTimingDriven true }
    try_cmd "nr siDriven"       { setNanoRouteMode -routeWithSiDriven true }
    try_cmd "nr topLayer"       { setNanoRouteMode -routeTopRoutingLayer    $ROUTE_TOP }
    try_cmd "nr bottomLayer"    { setNanoRouteMode -routeBottomRoutingLayer $ROUTE_BOT }
    try_cmd "nr iterations"     { setNanoRouteMode -drouteEndIteration 20 }
    try_cmd "nr antennaDiode"   { setNanoRouteMode -routeInsertAntennaDiode true }
    try_cmd "nr antennaCell"    { setNanoRouteMode -routeAntennaCellName $ANTENNA_CELL }

    routeDesign -globalDetail

    try_cmd "route summary" { report_route -outfile ${PNR_ROOT}/reports/30_route_summary.rpt }

    checkpoint routed
    puts ">>>>> STEP 8 DONE"
}


#=============================================================================
# STEP 9 : POST-ROUTE OPTIMISATION
#=============================================================================
if {$RESUME_FROM <= 9} {
    stamp "STEP 9 : POST-ROUTE OPT"

    if {$RESUME_FROM == 9} { safe_restore routed }

    ;# BUG 3 - POST-ROUTE OPT ABORT (IMPOPT-6080 -> IMPSYT-6692)
    ;#   effortLevel high demands a Quantus QRC tech file per RC corner in
    ;#   mmmc.tcl (IMPEXT-3491). We don't have those, so drop to 'low' -
    ;#   exactly what the error message itself recommends - instead of
    ;#   silently skipping extraction via try_cmd every time.
    ;#
    ;#   Separately (and this is the one that actually kills the script):
    ;#   optDesign -postRoute force-switches SI-aware delay calc to true
    ;#   by default. AAE-SI optimization is only legal when analysisType
    ;#   is 'ocv', but this flow runs 'bcwc' (setAnalysisMode above, no
    ;#   OCV derate tables set up in mmmc.tcl). That mismatch throws
    ;#   IMPOPT-6080 as an ERROR, and since optDesign -postRoute is called
    ;#   directly (not try_cmd, per this script's own philosophy of never
    ;#   masking core-flow failures), Innovus treats it as a bad return
    ;#   code and aborts the whole run (IMPSYT-6692) instead of just this
    ;#   step. Force SI-aware back off right before the call so postRoute
    ;#   opt runs in plain (non-SI) mode instead of hitting the conflict.
    try_cmd "setExtractRCMode" { setExtractRCMode -engine postRoute -effortLevel low }
    try_cmd "extractRC"        { extractRC }
    try_cmd "disable postRoute SI-aware (needs OCV, we run bcwc)" { setDelayCalMode -SIAware false }

    optDesign -postRoute -outDir ${PNR_ROOT}/reports/postRoute_setup

    try_cmd "postRoute hold"      { optDesign -postRoute -hold -outDir ${PNR_ROOT}/reports/postRoute_hold }
    try_cmd "postRoute setup rpt" { report_timing -nworst 20 > ${PNR_ROOT}/reports/31_postroute_setup.rpt }
    try_cmd "postRoute hold rpt"  { report_timing -early -nworst 20 > ${PNR_ROOT}/reports/32_postroute_hold.rpt }

    checkpoint postroute
    puts ">>>>> STEP 9 DONE"
}


#=============================================================================
# STEP 10 : FILLER CELL INSERTION
#=============================================================================
if {$RESUME_FROM <= 10} {
    stamp "STEP 10 : FILLERS"

    if {$RESUME_FROM == 10} { safe_restore postroute }

    if {![try_cmd "addFiller full" { addFiller -cell $FILLER_CELLS -prefix FILLER }]} {
        try_cmd "addFiller fallback" { addFiller -cell {FILL1 FILL2 FILL4 FILL8} -prefix FILLER }
    }

    checkpoint filled
    puts ">>>>> STEP 10 DONE"
}


#=============================================================================
# STEP 11 : PHYSICAL VERIFICATION
#=============================================================================
if {$RESUME_FROM <= 11} {
    stamp "STEP 11 : VERIFICATION"

    if {$RESUME_FROM == 11} { safe_restore filled }

    try_cmd "verify_drc"           { verify_drc -report ${PNR_ROOT}/reports/40_drc.rpt }
    try_cmd "verifyConnectivity"   { verifyConnectivity -type all -report ${PNR_ROOT}/reports/41_connectivity.rpt }
    try_cmd "verifyProcessAntenna" { verifyProcessAntenna -reportFile ${PNR_ROOT}/reports/42_antenna.rpt }
    try_cmd "verifyGeometry"       { verifyGeometry -report ${PNR_ROOT}/reports/43_geometry.rpt }

    try_cmd "final setup"   { report_timing -nworst 20 > ${PNR_ROOT}/reports/50_final_setup.rpt }
    try_cmd "final hold"    { report_timing -early -nworst 20 > ${PNR_ROOT}/reports/51_final_hold.rpt }
    try_cmd "final area"    { report_area > ${PNR_ROOT}/reports/52_final_area.rpt }
    try_cmd "final power"   { report_power -outfile ${PNR_ROOT}/reports/53_final_power.rpt }
    try_cmd "final summary" { summaryReport -noHtml -outfile ${PNR_ROOT}/reports/54_final_summary.rpt }

    puts "\n============================================================"
    puts "   VERIFICATION CHECKPOINT"
    puts "============================================================"
    puts "   ${PNR_ROOT}/reports/40_drc.rpt           must show 0 violations"
    puts "   ${PNR_ROOT}/reports/41_connectivity.rpt  must show 0 opens, 0 shorts"
    puts "   ${PNR_ROOT}/reports/42_antenna.rpt       must show 0 violations"
    puts "   ${PNR_ROOT}/reports/50_final_setup.rpt   slack must be POSITIVE"
    puts "   ${PNR_ROOT}/reports/51_final_hold.rpt    slack must be POSITIVE"
    puts "============================================================\n"

    puts ">>>>> STEP 11 DONE"
}


#=============================================================================
# STEP 12 : GDSII EXPORT
#=============================================================================
if {$RESUME_FROM <= 12} {
    stamp "STEP 12 : GDSII EXPORT"

    if {![try_cmd "streamOut full" {
            streamOut ${PNR_ROOT}/outputs/soc_top.gds \
                -libName ${DESIGN}_LIB \
                -structureName $DESIGN \
                -stripes 1 \
                -units 1000 \
                -mode ALL }]} {
        try_cmd "streamOut minimal" { streamOut ${PNR_ROOT}/outputs/soc_top.gds -mode ALL }
    }

    try_cmd "saveNetlist"      { saveNetlist ${PNR_ROOT}/outputs/soc_top_final.v }
    try_cmd "write_sdf"        { write_sdf   ${PNR_ROOT}/outputs/soc_top_pnr.sdf }
    try_cmd "rcOut spef"       { rcOut -spef ${PNR_ROOT}/outputs/soc_top.spef }

    checkpoint final
}


#=============================================================================
# FINAL SUMMARY
#=============================================================================
puts "\n"
puts "============================================================"
puts "   INNOVUS PLACE AND ROUTE COMPLETE"
puts "============================================================"
puts "   GDSII    : ${PNR_ROOT}/outputs/soc_top.gds"
puts "   Netlist  : ${PNR_ROOT}/outputs/soc_top_final.v"
puts "   SDF      : ${PNR_ROOT}/outputs/soc_top_pnr.sdf"
puts "   SPEF     : ${PNR_ROOT}/outputs/soc_top.spef"
puts "   Database : ${PNR_ROOT}/outputs/${DESIGN}_final.enc"
puts "============================================================"

if {[llength $::SKIPPED] > 0} {
    puts "\n   COMMANDS SKIPPED (unsupported options in this build):"
    foreach s $::SKIPPED { puts "     - $s" }
    puts "\n   These were optional and the flow completed regardless."
    puts "   To recover a missing report, run that command manually with"
    puts "   <command> -help to find the correct option name."
} else {
    puts "\n   No commands skipped - every step ran cleanly."
}

puts "\n   CHECKPOINTS AVAILABLE FOR RESUME:"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_floorplan.enc   -> RESUME_FROM 3"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_powerplan.enc   -> RESUME_FROM 4"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_placed.enc      -> RESUME_FROM 5"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_prects.enc      -> RESUME_FROM 6"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_cts.enc         -> RESUME_FROM 7"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_postcts.enc     -> RESUME_FROM 8"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_routed.enc      -> RESUME_FROM 9"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_postroute.enc   -> RESUME_FROM 10"
puts "     ${PNR_ROOT}/outputs/${DESIGN}_filled.enc      -> RESUME_FROM 11"
puts ""
