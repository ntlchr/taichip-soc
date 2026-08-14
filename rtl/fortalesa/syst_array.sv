// Copyright (c) 2025 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Reconfigurable systolic array with three execution modes:
//				performance mode (effective size N by N)
//				DRG mode (DRG0 implementation option, effective size N by N/2)
//				TRG mode (TRG4 implementation option, effective size N/2 by N/2)

module syst_array
    #(
    parameter N         =    12,            // Systolic array size, should be dividable by 2 and by 3!
    parameter IWIDTH    =     8,            // Input data width
    parameter OWIDTH    =    32             // Output data width
    )
    (
    // Clock and resets
    input logic                 clk_i,        // Input clock, rising edge active
    input logic                 reset_i,      // Input reset, active high, synchronous
    // Input data
    input logic [IWIDTH*N-1:0]  row_data_i,   // Activations (inputs)
    input logic [IWIDTH*N-1:0]  col_data_i,   // Weights
    input logic [31:0]          scale_i,      // Scale value in fixed-point format
    // Control interface
    input logic [1:0]           mode_i,       // Execution mode: 00 - performance, 01 - dmr, 10 - tmr
    input logic                 read_en_i,    // Valid input data
    input logic                 enable_i,     // Enable calculation
    input logic                 read_out_i,   // Read out the result
    input logic                 pe_clear_i,   // Clear partial sums after the calculation
    output logic                fault_flag_o, // Fault flag
    output logic [OWIDTH*N-1:0] data_o        // Output data
    );

    // --------------------------------------------------------------------------
    // -- Local parameters and signals
    // --------------------------------------------------------------------------
    
    localparam int PSUM_WIDTH = 32;
    
    logic [IWIDTH-1:0] a_in[N-1:0][N-1:0];
    logic [IWIDTH-1:0] b_in[N-1:0][N-1:0];
    logic [PSUM_WIDTH-1:0] c_in[N:0][N-1:0];
    
    logic [IWIDTH-1:0] a_out[N-1:0][N:0];
    logic [IWIDTH-1:0] b_out[N:0][N-1:0];
    logic [PSUM_WIDTH-1:0] c_out[N:0][N-1:0];
    
    logic fault_flag_in[N-1:0][N/2-1:0];
    logic fault_flag_out[N-1:0][N/2-1:0];
    
    logic [N-1:0] fault_flag_packed;
    
    logic [PSUM_WIDTH*N-1:0] result;
    logic [OWIDTH*N-1:0] result_scaled;
    
    logic pe_reset;
	
    // --------------------------------------------------------------------------
    // -- Reading data from the memory
    // -- It is assumed that data comes properly padded
    // --------------------------------------------------------------------------
	
	genvar g;
    generate for (g = 0; g < N; g++) begin : data_assignment
        assign a_out[g][0] = row_data_i[g*IWIDTH+:IWIDTH];
        assign b_out[0][g] = col_data_i[g*IWIDTH+:IWIDTH];
        assign c_out[0][g] = '0;
    end
    endgenerate
	
	assign pe_reset = reset_i || pe_clear_i;
	
	// --------------------------------------------------------------------------
    // -- 2D grid of PEs
    // --------------------------------------------------------------------------

    genvar x, y;
    generate for (x = 0; x < N; x++) begin : sa_row
        for (y = 0; y < N; y++) begin : sa_col
            if ((x % 2 == 1) && (y % 2 == 1)) begin : sa_pe2
                pe_tmr #(
                    .IWIDTH (IWIDTH),
                    .OWIDTH (PSUM_WIDTH)
                ) pe_tmr (
                    .clk      (clk_i),
                    .reset    (pe_reset),
                    .in_a     (a_in[x][y]),
                    .in_b     (b_in[x][y]),
                    .in_c0    (c_in[x][y-1]),
                    .in_c1    (c_in[x][y]),
                    .in_c2    (c_in[x+1][y-1]),
                    .out_a    (a_out[x][y+1]),
                    .out_b    (b_out[x+1][y]),
                    .out_c    (c_out[x+1][y]),
                    .mode     (mode_i),
                    .enable   (enable_i),
                    .read_out (read_out_i),
                    .fault_flag_i (fault_flag_in[x][y/2]),
                    .fault_flag_o (fault_flag_out[x][y/2]),
                    .o_valid  ( )
                );
            end else if ((x % 2 == 0) && (y % 2 == 1)) begin: sa_pe1
                pe_dmr #(
                    .IWIDTH (IWIDTH),
                    .OWIDTH (PSUM_WIDTH)
                ) pe_dmr (
                    .clk      (clk_i),
                    .reset    (pe_reset),
                    .in_a     (a_in[x][y]),
                    .in_b     (b_in[x][y]),
                    .in_c0    (c_in[x+1][y-1]),
                    .in_c1    (c_in[x][y]),
                    .out_a    (a_out[x][y+1]),
                    .out_b    (b_out[x+1][y]),
                    .out_c    (c_out[x+1][y]),
                    .mode     (mode_i),
                    .enable   (enable_i),
                    .read_out (read_out_i),
                    .fault_flag_i (fault_flag_in[x][y/2]),
                    .fault_flag_o (fault_flag_out[x][y/2]),
                    .o_valid  ( )
                );
            end else begin : sa_pe0
                pe #(
                    .IWIDTH (IWIDTH),
                    .OWIDTH (PSUM_WIDTH)
                ) pe (
                    .clk      (clk_i),
                    .reset    (pe_reset),
                    .in_a     (a_in[x][y]),
                    .in_b     (b_in[x][y]),
                    .in_c     (c_in[x][y]),
                    .out_a    (a_out[x][y+1]),
                    .out_b    (b_out[x+1][y]),
                    .out_c    (c_out[x+1][y]),
                    .enable   (enable_i),
                    .read_out (read_out_i),
                    .o_valid  ( )
                );
            end
        end
    end
    endgenerate
    
    // --------------------------------------------------------------------------
    // -- Interconnects
    // --------------------------------------------------------------------------
    
    genvar i, j;
    generate for (i = 0; i < N; i++) begin
        for (j = 0; j < N; j++) begin
            if (j == 0) begin
                assign a_in[i][j] = a_out[i][j];
            end else begin
                assign a_in[i][j] = (mode_i == 2'b00) ? a_out[i][j] : a_out[i][j-1];
            end
        end
    end
    endgenerate
    
    genvar ii, jj;
    generate for (ii = 0; ii < N; ii++) begin
        for (jj = 0; jj < N; jj++) begin
            if (ii == 0) begin
                assign b_in[ii][jj] = b_out[ii][jj];
            end else begin
                assign b_in[ii][jj] = (mode_i == 2'b10) ? b_out[ii-1][jj] : b_out[ii][jj];
            end
        end
    end
    endgenerate
    
    genvar idx, jdx;
    generate for (idx = 0; idx < N+1; idx++) begin
        for (jdx = 0; jdx < N; jdx++) begin
            if (idx == 0) begin
                assign c_in[idx][jdx] = c_out[idx][jdx];
            end else begin
                assign c_in[idx][jdx] = (mode_i == 2'b10 && read_out_i) ? c_out[idx-1][jdx] : c_out[idx][jdx];
            end
        end
    end
    endgenerate
    
    // --------------------------------------------------------------------------
    // -- Fault flag
    // --------------------------------------------------------------------------
    
    genvar h, v;
    generate for (h = 0; h < N; h++) begin
        for (v = 0; v < N/2; v++) begin
            if (v == 0) begin
                assign fault_flag_in[h][v] = 1'b0;
            end else begin
                assign fault_flag_in[h][v] = fault_flag_out[h][v-1];
            end
        end
    end
    endgenerate
    
    genvar row;
    generate for (row = 0; row < N; row++) begin
        assign fault_flag_packed[row] = fault_flag_out[row][N/2-1];
    end
    endgenerate
    
    assign fault_flag_o = | fault_flag_packed;
    
    // --------------------------------------------------------------------------
    // -- Output
    // --------------------------------------------------------------------------
    
    integer col;
    always @(*) begin
        for (col = 0; col < N; col++) begin
            result[col*PSUM_WIDTH+:PSUM_WIDTH] = c_out[N][col];
        end
    end
    
    syst_array_scale_module #(
        .N          (N),
        .IWIDTH     (PSUM_WIDTH),
        .OWIDTH     (OWIDTH)
    ) scale_module (
        .clk_i      (clk_i),
        .reset_i    (reset_i),
        .scale_i    (scale_i),
        .data_i     (result),
        .data_o     (result_scaled)
    );
    
    assign data_o = result_scaled;

endmodule