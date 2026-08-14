// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Lars Kröger <lkroeger@ethz.ch>

`include "common_cells/registers.svh"

module spi_reg_top import spi_reg_pkg::*; #(
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  obi_req_t  obi_req_i,
    output obi_rsp_t obi_rsp_o,

    output spi_reg2hw_t reg2hw,
    input  spi_hw2reg_t hw2reg,


    output logic rx_read_pulse,
    output logic tx_write_pulse,

    output logic activate_o
);

  logic activate_d, activate_q;
  assign activate_o = activate_q;

  // OBI preparation signals
  logic valid_d, valid_q;
  logic we_d, we_q;
  logic req_d, req_q;
  logic [AddressWidth-1:0] write_addr;
  logic [AddressWidth-1:0] read_addr_d, read_addr_q;
  logic [ObiCfg.IdWidth-1:0] id_d, id_q;
  logic obi_err;
  logic w_err_d, w_err_q;
  logic [ObiCfg.DataWidth-1:0] obi_rdata, obi_wdata;
  logic obi_read_request, obi_write_request;

  logic read_to_rxbuffer_q;
  logic rx_read_access_d, rx_read_access_q;

  logic tx_write_access_d, tx_write_access_q;
  logic write_to_txbuffer_q;

  logic read_to_rxbuffer; //pulse detection for fifo

  // OBI response assignment
  always_comb begin
    obi_rsp_o              = '0;
    obi_rsp_o.r.rdata      = obi_rdata;
    obi_rsp_o.r.rid        = id_q;
    obi_rsp_o.r.err        = obi_err;
    obi_rsp_o.gnt          = obi_req_i.req;
    obi_rsp_o.rvalid       = valid_q;
  end

  assign obi_wdata         = obi_req_i.a.wdata;
  assign obi_read_request  = req_q & ~we_q;
  assign obi_write_request = obi_req_i.req & obi_req_i.a.we;
  assign id_d              = obi_req_i.a.aid;
  assign valid_d           = obi_req_i.req;
  assign write_addr        = obi_req_i.a.addr[AddressWidth-1:2];
  assign read_addr_d       = obi_req_i.a.addr[AddressWidth-1:2];
  assign we_d              = obi_req_i.a.we;
  assign req_d             = obi_req_i.req;

  `FF(id_q, id_d, '0, clk_i, rst_ni)
  `FF(valid_q, valid_d, '0, clk_i, rst_ni)
  `FF(read_addr_q, read_addr_d, '0, clk_i, rst_ni)
  `FF(req_q, req_d, '0, clk_i, rst_ni)
  `FF(we_q, we_d, '0, clk_i, rst_ni)
  `FF(w_err_q, w_err_d, '0, clk_i, rst_ni)


  assign rx_read_access_d = obi_req_i.req && !obi_req_i.a.we &&
                          (obi_req_i.a.addr[AddressWidth-1:2] == SPI_RXBUFFER_OFFSET[AddressWidth-1:2]);

  assign tx_write_access_d = obi_req_i.req && obi_req_i.a.we &&
                           (obi_req_i.a.addr[AddressWidth-1:2] == SPI_TXBUFFER_OFFSET[AddressWidth-1:2]);
  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Registers
  ////////////////////////////////////////////////////////////////////////////////////////////////

  typedef struct packed {
    logic [7:0] control;
    logic [7:0] status;
    logic [7:0] fifo_status;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic [15:0] length;
    logic [7:0] mode_ctrl;
    logic [7:0] busy;
    logic [15:0]  freq;
  } spi_reg_fields_t;

  spi_reg_fields_t reg_d, reg_q;
  `FF(reg_q, reg_d, '0, clk_i, rst_ni)

  spi_reg_fields_t new_reg;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // COMB LOGIC
  ////////////////////////////////////////////////////////////////////////////////////////////////

  logic [ObiCfg.DataWidth-1:0] bit_mask;
  for (genvar i = 0; unsigned'(i) < ObiCfg.DataWidth/8; ++i ) begin : gen_write_mask
    assign bit_mask[8*i +: 8] = {8{obi_req_i.a.be[i]}};
  end

  always_comb begin
    // Defaults
    activate_d = '0;
    obi_rdata = '0;
    obi_err   = w_err_q;
    w_err_d   = 1'b0;
    new_reg   = reg_q;

    // Assign outputs to logic
    reg2hw.control = reg_q.control;
    reg2hw.tx_data = reg_q.tx_data;
    reg2hw.length = reg_q.length;
    reg2hw.mode_ctrl = reg_q.mode_ctrl;
    reg2hw.freq       = reg_q.freq;

    // Update from logic
    new_reg.status  = hw2reg.status;
    new_reg.rx_data = hw2reg.rx_data;
    new_reg.fifo_status = hw2reg.fifo_status;
    new_reg.busy        = hw2reg.busy;

    reg_d = new_reg;

    // WRITE
    if (obi_write_request) begin
      case ({write_addr, 2'b00})
        SPI_CONTROL_OFFSET: begin
          reg_d.control = obi_wdata[7:0];
          activate_d = obi_wdata[0];
        end
        SPI_TXBUFFER_OFFSET: begin
          reg_d.tx_data = obi_wdata[7:0];
        end
        SPI_LENGTH_OFFSET: begin
          reg_d.length= obi_wdata[15:0];
        end
        SPI_MODE_CTRL_OFFSET: begin
          reg_d.mode_ctrl= obi_wdata[7:0];
        end
        SPI_MODE_BUSY_OFFSET: begin
          reg_d.busy= obi_wdata[7:0];
        end
        SPI_MODE_FREQ_OFFSET: begin
          reg_d.freq= obi_wdata[15:0];
        end                        
        default: begin
          w_err_d = 1'b1;
        end
      endcase
    end

    // READ
    if (obi_read_request) begin
      case ({read_addr_q, 2'b00})
        SPI_CONTROL_OFFSET:     obi_rdata = {{24{1'b0}}, reg_q.control};
        SPI_STATUS_OFFSET:      obi_rdata = {{24{1'b0}}, reg_q.status};
        SPI_TXBUFFER_OFFSET:    obi_rdata = {{24{1'b0}}, reg_q.tx_data};
        SPI_RXBUFFER_OFFSET: begin
             obi_rdata = {{24{1'b0}}, reg_q.rx_data};
        end
        SPI_LENGTH_OFFSET:      obi_rdata = {{24{1'b0}}, reg_q.length};
        SPI_FIFOSTAT_OFFSET:      obi_rdata = {{24{1'b0}}, reg_q.fifo_status};
        SPI_MODE_CTRL_OFFSET:     obi_rdata = {{24{1'b0}}, reg_q.mode_ctrl};
        SPI_MODE_BUSY_OFFSET:     obi_rdata = {{24{1'b0}}, reg_q.busy};
        SPI_MODE_FREQ_OFFSET:     obi_rdata = {{24{1'b0}}, reg_q.freq};
        default: begin
          obi_rdata = 32'hDEAD_BEEF;
          obi_err   = 1'b1;
        end
      endcase
    end
  end



  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_read_access_q     <= 1'b0;
      read_to_rxbuffer_q   <= 1'b0;
      tx_write_access_q    <= 1'b0;
      write_to_txbuffer_q  <= 1'b0;
      activate_q           <= '0;
    end else begin
      rx_read_access_q     <= rx_read_access_d;
      read_to_rxbuffer_q   <= rx_read_access_q;
      tx_write_access_q    <= tx_write_access_d;
      write_to_txbuffer_q  <= tx_write_access_q;
      activate_q           <= activate_d;
    end
  end

  assign rx_read_pulse = rx_read_access_q & ~read_to_rxbuffer_q;

  assign tx_write_pulse = tx_write_access_q & ~write_to_txbuffer_q;

endmodule