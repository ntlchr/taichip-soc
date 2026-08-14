// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
//
// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for TAICHIP-1 SoC by:
// - Natalia Cherezova (TalTech)

module croc_soc import croc_pkg::*; #(
  parameter int unsigned GpioCount = 16
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic ref_clk_i,
  input  logic testmode_i,
  input  logic fetch_en_i,
  output logic status_o,
  output logic lockstep_error_o,
  output logic [1:0] obi_error_o,
  output logic [1:0] mem_error_o,

  input  logic jtag_tck_i,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,

  input  logic uart_rx_i,
  output logic uart_tx_o,
  
  output logic spi_sclk_o,
  output logic spi_mosi_o,
  input  logic spi_miso_i,
  output logic spi_cs_n_o,

  input  logic mbist_start_i,
  input  logic mbist_watch_i,
  output logic mbist_active_o,
  output logic mbist_all_done_o,
  output logic mbist_any_done_o,

  input  logic [GpioCount-1:0] gpio_i,       // Input from GPIO pins
  output logic [GpioCount-1:0] gpio_o,       // Output to GPIO pins
  output logic [GpioCount-1:0] gpio_out_en_o // Output enable signal; 0 -> input, 1 -> output
);

  logic synced_rst_n, synced_fetch_en;

  rstgen i_rstgen (
    .clk_i,
    .rst_ni,
    .test_mode_i ( testmode_i ),
    .rst_no      ( synced_rst_n ),
    .init_no ( )
  );

  sync #(
      .STAGES     (    2 ),
      .ResetValue ( 1'b0 )
    ) i_ext_intr_sync (
      .clk_i,
      .rst_ni   ( synced_rst_n    ),
      .serial_i ( fetch_en_i      ),
      .serial_o ( synced_fetch_en )
    );

  
  croc_domain #(
    .GpioCount( GpioCount ) 
  ) i_croc (
    .clk_i,
    .rst_ni ( synced_rst_n ),
    .ref_clk_i,
    .testmode_i,
    .fetch_en_i ( synced_fetch_en ),
  
    .jtag_tck_i,
    .jtag_tdi_i,
    .jtag_tdo_o,
    .jtag_tms_i,
    .jtag_trst_ni,
  
    .uart_rx_i,
    .uart_tx_o,
	
	.spi_sclk_o,
    .spi_mosi_o,
    .spi_miso_i,
    .spi_cs_n_o,
  
    .mbist_start_i,
    .mbist_watch_i,
    .mbist_active_o,
    .mbist_all_done_o,
    .mbist_any_done_o,

    .gpio_i,             
    .gpio_o,            
    .gpio_out_en_o,

    .core_busy_o  ( status_o ),
    .lockstep_error_o,
	.obi_error_o,
	.mem_error_o
  );

endmodule
