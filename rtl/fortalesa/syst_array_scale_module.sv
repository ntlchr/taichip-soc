// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Scale module for systolic array outputs

module syst_array_scale_module
    #(
    parameter N         =    12,            // Systolic array size, should be dividable by 2 and by 3!
    parameter IWIDTH    =    32,            // Input data width
    parameter OWIDTH    =     8,            // Output data width
    parameter FRACTION  =    28             // Size of the fraction part of the scale
    )
    (
    // Clock and resets
    input logic                 clk_i,      // Input clock, rising edge active
    input logic                 reset_i,    // Input reset, active high, synchronous
    // Input data
    input logic [31:0]          scale_i,    // Scale value in fixed-point format
    input logic [IWIDTH*N-1:0]  data_i,     // Input data
    output logic [OWIDTH*N-1:0] data_o      // Output data (scaled and truncated)
    );

    // --------------------------------------------------------------------------
    // -- Local parameters and signals
    // --------------------------------------------------------------------------
    
    logic [IWIDTH-1:0] input_data[N-1:0];
    logic [OWIDTH-1:0] scaled_data[N-1:0];
    
    logic [OWIDTH*N-1:0] scaled_data_packed;
	
	genvar g;
    generate for (g = 0; g < N; g++) begin : data_assignment
        assign input_data[g] = data_i[g*IWIDTH+:IWIDTH];
    end
    endgenerate

    genvar p;
    generate for (p = 0; p < N; p++) begin : scaling
        wallace_trunc mult (
            .x (input_data[p]),
            .y (scale_i),
            .r (scaled_data[p])
        );
    end
    endgenerate
    
    genvar i;
    generate for (i = 0; i < N; i++) begin
        assign scaled_data_packed[i*OWIDTH+:OWIDTH] = scaled_data[i];
    end
    endgenerate
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            data_o <= '0;
        end else begin
            data_o <= scaled_data_packed;
        end
    end

endmodule