# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)


make_io_sites -horizontal_site sg13cmos5l_ioSite \
    -vertical_site sg13cmos5l_ioSite \
    -corner_site sg13cmos5l_ioSite \
    -offset 0 \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0

set padD    180; # pad depth (edge to core)
set padW     80; # pad width (beachfront)
set padBond  70; # bonding pad size

#set chipW  [expr 5000.0 - 2*(39+70)]; # top/bottom (width)
#set chipH  [expr 4000.0 - 2*(39+70)]; # left/right (height)

# Corner width is equal to padD, bondpad outside
set cornerToPad [expr {$padBond + $padD}]


# Edge: BOTTOM (left to right)
set numPadsPerEdge 16
set southSpan  [expr {$chipW - 2*$cornerToPad - $padW}]
set southPitch [expr {floor($southSpan / double($numPadsPerEdge - 1))}]
puts "IO_SOUTH_pitch: $southPitch "
set southStart $cornerToPad

place_pad -row IO_SOUTH -location [expr {$southStart +  0*$southPitch}] "pad_vssio0"       ; # pin no:  1
place_pad -row IO_SOUTH -location [expr {$southStart +  1*$southPitch}] "pad_vddio0"       ; # pin no:  2
place_pad -row IO_SOUTH -location [expr {$southStart +  2*$southPitch}] "pad_uart_rx_i"    ; # pin no:  3
place_pad -row IO_SOUTH -location [expr {$southStart +  3*$southPitch}] "pad_uart_tx_o"    ; # pin no:  4
place_pad -row IO_SOUTH -location [expr {$southStart +  4*$southPitch}] "pad_testmode_i"   ; # pin no:  5
place_pad -row IO_SOUTH -location [expr {$southStart +  5*$southPitch}] "pad_status_o"     ; # pin no:  6
place_pad -row IO_SOUTH -location [expr {$southStart +  6*$southPitch}] "pad_clk_i"        ; # pin no:  7
place_pad -row IO_SOUTH -location [expr {$southStart +  7*$southPitch}] "pad_ref_clk_i"    ; # pin no:  8
place_pad -row IO_SOUTH -location [expr {$southStart +  8*$southPitch}] "pad_rst_ni"       ; # pin no:  9
place_pad -row IO_SOUTH -location [expr {$southStart +  9*$southPitch}] "pad_jtag_tck_i"   ; # pin no: 10
place_pad -row IO_SOUTH -location [expr {$southStart + 10*$southPitch}] "pad_jtag_trst_ni" ; # pin no: 11
place_pad -row IO_SOUTH -location [expr {$southStart + 11*$southPitch}] "pad_jtag_tms_i"   ; # pin no: 12
place_pad -row IO_SOUTH -location [expr {$southStart + 12*$southPitch}] "pad_jtag_tdi_i"   ; # pin no: 13
place_pad -row IO_SOUTH -location [expr {$southStart + 13*$southPitch}] "pad_jtag_tdo_o"   ; # pin no: 14
place_pad -row IO_SOUTH -location [expr {$southStart + 14*$southPitch}] "pad_vss0"         ; # pin no: 15
place_pad -row IO_SOUTH -location [expr {$southStart + 15*$southPitch}] "pad_vdd0"         ; # pin no: 16


# Edge: RIGHT (bottom to top)
set numPadsPerEdge 13
set eastSpan  [expr {$chipH - 2*$cornerToPad - $padW}]
set eastPitch [expr {floor($eastSpan / double($numPadsPerEdge - 1))}]
puts "IO_EAST_pitch: $eastPitch "
set eastStart $cornerToPad

place_pad -row IO_EAST -location [expr {$eastStart +  0*$eastPitch}] "pad_vssio1"           ; # pin no:  1
place_pad -row IO_EAST -location [expr {$eastStart +  1*$eastPitch}] "pad_vddio1"           ; # pin no:  2
place_pad -row IO_EAST -location [expr {$eastStart +  2*$eastPitch}] "pad_mbist_start_i"    ; # pin no:  3
place_pad -row IO_EAST -location [expr {$eastStart +  3*$eastPitch}] "pad_mbist_watch_i"    ; # pin no:  4
place_pad -row IO_EAST -location [expr {$eastStart +  4*$eastPitch}] "pad_mbist_active_o"   ; # pin no:  5
place_pad -row IO_EAST -location [expr {$eastStart +  5*$eastPitch}] "pad_mbist_all_done_o" ; # pin no:  6
place_pad -row IO_EAST -location [expr {$eastStart +  6*$eastPitch}] "pad_mbist_any_done_o" ; # pin no:  7
place_pad -row IO_EAST -location [expr {$eastStart +  7*$eastPitch}] "pad_gpio0_io"         ; # pin no:  8
place_pad -row IO_EAST -location [expr {$eastStart +  8*$eastPitch}] "pad_gpio1_io"         ; # pin no:  9
place_pad -row IO_EAST -location [expr {$eastStart +  9*$eastPitch}] "pad_gpio2_io"         ; # pin no: 10
place_pad -row IO_EAST -location [expr {$eastStart + 10*$eastPitch}] "pad_gpio3_io"         ; # pin no: 11
place_pad -row IO_EAST -location [expr {$eastStart + 11*$eastPitch}] "pad_vss1"             ; # pin no: 12
place_pad -row IO_EAST -location [expr {$eastStart + 12*$eastPitch}] "pad_vdd1"             ; # pin no: 13


