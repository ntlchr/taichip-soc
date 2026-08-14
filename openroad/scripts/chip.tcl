# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Tobias Senti      <tsenti@ethz.ch>
# - Jannis Schönleber <janniss@iis.ee.ethz.ch>
# - Philippe Sauter   <phsauter@iis.ee.ethz.ch>
#
# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)

# The main OpenRoad chip flow

###############################################################################
# Initialization and floorplan
###############################################################################

set proj_name [expr {[info exists ::env(PROJ_NAME)]  ? $::env(PROJ_NAME)  : "taichip_soc"}]
set netlist [expr {[info exists ::env(NETLIST)] ? $::env(NETLIST) : "../yosys/out/${proj_name}_yosys.v"}]
set top_design [expr {[info exists ::env(TOP_DESIGN)] ? $::env(TOP_DESIGN) : "croc_chip"}]
set report_dir [expr {[info exists ::env(REPORTS)] ? $::env(REPORTS) : "reports"}]
set save_dir [expr {[info exists ::env(SAVE)] ? $::env(SAVE) : "save"}]

# Helper scripts
source scripts/reports.tcl
source scripts/checkpoint.tcl

# Initialize technology data
source scripts/init_tech.tcl

# Read and check design
utl::report "Read netlist"
read_verilog $netlist
link_design $top_design

utl::report "Read constraints"
read_sdc src/constraints.sdc

utl::report "Check constraints"
check_setup -verbose                                      > ${report_dir}/${proj_name}_checks.rpt
report_checks -unconstrained -format end -no_line_splits >> ${report_dir}/${proj_name}_checks.rpt
report_checks -format end -no_line_splits                >> ${report_dir}/${proj_name}_checks.rpt
report_checks -format end -no_line_splits                >> ${report_dir}/${proj_name}_checks.rpt

# Size of the chip
set chipW      [expr 5000.0 - 2*(39+70)];
set chipH      [expr 4000.0 - 2*(39+70)];

# Thickness of annular ring for pads (length of a pad)
set padRing    180.0
set coreMargin [expr $padRing + 35]; # space for power ring

utl::report "Initialize chip"
initialize_floorplan -die_area "0 0 $chipW $chipH" \
                     -core_area "$coreMargin $coreMargin [expr $chipW-$coreMargin] [expr $chipH-$coreMargin]" \
                     -site "CoreSite"

utl::report "Connect global nets (power)"
source scripts/power_connect.tcl

utl::report "Create padring"
source src/padring.tcl

# Define metal tracks
make_tracks

utl::report "Place macros"
source scripts/floorplan.tcl

utl::report "Create power grid"
source scripts/power_grid.tcl
save_checkpoint ${proj_name}.power_grid
report_image "${proj_name}.power" true


###############################################################################
# Initial Repair Netlist
###############################################################################

# Set layers used for estimate_parasitics
set_wire_rc -clock -layer Metal4
set_wire_rc -signal -layer Metal4

# Don't touch any clock-tree related nets as 
# repair_timing can insert a 'split0000' buffer which then prevents CTS from running
set clock_nets [get_nets -of_objects [get_pins -of_objects "*_reg" -filter "name == CLK"]]
set_dont_touch $clock_nets
set_dont_use $dont_use_cells

utl::report "Repair tie fanout"
repair_tie_fanout sg13cmos5l_tielo/L_LO
repair_tie_fanout sg13cmos5l_tiehi/L_HI

utl::report "Remove buffers"
remove_buffers

save_checkpoint ${proj_name}.pre_place


###############################################################################
# GLOBAL PLACEMENT
###############################################################################
set_thread_count 12

set GPL_ARGS {	-density 0.50
                -routability_driven
                -routability_check_overflow 0.50
				-max_phi_coef 1.03
                -timing_driven }
# density:            In every part of the chip, about N% of the area is occupied by standard cells
# routability_driven: Reduce density target when there are a lot of wires in an area
# check_overflow:     Higher means routability starts being considered earlier in placement
#                     too early -> very dense regions, too late -> little to no effect
# timing_driven:      Prioritize near-critical timing paths (reduce their length)
# max_phi_coef:       Step size


utl::report "Global placement"
global_placement {*}$GPL_ARGS
report_metrics "${proj_name}.gpl"
report_image "${proj_name}.gpl" true true
save_checkpoint ${proj_name}.gpl

utl::report "Estimate parasitics"
estimate_parasitics -placement
utl::report "Repair design"
repair_design -verbose
save_checkpoint ${proj_name}.gpl_fix

utl::report "Repair setup"
repair_timing -setup -skip_pin_swap -verbose
save_checkpoint ${proj_name}.gpl_repaired


#############################################################################
# DETAILED PLACEMENT
#############################################################################
set DPL_ARGS {}
# Legalize overlapping cells
utl::report "Detailed placement"
detailed_placement {*}$DPL_ARGS
utl::report "Optimize mirroring"
optimize_mirroring

