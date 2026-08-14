# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)

# All paths are relative to yosys/

puts "0. Executing init_tech: load technology from Github PDK"
if {![info exists pdk_dir]} {
	set pdk_dir "../ihp13/sg13cmos5l"
}
set pdk_cells_lib ${pdk_dir}/libs.ref/sg13cmos5l_stdcell/lib
set pdk_sram_lib  ${pdk_dir}/libs.ref/sg13cmos5l_sram/lib
set pdk_io_lib    ${pdk_dir}/libs.ref/sg13cmos5l_io/lib

set tech_cells [list "$pdk_cells_lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib"]
set tech_macros [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib]
lappend tech_macros "$pdk_io_lib/sg13cmos5l_io_typ_1p2V_3p3V_25C.lib"

# For hilomap
set tech_cell_tiehi {sg13cmos5l_tiehi L_HI}
set tech_cell_tielo {sg13cmos5l_tielo L_LO}

# Pre-formated for easier use in yosys commands
# All liberty files
set lib_list [concat [split $tech_cells] [split $tech_macros] ]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args [concat {*}$liberty_args_list]
# Only the standard cells
set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args [concat {*}$tech_cells_args_list]

# Read library files
foreach file $lib_list {
	yosys read_liberty -lib "$file"
}