# Edge: TOP (right to left)
set numPadsPerEdge 16
set northSpan  [expr {$chipW - 2*$cornerToPad - $padW}]
set northPitch [expr {floor($northSpan / double($numPadsPerEdge - 1))}]
puts "IO_NORTH_pitch: $northPitch "
set northStart [expr {$chipW - $cornerToPad - $padW}]

place_pad -row IO_NORTH  -location [expr {$northStart -  0*$northPitch}] "pad_vssio2"       ; # pin no:  1
place_pad -row IO_NORTH  -location [expr {$northStart -  1*$northPitch}] "pad_vddio2"       ; # pin no:  2
place_pad -row IO_NORTH  -location [expr {$northStart -  2*$northPitch}] "pad_gpio4_io"     ; # pin no:  3
place_pad -row IO_NORTH  -location [expr {$northStart -  3*$northPitch}] "pad_gpio5_io"     ; # pin no:  4
place_pad -row IO_NORTH  -location [expr {$northStart -  4*$northPitch}] "pad_gpio6_io"     ; # pin no:  5
place_pad -row IO_NORTH  -location [expr {$northStart -  5*$northPitch}] "pad_gpio7_io"     ; # pin no:  6
place_pad -row IO_NORTH  -location [expr {$northStart -  6*$northPitch}] "pad_gpio8_io"     ; # pin no:  7
place_pad -row IO_NORTH  -location [expr {$northStart -  7*$northPitch}] "pad_gpio9_io"     ; # pin no:  8
place_pad -row IO_NORTH  -location [expr {$northStart -  8*$northPitch}] "pad_gpio10_io"    ; # pin no:  9
place_pad -row IO_NORTH  -location [expr {$northStart -  9*$northPitch}] "pad_gpio11_io"    ; # pin no: 10
place_pad -row IO_NORTH  -location [expr {$northStart - 10*$northPitch}] "pad_gpio12_io"    ; # pin no: 11
place_pad -row IO_NORTH  -location [expr {$northStart - 11*$northPitch}] "pad_gpio13_io"    ; # pin no: 12
place_pad -row IO_NORTH  -location [expr {$northStart - 12*$northPitch}] "pad_gpio14_io"    ; # pin no: 13
place_pad -row IO_NORTH  -location [expr {$northStart - 13*$northPitch}] "pad_gpio15_io"    ; # pin no: 14
place_pad -row IO_NORTH  -location [expr {$northStart - 14*$northPitch}] "pad_vss2"         ; # pin no: 15
place_pad -row IO_NORTH  -location [expr {$northStart - 15*$northPitch}] "pad_vdd2"         ; # pin no: 16


# Edge: LEFT (top to bottom)
set numPadsPerEdge 14
set westSpan  [expr {$chipH - 2*$cornerToPad - $padW}];
set westPitch [expr {floor($westSpan / double($numPadsPerEdge - 1))}]
puts "IO_WEST_pitch: $westPitch "
set westStart [expr {$chipH - $cornerToPad - $padW}]

place_pad -row IO_WEST -location [expr {$westStart -  0*$westPitch}] "pad_vssio3"           ; # pin no:  1
place_pad -row IO_WEST -location [expr {$westStart -  1*$westPitch}] "pad_vddio3"           ; # pin no:  2
place_pad -row IO_WEST -location [expr {$westStart -  2*$westPitch}] "pad_lockstep_error_o" ; # pin no:  3
place_pad -row IO_WEST -location [expr {$westStart -  3*$westPitch}] "pad_obi_error0_o"     ; # pin no:  4
place_pad -row IO_WEST -location [expr {$westStart -  4*$westPitch}] "pad_obi_error1_o"     ; # pin no:  5
place_pad -row IO_WEST -location [expr {$westStart -  5*$westPitch}] "pad_mem_error0_o"     ; # pin no:  6
place_pad -row IO_WEST -location [expr {$westStart -  6*$westPitch}] "pad_mem_error1_o"     ; # pin no:  7
place_pad -row IO_WEST -location [expr {$westStart -  7*$westPitch}] "pad_fetch_en_i"       ; # pin no:  8
place_pad -row IO_WEST -location [expr {$westStart -  8*$westPitch}] "pad_spi_sclk_o"       ; # pin no:  9
place_pad -row IO_WEST -location [expr {$westStart -  9*$westPitch}] "pad_spi_mosi_o"       ; # pin no: 10
place_pad -row IO_WEST -location [expr {$westStart - 10*$westPitch}] "pad_spi_miso_i"       ; # pin no: 11
place_pad -row IO_WEST -location [expr {$westStart - 11*$westPitch}] "pad_spi_cs_n_o"       ; # pin no: 12
place_pad -row IO_WEST -location [expr {$westStart - 12*$westPitch}] "pad_vss3"             ; # pin no: 13
place_pad -row IO_WEST -location [expr {$westStart - 13*$westPitch}] "pad_vdd3"             ; # pin no: 14

place_corners $iocorner

place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill


# Connect built-in rings
connect_by_abutment

# Bondpad as seperate cell placed in OpenROAD:
# place the bonding pad relative to the IO cell
place_bondpad -bond bondpad_70x70_5L -offset {5.0 -70.0} pad_*

# remove rows created by via make_io_sites as they are no longer needed
remove_io_rows