# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)

# Backend constraints

############
## Global ##
############

source src/instances.tcl

#############################
## Driving Cells and Loads ##
#############################

# As a default, drive multiple GPIO pads and be driven by one.
# accomodate for driving up to 2 74HC pads plus a 5pF trace
set_load [expr 2 * 5.0 + 5.0] [all_outputs]
set_driving_cell [all_inputs] -lib_cell sg13cmos5l_IOPadOut16mA -pin pad


##################
## Input Clocks ##
##################
puts "Clocks"

# For 80 MHz
#set TCK_SYS 12.5
# For 50 MHz
set TCK_SYS 20
create_clock -name clk_sys -period $TCK_SYS [get_ports clk_i]

set TCK_JTG 25.0
create_clock -name clk_jtg -period $TCK_JTG [get_ports jtag_tck_i]

set TCK_RTC 50.0
create_clock -name clk_rtc -period $TCK_RTC [get_ports ref_clk_i]


##################################
## Clock Groups & Uncertainties ##
##################################

# Define which clocks are asynchronous to each other
# -allow_paths re-activates timing checks between asyncs -> we must constrain CDCs!
set_clock_groups -asynchronous -name clk_groups_async \
     -group {clk_rtc} \
     -group {clk_jtg} \
     -group {clk_sys}

# We set reasonable uncertainties in their transistion timing
# and transition (rise/fall) times for all clocks (ns)
set_clock_uncertainty 0.1 [all_clocks]
set_clock_transition  0.2 [all_clocks]


####################
## Cdcs and Syncs ##
####################
#puts "CDC/Sync"

# Clock Domain Crossings: paths going from a FF with one clock to an FF with another another)
# to increase the metastability-recovery window we do not wants any additional delays in these paths
# so we deactivate the hold checking (as it may add buffers)

# Constrain `cdc_2phase` for DMI request
set_false_path -hold                  -through $JTAG_ASYNC_REQ
set_max_delay  [expr $TCK_SYS * 0.35] -through $JTAG_ASYNC_REQ -ignore_clock_latency

# Constrain `cdc_2phase` for DMI response
set_false_path -hold                  -through $JTAG_ASYNC_RSP
set_max_delay  [expr $TCK_SYS * 0.35] -through $JTAG_ASYNC_RSP -ignore_clock_latency


#############
##  Reset  ##
#############
puts "Resets"

# Reset should propagate to system domain within a clock cycle.
set_input_delay -max [ expr $TCK_SYS * 0.10 ] [get_ports {rst_ni testmode_i}]  
set_false_path -hold   -from [get_ports {rst_ni testmode_i}]
set_max_delay $TCK_SYS -from [get_ports {rst_ni testmode_i}]


##########
## JTAG ##
##########
#puts "JTAG"

set_input_delay  -min -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.10 ]     [get_ports {jtag_tdi_i jtag_tms_i}]
set_input_delay  -max -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.30 ]     [get_ports {jtag_tdi_i jtag_tms_i}]
set_output_delay -min -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.10 ] [get_ports jtag_tdo_o]
set_output_delay -max -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.20 ] [get_ports jtag_tdo_o]

# Reset should propagate to system domain within a clock cycle.
set_input_delay -max [ expr $TCK_JTG * 0.10 ] [get_ports jtag_trst_ni]  
set_false_path -hold    -from [get_ports jtag_trst_ni]
set_max_delay $TCK_JTG  -from [get_ports jtag_trst_ni]


##########
## GPIO ##
##########
puts "GPIO"

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {gpio*}]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports {gpio*}]

set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {gpio*}]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports {gpio*}]


##########
##  IO  ##
##########
puts "Control and status signals"

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {fetch_en_i mbist_start_i mbist_watch_i}]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports {fetch_en_i mbist_start_i mbist_watch_i}]

set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {status_o lockstep_error_o obi_error0_o obi_error1_o mem_error0_o mem_error1_o mbist_active_o mbist_all_done_o mbist_any_done_o}]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {status_o lockstep_error_o obi_error0_o obi_error1_o mem_error0_o mem_error1_o mbist_active_o mbist_all_done_o mbist_any_done_o}]


##########
## UART ##
##########
puts "UART"

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports uart_rx_i]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports uart_rx_i]
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports uart_tx_o]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports uart_tx_o]


#########
## SPI ##
#########
puts "SPI"

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports spi_miso_i]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports spi_miso_i]
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports spi_cs_n_o]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports spi_cs_n_o]
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports spi_mosi_o]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports spi_mosi_o]
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports spi_sclk_o]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports spi_sclk_o]
