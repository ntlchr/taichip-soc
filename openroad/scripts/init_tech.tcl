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

# Initialize the PDK
utl::report "Init tech from Github PDK"
if {![info exists pdk_dir]} {
	set pdk_dir "../ihp13/pdk"
}
set pdk_cells_lib ${pdk_dir}/libs.ref/sg13cmos5l_stdcell/lib
set pdk_cells_lef ${pdk_dir}/libs.ref/sg13cmos5l_stdcell/lef
set pdk_sram_lib  ${pdk_dir}/libs.ref/sg13cmos5l_sram/lib
set pdk_sram_lef  ${pdk_dir}/libs.ref/sg13cmos5l_sram/lef
set pdk_io_lib    ${pdk_dir}/libs.ref/sg13cmos5l_io/lib
set pdk_io_lef    ${pdk_dir}/libs.ref/sg13cmos5l_io/lef

set pdk_pad_lef   ../ihp13/bondpad/lef


# LIB
define_corners tt ff

puts "Init standard cells"
read_liberty -corner tt ${pdk_cells_lib}/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_liberty -corner ff ${pdk_cells_lib}/sg13cmos5l_stdcell_fast_1p32V_m40C.lib

puts "Init IO cells"
read_liberty -corner tt ${pdk_io_lib}/sg13cmos5l_io_typ_1p2V_3p3V_25C.lib
read_liberty -corner ff ${pdk_io_lib}/sg13cmos5l_io_fast_1p32V_3p6V_m40C.lib

puts "Init SRAM macros"
foreach file [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib] {
	read_liberty -corner tt "$file"
}

foreach file [glob -directory $pdk_sram_lib *_fast_1p32V_m55C.lib] {
	read_liberty -corner ff "$file"
}

puts "Init tech-lef"
read_lef ${pdk_cells_lef}/sg13cmos5l_tech.lef

puts "Init cell-lef"
read_lef ${pdk_cells_lef}/sg13cmos5l_stdcell.lef
read_lef ${pdk_io_lef}/sg13cmos5l_io.lef
read_lef ${pdk_pad_lef}/bondpad_70x70_5L.lef

foreach file [glob -directory $pdk_sram_lef *.lef] {
	read_lef "$file"
}

set ctsBuf [ list sg13cmos5l_buf_16 sg13cmos5l_buf_8 sg13cmos5l_buf_4 sg13cmos5l_buf_2 ]
set ctsBufRoot sg13cmos5l_buf_8

set stdfill [ list sg13cmos5l_fill_8 sg13cmos5l_fill_4 sg13cmos5l_fill_2 sg13cmos5l_fill_1 ]

set iocorner sg13cmos5l_Corner
set iofill [ list sg13cmos5l_Filler10000 sg13cmos5l_Filler4000 sg13cmos5l_Filler2000 sg13cmos5l_Filler1000 sg13cmos5l_Filler400 sg13cmos5l_Filler200 ]

# The repair_timing/repair_design commands may try to use IO cells as buffers
set dont_use_cells sg13cmos5l_IOPad*

proc makeTracks {} {
    utl::report "Metal Tracks"
	make_tracks Metal1    -x_offset 0 -x_pitch 0.42 -y_offset 0 -y_pitch 0.42
	make_tracks Metal2    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.48
	make_tracks Metal3    -x_offset 0 -x_pitch 0.42 -y_offset 0 -y_pitch 0.42
	make_tracks Metal4    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.48
	make_tracks TopMetal1 -x_offset 1.64 -x_pitch 3.28 -y_offset 1.64 -y_pitch 3.28
}
