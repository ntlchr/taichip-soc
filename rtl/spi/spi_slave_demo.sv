// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Lars Kröger <lkroeger@ethz.ch>


`include "common_cells/registers.svh"

module spi_slave_demo (
    input  logic clk_i,       // simulation time clock
    input  logic rst_ni,

    input  logic sclk_i,      // SPI clock from master
    input  logic cs_n_i,      // active-low chip select
    input  logic mosi_i,      // data from master
    output logic miso_o       // data to master

);

    localparam IMGLENGTH = 512;
    string filename;


    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        SHIFT,
        DONE
    } spi_state_e;

    spi_state_e spi_state_d, spi_state_q;

    logic [7:0] rx_shift_reg_q, rx_shift_reg_d, tx_shift_reg_q, tx_shift_reg_d;
    logic [3:0] bit_cnt_q, bit_cnt_d;
    logic [7:0] clk_div_count_q, clk_div_count_d;
    logic       sclk_int_q, sclk_int_d;
    logic [15:0] byte_cnt_q, byte_cnt_d;
    logic [7:0] cmd_q, cmd_d;
    logic [7:0] length_d, length_q;
    logic [1:0] rw_type_d, rw_type_q;
    logic [4:0] clk_scale_q, clk_scale_d;
    logic [7:0] status_q, status_d;
    logic [15:0] address_d, address_q;
    logic [7:0]  store_d, store_q;
    logic cs_edge_d, cs_edge_q;

    logic cs_falling;
    assign cs_falling = (!cs_edge_q) && (cs_edge_d);
    
    logic sclk_rising;
    assign sclk_rising = !sclk_int_q && sclk_int_d;

    logic sclk_falling;
    assign sclk_falling = sclk_int_q && !sclk_int_d;

    logic [7:0] mem [0:IMGLENGTH-1];
    logic [7:0] mem_d [0:IMGLENGTH-1];
    logic [7:0] mem_q [0:IMGLENGTH-1];

    typedef enum logic [2:0] {
        BYTE_CMD, BYTE_LENGTH, BYTE_ADDR1, BYTE_ADDR0, BYTE_DATA
        } byte_type_e;
    byte_type_e byte_type;

    assign miso_o = tx_shift_reg_q[7] && !cs_n_i;

    
    always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        spi_state_q     <= IDLE;
        bit_cnt_q       <= 0;
        clk_div_count_q <= 0;
        sclk_int_q      <= 0;
        byte_cnt_q      <= 0;
        cmd_q           <= 0;
        length_q        <= 0;
        rx_shift_reg_q  <= 0;
        tx_shift_reg_q  <= 0;
        rw_type_q       <= 0;
        clk_scale_q     <= 1;
        status_q        <= 0;
        store_q         <= 0;
        address_q       <= 0;

        // mem_q           <= mem;
    end else begin
        spi_state_q     <= spi_state_d;
        bit_cnt_q       <= bit_cnt_d;
        clk_div_count_q <= clk_div_count_d;
        sclk_int_q      <= sclk_int_d;
        byte_cnt_q      <= byte_cnt_d;
        cmd_q           <= cmd_d;
        length_q        <= length_d;
        rx_shift_reg_q  <= rx_shift_reg_d;
        tx_shift_reg_q  <= tx_shift_reg_d;
        rw_type_q       <= rw_type_d;
        clk_scale_q     <= clk_scale_d;
        status_q        <= status_d;
        cs_edge_q       <= cs_edge_d;
        store_q         <= store_d;
        address_q       <= address_d;
        mem_q           <= mem_d;
        //not good, see if it works
        // if (spi_state_q == DONE && byte_type == BYTE_DATA && rw_type_q == 2'b10) begin
        //         mem_q[address_q] <= rx_shift_reg_q;
        // end


    end
    end

    always_comb begin
        case (byte_cnt_q)
            // 6'd0: byte_type = BYTE_CMD;
            // 6'd1: byte_type = BYTE_LENGTH;
            // 6'd2: byte_type = BYTE_ADDR0;
            // 6'd3: byte_type = BYTE_ADDR1;
            default: byte_type = BYTE_DATA;
        endcase
    end

    // logic active_clk;
    // logic sampling_edge;
    // always_comb begin
    //     active_clk = cpol_q;
    //     sampling_edge = 
    // end

    // always_comb begin
    //     case({cpol, cpha})
    //         00:
    //         01:
    //         10:
    //         11: 
    //     endcase
    // end

    always_comb begin
        spi_state_d     = spi_state_q;
        bit_cnt_d       = bit_cnt_q;
        clk_div_count_d = clk_div_count_q;
        sclk_int_d      = sclk_i;
        byte_cnt_d      = byte_cnt_q;
        cmd_d           = cmd_q;
        length_d        = length_q;
        rx_shift_reg_d  = rx_shift_reg_q;
        tx_shift_reg_d  = tx_shift_reg_q;
        rw_type_d       = rw_type_q;
        clk_scale_d     = clk_scale_q;
        status_d        = status_q;
        cs_edge_d       = cs_n_i;
        store_d         = store_q;
        mem_d           = mem_q;
        case (spi_state_q) 
            IDLE: begin
                if (!cs_n_i) begin
                    spi_state_d = LOAD;
                end else begin 
                    spi_state_d = IDLE;
                end
                address_d = 0;
                length_d = 0;
                rw_type_d = 0;
                rx_shift_reg_d =0;
                byte_cnt_d = 0;
                bit_cnt_d =0;
            end
            LOAD: begin
                spi_state_d = SHIFT;
                rx_shift_reg_d = 0;
                bit_cnt_d = 0;
                clk_div_count_d = 0;
                tx_shift_reg_d = 8'hf4;
            end

            SHIFT: begin

                if((bit_cnt_q == 4'b1000)) begin
                    spi_state_d = DONE;
                end
                if(sclk_rising) begin
                    rx_shift_reg_d = {rx_shift_reg_q[6:0], mosi_i}; // does this still conflicts with non shift laoding
                end else if (sclk_falling) begin
                    tx_shift_reg_d = {tx_shift_reg_q[6:0], 1'b0};
                    bit_cnt_d  = bit_cnt_q + 1;
                end
            end

            DONE: begin
                
                mem_d[address_q] = rx_shift_reg_q;  // pull from fifo     // set fifo enable bit
                address_d = address_q + 1;
                // $display("@%t | [SPI SLAVE] Received byte %0x", $time, rx_shift_reg_q);

                if ((byte_cnt_q >= IMGLENGTH) ||  cs_n_i) begin
                    spi_state_d = IDLE;
                    byte_cnt_d  = 0;
                    $sformat(filename, "videoframes/frame_%0t.hex", $time);
                    $writememh(filename, mem_d);
                    $display("@%t | [SPI SLAVE] Received frame.", $time);
                end else begin
                    spi_state_d = LOAD;
                    byte_cnt_d = byte_cnt_q+1;
                end



            end

            default: spi_state_d = IDLE;
        endcase
    end
endmodule