utl::report "Estimate parasitics"
estimate_parasitics -placement
report_metrics "${proj_name}.dpl"
save_checkpoint ${proj_name}.dpl
report_image "${proj_name}.dpl" true true


###############################################################################
# CLOCK TREE SYNTHESIS
###############################################################################
unset_dont_touch $clock_nets
utl::report "Repair clock inverters"
repair_clock_inverters

utl::report "Clock tree synthesis"
set_wire_rc -clock -layer Metal4
clock_tree_synthesis -buf_list $ctsBuf -root_buf $ctsBufRoot \
                     -sink_clustering_enable \
                     -obstruction_aware \
                     -balance_levels

# Repair wire length between clock pad and clock-tree root
utl::report "Repair clock nets"
repair_clock_nets

# Legalize cts cells
utl::report "Detailed placement"
detailed_placement {*}$DPL_ARGS
utl::report "Estimate parasitics"
estimate_parasitics -placement

# Propagate clocks
set_propagated_clock [all_clocks]

report_metrics "${proj_name}.cts_unrepaired"

# Repair setup timing
utl::report "Repair setup"
repair_timing -setup -skip_pin_swap -verbose

# Place inserted cells
utl::report "Detailed placement"
detailed_placement {*}$DPL_ARGS
utl::report "Check placement"
check_placement -verbose

utl::report "Estimate parasitics"
estimate_parasitics -placement
report_cts -out_file ${report_dir}/${proj_name}.cts.rpt
report_metrics "${proj_name}.cts"
save_checkpoint ${proj_name}.cts
report_image "${proj_name}.cts" true false true


###############################################################################
# GLOBAL ROUTE
###############################################################################

# Reduce routing resources (max utilization) of lower layers by 20-35%
# to spread routing out a bit more to other layers
# OpenRoad strongly prefers routing with M2/M3 first and then when it
# eventually needs M4/M5 it may struggle with finding space 
# to place vias down to M2/M3 -> reserve some space on M2/M3
# Reduce TM1 to avoid too much routing there (bigger tracks -> bad for routing)
set_global_routing_layer_adjustment Metal2-Metal3 0.15
set_global_routing_layer_adjustment TopMetal1 0.30
set_routing_layers -signal Metal2-TopMetal1 -clock Metal2-TopMetal1

utl::report "Global route"
global_route -guide_file ${report_dir}/${proj_name}_route.guide -congestion_iterations 40 \
    -congestion_report_file ${report_dir}/${proj_name}_congestion.rpt \
    -allow_congestion

utl::report "Estimate parasitics"
estimate_parasitics -global_routing
report_metrics "${proj_name}.grt"
save_checkpoint ${proj_name}.grt
report_image "${proj_name}.grt" true false false true


###############################################################################
# REPAIR ROUTED TIMING
###############################################################################
grt::set_verbose 0
# Repair design using global route parasitics
utl::report "Perform buffer insertion"
repair_design -verbose
utl::report "Repair setup and hold violations"
repair_timing -skip_pin_swap -setup -verbose -repair_tns 100
repair_timing -skip_pin_swap -hold -hold_margin 0.05 -verbose -repair_tns 100

utl::report "GRT incremental"
# Run to get modified net by DPL
global_route -start_incremental -allow_congestion
# Running DPL to fix overlapped instances
detailed_placement
# Route only the modified net by DPL
global_route -end_incremental \
            -congestion_report_file ${report_dir}/congestion_repaired_initial.rpt -congestion_iterations 40 \
            -guide_file ${report_dir}/${proj_name}_route.guide \
			-verbose -allow_congestion

utl::report "Estimate parasitics"
estimate_parasitics -global_routing
report_metrics "${proj_name}.grt_repaired"
save_checkpoint ${proj_name}.grt_repaired
report_image "${proj_name}.grt_repaired" true true false true


###############################################################################
# DETAILED ROUTE
###############################################################################

# Requires LEF cell with class 'CORE ANTENNACELL', otherwise you need to give a cell
repair_antennas -ratio_margin 30 -iterations 5

utl::report "Detailed route"
set_thread_count 16
detailed_route -output_drc ${report_dir}/${proj_name}_route_drc.rpt \
               -droute_end_iter 40 \
               -drc_report_iter_step 5 \
               -save_guide_updates \
               -clean_patches \
               -verbose 1

utl::report "Saving detailed route"
save_checkpoint ${proj_name}.drt
report_design_area
report_metrics "${proj_name}.drt"
report_image "${proj_name}.drt" true false false true


utl::report "Filler placement"
filler_placement $stdfill
global_connect

save_checkpoint ${proj_name}.final
report_image "${proj_name}.final" true true false true
estimate_parasitics -global_routing
report_metrics "${proj_name}.final"

utl::report "Write output"
write_def     out/${proj_name}.def
write_verilog out/${proj_name}.v
write_verilog -include_pwr_gnd -remove_cells "$stdfill bondpad*" out/${proj_name}_lvs.v
write_db      out/${proj_name}.odb
write_sdc     out/${proj_name}.sdc

exit
