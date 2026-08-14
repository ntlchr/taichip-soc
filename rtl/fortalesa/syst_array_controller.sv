// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Controller for the reconfigurable systolic array

module syst_array_controller
    #(
    parameter N = 12,                   // Systolic array size, should be dividable by 2
    parameter BUFFER_SIZE = 256,        // Size of the buffers
    parameter AW = 32                   // Address width
    )
    (
    // Clock and reset
    input logic             clk_i,
    input logic             reset_i,
    // Config signals
    input logic             start_i,
    input logic             test_mode_i,
    input logic [1:0]       mode_i,     // Execution mode: 00 - performance, 01 - dmr, 10 - tmr
    input logic [15:0]      length_i,
    // Output control signals
    output logic [AW-1:0]   ibuffer_addr_o,
    output logic [AW-1:0]   obuffer_addr_o,
    output logic            read_en_o,
    output logic            test_en_o,
    output logic            enable_o,
    output logic            read_out_o,
    output logic            done_o,
    output logic            ready_o,
    output logic [N-1:0]    strb_o
    );

    // --------------------------------------------------------------------------
    // -- Local parameters and signals
    // --------------------------------------------------------------------------
    
    logic start_d, start_q, start_q1;
    
    logic start_edge;
    
    logic [$clog2(BUFFER_SIZE):0] readin_count;
    logic [$clog2(N):0] shift_count;
    logic [$clog2(N):0] readout_count;
    
    logic [AW-1:0] ibuffer_addr, obuffer_addr;
    
    logic readin_count_en, shift_count_en, readout_count_en;
    logic readin_count_done, shift_count_done, readout_count_done;
    logic write_out_en, write_out_done;
    
    enum logic [2:0] {
        READY_S,
        START_READ_S,
        READ_IN_S,
        SHIFT_LAST_S,
        READ_OUT_S,
        DONE_S,
        START_TEST_S,
        TEST_MODE_S
    } current_state, next_state;
    
    // --------------------------------------------------------------------------
    // -- Counters and registers
    // --------------------------------------------------------------------------
    
    assign ibuffer_addr_o = ibuffer_addr;
    assign obuffer_addr_o = obuffer_addr;
    
    assign start_edge = start_q & !start_q1;
    
    assign readin_count_done = (readin_count == length_i-1) ? 1'b1 : 1'b0;
    assign shift_count_done = (mode_i == 2'b00 && shift_count == N-2+1)   ? 1'b1 :
                              (mode_i != 2'b00 && shift_count == N/2-1+1) ? 1'b1 : 1'b0;
    assign readout_count_done = (mode_i[1] == 1'b0 && readout_count == N-1)   ? 1'b1 :
                                (mode_i[1] == 1'b1 && readout_count == N/2-1) ? 1'b1 : 1'b0;
    
    // Registers
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            start_q  <= '0;
            start_q1 <= '0;
        end else begin
            start_q  <= start_d;
            start_q1 <= start_q;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            write_out_en   <= '0;
            write_out_done <= '0;
        end else begin
            write_out_en   <= readout_count_en;
            write_out_done <= readout_count_done;;
        end
    end
    
    // Counters
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            readin_count <= '0;
        end else if (readin_count_done) begin
            readin_count <= '0;
        end else if (readin_count_en) begin
            readin_count <= readin_count + 1'b1;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            shift_count <= '0;
        end else if (shift_count_done) begin
            shift_count <= '0;
        end else if (shift_count_en) begin
            shift_count <= shift_count + 1'b1;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            readout_count <= '0;
        end else if (readout_count_done) begin
            readout_count <= '0;
        end else if (readout_count_en) begin
            readout_count <= readout_count + 1'b1;
        end
    end
    
    // Address generation
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            ibuffer_addr <= '0;
        end else if (readin_count_done) begin
            ibuffer_addr <= '0;
        end else if (readin_count_en) begin
            ibuffer_addr <= ibuffer_addr + 1'b1;
        end
    end
    // TODO: Output address reset should be controlled based on the layer configs
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            obuffer_addr <= '0;
        end else if (write_out_done) begin
            obuffer_addr <= '0;
        end else if (write_out_en) begin
            obuffer_addr <= obuffer_addr + 1'b1;
        end
    end
    
    // --------------------------------------------------------------------------
    // -- FSM controller
    // --------------------------------------------------------------------------
    
    // State register
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            current_state <= READY_S;
        end else begin
            current_state <= next_state;
        end
    end

    // State transition
    always_comb begin
        case(current_state)
        READY_S: begin
            if (start_edge)         next_state = START_READ_S;
            else if (test_mode_i)   next_state = START_TEST_S;
            else                    next_state = READY_S;
        end
        START_READ_S: begin
            next_state = READ_IN_S;
        end
        READ_IN_S: begin
            if (readin_count_done)  next_state = SHIFT_LAST_S;
            else                    next_state = READ_IN_S;
        end
        SHIFT_LAST_S: begin
            if (shift_count_done)   next_state = READ_OUT_S;
            else                    next_state = SHIFT_LAST_S;
        end
        READ_OUT_S: begin
            if (write_out_done)     next_state = DONE_S;
            else                    next_state = READ_OUT_S;
        end
        DONE_S: begin
            next_state = READY_S;
        end
        START_TEST_S: begin
            next_state = TEST_MODE_S;
        end
        TEST_MODE_S: begin
            if (!test_mode_i)       next_state = SHIFT_LAST_S;
            else                    next_state = TEST_MODE_S;
        end
		default: begin
			next_state = READY_S;
		end
        endcase
    end
    
    // Control signals
    always_comb begin
        // Default values
        start_d  = start_q;
        
        read_en_o = 1'b0;
        test_en_o = 1'b0;
        ready_o = 1'b0;
        enable_o = 1'b0;
        read_out_o = 1'b0;
        done_o = 1'b0;
        strb_o = '0;
        
        readin_count_en = 1'b0;
        shift_count_en = 1'b0;
        readout_count_en = 1'b0;
        
        case(current_state)
        READY_S: begin
            start_d  = start_i;
            ready_o  = 1'b1;
        end
        START_READ_S: begin
            start_d   = 1'b0;          // Start is auto-deasserted
            read_en_o = 1'b1;
            readin_count_en = 1'b1;
        end
        READ_IN_S: begin
            read_en_o = 1'b1;
            enable_o  = 1'b1;
            readin_count_en = 1'b1;
        end
        SHIFT_LAST_S: begin
            enable_o = 1'b1;
            shift_count_en = 1'b1;
        end
        READ_OUT_S: begin
            read_out_o = 1'b1;
            strb_o = (mode_i == 2'b00) ? {N{1'b1}} : {N/2{2'b01}};
            readout_count_en = 1'b1;
        end
        DONE_S: begin
            done_o = 1'b1;
        end
        START_TEST_S: begin
            read_en_o = 1'b1;
            test_en_o = 1'b1;
        end
        TEST_MODE_S: begin
            enable_o  = 1'b1;
            read_en_o = 1'b1;
            test_en_o = 1'b1;
        end
        endcase
    end

endmodule