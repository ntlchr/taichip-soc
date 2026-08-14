// Copyright (c) 2025 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: PE for the reconfigurable systolic array with three execution modes
//				PE type 2 (acts as a main PE in both fault tolerance modes)

module pe_tmr
    #(
    parameter IWIDTH  =      8,             	// Input data width
    parameter OWIDTH  =     23              	// Output data width
    )
    (
    // Clock and resets
    input logic                 clk,        	// Input clock, rising edge active
    input logic                 reset,      	// Input reset, active high, synchronous
    // Input interface
    input logic [IWIDTH-1:0]    in_a,       	// Input data from the LEFT
    input logic [IWIDTH-1:0]    in_b,       	// Input data from the ABOVE
    input logic [OWIDTH-1:0]    in_c0,      	// Input data from the diagonal module
    input logic [OWIDTH-1:0]    in_c1,      	// Input data from the above module
    input logic [OWIDTH-1:0]    in_c2,      	// Input data from the left module
    // Output interface
    output logic [IWIDTH-1:0]   out_a,      	// Output for the module on the RIGHT
    output logic [IWIDTH-1:0]   out_b,      	// output for the module BELOW
    output logic [OWIDTH-1:0]   out_c,      	// MAC result
    // Control interface
    input logic [1:0]           mode,       	// Execution mode: 00 - performance, 01 - dmr, 10 - tmr
    input logic                 enable,     	// Valid input data
    input logic                 read_out,   	// Read out stage after the end of calculation
    input logic                 fault_flag_i,   // Fault flag input from the left module
    output logic                fault_flag_o,   // Fault flag output to the right module
    output logic                o_valid     	// Valid output
    );
    
    logic signed [2*IWIDTH-1:0] mult_out;
    
    always @(posedge clk) begin
        if (reset)          o_valid <= 1'b0;
        else if (enable)    o_valid <= 1'b1;
        else                o_valid <= 1'b0;
    end
    
    always @(posedge clk) begin
        if (reset)          out_a <= '0;
        else if (enable)    out_a <= in_a;
    end
    
    always @(posedge clk) begin
        if (reset)          out_b <= '0;
        else if (enable)    out_b <= in_b;
    end
    
    assign mult_out = $signed(in_a) * $signed(in_b);
    
    always @(posedge clk) begin
        if (reset)                  out_c <= '0;
        else if (enable)
            if (mode == 2'b00)      out_c <= mult_out + $signed(out_c);
            else if (mode == 2'b01) out_c <= mult_out + $signed((in_c2 & out_c));
            else                    out_c <= (in_c0 & in_c1) | (in_c0 & in_c2) | (in_c1 & in_c2);
        else if (read_out)          out_c <= in_c1;
    end
    
    always @(posedge clk) begin
        if (reset)                          fault_flag_o <= 1'b0;
        else if (enable & mode == 2'b01)    fault_flag_o <= fault_flag_i | (in_c2 != out_c);
        else if (enable & mode == 2'b10)    fault_flag_o <= fault_flag_i | (in_c2 != in_c0) | (in_c2 != in_c1);
        else                                fault_flag_o <= 1'b0;
    end
 
endmodule