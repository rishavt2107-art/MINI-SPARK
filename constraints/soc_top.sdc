#=============================================================================
# FILE   : constraints/soc_top.sdc
# DESC   : Synopsys Design Constraints for Mini Spark SoC
# PDK    : Cadence GPDK045nm
# TARGET : 100 MHz  (10.0 ns period)
# USED BY: Genus (synthesis), Innovus (PnR), Tempus (signoff STA)
#=============================================================================

#-----------------------------------------------------------------------------
# 1. Clock definition
#-----------------------------------------------------------------------------
create_clock -name clk -period 10.000 [get_ports clk]

#-----------------------------------------------------------------------------
# 2. Clock quality
#    Uncertainty covers jitter plus pre-CTS estimated skew.
#-----------------------------------------------------------------------------
set_clock_uncertainty -setup 0.200 [get_clocks clk]
set_clock_uncertainty -hold  0.050 [get_clocks clk]
set_clock_transition   0.100       [get_clocks clk]
set_clock_latency      0.500       [get_clocks clk]

#-----------------------------------------------------------------------------
# 3. Input and output timing budgets
#    30 percent of the period is reserved on each side of the boundary.
#-----------------------------------------------------------------------------
set ALL_IN_EXCEPT_CLK [remove_from_collection [all_inputs] [get_ports clk]]

set_input_delay  -clock clk -max 3.000 $ALL_IN_EXCEPT_CLK
set_input_delay  -clock clk -min 0.200 $ALL_IN_EXCEPT_CLK
set_output_delay -clock clk -max 3.000 [all_outputs]
set_output_delay -clock clk -min 0.200 [all_outputs]

#-----------------------------------------------------------------------------
# 4. Drive and load
#    BUFX4 is a mid-strength GPDK045 buffer. Change the cell name if your
#    library uses a different naming convention.
#-----------------------------------------------------------------------------
set_driving_cell -lib_cell BUFX4 -pin Y $ALL_IN_EXCEPT_CLK
set_load 0.050 [all_outputs]

#-----------------------------------------------------------------------------
# 5. Asynchronous reset is a false path for timing
#-----------------------------------------------------------------------------
set_false_path -from [get_ports rst]

#-----------------------------------------------------------------------------
# 6. Design rule limits
#-----------------------------------------------------------------------------
set_max_fanout      20     [current_design]
set_max_transition  0.500  [current_design]
set_max_capacitance 0.200  [current_design]

#-----------------------------------------------------------------------------
# 7. Area goal - 0 means minimise
#-----------------------------------------------------------------------------
set_max_area 0
