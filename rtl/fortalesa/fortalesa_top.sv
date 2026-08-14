// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: FORTALESA systolic array top file


module fortalesa_top #(
    parameter int unsigned N           = 4,
    parameter int unsigned BUFFER_SIZE = 256,
    parameter int unsigned IWIDTH      = 8,
    parameter int unsigned OWIDTH      = 8,
    parameter int unsigned AW          = 32,
    parameter type reg_req_t           = logic,
    parameter type reg_rsp_t           = logic
    ) (
    input logic                 clk_i,
    input logic                 rst_ni,
    input logic [IWIDTH*N-1:0]  row_data_i,
    input logic [IWIDTH*N-1:0]  col_data_i,
    output logic [AW-1:0]       ibuffer_addr_o,
    output logic [AW-1:0]       obuffer_addr_o,
    output logic                read_en_o,
    output logic                done_o,
    output logic                valid_o,
    output logic [OWIDTH*N-1:0] data_o,
    output logic [N-1:0]        strb_o,
    input  reg_req_t            reg_req_i,
    output reg_rsp_t            reg_rsp_o
    );
    
    import fortalesa_pkg::* ;
    
    // Regbus signals
    logic reg_we, reg_re;
    logic [ADDR_WIDTH-1:0] reg_addr;
    logic [3:0] reg_be;
    logic [31:0] reg_wdata;
    logic [31:0] reg_rdata;
    logic reg_error, addrmiss, wr_err;
    
    // Config/ctrl registers
    logic [1:0] mode_d, mode_q;
    logic [1:0] err_d, err_q;
    logic [15:0] length_d, length_q;
    logic [31:0] scale_d, scale_q;
    
    logic start, clear_err;
    logic status_d, status_q;
    logic mode_we, length_we, scale_we, ctrl_we, err_we;
    logic invalid_mode_q, invalid_mode_d;
    logic invalid_length_q, invalid_length_d;
    
    assign reg_we = reg_req_i.valid & reg_req_i.write;
    assign reg_re = reg_req_i.valid & ~reg_req_i.write;
    assign reg_addr = reg_req_i.addr[ADDR_WIDTH-1:0];
    assign reg_wdata = reg_req_i.wdata;
    assign reg_be = reg_req_i.wstrb;
    assign reg_rsp_o.rdata = reg_rdata;
    assign reg_rsp_o.error = reg_error;
    assign reg_rsp_o.ready = 1'b1;
    
    assign reg_error = addrmiss | wr_err;
    
    logic [4:0] addr_hit;
    always_comb begin
        addr_hit = '0;
        addr_hit[0] = (reg_addr == FORTALESA_MODE_OFFSET);
        addr_hit[1] = (reg_addr == FORTALESA_LENGTH_OFFSET);
        addr_hit[2] = (reg_addr == FORTALESA_SCALE_OFFSET);
        addr_hit[3] = (reg_addr == FORTALESA_CTRL_STATUS_OFFSET);
        addr_hit[4] = (reg_addr == FORTALESA_ERROR_OFFSET);
    end
    
    assign addrmiss = (reg_re || reg_we) ? ~|addr_hit : 1'b0;
    
    // Check read/write is permitted
    always_comb begin
        wr_err = ((addr_hit[0] & (|(FORTALESA_REG_PERMIT[0] & {reg_re,reg_we}))) |
                  (addr_hit[1] & (|(FORTALESA_REG_PERMIT[1] & {reg_re,reg_we}))) |
                  (addr_hit[2] & (|(FORTALESA_REG_PERMIT[2] & {reg_re,reg_we}))) |
                  (addr_hit[3] & (|(FORTALESA_REG_PERMIT[3] & {reg_re,reg_we}))) |
                  (addr_hit[4] & (|(FORTALESA_REG_PERMIT[4] & {reg_re,reg_we}))));
    end
    
    assign mode_we = addr_hit[0] & reg_we & status_d;   // Status 1 means SA is idle
    assign mode_d = reg_wdata[1:0];
    
    assign length_we = addr_hit[1] & reg_we & status_d; // Status 1 means SA is idle
    assign length_d = reg_wdata[15:0];
    
    assign scale_we = addr_hit[2] & reg_we & status_d;  // Status 1 means SA is idle
    assign scale_d = reg_wdata;
    
    assign ctrl_we = addr_hit[3] & reg_we & status_d;   // Status 1 means SA is idle
    
    // Invalid mode/length
    assign invalid_mode_d = (mode_d == 2'b11) ? 1'b1 : 1'b0;
    assign invalid_length_d = (length_d > BUFFER_SIZE) ? 1'b1 : 1'b0;
    
    // Read data return
    always_comb begin
        reg_rdata = '0;
        unique case (1'b1)
            addr_hit[0]: begin
                reg_rdata[1:0] = mode_q;
            end
            addr_hit[1]: begin
                reg_rdata[15:0] = length_q;
            end
            addr_hit[2]: begin
                reg_rdata = scale_q;
            end
            addr_hit[3]: begin
                reg_rdata[0] = status_q;
            end
            addr_hit[4]: begin
                reg_rdata[1:0] = err_q;
            end
            default: begin
                reg_rdata = '1;
            end
        endcase
    end
    
    // Registers
    always_ff @(posedge clk_i or negedge rst_ni) begin : mode_reg_proc
        if (!rst_ni) begin
            mode_q <= '0;
            invalid_mode_q <= '0;
        end else if (mode_we) begin
            mode_q <= invalid_mode_d ? 2'b00 : mode_d;
            invalid_mode_q <= invalid_mode_d;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin : length_reg_proc
        if (!rst_ni) begin
            length_q <= '0;
            invalid_length_q <= '0;
        end else if (length_we) begin
            length_q <= invalid_length_d ? BUFFER_SIZE : length_d;
            invalid_length_q <= invalid_length_d;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin : scale_reg_proc
        if (!rst_ni) begin
            scale_q <= '0;
        end else if (scale_we) begin
            scale_q <= scale_d;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin : start_reg_proc
        if (!rst_ni) begin
            start <= '0;
        end else if (ctrl_we) begin
            start <= reg_wdata[0];
        end else begin
            start <= '0;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin : clear_reg_proc
        if (!rst_ni) begin
            clear_err <= '0;
        end else if (ctrl_we) begin
            clear_err <= reg_wdata[4];
        end else begin
            clear_err <= '0;
        end
    end
    
    assign err_we = mode_we | length_we;
    always_ff @(posedge clk_i or negedge rst_ni) begin : err_reg_proc
        if (!rst_ni) begin
            err_q <= '0;
        end else if (mode_we) begin
            err_q <= err_q | {1'b0, invalid_mode_d};
        end else if (length_we) begin
            err_q <= err_q | {invalid_length_d, 1'b0};
        end else if (clear_err) begin
            err_q <= '0;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin : status_reg_proc
        if (!rst_ni) begin
            status_q <= '0;
        end else begin
            status_q <= status_d;
        end
    end
    
    syst_array_top #(
        .N              (N),
        .BUFFER_SIZE    (BUFFER_SIZE),
        .IWIDTH         (IWIDTH),
        .OWIDTH         (OWIDTH),
        .AW             (AW)
    ) syst_array_core (
        .clk_i          (clk_i),
        .reset_i        (~rst_ni),
        .row_data_i     (row_data_i),
        .col_data_i     (col_data_i),
        .scale_i        (scale_q),
        .start_i        (start),
        .test_mode_i    ('0),
        .mode_i         (mode_q),
        .length_i       (length_q),
        .ibuffer_addr_o (ibuffer_addr_o),
        .obuffer_addr_o (obuffer_addr_o),
        .read_en_o      (read_en_o),
        .test_en_o      ( ),
        .done_o         (done_o),
        .ready_o        (status_d),
        .valid_o        (valid_o),
        .fault_flag_o   ( ),
        .data_o         (data_o),
        .strb_o         (strb_o)
    );
    
endmodule
