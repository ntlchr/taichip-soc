// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Authors:
//    Lionel Noussi <lnoussi@ethz.ch> <lio.noussi@gmail.com>


module dma_fifo_buffer #(
    parameter DEPTH = 4,  // Must be power of 2
    parameter DATA_WIDTH = 32
)(
    input  logic        clk_i,
    input  logic        rst_ni,

    // Write interface
    input  logic        wr_en_i,
    input  logic [31:0] wr_data_i,
    output logic        full_o,
    output logic        almost_full_o,

    // Read interface
    input  logic        rd_en_i,
    output logic [31:0] rd_data_o,
    output logic        empty_o,
    output logic        almost_empty_o,

    input logic         reset_i
);

    // Internal memory
    logic [DATA_WIDTH-1:0] mem_q [0:DEPTH-1];

    // Pointers and counter
    localparam PTR_W = $clog2(DEPTH);
    logic [PTR_W-1:0] wr_ptr_d, wr_ptr_q;
    logic [PTR_W-1:0] rd_ptr_d, rd_ptr_q;
    logic [PTR_W:0]   count_d, count_q;

    // -------------------------------
    // Combinational: next-state logic
    // -------------------------------
    always_comb begin
        wr_ptr_d   = wr_ptr_q;
        rd_ptr_d   = rd_ptr_q;
        count_d    = count_q;

        if (reset_i) begin
            wr_ptr_d = '0;
            rd_ptr_d = '0;
            count_d = '0;
        end else begin
            if (wr_en_i && !full_o) begin
                wr_ptr_d = (wr_ptr_q + 1) % DEPTH;
            end

            if (rd_en_i && !empty_o) begin
                rd_ptr_d  = (rd_ptr_q + 1) % DEPTH;
            end

            unique case ({wr_en_i && !full_o, rd_en_i && !empty_o})
                2'b10: count_d = count_q + 1;
                2'b01: count_d = count_q - 1;
                2'b11: count_d = count_q;
                default: count_d = count_q;
            endcase
        end
    end

    // -------------------------------
    // Sequential logic
    // -------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr_q   <= '0;
            rd_ptr_q   <= '0;
            count_q    <= '0;
        end else begin
            wr_ptr_q   <= wr_ptr_d;
            rd_ptr_q   <= rd_ptr_d;
            count_q    <= count_d;
        end
    end

    // -------------------------------
    // Synchronous memory write
    // -------------------------------
    always_ff @(posedge clk_i) begin
        if (wr_en_i && !full_o) begin
            mem_q[wr_ptr_q] <= wr_data_i;
        end
    end
    
    assign rd_data_o        = mem_q[rd_ptr_q];
    assign full_o           = (count_q == DEPTH);
    assign almost_full_o    = (count_q == DEPTH - 1);
    assign empty_o          = (count_q == 0);
    assign almost_empty_o   = (count_q == 1);

endmodule
