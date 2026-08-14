# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Tobias Senti <tsenti@ethz.ch>
# - Jannis Schönleber <janniss@iis.ee.ethz.ch>
# - Philippe Sauter   <phsauter@iis.ee.ethz.ch>
#
# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)
#
# Macro placement. Note that all SRAM macros are placed horizontally (R0 MX)
# because sg13cmos5l have only 5 metal layers, SRAM macros go up to M4,
# so there is only one layer above them for power stripes, and TM1 is
# horizontal.

source scripts/floorplan_util.tcl


##########################################################################
# RAM sizes
##########################################################################
set RamMaster256x32_1P  [[ord::get_db] findMaster "RM_IHPSG13_1P_256x32_c2_bm_bist"]
set RamSize256x32_W_1P  [ord::dbu_to_microns [$RamMaster256x32_1P getWidth]]
set RamSize256x32_H_1P  [ord::dbu_to_microns [$RamMaster256x32_1P getHeight]]

set RamMaster256x32_2P  [[ord::get_db] findMaster "RM_IHPSG13_2P_256x32_c2_bm_bist"]
set RamSize256x32_W_2P  [ord::dbu_to_microns [$RamMaster256x32_2P getWidth]]
set RamSize256x32_H_2P  [ord::dbu_to_microns [$RamMaster256x32_2P getHeight]]

set RamMaster256x8_1P   [[ord::get_db] findMaster "RM_IHPSG13_1P_256x8_c3_bm_bist"]
set RamSize256x8_W_1P   [ord::dbu_to_microns [$RamMaster256x8_1P getWidth]]
set RamSize256x8_H_1P   [ord::dbu_to_microns [$RamMaster256x8_1P getHeight]]

set RamMaster256x8_2P   [[ord::get_db] findMaster "RM_IHPSG13_2P_256x8_c2_bm_bist"]
set RamSize256x8_W_2P   [ord::dbu_to_microns [$RamMaster256x8_2P getWidth]]
set RamSize256x8_H_2P   [ord::dbu_to_microns [$RamMaster256x8_2P getHeight]]


##########################################################################
# Chip and Core Area
##########################################################################
# Core gets snapped to site-grid -> get real values
set coreArea      [ord::get_core_area]
set core_leftX    [lindex $coreArea 0]
set core_bottomY  [lindex $coreArea 1]
set core_rightX   [lindex $coreArea 2]
set core_topY     [lindex $coreArea 3]


##########################################################################
# Macro instances
##########################################################################
utl::report "Read macro names"
source src/instances.tcl


##########################################################################
# Macro placement
##########################################################################
# Parameters for macro placement
set floor_paddingX    50.0
set floor_paddingY    50.0
set floor_leftX       [expr $core_leftX + $floor_paddingX]
set floor_bottomY     [expr $core_bottomY + $floor_paddingY]
set floor_rightX      [expr $core_rightX - $floor_paddingX]
set floor_topY        [expr $core_topY - $floor_paddingY]
set floor_midpointX   [expr $floor_leftX + ($floor_rightX - $floor_leftX)/2]
set floor_midpointY   [expr $floor_bottomY + ($floor_topY - $floor_bottomY)/2 + 200]

set mem_ecc_block_2P  [expr $RamSize256x32_W_2P + $RamSize256x8_W_2P + 100]
set mem_ecc_block_1P  [expr $RamSize256x32_W_1P + $RamSize256x8_W_1P + 100]
set mem_ecc_block_2P_bottom  [expr $RamSize256x32_W_2P + $RamSize256x8_W_2P + 200]

utl::report "Place SRAM macros"

# GENERAL MEMORY
# Bank 0
set X [expr $floor_midpointX - $mem_ecc_block_2P/2 - $mem_ecc_block_2P - 100]
set Y [expr $floor_topY - 310]
placeInstance $gen_bank0_sram0 $X $Y R0

