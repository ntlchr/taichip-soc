// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Authors:
//    Lionel Noussi <lnoussi@ethz.ch> <lio.noussi@gmail.com>


package dma_pkg;

  localparam AddrW = 32;
  localparam DataW = 32;

  // Register address map
  localparam logic [7:0] REG_SRC_ADDR     = 8'h00;
  localparam logic [7:0] REG_DST_ADDR     = 8'h04;
  localparam logic [7:0] REG_CONTROL      = 8'h08;
  localparam logic [7:0] REG_CONDITION    = 8'h0C;
  localparam logic [7:0] REG_INTERRUPT    = 8'h10;
  localparam logic [7:0] REG_ACTIVATE     = 8'h14;
  localparam logic [7:0] REG_STATUS       = 8'h18;

  // ENUMS
  typedef enum logic { 
    WORD = 0,
    BYTE = 1
  } transfer_size_t;

  typedef enum logic {
    READ_CONDITION = 0,
    WRITE_CONDITION = 1
  } condition_type_t;

  // Receiver FSM states
  typedef enum logic [2:0] {
    REICEIVER_IDLE,
    REICEVER_WAIT_FOR_FIFO_SPACE,
    RECEIVER_WAIT_FOR_COND_GNT,
    RECEIVER_WAIT_FOR_COND_RVALID,
    RECEIVER_WAIT_FOR_GNT,
    REICEVER_WAIT_FOR_RVALID
  } dma_receiver_states_t;

  // TRANSMITTER FSM states
  typedef enum logic [1:0] {
    TRANSMITTER_IDLE,
    TRANSMITTER_WAIT_FOR_NEW_INPUTS,
    TRANSMITTER_WAIT_FOR_GNT
  } dma_transmitter_states_t;

endpackage
