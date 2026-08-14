// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Lars Kröger <lkroeger@ethz.ch>

package spi_reg_pkg;

  parameter int AddressWidth = 12;


  typedef struct packed{
    logic [7:0] control;
    logic [7:0] tx_data;   // 16-byte TX buffer
    logic [15:0] length; 
    logic [7:0] mode_ctrl;
    logic [15:0] freq;
  } spi_reg2hw_t;


  typedef struct packed{
    logic [7:0] status;
    logic [7:0] busy;
    logic [7:0] fifo_status;
    logic [7:0] rx_data;   // 16-byte RX buffer
  } spi_hw2reg_t;

  // Register Offsets
  parameter logic [AddressWidth-1:0] SPI_CONTROL_OFFSET     = 12'h000;
  parameter logic [AddressWidth-1:0] SPI_STATUS_OFFSET      = 12'h004;
  parameter logic [AddressWidth-1:0] SPI_TXBUFFER_OFFSET    = 12'h008; // write one byte at a time
  parameter logic [AddressWidth-1:0] SPI_RXBUFFER_OFFSET    = 12'h00C; // read one byte at a time
  parameter logic [AddressWidth-1:0] SPI_ADDRESS_LO_OFFSET  = 12'h010;
  parameter logic [AddressWidth-1:0] SPI_ADDRESS_HI_OFFSET  = 12'h014;
  parameter logic [AddressWidth-1:0] SPI_LENGTH_OFFSET      = 12'h018;
  parameter logic [AddressWidth-1:0] SPI_FIFOSTAT_OFFSET    = 12'h01C;
  parameter logic [AddressWidth-1:0] SPI_MODE_CTRL_OFFSET   = 12'h020;
  parameter logic [AddressWidth-1:0] SPI_MODE_BUSY_OFFSET   = 12'h024;
  parameter logic [AddressWidth-1:0] SPI_MODE_FREQ_OFFSET   = 12'h028;


endpackage
