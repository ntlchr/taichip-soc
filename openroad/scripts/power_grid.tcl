# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author:
# - Natalia Cherezova (TalTech)

# Power grid generation

utl::report "Power Grid"

##########################################################################
# Reset
##########################################################################

if {[info exists power_grid_defined]} {
    pdngen -ripup
    pdngen -reset
} else {
    set power_grid_defined 1
}

##########################################################################
##  SRAM power rings
##########################################################################

proc sram_power { name macro } {
    # Macro Grid and Rings
    define_pdn_grid -macro -cells $macro -name ${name}_grid -orient "R0 R180 MY MX" \
        -grid_over_boundary -voltage_domains {CORE} \
        -halo {1.0 1.0}

    add_pdn_ring -grid ${name}_grid \
        -layer        {Metal3 Metal4} \
        -widths       {2 2} \
        -spacings     {0.6 0.6} \
        -core_offsets {2.4 0.6} \
        -add_connect

    # Connection of Macro Power Ring to standard-cell rails
    add_pdn_connect -grid ${name}_grid -layers {Metal4 Metal1}
    # Connection of Core Power Stripes to Macro Power Ring
    add_pdn_connect -grid ${name}_grid -layers {TopMetal1 Metal4}	
}

##########################################################################
##  Core Power
##########################################################################

# Core Power Ring (TM1 M4)
add_pdn_ring -grid {core_grid} \
   -layer        {TopMetal1 Metal4} \
   -widths       {10 10} \
   -spacings     {6 6} \
   -pad_offsets  {6 6} \
   -add_connect \
   -connect_to_pads \
   -connect_to_pad_layers TopMetal1

# M1 Standard-cell Rows (tracks)
add_pdn_stripe -grid {core_grid} -layer {Metal1} -width 0.44 -offset 0 \
               -followpins -extend_to_core_ring

# SRAM blocks power grids
sram_power "sram_256x32_1P"  "RM_IHPSG13_1P_256x32_c2_bm_bist"
sram_power "sram_256x32_2P"  "RM_IHPSG13_2P_256x32_c2_bm_bist"
sram_power "sram_256x8_1P"   "RM_IHPSG13_1P_256x8_c3_bm_bist"
sram_power "sram_256x8_2P"   "RM_IHPSG13_2P_256x8_c2_bm_bist"


# TM1 Stripes
add_pdn_stripe -grid {core_grid} -layer {TopMetal1} -width 4.0 \
               -pitch 50.0 -spacing 4.0 -offset 90.0 \
               -extend_to_core_ring -snap_to_grid

# M4 Stripes
add_pdn_stripe -grid {core_grid} -layer {Metal4} -width 1.0 \
               -pitch 50.0 -spacing 2.0 -offset 50.0 \
               -extend_to_core_ring -snap_to_grid


# Horizontal TM1 to below vertical layers
add_pdn_connect -grid {core_grid} -layers {TopMetal1 Metal2}

# Vertical M4 to below horizontal layers
add_pdn_connect -grid {core_grid} -layers {Metal4 Metal3}
add_pdn_connect -grid {core_grid} -layers {Metal4 Metal1}


##########################################################################
##  Generate
##########################################################################
pdngen -failed_via_report ${report_dir}/${proj_name}_pdngen.rpt
