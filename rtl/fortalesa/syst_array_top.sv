// Copyright (c) 2025 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Top file for the reconfigurable systolic array that connects
//				systolic array core with the controller

module syst_array_top
    #(
    parameter N           =   12,           // Systolic array size, should be dividable by 2 and by 3!
    parameter BUFFER_SIZE = 1024,           // Size of the buffers
    parameter IWIDTH      =    8,           // Input data width
    parameter OWIDTH      =   32,           // Output data width
    parameter AW          =   32            // Address width
    )
    (
    // Clock and resets
    input logic                 clk_i,        // Input clock, rising edge active
    input logic                 reset_i,      // Input reset, active high, synchronous
    // Input data
    input logic [IWIDTH*N-1:0]  row_data_i,   // Activations (inputs)
    input logic [IWIDTH*N-1:0]  col_data_i,   // Weights
    input logic [31:0]          scale_i,      // Scale in fixed-point format
    // Control interface
    input logic                 start_i,      // Start command
    input logic                 test_mode_i,  // Test mode
    input logic [1:0]           mode_i,       // Execution mode: 00 - performance, 01 - dmr, 10 - tmr
    input logic [15:0]          length_i,     // Length of the matrix tiles
    output logic [AW-1:0]       ibuffer_addr_o, // Input/weight buffer address
    output logic [AW-1:0]       obuffer_addr_o, // Output buffer address
    output logic                read_en_o,    // Read enable signal for input buffers
    output logic                test_en_o,    // Enable signal for LFSRs
    output logic                done_o,       // Calculation is completed, toggled for one clock cycle
    output logic                ready_o,      // Systolic array is ready for the new calculation
    output logic                valid_o,      // Output data is valid
    output logic                fault_flag_o, // Fault flag
    output logic [OWIDTH*N-1:0] data_o,       // Output data
    output logic [N-1:0]        strb_o        // Strobe signal, which words in the output are valid
    );
    
    // --------------------------------------------------------------------------
    // -- Signals declaration and logic
    // --------------------------------------------------------------------------
    
    logic [IWIDTH*N-1:0] row_data;
    logic [IWIDTH*N-1:0] col_data;
    logic [OWIDTH*N-1:0] out_data;
    
    logic read_en, enable, read_out, done;
    logic read_en_d, read_out_d;
    
    assign valid_o = read_out_d;
    assign done_o = done;
    
    assign row_data = (read_en_d) ? row_data_i : '0;
    assign col_data = (read_en_d) ? col_data_i : '0;
    
    assign data_o = (read_out_d) ? out_data : '0;
    assign read_en_o = read_en;
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            read_en_d <= 1'b0;
        end else begin
            read_en_d <= read_en;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            read_out_d <= 1'b0;
        end else begin
            read_out_d <= read_out;
        end
    end
    
    // --------------------------------------------------------------------------
    // -- Controller
    // --------------------------------------------------------------------------
    
    syst_array_controller #(
        .N            (N),
        .BUFFER_SIZE  (BUFFER_SIZE),
        .AW           (AW)
    ) controller (
        .clk_i        (clk_i),
        .reset_i      (reset_i),
        .start_i      (start_i),
        .test_mode_i  (test_mode_i),
        .mode_i       (mode_i),
        .length_i     (length_i),
        .ibuffer_addr_o (ibuffer_addr_o),
        .obuffer_addr_o (obuffer_addr_o),
        .read_en_o    (read_en),
        .test_en_o    (test_en_o),
        .enable_o     (enable),
        .read_out_o   (read_out),
        .done_o       (done),
        .ready_o      (ready_o),
        .strb_o       (strb_o)
    );
    
    // --------------------------------------------------------------------------
    // -- Systolic array core
    // --------------------------------------------------------------------------
    
    syst_array #(
        .N            (N),
        .IWIDTH       (IWIDTH),
        .OWIDTH       (OWIDTH)
    ) systolic_array (
        .clk_i        (clk_i),
        .reset_i      (reset_i),
        .row_data_i   (row_data),
        .col_data_i   (col_data),
        .scale_i      (scale_i),
        .mode_i       (mode_i),
        .read_en_i    (read_en_d),
        .enable_i     (enable),
        .read_out_i   (read_out),
        .pe_clear_i   (done),
        .fault_flag_o (fault_flag_o),
        .data_o       (out_data)
    );
    
endmodule