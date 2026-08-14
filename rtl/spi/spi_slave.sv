// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Lars Kröger <lkroeger@ethz.ch>


`include "common_cells/registers.svh"

module spi_slave (
    input  logic clk_i,       // simulation time clock
    input  logic rst_ni,

    input  logic sclk_i,      // SPI clock from master
    input  logic cs_n_i,      // active-low chip select
    input  logic mosi_i,      // data from master
    output logic miso_o       // data to master

);



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
    logic [7:0] byte_cnt_q, byte_cnt_d;
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

    logic [7:0] mem [0:512];  // 64 KB
    logic [7:0] mem_d [0:512];
    logic [7:0] mem_q [0:512];
  // Load memory from HEX file
    initial begin
        $readmemh("memory.hex", mem_q);
    end


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
            6'd0: byte_type = BYTE_CMD;
            6'd1: byte_type = BYTE_LENGTH;
            6'd2: byte_type = BYTE_ADDR0;
            6'd3: byte_type = BYTE_ADDR1;
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
        address_d       = address_q;
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
            end

            SHIFT: begin
                // if(cs_n_i) begin
                //     spi_state_d = IDLE;
                // end else begin

                    if((bit_cnt_q == 4'b1000)) begin
                        spi_state_d = DONE;
                    end

                    // clk_div_count_d = clk_div_count_q +1;
                    // if (clk_div_count_q+1 == clk_scale_q) begin
                        // clk_div_count_d = 8'h0;
                        // sclk_int_d = ~sclk_int_q; //eventuell jetzt vertauscht
                        if(sclk_rising) begin
                            rx_shift_reg_d = {rx_shift_reg_q[6:0], mosi_i}; // does this still conflicts with non shift laoding
                        end else if (sclk_falling) begin
                            // if(bit_cnt_q != 0) begin
                            tx_shift_reg_d = {tx_shift_reg_q[6:0], 1'b0}; //FIX
                            // end
                            bit_cnt_d  = bit_cnt_q + 1;
                        end
                    

                // write logic to set a flag and write to a buffer when a transaction is done and its a read
                // end
            end

            DONE: begin
                if ((byte_cnt_q == length_q+4) && (byte_cnt_q >=3) || cs_n_i) begin
                    spi_state_d = IDLE;
                    byte_cnt_d  = 0;
                end else begin
                    spi_state_d = LOAD;
                    byte_cnt_d = byte_cnt_q+1;
                end

                // if(byte_cnt_q >= 4) begin
                //     status_d = byte_cnt_q - 3; // with this we can only send 32 bits, do we need to extend this?
                // end
                // if (byte_cnt_q >= length_q + 4) begin
                //     byte_cnt_d = 0;
                // end else begin
                //     byte_cnt_d = byte_cnt_q+1;
                // end

                case (byte_type)
                    BYTE_CMD: begin 
                        cmd_d = rx_shift_reg_q;
                        rw_type_d = rx_shift_reg_q[2:1];
                    end
                    BYTE_LENGTH: begin
                        length_d = rx_shift_reg_q;
                    end
                    BYTE_ADDR0: begin
                        address_d[15:8] = rx_shift_reg_q;
                    end
                    BYTE_ADDR1: begin
                        address_d[7:0] = rx_shift_reg_q;
                    end
                    BYTE_DATA: begin
                        if(rw_type_q == 2'b10) begin //write
                            mem_d[address_q] = rx_shift_reg_q;  // pull from fifo     // set fifo enable bit
                            $display("@%t | [SPI SLAVE] Wrote byte: 0x%02h, to Adress: 0x%02h.", $time, rx_shift_reg_q, address_q);
                            address_d = address_q + 1;
                        end
                    end
                endcase

            end

            default: spi_state_d = IDLE;
        endcase

        // if ((spi_state_q == SHIFT || spi_state_q == LOAD || spi_state_q == DONE)) begin
        //     if (clk_div_count_q == clk_scale_q) begin
        //         clk_div_count_d = 8'h0;
        //         sclk_int_d = ~sclk_int_q;
        //     end else begin
        //         clk_div_count_d = clk_div_count_q + 1;
        //     end
        // end


        // determines which data has to be sent during the shift
        if(spi_state_q == LOAD) begin
            case (byte_type)
                BYTE_CMD: begin 
                    tx_shift_reg_d = 8'h2f;
                end
                BYTE_LENGTH: begin
                    tx_shift_reg_d = 8'h42;
                end
                BYTE_ADDR0: begin
                    tx_shift_reg_d = 8'h22;
                end
                BYTE_ADDR1: begin
                    tx_shift_reg_d = 8'h6d;
                end
                BYTE_DATA: begin
                    if(rw_type_q == 2'b01) begin //read
                        tx_shift_reg_d = mem_q[address_q];  // pull from fifo     // set fifo enable bit
                        $display("@%t | [SPI SLAVE] Read byte: 0x%02h, from Adress: 0x%02h.", $time, mem_q[address_q], address_q);
                        address_d = address_q + 1;
                    end
                end
            endcase
        end
    end
endmodule