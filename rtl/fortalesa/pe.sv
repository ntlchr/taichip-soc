// Copyright (c) 2025 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: PE for the reconfigurable systolic array with three execution modes
//				PE type 0 (acts as a shadow in both fault tolerance modes)

module pe
    #(
    parameter IWIDTH  =      8,             // Input data width
    parameter OWIDTH  =     32              // Output data width
    )
    (
    // Clock and resets
    input logic                 clk,        // Input clock, rising edge active
    input logic                 reset,      // Input reset, active high, synchronous
    // Input interface
    input logic [IWIDTH-1:0]    in_a,       // Input data from the LEFT
    input logic [IWIDTH-1:0]    in_b,       // Input data from the ABOVE
    input logic [OWIDTH-1:0]    in_c,       // Output data from the ABOVE
    // Output interface
    output logic [IWIDTH-1:0]   out_a,      // Output for the module on the RIGHT
    output logic [IWIDTH-1:0]   out_b,      // Output for the module BELOW
    output logic [OWIDTH-1:0]   out_c,      // MAC result
    // Control interface
    input logic                 enable,     // Computation enable
    input logic                 read_out,   // Read out stage after the end of the calculation
    output logic                o_valid     // Valid output
    );
    
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

    always @(posedge clk) begin
        if (reset)          out_c <= '0;
        else if (enable)    out_c <= $signed(out_c) + ($signed(in_a) * $signed(in_b));
        else if (read_out)  out_c <= in_c;
    end
 
endmodule