// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Lars Kröger <lkroeger@ethz.ch>


`include "common_cells/registers.svh"

module spi #(
    /// The OBI configuration for all ports.
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    /// OBI request type
    parameter type obi_req_t         = logic,
    /// OBI response type
    parameter type obi_rsp_t         = logic
) (
    /// Primary input clock
    input  logic         clk_i,
    /// Asynchronous active-low reset
    input  logic         rst_ni,

    /// Control interface from interconnect (request).
    input  obi_req_t     obi_req_i,
    /// Control interface back into interconnect (response).
    output obi_rsp_t     obi_rsp_o,

    /// SPI signals
    output logic         sclk_o,
    output logic         mosi_o,
    input  logic         miso_i,
    output logic         cs_n_o

);

    import spi_reg_pkg::*;
    // localparam logic [4:0] CLK_DIV_MAX = 8'd5;
    //-----------------------------------------------------------------------------------------------
    // Instantiations
    //-----------------------------------------------------------------------------------------------

    // Internal Signals
    spi_reg2hw_t reg2hw; // Interface from Register to Internal SPI Logic(HW)
    spi_hw2reg_t hw2reg; // Interface from Internal SPI Logic(HW) to Register

    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        SHIFT,
        DONE
    } spi_state_e;

    typedef enum logic {
        LENGTH,
        UNLIMITED
    } mode_t;

    spi_state_e spi_state_d, spi_state_q;
    logic tx_empty, rx_empty, rx_full;
    logic rx_pulse;
    logic tx_pulse;
    logic spi_tx_fifo_rd_en_q, spi_tx_fifo_rd_en_d;
    logic [7:0] tx_fifo_data;

    logic [7:0] rx_shift_reg_q, rx_shift_reg_d, tx_shift_reg_q, tx_shift_reg_d;
    logic [3:0] bit_cnt_q, bit_cnt_d;
    logic [15:0] clk_div_count_q, clk_div_count_d;
    logic       sclk_int_q, sclk_int_d;
    logic [15:0] byte_cnt_q, byte_cnt_d;
    logic [7:0] cmd_q, cmd_d;
    logic [15:0] length_d, length_q;
    logic [15:0] clk_scale_q, clk_scale_d;
    logic [7:0] status_q, status_d;
    logic mosi_q, mosi_d;

    logic activate;
  // Instantiate register file
    spi_reg_top #(
        .obi_req_t(obi_req_t),
        .obi_rsp_t(obi_rsp_t)
    ) i_reg_file (
        .clk_i,
        .rst_ni,
        .obi_req_i,
        .obi_rsp_o,
        .reg2hw(reg2hw),
        .hw2reg(hw2reg),
        .rx_read_pulse(rx_pulse),
        .tx_write_pulse(tx_pulse),
        .activate_o(activate)
    );



    mode_t mode;
    assign mode = (reg2hw.control[7]) ? UNLIMITED : LENGTH;

    logic spi_fifo_write;
    assign spi_fifo_write = (spi_state_q == DONE) && !rx_full;
    logic obi_read_enable;
    // assign obi_read_enable = (obi_req_i.addr == SPI_RXBUFFER_OFFSET) && obi_req_i.req && !obi_req_i.we;



    logic [7:0] fifo_status;
    spi_fifo_buffer #(
        .DEPTH(16),
        .DATA_WIDTH(8)
    ) i_spi_rx_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .spi_write_i(spi_fifo_write),      // from FSM
        .spi_data_i(rx_shift_reg_q),  // from FSM
        .obi_read_en(rx_pulse),
        .rd_data_o(hw2reg.rx_data),
        .full_o(rx_full),
        .almost_full_o(fifo_status[6]),
        .empty_o(rx_empty),
        .almost_empty_o(fifo_status[4])
    );



    spi_fifo_buffer #(
        .DEPTH(16),
        .DATA_WIDTH(8)
    ) i_spi_tx_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .spi_write_i(tx_pulse),        // core writes to tx_data register
        .spi_data_i(reg2hw.tx_data),     // core register value
        .obi_read_en(spi_tx_fifo_rd_en_q),    // FSM reads when sending
        .rd_data_o(tx_fifo_data),       // drive tx_shift_reg from here
        .full_o(fifo_status[3]),
        .almost_full_o(fifo_status[2]),
        .empty_o(tx_empty),
        .almost_empty_o(fifo_status[0])
    );

    assign fifo_status[5] = rx_empty;
    assign fifo_status[1] = tx_empty;
    assign fifo_status[7] = rx_full;




    logic cpol;   //_q, cpol,d;
    logic cpha;    //_q, cpha_d;
    logic active_clk, sample_edge;
    // logic [7:0] sample;

    assign cpol = reg2hw.mode_ctrl[0];
    assign cpha = reg2hw.mode_ctrl[1];
    assign active_clk = cpol;                 // sets the acive clock
    assign sample_edge = cpol ^ cpha;    // when it is zero, we sample on the rising edge, if 1 on the falling edge. Default mode is therfore SPI MODE 0

    assign sclk_o = sclk_int_q;
    assign mosi_o = mosi_q && !cs_n_o;//!((spi_state_q != IDLE) ? 1'b0 : 1'b1);
    assign cs_n_o = (spi_state_q != IDLE) ? 1'b0 : 1'b1;

    assign hw2reg.busy   = {6'd0, !cs_n_o};
    
    assign hw2reg.status = status_q;
    assign hw2reg.fifo_status = fifo_status;

    always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        spi_state_q     <= IDLE;
        bit_cnt_q       <= 0;
        clk_div_count_q <= 0;
        sclk_int_q      <= '0; // active_clk; Natalia: Changed for TAICHIP-1 Soc to 0 because ihp13cmos5l doesn't have ff with both set and reset!
        byte_cnt_q      <= 0;
        cmd_q           <= 0;
        length_q        <= 0;
        rx_shift_reg_q  <= 0;
        tx_shift_reg_q  <= 0;
        spi_tx_fifo_rd_en_q <= 0;
        clk_scale_q     <= 1;
        status_q        <= 0;
        mosi_q          <= 0;
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
        spi_tx_fifo_rd_en_q <= spi_tx_fifo_rd_en_d;
        clk_scale_q     <= clk_scale_d;
        status_q        <= status_d;
        mosi_q          <= mosi_d;
    end
    end

    always_comb begin
        spi_state_d     = spi_state_q;
        bit_cnt_d       = bit_cnt_q;
        clk_div_count_d = clk_div_count_q;
        sclk_int_d      = sclk_int_q;
        byte_cnt_d      = byte_cnt_q;
        cmd_d           = cmd_q;
        length_d        = length_q;
        rx_shift_reg_d  = rx_shift_reg_q;
        tx_shift_reg_d  = tx_shift_reg_q;
        spi_tx_fifo_rd_en_d = 0;
        clk_scale_d     = clk_scale_q;
        status_d        = status_q;
        mosi_d          = mosi_q;
    
        case (spi_state_q) 
            IDLE: begin
                if (activate) begin
                    spi_state_d = LOAD;
                    status_d = 0;
                end
                sclk_int_d = active_clk;
                
            end
            LOAD: begin
                spi_state_d = SHIFT;
                rx_shift_reg_d = 0;
                bit_cnt_d = 0;
                sclk_int_d = active_clk;
                clk_div_count_d = 0;
                cmd_d = reg2hw.control;
                clk_scale_d = reg2hw.freq;
                length_d = reg2hw.length;
                if (!tx_empty) begin
                    spi_tx_fifo_rd_en_d = 1;
                    tx_shift_reg_d = tx_fifo_data;
                    if(!cpha) begin
                        mosi_d         = tx_fifo_data[7];
                    end
                end

            end

            SHIFT: begin

                if((bit_cnt_q == (4'b0111 + cpha)) && (clk_div_count_q +1  == clk_scale_q) && (sclk_int_q == (!active_clk))) begin
                    spi_state_d = DONE;
                end

                clk_div_count_d = clk_div_count_q +1;
                if (clk_div_count_q+1 == clk_scale_q) begin
                    // clk_div_count_d = 8'h0;
                    // sclk_int_d = ~sclk_int_q; //eventuell jetzt vertauscht
                    if(sclk_int_q == sample_edge) begin
                        rx_shift_reg_d = {rx_shift_reg_q[6:0], miso_i}; // does this still conflicts with non shift laoding
                    end else begin
                        if(cpha== 0) begin
                            tx_shift_reg_d = {tx_shift_reg_q[6:0], 1'b0}; //FIX
                            // if(bit_cnt_q != 4'b1000) begin
                            mosi_d         = tx_shift_reg_q[6];
                            // end
                        end else begin
                            tx_shift_reg_d = {tx_shift_reg_q[6:0], 1'b0}; //FIX
                            // if(bit_cnt_q != 4'b0000) begin
                                mosi_d         = tx_shift_reg_q[7];
                            // end
                        end

                        // end
                        bit_cnt_d  = bit_cnt_q + 1;
                    end
                end

                // write logic to set a flag and write to a buffer when a transaction is done and its a read

            end

            DONE: begin
                if (byte_cnt_q >= length_q && mode==LENGTH) begin
                    spi_state_d = IDLE;
                    byte_cnt_d = 0;
                end else begin
                    spi_state_d = LOAD;
                    byte_cnt_d = byte_cnt_q+1;
                    // status_d   = status_q+1;
                end
                tx_shift_reg_d = tx_fifo_data;
                sclk_int_d = 0;
                status_d = byte_cnt_q+1;
                cmd_d = 0;
            end

            default: spi_state_d = IDLE;
        endcase

        if ((spi_state_q == SHIFT || spi_state_q == LOAD || spi_state_q == DONE)) begin
            if (clk_div_count_q == clk_scale_q) begin
                clk_div_count_d = 8'h0;
                sclk_int_d = ~sclk_int_q;
            end else begin
                clk_div_count_d = clk_div_count_q + 1;
            end
        end

        if(spi_state_q != SHIFT) begin
            tx_shift_reg_d = tx_fifo_data;  // pull from fifo     // set fifo enable bit
            // mosi_d         = tx_fifo_data[7];
        end

    end
endmodule
