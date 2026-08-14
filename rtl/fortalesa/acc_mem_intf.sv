// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Interface between FORTALESA systolic array and memory buffers


module acc_mem_intf #(
    parameter int unsigned N            = 4,	// Systolic array size
    parameter int unsigned IWIDTH       = 8,	// Systolic array input data width
    parameter int unsigned OWIDTH       = 8,	// Systolic array output data width
    parameter int unsigned DW           = 32,	// SRAM data width
    parameter int unsigned AW           = 32,	// SRAM address width
    parameter int unsigned BW           = 4,	// SRAM be width
    parameter int unsigned SRAM_BANKS   = 3,    // Number of SRAM banks per buffer
    // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
    parameter type addr_t    = logic [AW-1:0],
    parameter type data_t    = logic [DW-1:0],
    parameter type be_t      = logic [BW-1:0]
    ) (
    // Accelerator interface
    input logic [AW-1:0]        ibuffer_addr_i,
    input logic [AW-1:0]        obuffer_addr_i,
    input logic                 read_en_i,
    input logic                 write_en_i,
    input logic [N-1:0]         strb_i,
    input logic [N*OWIDTH-1:0]  result_data_i,
    output logic [N*IWIDTH-1:0] row_data_o,
    output logic [N*IWIDTH-1:0] col_data_o,    
    // Memory interface
    input logic [3*SRAM_BANKS-1:0][DW-1:0]  mem_rdata_i,
    output logic [3*SRAM_BANKS-1:0][DW-1:0] mem_wdata_o,
    output logic [3*SRAM_BANKS-1:0] 		mem_req_o,
    output logic [3*SRAM_BANKS-1:0] 		mem_we_o,
    output logic [3*SRAM_BANKS-1:0][BW-1:0] mem_be_o,
    output logic [3*SRAM_BANKS-1:0][AW-1:0] mem_word_addr_o
    );
    
    logic [SRAM_BANKS*DW-1:0] mem_rdata_row, mem_rdata_col;
    
    assign mem_req_o[0+:SRAM_BANKS] = {SRAM_BANKS{read_en_i}};
    assign mem_req_o[1*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{read_en_i}};
    assign mem_req_o[2*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{write_en_i}};
    
    assign mem_be_o[0+:SRAM_BANKS] = '0;
    assign mem_be_o[1*SRAM_BANKS+:SRAM_BANKS] = '0;
    assign mem_be_o[2*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{strb_i}};
    
    assign mem_we_o[0+:SRAM_BANKS]  = '0;
    assign mem_we_o[1*SRAM_BANKS+:SRAM_BANKS] = '0;
    assign mem_we_o[2*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{write_en_i}};
    
    assign mem_word_addr_o[0+:SRAM_BANKS] = {SRAM_BANKS{ibuffer_addr_i}};
    assign mem_word_addr_o[1*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{ibuffer_addr_i}};
    assign mem_word_addr_o[2*SRAM_BANKS+:SRAM_BANKS] = {SRAM_BANKS{obuffer_addr_i}};
    
    assign mem_wdata_o[0+:SRAM_BANKS] = '0;
    assign mem_wdata_o[1*SRAM_BANKS+:SRAM_BANKS] = '0;
    assign mem_wdata_o[2*SRAM_BANKS+:SRAM_BANKS] = result_data_i;
    
    assign mem_rdata_row = mem_rdata_i[0+:SRAM_BANKS];
    assign mem_rdata_col = mem_rdata_i[1*SRAM_BANKS+:SRAM_BANKS];
    
    assign row_data_o = mem_rdata_row[N*IWIDTH-1:0];
    assign col_data_o = mem_rdata_col[N*IWIDTH-1:0];
    
endmodule