set X [expr $X + $RamSize256x32_W_1P + 100]
set Y [expr $Y]
placeInstance $gen_bank0_ecc_sram0 $X $Y R0

# Bank 1
set X [expr $X + $RamSize256x8_W_1P + 100]
set Y [expr $Y]
placeInstance $gen_bank1_sram0 $X $Y R0

set X [expr $X + $RamSize256x32_W_1P + 100]
set Y [expr $Y]
placeInstance $gen_bank1_ecc_sram0 $X $Y R0

# ACCELERATOR MEMORY
# WEIGHT BUFFER (sram 0)
set X [expr $floor_midpointX - $mem_ecc_block_2P/2 - $mem_ecc_block_2P - 100]
set Y [expr $floor_topY - $RamSize256x32_H_2P]
placeInstance $acc_bank0_sram0 $X $Y R0

set X [expr $X + $RamSize256x32_W_2P + 100]
set Y [expr $Y]
placeInstance $acc_bank0_ecc_sram0 $X $Y R0

# Weight buffer (sram 1)
set X [expr $floor_midpointX - $mem_ecc_block_2P/2]
set Y [expr $Y]
placeInstance $acc_bank0_sram1 $X $Y R0

set X [expr $X + $RamSize256x32_W_2P + 100]
set Y [expr $Y]
placeInstance $acc_bank0_ecc_sram1 $X $Y R0

# Weight buffer (sram 2)
set X [expr $X + $RamSize256x8_W_2P + 100]
set Y [expr $Y]
placeInstance $acc_bank0_sram2 $X $Y R0

set X [expr $X + $RamSize256x32_W_2P + 100]
set Y [expr $Y]
placeInstance $acc_bank0_ecc_sram2 $X $Y R0

# INPUT BUFFER (sram 0)
set X [expr $floor_midpointX - $mem_ecc_block_2P_bottom/2 - $mem_ecc_block_2P_bottom - 200]
set Y [expr $floor_bottomY + 186]
placeInstance $acc_bank1_ecc_sram0 $X $Y MX

set X [expr $X + $RamSize256x8_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank1_sram0 $X $Y MX

# Input buffer (sram 1)
set X [expr $floor_midpointX - $mem_ecc_block_2P_bottom/2]
set Y [expr $Y]
placeInstance $acc_bank1_ecc_sram1 $X $Y MX

set X [expr $X + $RamSize256x8_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank1_sram1 $X $Y MX

# Input buffer (sram 2)
set X [expr $X + $RamSize256x32_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank1_ecc_sram2 $X $Y MX

set X [expr $X + $RamSize256x8_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank1_sram2 $X $Y MX

# OUTPUT BUFFER (sram 0)
set X [expr $floor_midpointX - $mem_ecc_block_2P_bottom/2 - $mem_ecc_block_2P_bottom - 200]
set Y [expr $floor_bottomY]
placeInstance $acc_bank2_sram0 $X $Y MX

set X [expr $X + $RamSize256x32_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank2_ecc_sram0 $X $Y MX

# Output buffer (sram 1)
set X [expr $floor_midpointX - $mem_ecc_block_2P_bottom/2]
set Y [expr $Y]
placeInstance $acc_bank2_sram1 $X $Y MX

set X [expr $X + $RamSize256x32_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank2_ecc_sram1 $X $Y MX

# Output buffer (sram 2)
set X [expr $X + $RamSize256x8_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank2_sram2 $X $Y MX

set X [expr $X + $RamSize256x32_W_2P + 200]
set Y [expr $Y]
placeInstance $acc_bank2_ecc_sram2 $X $Y MX


cut_rows -halo_width_x 2 -halo_width_y 1

# SRAM macros are placed in four rows: two rows on top and two rows
# at the bottom. To prevent OpenRoad putting standard cells in-between
# two bottom rows of SRAMs, which would obstruct proper routing,
# a placement blockage was created.
utl::report "Create placement blockage"
create_blockage -region {668 402 4537 450}
