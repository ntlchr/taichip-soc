// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
//
// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for TAICHIP-1 SoC by:
// - Natalia Cherezova (TalTech)
// - Abdelmadjid Dahmani (TalTech)
// - Andre Lucas Chinazzo (IHP)

module croc_domain import croc_pkg::*; #(
  parameter int unsigned GpioCount = 16
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic ref_clk_i,
  input  logic testmode_i,
  input  logic fetch_en_i,

  input  logic jtag_tck_i,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,

  input  logic uart_rx_i,
  output logic uart_tx_o,
  
  output logic spi_sclk_o,
  output logic spi_mosi_o,
  input  logic spi_miso_i,
  output logic spi_cs_n_o,

  input  logic mbist_start_i,
  input  logic mbist_watch_i,
  output logic mbist_active_o,
  output logic mbist_all_done_o,
  output logic mbist_any_done_o,

  input  logic [GpioCount-1:0] gpio_i,        	// Input from GPIO pins
  output logic [GpioCount-1:0] gpio_o,        	// Output to GPIO pins
  output logic [GpioCount-1:0] gpio_out_en_o, 	// Output enable signal; 0 -> input, 1 -> output

  output logic core_busy_o,
  output logic lockstep_error_o,
  output logic [1:0] obi_error_o,				// [0] - single-bit error, [1] - multi-bit error
  output logic [1:0] mem_error_o
);

  logic [GpioCount-1:0] gpio_o_internal;
  logic [GpioCount-1:0] gpio_out_en_o_internal;


  // -----------------
  // Control Signals
  // -----------------
  logic sram_impl; // soc_ctrl -> SRAM config signals
  logic debug_req;
  logic fetch_enable;
  logic [31:0] boot_addr;
  
  // -----------------
  // Error Signals
  // -----------------
  logic [1:0] obi_xbar_faults, obi_xbar_faults_d1, obi_periph_faults, obi_periph_faults_d1;
  logic [NumSramBanks-1:0][1:0] sram_faults;
  logic [1:0][NumSramBanks-1:0] sram_faults_transposed;
  
  for (genvar i = 0; i < NumSramBanks; i++) begin
	assign sram_faults_transposed[0][i] = sram_faults[i][0];
	assign sram_faults_transposed[1][i] = sram_faults[i][1];
  end
  
  assign obi_error_o = obi_xbar_faults_d1 | obi_periph_faults_d1;
  assign mem_error_o[0] = |sram_faults_transposed[0];
  assign mem_error_o[1] = |sram_faults_transposed[1];
  
  always_ff @(posedge clk_i) begin : obi_error_proc
	obi_xbar_faults_d1   <= obi_xbar_faults;
	obi_periph_faults_d1 <= obi_periph_faults;
  end
  
  // ------------------
  // FORTALESA Signals
  // ------------------
  logic [SystArraySize*SystArrayDataWidth-1:0] acc_row_data, acc_col_data;
  logic [SystArraySize*SystArrayDataWidth-1:0] acc_data_out;
  logic [SramBankAddrWidth-1:0] acc_ibuffer_addr, acc_obuffer_addr;
  logic acc_read_en, acc_write_en, acc_done_irq;
  logic [SystArraySize*SystArrayDataWidth/8-1:0] acc_strb;
  
  logic [NumAccSramBanks-1:0] acc_mem_req, acc_mem_we;
  logic [NumAccSramBanks-1:0][SbrObiCfg.DataWidth/8-1:0] acc_mem_be;
  logic [NumAccSramBanks-1:0][SramBankAddrWidth-1:0] acc_mem_word_addr;
  logic [NumAccSramBanks-1:0][31:0] acc_mem_rdata, acc_mem_wdata;
  
  // ------------------
  // Interrupts (irqs)
  // ------------------
  logic uart_irq;
  logic gpio_irq;
  logic timer0_irq0;
  logic timer0_irq1;
  logic dma_irq;
  logic [15:0] interrupts;
  always_comb begin
    interrupts    = '0;
    interrupts[0] = timer0_irq1;
    interrupts[1] = uart_irq;
    interrupts[2] = gpio_irq;
    interrupts[3] = acc_done_irq;
	interrupts[4] = dma_irq;
  end

  // ----------------------------
  // Manager buses into crossbar
  // ----------------------------

  // Core instr bus
  mgr_obi_req_t core_instr_obi_req;
  mgr_obi_rsp_t core_instr_obi_rsp;
  assign core_instr_obi_req.a.aid = '0;
  assign core_instr_obi_req.a.we = '0;
  assign core_instr_obi_req.a.be = '1;
  assign core_instr_obi_req.a.wdata = '0;
  assign core_instr_obi_req.a.a_optional = '0;
  
  rel_mgr_obi_req_t rel_core_instr_obi_req;
  rel_mgr_obi_rsp_t rel_core_instr_obi_rsp;

  // Core data bus
  mgr_obi_req_t core_data_obi_req;
  mgr_obi_rsp_t core_data_obi_rsp;
  assign core_data_obi_req.a.aid = '0;
  assign core_data_obi_req.a.a_optional = '0;
  
  rel_mgr_obi_req_t rel_core_data_obi_req;
  rel_mgr_obi_rsp_t rel_core_data_obi_rsp;

  // dbg req bus
  mgr_obi_req_t dbg_req_obi_req;
  mgr_obi_rsp_t dbg_req_obi_rsp;
  assign dbg_req_obi_req.a.aid = '0;
  assign dbg_req_obi_req.a.a_optional = '0;
  
  rel_mgr_obi_req_t rel_dbg_req_obi_req;
  rel_mgr_obi_rsp_t rel_dbg_req_obi_rsp;

  // ----------------------------------
  // Subordinate buses out of crossbar
  // ----------------------------------
  // Main xbar subordinate buses, must align with addr map indices!
  rel_sbr_obi_req_t [NumXbarSbr-1:0] all_sbr_obi_req;
  rel_sbr_obi_rsp_t [NumXbarSbr-1:0] all_sbr_obi_rsp;

  // User bus defined in module port

  // Mem bank buses
  rel_sbr_obi_req_t [NumSramBanks-1:0] xbar_mem_bank_obi_req;
  rel_sbr_obi_rsp_t [NumSramBanks-1:0] xbar_mem_bank_obi_rsp;
  
  sbr_obi_req_t [NumSramBanks-1:0] mem_bank_obi_req;
  sbr_obi_rsp_t [NumSramBanks-1:0] mem_bank_obi_rsp;
  
  // DMA bus
  rel_mgr_obi_req_t rel_dma_receive_obi_req;
  rel_mgr_obi_rsp_t rel_dma_receive_obi_rsp;

  rel_mgr_obi_req_t rel_dma_transmit_obi_req;
  rel_mgr_obi_rsp_t rel_dma_transmit_obi_rsp;

  rel_sbr_obi_req_t rel_dma_subordinate_obi_req;
  rel_sbr_obi_rsp_t rel_dma_subordinate_obi_rsp;

  // Periph bus
  rel_sbr_obi_req_t xbar_periph_obi_req;
  rel_sbr_obi_rsp_t xbar_periph_obi_rsp;

  // Error (connected to bus error slave)
  rel_sbr_obi_req_t xbar_error_obi_req;
  rel_sbr_obi_rsp_t xbar_error_obi_rsp;

  assign xbar_error_obi_req          = all_sbr_obi_req[XbarError];
  assign all_sbr_obi_rsp[XbarError]  = xbar_error_obi_rsp;
  
  assign rel_dma_subordinate_obi_req = all_sbr_obi_req[XbarDma];
  assign all_sbr_obi_rsp[XbarDma]    = rel_dma_subordinate_obi_rsp;

  assign xbar_periph_obi_req         = all_sbr_obi_req[XbarPeriph];
  assign all_sbr_obi_rsp[XbarPeriph] = xbar_periph_obi_rsp;

  for (genvar i = 0; i < NumSramBanks; i++) begin : gen_xbar_sbr_connect
    assign xbar_mem_bank_obi_req[i]     = all_sbr_obi_req[XbarBank0+i];
    assign all_sbr_obi_rsp[XbarBank0+i] = xbar_mem_bank_obi_rsp[i];
  end


  // -----------------
  // Peripheral buses
  // -----------------
  // Array of subordinate buses from peripheral demultiplexer
  rel_sbr_obi_req_t [NumPeriphs-1:0] all_periph_obi_req;
  rel_sbr_obi_rsp_t [NumPeriphs-1:0] all_periph_obi_rsp;

  // Error bus
  rel_sbr_obi_req_t error_obi_req;
  rel_sbr_obi_rsp_t error_obi_rsp;

  // Debug mem bus
  sbr_obi_req_t dbg_mem_obi_req;
  sbr_obi_rsp_t dbg_mem_obi_rsp;
  
  rel_sbr_obi_req_t rel_dbg_mem_obi_req;
  rel_sbr_obi_rsp_t rel_dbg_mem_obi_rsp;

  // SoC control bus
  sbr_obi_req_t soc_ctrl_obi_req;
  sbr_obi_rsp_t soc_ctrl_obi_rsp;
  
  rel_sbr_obi_req_t rel_soc_ctrl_obi_req;
  rel_sbr_obi_rsp_t rel_soc_ctrl_obi_rsp;

  // UART periph bus
  sbr_obi_req_t uart_obi_req;
  sbr_obi_rsp_t uart_obi_rsp;
  
  rel_sbr_obi_req_t rel_uart_obi_req;
  rel_sbr_obi_rsp_t rel_uart_obi_rsp;

  // GPIO periph bus
  sbr_obi_req_t gpio_obi_req;
  sbr_obi_rsp_t gpio_obi_rsp;
  
  rel_sbr_obi_req_t rel_gpio_obi_req;
  rel_sbr_obi_rsp_t rel_gpio_obi_rsp;

  // Timer periph bus
  sbr_obi_req_t timer_obi_req;
  sbr_obi_rsp_t timer_obi_rsp;
  
  rel_sbr_obi_req_t rel_timer_obi_req;
  rel_sbr_obi_rsp_t rel_timer_obi_rsp;
  
  // FORTALESA periph bus
  sbr_obi_req_t acc_obi_req;
  sbr_obi_rsp_t acc_obi_rsp;
  
  rel_sbr_obi_req_t rel_acc_obi_req;
  rel_sbr_obi_rsp_t rel_acc_obi_rsp;
  
  // SPI periph bus
  sbr_obi_req_t spi_obi_req;
  sbr_obi_rsp_t spi_obi_rsp;

  rel_sbr_obi_req_t rel_spi_obi_req;
  rel_sbr_obi_rsp_t rel_spi_obi_rsp;
  
  // Fanout to individual peripherals
  assign error_obi_req                     = all_periph_obi_req[PeriphError];
  assign all_periph_obi_rsp[PeriphError]   = error_obi_rsp;
  assign rel_dbg_mem_obi_req               = all_periph_obi_req[PeriphDebug];
  assign all_periph_obi_rsp[PeriphDebug]   = rel_dbg_mem_obi_rsp;
  assign rel_soc_ctrl_obi_req              = all_periph_obi_req[PeriphSocCtrl];
  assign all_periph_obi_rsp[PeriphSocCtrl] = rel_soc_ctrl_obi_rsp;
  assign rel_uart_obi_req                  = all_periph_obi_req[PeriphUart];
  assign all_periph_obi_rsp[PeriphUart]    = rel_uart_obi_rsp;
  assign rel_gpio_obi_req                  = all_periph_obi_req[PeriphGpio];
  assign all_periph_obi_rsp[PeriphGpio]    = rel_gpio_obi_rsp;
  assign rel_timer_obi_req                 = all_periph_obi_req[PeriphTimer];
  assign all_periph_obi_rsp[PeriphTimer]   = rel_timer_obi_rsp;
  assign rel_spi_obi_req                   = all_periph_obi_req[PeriphSPI];
  assign all_periph_obi_rsp[PeriphSPI]     = rel_spi_obi_rsp;
  assign rel_acc_obi_req                   = all_periph_obi_req[PeriphAcc];
  assign all_periph_obi_rsp[PeriphAcc]     = rel_acc_obi_rsp;


  // -----------------
  // Core
  // -----------------
  core_wrap #(
  ) i_core_wrap (
    .clk_i,
    .rst_ni,
    .ref_clk_i,
    .test_enable_i    ( testmode_i  ),

    .irqs_i           ( interrupts  ),
    .timer0_irq_i     ( timer0_irq0 ),

    .boot_addr_i      ( boot_addr   ),

    .instr_req_o      ( core_instr_obi_req.req     ),
    .instr_gnt_i      ( core_instr_obi_rsp.gnt     ),
    .instr_rvalid_i   ( core_instr_obi_rsp.rvalid  ),
    .instr_addr_o     ( core_instr_obi_req.a.addr  ),
    .instr_rdata_i    ( core_instr_obi_rsp.r.rdata ),
    .instr_err_i      ( core_instr_obi_rsp.r.err   ),

    .data_req_o       ( core_data_obi_req.req      ),
    .data_gnt_i       ( core_data_obi_rsp.gnt      ),
    .data_rvalid_i    ( core_data_obi_rsp.rvalid   ),
    .data_we_o        ( core_data_obi_req.a.we     ),
    .data_be_o        ( core_data_obi_req.a.be     ),
    .data_addr_o      ( core_data_obi_req.a.addr   ),
    .data_wdata_o     ( core_data_obi_req.a.wdata  ),
    .data_rdata_i     ( core_data_obi_rsp.r.rdata  ),
    .data_err_i       ( core_data_obi_rsp.r.err    ),

    .debug_req_i      ( debug_req    ),
    .fetch_enable_i   ( fetch_enable ),

    .core_busy_o      ( core_busy_o ),
	.lockstep_error_o ( lockstep_error_o )
  );
  
  relobi_encoder #(
    .Cfg            (MgrObiCfg),
    .relobi_req_t   (rel_mgr_obi_req_t),
    .relobi_rsp_t   (rel_mgr_obi_rsp_t),
    .obi_req_t      (mgr_obi_req_t),
    .obi_rsp_t      (mgr_obi_rsp_t)
  ) i_core_data_relobi_encoder (
    .req_i          (core_data_obi_req),
    .rsp_o          (core_data_obi_rsp),
    .rel_req_o      (rel_core_data_obi_req),
    .rel_rsp_i      (rel_core_data_obi_rsp),
    .fault_o        ( )
  );
  
  relobi_encoder #(
    .Cfg            (MgrObiCfg),
    .relobi_req_t   (rel_mgr_obi_req_t),
    .relobi_rsp_t   (rel_mgr_obi_rsp_t),
    .obi_req_t      (mgr_obi_req_t),
    .obi_rsp_t      (mgr_obi_rsp_t)
  ) i_core_instr_relobi_encoder (
    .req_i          (core_instr_obi_req),
    .rsp_o          (core_instr_obi_rsp),
    .rel_req_o      (rel_core_instr_obi_req),
    .rel_rsp_i      (rel_core_instr_obi_rsp),
    .fault_o        ( )
  );

  // -----------------
  // Debug Module
  // -----------------

  localparam dm::hartinfo_t HARTINFO = '{
    zero1: '0,
    nscratch: 2,
    zero0: '0,
    dataaccess: 1'b1,
    datasize: dm::DataCount,
    dataaddr: dm::DataAddr
  };
  dm::hartinfo_t hartinfo = HARTINFO;

  logic dmi_rst_n, dmi_req_valid, dmi_req_ready, dmi_resp_valid, dmi_resp_ready;
  dm::dmi_req_t dmi_req;
  dm::dmi_resp_t dmi_resp;

  dmi_jtag #(
    .IdcodeValue ( PulpJtagIdCode )
  ) i_dmi_jtag (
    .clk_i,
    .rst_ni,
    .testmode_i,

    .dmi_rst_no       ( dmi_rst_n      ),
    .dmi_req_o        ( dmi_req        ),
    .dmi_req_valid_o  ( dmi_req_valid  ),
    .dmi_req_ready_i  ( dmi_req_ready  ),

    .dmi_resp_i       ( dmi_resp       ),
    .dmi_resp_ready_o ( dmi_resp_ready ),
    .dmi_resp_valid_i ( dmi_resp_valid ),

    .tck_i            ( jtag_tck_i     ),
    .tms_i            ( jtag_tms_i     ),
    .trst_ni          ( jtag_trst_ni   ),
    .td_i             ( jtag_tdi_i     ),
    .td_o             ( jtag_tdo_o     ),
    .tdo_oe_o         ()
  );

  dm_obi_top #(
    .BusWidth   ( SbrObiCfg.DataWidth ),
    .IdWidth    ( SbrObiCfg.IdWidth   )
  ) i_dm_top (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .ndmreset_o           (),
    .dmactive_o           (),
    .debug_req_o          ( debug_req  ),
    .unavailable_i        ( 1'b0       ),
    .hartinfo_i           ( hartinfo   ),

    .slave_req_i          ( dbg_mem_obi_req.req     ),
    .slave_we_i           ( dbg_mem_obi_req.a.we    ),
    .slave_addr_i         ( dbg_mem_obi_req.a.addr  ),
    .slave_be_i           ( dbg_mem_obi_req.a.be    ),
    .slave_wdata_i        ( dbg_mem_obi_req.a.wdata ),
    .slave_aid_i          ( dbg_mem_obi_req.a.aid   ),
    .slave_gnt_o          ( dbg_mem_obi_rsp.gnt     ),
    .slave_rvalid_o       ( dbg_mem_obi_rsp.rvalid  ),
    .slave_rdata_o        ( dbg_mem_obi_rsp.r.rdata ),
    .slave_rid_o          ( dbg_mem_obi_rsp.r.rid   ),

    .master_req_o         ( dbg_req_obi_req.req     ),
    .master_addr_o        ( dbg_req_obi_req.a.addr  ),
    .master_we_o          ( dbg_req_obi_req.a.we    ),
    .master_wdata_o       ( dbg_req_obi_req.a.wdata ),
    .master_be_o          ( dbg_req_obi_req.a.be    ),
    .master_gnt_i         ( dbg_req_obi_rsp.gnt     ),
    .master_rvalid_i      ( dbg_req_obi_rsp.rvalid  ),
    .master_rdata_i       ( dbg_req_obi_rsp.r.rdata ),
    .master_err_i         ( dbg_req_obi_rsp.r.err   ),
    .master_other_err_i   ( 1'b0                    ),

    .dmi_rst_ni           ( dmi_rst_n      ),
    .dmi_req_valid_i      ( dmi_req_valid  ),
    .dmi_req_ready_o      ( dmi_req_ready  ),
    .dmi_req_i            ( dmi_req        ),

    .dmi_resp_valid_o     ( dmi_resp_valid ),
    .dmi_resp_ready_i     ( dmi_resp_ready ),
    .dmi_resp_o           ( dmi_resp       )
  );
  // Unused
  assign dbg_mem_obi_rsp.r.r_optional = 1'b0;
  assign dbg_mem_obi_rsp.r.err        = 1'b0;
  
  relobi_encoder #(
    .Cfg            (MgrObiCfg),
    .relobi_req_t   (rel_mgr_obi_req_t),
    .relobi_rsp_t   (rel_mgr_obi_rsp_t),
    .obi_req_t      (mgr_obi_req_t),
    .obi_rsp_t      (mgr_obi_rsp_t)
  ) i_dbg_req_relobi_encoder (
    .req_i          (dbg_req_obi_req),
    .rsp_o          (dbg_req_obi_rsp),
    .rel_req_o      (rel_dbg_req_obi_req),
    .rel_rsp_i      (rel_dbg_req_obi_rsp),
    .fault_o        ( )
  );
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_dbg_mem_relobi_decoder (
    .rel_req_i      (rel_dbg_mem_obi_req),
    .rel_rsp_o      (rel_dbg_mem_obi_rsp),
    .req_o          (dbg_mem_obi_req),
    .rsp_i          (dbg_mem_obi_rsp),
    .fault_o        ( )
  );

  // -----------------
  // Main Interconnect
  // -----------------

  relobi_xbar #(
    .SbrPortObiCfg      ( MgrObiCfg        ),
    .MgrPortObiCfg      ( SbrObiCfg        ),
    .sbr_port_obi_req_t ( rel_mgr_obi_req_t    ),
    .sbr_port_a_chan_t  ( rel_mgr_obi_a_chan_t ),
    .sbr_port_obi_rsp_t ( rel_mgr_obi_rsp_t    ),
    .sbr_port_r_chan_t  ( rel_mgr_obi_r_chan_t ),
    .mgr_port_obi_req_t ( rel_sbr_obi_req_t    ),
    .mgr_port_obi_rsp_t ( rel_sbr_obi_rsp_t    ),
    .mgr_port_a_chan_t  ( rel_sbr_obi_a_chan_t ),
    .mgr_port_r_chan_t  ( rel_sbr_obi_r_chan_t ),
    .NumSbrPorts        ( NumXbarManagers  ),
    .NumMgrPorts        ( NumXbarSbr       ),
    .NumMaxTrans        ( 2                ),
    .NumAddrRules       ( NumXbarSbrRules  ),
    .addr_map_rule_t    ( addr_map_rule_t  ),
    .UseIdForRouting    ( 1'b0             ),
    .Connectivity       ( '1               ),
    .TmrMap             ( 1'b1             )
  ) i_main_xbar (
    .clk_i,
    .rst_ni,
    .testmode_i,

    .sbr_ports_req_i  ( {rel_core_instr_obi_req, rel_core_data_obi_req, rel_dbg_req_obi_req, rel_dma_receive_obi_req, rel_dma_transmit_obi_req } ), // from managers towards subordinates
    .sbr_ports_rsp_o  ( {rel_core_instr_obi_rsp, rel_core_data_obi_rsp, rel_dbg_req_obi_rsp, rel_dma_receive_obi_rsp, rel_dma_transmit_obi_rsp } ),
    .mgr_ports_req_o  ( all_sbr_obi_req ), // connections to subordinates
    .mgr_ports_rsp_i  ( all_sbr_obi_rsp ),

    .addr_map_i       ( {3{croc_addr_map}} ),
    .en_default_idx_i ( {3{5'b1111}}       ),
    .default_idx_i    ( '0                 ),
    
    .fault_o          ( obi_xbar_faults )
  );
  
  // -----------------
  // DMA
  // -----------------
  mgr_obi_req_t dma_receive_obi_req;
  mgr_obi_rsp_t dma_receive_obi_rsp;

  mgr_obi_req_t dma_transmit_obi_req;
  mgr_obi_rsp_t dma_transmit_obi_rsp;

  sbr_obi_req_t dma_subordinate_obi_req;
  sbr_obi_rsp_t dma_subordinate_obi_rsp;

  relobi_encoder #(
    .Cfg            (MgrObiCfg),
    .relobi_req_t   (rel_mgr_obi_req_t),
    .relobi_rsp_t   (rel_mgr_obi_rsp_t),
    .obi_req_t      (mgr_obi_req_t),
    .obi_rsp_t      (mgr_obi_rsp_t)
  ) i_dma_receive_relobi_encoder (
    .req_i          (dma_receive_obi_req),
    .rsp_o          (dma_receive_obi_rsp),
    .rel_req_o      (rel_dma_receive_obi_req),
    .rel_rsp_i      (rel_dma_receive_obi_rsp),
    .fault_o        ( )
  );

  relobi_encoder #(
    .Cfg            (MgrObiCfg),
    .relobi_req_t   (rel_mgr_obi_req_t),
    .relobi_rsp_t   (rel_mgr_obi_rsp_t),
    .obi_req_t      (mgr_obi_req_t),
    .obi_rsp_t      (mgr_obi_rsp_t)
  ) i_dma_transmit_relobi_encoder (
    .req_i          (dma_transmit_obi_req),
    .rsp_o          (dma_transmit_obi_rsp),
    .rel_req_o      (rel_dma_transmit_obi_req),
    .rel_rsp_i      (rel_dma_transmit_obi_rsp),
    .fault_o        ( )
  );

  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_mem_bank_relobi_decoder (
    .rel_req_i      (rel_dma_subordinate_obi_req),
    .rel_rsp_o      (rel_dma_subordinate_obi_rsp),
    .req_o          (dma_subordinate_obi_req),
    .rsp_i          (dma_subordinate_obi_rsp),
    .fault_o        ( )
  );

  dma #(
    .SbrObiCfg       ( SbrObiCfg     ),
    .MgrObiCfg       ( MgrObiCfg     ),
    .sbr_obi_req_t   ( sbr_obi_req_t ),
    .sbr_obi_rsp_t   ( sbr_obi_rsp_t ),
    .mgr_obi_req_t   ( mgr_obi_req_t ),
    .mgr_obi_rsp_t   ( mgr_obi_rsp_t )
  ) i_dma (
    .clk_i,
    .rst_ni,

    .dma_receive_obi_req_o(dma_receive_obi_req),
    .dma_receive_obi_rsp_i(dma_receive_obi_rsp),
    
    .dma_transmit_obi_req_o(dma_transmit_obi_req),
    .dma_transmit_obi_rsp_i(dma_transmit_obi_rsp),

    .dma_subordinate_obi_req_i(dma_subordinate_obi_req),
    .dma_subordinate_obi_rsp_o(dma_subordinate_obi_rsp),

    .dma_irq_o(dma_irq)
  );

  // -----------------
  // Memories
  // -----------------

  logic [NumSramBanks-1:0] mbist_active;
  logic [NumSramBanks-1:0] mbist_matches;
  logic [NumSramBanks-1:0] mbist_done;

  assign mbist_active_o = |mbist_active;
  assign mbist_all_done_o = &mbist_done;
  assign mbist_any_done_o = |mbist_done;
  assign mbist_matches_o = mbist_matches;
  
  // During MBIST, the result is displayed using GPIO
  always_comb begin : mbist_gpio_overwrite
    for (int i = 0; i < GpioCount; i++) begin
      if (i < NumSramBanks) begin
        gpio_o[i]        = mbist_watch_i ? mbist_matches[i] : gpio_o_internal[i];
        gpio_out_en_o[i] = mbist_watch_i ? 1'b1 : gpio_out_en_o_internal[i];
      end else begin
        gpio_o[i]        = gpio_o_internal[i];
        gpio_out_en_o[i] = gpio_out_en_o_internal[i];
      end        
    end
  end
  
  logic [NumBitsBistPattern-1:0] mbist_pattern;

  for (genvar i = 0; i < NumCoreSramBanks; i++) begin : gen_sram_bank
    logic bank_req, bank_we, bank_gnt, bank_single_err;
    logic [SbrObiCfg.AddrWidth-1:0] bank_byte_addr;
    logic [SramBankAddrWidth-1:0] bank_word_addr;
    logic [SbrObiCfg.DataWidth-1:0] bank_wdata, bank_rdata;
    logic [SbrObiCfg.DataWidth/8-1:0] bank_be;

    logic obi_bank_req, mbist_bank_req, mbist_re;
    logic obi_bank_we, mbist_bank_we;
    logic [SramBankAddrWidth-1:0] obi_bank_word_addr, mbist_bank_word_addr;
    logic [SbrObiCfg.DataWidth-1:0] obi_bank_wdata, mbist_bank_wdata;
    logic [SbrObiCfg.DataWidth/8-1:0] obi_bank_be, mbist_bank_be;
	
	logic bank_ecc_enable;

    assign bank_req       = mbist_active[i] ? mbist_bank_req       : obi_bank_req      ;
    assign bank_we        = mbist_active[i] ? mbist_bank_we        : obi_bank_we       ;
    assign bank_word_addr = mbist_active[i] ? mbist_bank_word_addr : obi_bank_word_addr;
    assign bank_wdata     = mbist_active[i] ? mbist_bank_wdata     : obi_bank_wdata    ;
    assign bank_be        = mbist_active[i] ? mbist_bank_be        : obi_bank_be       ;

    assign obi_bank_word_addr = bank_byte_addr[SbrObiCfg.AddrWidth-1:2];
    assign mbist_bank_req = mbist_re | mbist_bank_we;
    assign mbist_bank_be = '1;
	
	assign bank_ecc_enable = mbist_active[i] ? 1'b0 : 1'b1;

    obi_sram_shim #(
      .ObiCfg    ( SbrObiCfg     ),
      .obi_req_t ( sbr_obi_req_t ),
      .obi_rsp_t ( sbr_obi_rsp_t )
    ) i_sram_shim (
      .clk_i,
      .rst_ni,

      .obi_req_i ( mem_bank_obi_req[i] ),
      .obi_rsp_o ( mem_bank_obi_rsp[i] ),

      .req_o   ( obi_bank_req       ),
      .we_o    ( obi_bank_we        ),
      .addr_o  ( bank_byte_addr ),
      .wdata_o ( obi_bank_wdata     ),
      .be_o    ( obi_bank_be        ),

      .gnt_i   ( bank_gnt   ),
      .rdata_i ( bank_rdata )
    );
    
    relobi_decoder #(
      .Cfg            (SbrObiCfg),
      .relobi_req_t   (rel_sbr_obi_req_t),
      .relobi_rsp_t   (rel_sbr_obi_rsp_t),
      .obi_req_t      (sbr_obi_req_t),
      .obi_rsp_t      (sbr_obi_rsp_t)
	) i_mem_bank_relobi_decoder (
	  .rel_req_i      (xbar_mem_bank_obi_req[i]),
	  .rel_rsp_o      (xbar_mem_bank_obi_rsp[i]),
	  .req_o          (mem_bank_obi_req[i]),
	  .rsp_i          (mem_bank_obi_rsp[i]),
	  .fault_o        ( )
	);

    // assign bank_gnt = 1'b1;
	ecc_sram #(
	  .NumWords         ( SramBankNumWords ),
	  .UnprotectedWidth ( 32 ),
	  .ProtectedWidth   ( 39 ),
	  .ByteWidth        ( 8 ),
	  .InputECC         ( 0 ),
	  .NumRMWCuts       ( 0 ),
	  .SimInit          ( "zeros" )
	) i_sram (
	  .clk_i,
	  .rst_ni,
	  
	  .impl_i  ( sram_impl      ),
      .impl_o  ( ), // not connected

	  .scrub_trigger_i 		 ( 1'b0 ), // Set to 1'b0 to disable scrubber
	  .scrubber_fix_o		 ( ),
	  .scrub_uncorrectable_o ( ),
	  
	  .ecc_enable_i ( bank_ecc_enable ),

	  .req_i   ( bank_req       ),
      .we_i    ( bank_we        ),
      .addr_i  ( bank_word_addr ),

      .wdata_i ( bank_wdata ),
      .be_i    ( bank_be    ),
      .rdata_o ( bank_rdata ),
	  .gnt_o   ( bank_gnt   ),

	  .single_error_o ( sram_faults[i][0] ),
	  .multi_error_o  ( sram_faults[i][1] )
	);

	// MBIST module
    memory_initializer #(
      .MEM_DATA_BW ( SbrObiCfg.DataWidth ),
      .MEM_ADDR_BW ( SramBankAddrWidth   ),
      .PATTERN_BW  ( NumBitsBistPattern  ),
      .CMD_SPD_BW  ( 1 )
    ) i_memory_initializer (
      .clk_i,
      .rst_ni,
      .start_init_i	( mbist_start_i ),
      .pattern_i	( mbist_pattern ),
      .cmd_speed_i	( '1 ),
      .data_i		( bank_rdata ),
      .active_o		( mbist_active[i] ),
      .wen_o		( mbist_bank_we ),
      .ren_o		( mbist_re ),
      .addr_o		( mbist_bank_word_addr ),
      .data_o		( mbist_bank_wdata ),
      .match_o		( mbist_matches[i] ),
      .done_o		( mbist_done[i] )
    );

  end
  
  // Dual-port SRAM blocks for accelerator
  for (genvar i = 0; i < NumAccSramBanks; i++) begin : acc_sram_bank
    logic [1:0] bank_req, bank_we;
    logic bank_gnt, bank_single_err;
    logic [SbrObiCfg.AddrWidth-1:0] bank_byte_addr;
    logic [1:0][SramBankAddrWidth-1:0] bank_word_addr;
    logic [1:0][SbrObiCfg.DataWidth-1:0] bank_wdata, bank_rdata;
    logic [1:0][SbrObiCfg.DataWidth/8-1:0] bank_be;

    logic obi_bank_req, mbist_bank_req, mbist_re;
    logic obi_bank_we, mbist_bank_we;
    logic [SramBankAddrWidth-1:0] obi_bank_word_addr, mbist_bank_word_addr;
    logic [SbrObiCfg.DataWidth-1:0] obi_bank_wdata, mbist_bank_wdata;
    logic [SbrObiCfg.DataWidth/8-1:0] obi_bank_be, mbist_bank_be;
	
	logic bank_ecc_enable;

    assign bank_req[0]       = mbist_active[i+NumCoreSramBanks] ? mbist_bank_req       : obi_bank_req;
    assign bank_we[0]        = mbist_active[i+NumCoreSramBanks] ? mbist_bank_we        : obi_bank_we;
    assign bank_word_addr[0] = mbist_active[i+NumCoreSramBanks] ? mbist_bank_word_addr : obi_bank_word_addr;
    assign bank_wdata[0]     = mbist_active[i+NumCoreSramBanks] ? mbist_bank_wdata     : obi_bank_wdata;
    assign bank_be[0]        = mbist_active[i+NumCoreSramBanks] ? mbist_bank_be        : obi_bank_be;

    assign obi_bank_word_addr = bank_byte_addr[SbrObiCfg.AddrWidth-1:2];
    assign mbist_bank_req = mbist_re | mbist_bank_we;
    assign mbist_bank_be = '1;

    // The second port is connected to the accelerator interface
    assign bank_req[1]       = mbist_active[i+NumCoreSramBanks] ? '0 : acc_mem_req[i];
    assign bank_we[1]        = mbist_active[i+NumCoreSramBanks] ? '0 : acc_mem_we[i];
    assign bank_word_addr[1] = mbist_active[i+NumCoreSramBanks] ? '0 : acc_mem_word_addr[i];
    assign bank_wdata[1]     = mbist_active[i+NumCoreSramBanks] ? '0 : acc_mem_wdata[i];
    assign bank_be[1]        = mbist_active[i+NumCoreSramBanks] ? '0 : acc_mem_be[i];
    assign acc_mem_rdata[i]  = bank_rdata[1];
	
	assign bank_ecc_enable = mbist_active[i+NumCoreSramBanks] ? 1'b0 : 1'b1;

    obi_sram_shim #(
      .ObiCfg    ( SbrObiCfg     ),
      .obi_req_t ( sbr_obi_req_t ),
      .obi_rsp_t ( sbr_obi_rsp_t )
    ) i_sram_shim (
      .clk_i,
      .rst_ni,

      .obi_req_i ( mem_bank_obi_req[i+NumCoreSramBanks] ),
      .obi_rsp_o ( mem_bank_obi_rsp[i+NumCoreSramBanks] ),

      .req_o   ( obi_bank_req    ),
      .we_o    ( obi_bank_we     ),
      .addr_o  ( bank_byte_addr  ),
      .wdata_o ( obi_bank_wdata  ),
      .be_o    ( obi_bank_be     ),

      .gnt_i   ( bank_gnt      ),
      .rdata_i ( bank_rdata[0] )
    );
    
    relobi_decoder #(
      .Cfg            (SbrObiCfg),
      .relobi_req_t   (rel_sbr_obi_req_t),
      .relobi_rsp_t   (rel_sbr_obi_rsp_t),
      .obi_req_t      (sbr_obi_req_t),
      .obi_rsp_t      (sbr_obi_rsp_t)
    ) i_mem_bank_relobi_decoder (
      .rel_req_i      (xbar_mem_bank_obi_req[i+NumCoreSramBanks]),
      .rel_rsp_o      (xbar_mem_bank_obi_rsp[i+NumCoreSramBanks]),
      .req_o          (mem_bank_obi_req[i+NumCoreSramBanks]),
      .rsp_i          (mem_bank_obi_rsp[i+NumCoreSramBanks]),
      .fault_o        ( )
    );
	
	ecc_sram_dual_port #(
	  .NumWords         ( SramBankNumWords ),
	  .UnprotectedWidth ( 32 ),
	  .ProtectedWidth   ( 39 ),
	  .ByteWidth        ( 8 ),
	  .NumPorts  		( 2 ),
	  .InputECC         ( 0 ),
	  .NumRMWCuts       ( 0 ),
	  .SimInit          ( "zeros" )
	) i_sram (
	  .clk_i,
	  .rst_ni,
	  
	  .impl_i  ( sram_impl      ),
      .impl_o  ( ), // not connected

	  .scrub_trigger_i 		 ( 1'b0 ), // Set to 1'b0 to disable scrubber
	  .scrubber_fix_o		 ( ),
	  .scrub_uncorrectable_o ( ),
	  
	  .ecc_enable_i ( bank_ecc_enable ),

	  .req_i   ( bank_req       ),
      .we_i    ( bank_we        ),
      .addr_i  ( bank_word_addr ),

      .wdata_i ( bank_wdata ),
      .be_i    ( bank_be    ),
      .rdata_o ( bank_rdata ),
	  .gnt_o   ( bank_gnt   ),

	  .single_error_o ( sram_faults[i+NumCoreSramBanks][0]),
	  .multi_error_o  ( sram_faults[i+NumCoreSramBanks][1])
	);

	// MBIST module
    memory_initializer #(
      .MEM_DATA_BW ( SbrObiCfg.DataWidth ),
      .MEM_ADDR_BW ( SramBankAddrWidth   ),
      .PATTERN_BW  ( NumBitsBistPattern  ),
      .CMD_SPD_BW  ( 1 )
    ) i_memory_initializer (
      .clk_i		( clk_i ),
      .rst_ni		( rst_ni ),
      .start_init_i ( mbist_start_i ),
      .pattern_i	( mbist_pattern ),
      .cmd_speed_i	( '1 ), // fixed to max speed
      .data_i		( bank_rdata[0] ),
      .active_o		( mbist_active[i+NumCoreSramBanks] ),
      .wen_o		( mbist_bank_we ),
      .ren_o		( mbist_re ),
      .addr_o		( mbist_bank_word_addr ),
      .data_o		( mbist_bank_wdata ),
      .match_o		( mbist_matches[i+NumCoreSramBanks] ),
      .done_o		( mbist_done[i+NumCoreSramBanks] )
    );

  end


  // Xbar space error subordinate
  relobi_err_sbr #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( rel_sbr_obi_req_t ),
    .obi_rsp_t   ( rel_sbr_obi_rsp_t ),
    .NumMaxTrans ( 1             ),
    .RspData     ( 32'hBADCAB1E  )
  ) i_xbar_err (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .obi_req_i  ( xbar_error_obi_req ),
    .obi_rsp_o  ( xbar_error_obi_rsp ),
    .fault_o    ( )
  );


  // -----------------
  // Peripherals
  // -----------------

  // Demultiplex to peripherals according to address map
  relobi_periph_demux #(
	.ObiCfg				( SbrObiCfg ),
	.obi_req_t			( rel_sbr_obi_req_t ),
	.obi_rsp_t			( rel_sbr_obi_rsp_t ),
	.obi_r_chan_t		( rel_sbr_obi_r_chan_t ),
	.NumMgrPorts		( NumPeriphs ),
	.NumMaxTrans		( 2 ),
	.NumAddrRules		( NumPeriphRules ),
	.addr_map_rule_t	( addr_map_rule_t ),
	.TmrMap             ( 1'b1 )
  ) i_periph_demux (
	.clk_i,
	.rst_ni,
	.sbr_port_req_i	    ( xbar_periph_obi_req  ),
	.sbr_port_rsp_o	    ( xbar_periph_obi_rsp  ),
	.mgr_ports_req_o	( all_periph_obi_req   ),
	.mgr_ports_rsp_i	( all_periph_obi_rsp   ),
	.addr_map_i			( {3{periph_addr_map}} ),
	.en_default_idx_i	( {3{1'b1}}			   ),
	.default_idx_i		( '0				   ),
	.fault_o			( obi_periph_faults )
  );

  // Peripheral space error subordinate
  relobi_err_sbr #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( rel_sbr_obi_req_t ),
    .obi_rsp_t   ( rel_sbr_obi_rsp_t ),
    .NumMaxTrans ( 1             ),
    .RspData     ( 32'hBADCAB1E  )
  ) i_periph_err (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .obi_req_i  ( error_obi_req ),
    .obi_rsp_o  ( error_obi_rsp ),
    .fault_o    ( )
  );

  // SoC Control
  reg_req_t soc_ctrl_reg_req;
  reg_rsp_t soc_ctrl_reg_rsp;

  periph_to_reg #(
    .AW    ( SbrObiCfg.AddrWidth  ),
    .DW    ( SbrObiCfg.DataWidth  ),
    .BW    ( 8                    ),
    .IW    ( SbrObiCfg.IdWidth    ),
    .req_t ( reg_req_t            ),
    .rsp_t ( reg_rsp_t            )
  ) i_soc_ctrl_translate (
    .clk_i,
    .rst_ni,

    .req_i     ( soc_ctrl_obi_req.req     ),
    .add_i     ( soc_ctrl_obi_req.a.addr  ),
    .wen_i     ( ~soc_ctrl_obi_req.a.we   ),
    .wdata_i   ( soc_ctrl_obi_req.a.wdata ),
    .be_i      ( soc_ctrl_obi_req.a.be    ),
    .id_i      ( soc_ctrl_obi_req.a.aid   ),

    .gnt_o     ( soc_ctrl_obi_rsp.gnt     ),
    .r_rdata_o ( soc_ctrl_obi_rsp.r.rdata ),
    .r_opc_o   ( soc_ctrl_obi_rsp.r.err   ),
    .r_id_o    ( soc_ctrl_obi_rsp.r.rid   ),
    .r_valid_o ( soc_ctrl_obi_rsp.rvalid  ),

    .reg_req_o ( soc_ctrl_reg_req ),
    .reg_rsp_i ( soc_ctrl_reg_rsp )
  );  
  assign soc_ctrl_obi_rsp.r.r_optional = '0;
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_soc_ctrl_relobi_decoder (
    .rel_req_i      (rel_soc_ctrl_obi_req),
    .rel_rsp_o      (rel_soc_ctrl_obi_rsp),
    .req_o          (soc_ctrl_obi_req),
    .rsp_i          (soc_ctrl_obi_rsp),
    .fault_o        ( )
  );

  soc_ctrl_reg_pkg::soc_ctrl_reg2hw_t soc_ctrl_reg2hw;
  soc_ctrl_reg_pkg::soc_ctrl_hw2reg_t soc_ctrl_hw2reg;
  assign fetch_enable    = soc_ctrl_reg2hw.fetchen.q | fetch_en_i;
  assign boot_addr       = soc_ctrl_reg2hw.bootaddr.q;
  assign sram_impl       = soc_ctrl_reg2hw.sram_dly;
  assign mbist_pattern   = soc_ctrl_reg2hw.bist_pattern.q;
  assign soc_ctrl_hw2reg = '0;

  soc_ctrl_reg_top #(
    .reg_req_t       	( reg_req_t    ),
    .reg_rsp_t       	( reg_rsp_t    ),
    .BootAddrDefault 	( SramBaseAddr ),
	.BistPatternDefault ( DefaultBistPattern )
  ) i_soc_ctrl (
    .clk_i,
    .rst_ni,
    .reg_req_i ( soc_ctrl_reg_req ),
    .reg_rsp_o ( soc_ctrl_reg_rsp ),
    .reg2hw    ( soc_ctrl_reg2hw  ),
    .hw2reg    ( soc_ctrl_hw2reg  ),
    .devmode_i ( 1'b0             )
  );

  // UART
  reg_req_t uart_reg_req;
  reg_rsp_t uart_reg_rsp;

  periph_to_reg #(
    .AW    ( SbrObiCfg.AddrWidth  ),
    .DW    ( SbrObiCfg.DataWidth  ),
    .BW    ( 8                    ),
    .IW    ( SbrObiCfg.IdWidth    ),
    .req_t ( reg_req_t            ),
    .rsp_t ( reg_rsp_t            )
  ) i_uart_translate (
    .clk_i,
    .rst_ni,

    .req_i     ( uart_obi_req.req     ),
    .add_i     ( uart_obi_req.a.addr  ),
    .wen_i     ( ~uart_obi_req.a.we   ),
    .wdata_i   ( uart_obi_req.a.wdata ),
    .be_i      ( uart_obi_req.a.be    ),
    .id_i      ( uart_obi_req.a.aid   ),

    .gnt_o     ( uart_obi_rsp.gnt     ),
    .r_rdata_o ( uart_obi_rsp.r.rdata ),
    .r_opc_o   ( uart_obi_rsp.r.err   ),
    .r_id_o    ( uart_obi_rsp.r.rid   ),
    .r_valid_o ( uart_obi_rsp.rvalid  ),

    .reg_req_o ( uart_reg_req ),
    .reg_rsp_i ( uart_reg_rsp )
  );
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_uart_relobi_decoder (
    .rel_req_i      (rel_uart_obi_req),
    .rel_rsp_o      (rel_uart_obi_rsp),
    .req_o          (uart_obi_req),
    .rsp_i          (uart_obi_rsp),
    .fault_o        ( )
  );

  reg_uart_wrap #(
    .AddrWidth  ( 32        ),
    .reg_req_t  ( reg_req_t ),
    .reg_rsp_t  ( reg_rsp_t )
  ) i_uart (
    .clk_i,
    .rst_ni,
    .reg_req_i  ( uart_reg_req  ),
    .reg_rsp_o  ( uart_reg_rsp  ),
    .intr_o     ( uart_irq      ),
    .out2_no    ( ),
    .out1_no    ( ),
    .rts_no     ( ),
    .dtr_no     ( ),
    .cts_ni     ( 1'b0 ),
    .dsr_ni     ( 1'b0 ),
    .dcd_ni     ( 1'b0 ),
    .rin_ni     ( 1'b0 ),
    .sin_i      ( uart_rx_i ),
    .sout_o     ( uart_tx_o )
  );
  assign uart_obi_rsp.r.r_optional = '0;

  // GPIO
  gpio #(
    .ObiCfg    ( SbrObiCfg     ),
    .obi_req_t ( sbr_obi_req_t ),
    .obi_rsp_t ( sbr_obi_rsp_t ),
    .GpioCount ( GpioCount     )
  ) i_gpio (
    .clk_i,
    .rst_ni,
    .gpio_i,              
    .gpio_o			( gpio_o_internal ),                   
    .gpio_out_en_o	( gpio_out_en_o_internal ),          
    .gpio_in_sync_o ( ),       
    .interrupt_o    ( gpio_irq     ),
    .obi_req_i      ( gpio_obi_req ),
    .obi_rsp_o      ( gpio_obi_rsp )
  );
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_gpio_relobi_decoder (
    .rel_req_i      (rel_gpio_obi_req),
    .rel_rsp_o      (rel_gpio_obi_rsp),
    .req_o          (gpio_obi_req),
    .rsp_i          (gpio_obi_rsp),
    .fault_o        ( )
  );

  // Timer
  timer_unit #(
    .ID_WIDTH   ( SbrObiCfg.IdWidth )
  ) i_timer (
    .clk_i,
    .rst_ni,
    .ref_clk_i,
    
    .req_i      ( timer_obi_req.req     ),
    .addr_i     ( timer_obi_req.a.addr  ),
    .wen_i      ( ~timer_obi_req.a.we   ),
    .wdata_i    ( timer_obi_req.a.wdata ),
    .be_i       ( timer_obi_req.a.be    ),
    .id_i       ( timer_obi_req.a.aid   ),
    .gnt_o      ( timer_obi_rsp.gnt     ),
    
    .r_valid_o  ( timer_obi_rsp.rvalid  ),
    .r_opc_o    ( ),
    .r_id_o     ( timer_obi_rsp.r.rid   ),
    .r_rdata_o  ( timer_obi_rsp.r.rdata ),
    .event_lo_i ('0 ),
    .event_hi_i ('0 ),
    .irq_lo_o   ( timer0_irq0           ),
    .irq_hi_o   ( timer0_irq1           ),
    .busy_o     (                       )
  );
  assign timer_obi_rsp.r.err        = 1'b0;
  assign timer_obi_rsp.r.r_optional = 1'b0;
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_timer_relobi_decoder (
    .rel_req_i      (rel_timer_obi_req),
    .rel_rsp_o      (rel_timer_obi_rsp),
    .req_o          (timer_obi_req),
    .rsp_i          (timer_obi_rsp),
    .fault_o        ( )
  );
  
  // FORTALESA
  reg_req_t acc_reg_req;
  reg_rsp_t acc_reg_rsp;

  periph_to_reg #(
    .AW    ( SbrObiCfg.AddrWidth  ),
    .DW    ( SbrObiCfg.DataWidth  ),
    .BW    ( 8                    ),
    .IW    ( SbrObiCfg.IdWidth    ),
    .req_t ( reg_req_t            ),
    .rsp_t ( reg_rsp_t            )
  ) i_acc_translate (
    .clk_i,
    .rst_ni,

    .req_i     ( acc_obi_req.req     ),
    .add_i     ( acc_obi_req.a.addr  ),
    .wen_i     ( ~acc_obi_req.a.we   ),
    .wdata_i   ( acc_obi_req.a.wdata ),
    .be_i      ( acc_obi_req.a.be    ),
    .id_i      ( acc_obi_req.a.aid   ),

    .gnt_o     ( acc_obi_rsp.gnt     ),
    .r_rdata_o ( acc_obi_rsp.r.rdata ),
    .r_opc_o   ( acc_obi_rsp.r.err   ),
    .r_id_o    ( acc_obi_rsp.r.rid   ),
    .r_valid_o ( acc_obi_rsp.rvalid  ),

    .reg_req_o ( acc_reg_req ),
    .reg_rsp_i ( acc_reg_rsp )
  );
  
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_acc_relobi_decoder (
    .rel_req_i      (rel_acc_obi_req),
    .rel_rsp_o      (rel_acc_obi_rsp),
    .req_o          (acc_obi_req),
    .rsp_i          (acc_obi_rsp),
    .fault_o        ( )
  );
  
  fortalesa_top #(
    .N              (SystArraySize),
    .BUFFER_SIZE    (SramBankNumWords),
    .IWIDTH         (SystArrayDataWidth),
    .OWIDTH         (SystArrayDataWidth),
    .AW             (SramBankAddrWidth),
    .reg_req_t      (reg_req_t),
    .reg_rsp_t      (reg_rsp_t)
  ) i_fortalesa (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .row_data_i     (acc_row_data),
    .col_data_i     (acc_col_data),
    .ibuffer_addr_o (acc_ibuffer_addr),
    .obuffer_addr_o (acc_obuffer_addr),
    .read_en_o      (acc_read_en),
    .done_o         (acc_done_irq),
    .valid_o        (acc_write_en),
    .data_o         (acc_data_out),
    .strb_o         (acc_strb),
    .reg_req_i      (acc_reg_req),
    .reg_rsp_o      (acc_reg_rsp)
  );
  
  acc_mem_intf #(
    .N              (SystArraySize),
    .AW             (SramBankAddrWidth),
    .BW             (SbrObiCfg.DataWidth/8),
    .SRAM_BANKS     (AccSramPerBuffer)
  ) i_acc_mem_intf (
    .ibuffer_addr_i (acc_ibuffer_addr),
    .obuffer_addr_i (acc_obuffer_addr),
    .read_en_i      (acc_read_en),
    .write_en_i     (acc_write_en),
    .strb_i         (acc_strb),
    .result_data_i  (acc_data_out),
    .row_data_o     (acc_row_data),
    .col_data_o     (acc_col_data),
    .mem_rdata_i    (acc_mem_rdata),
    .mem_wdata_o    (acc_mem_wdata),
    .mem_req_o      (acc_mem_req),
    .mem_we_o       (acc_mem_we),
    .mem_be_o       (acc_mem_be),
    .mem_word_addr_o (acc_mem_word_addr)
  );
  
  // SPI
  relobi_decoder #(
    .Cfg            (SbrObiCfg),
    .relobi_req_t   (rel_sbr_obi_req_t),
    .relobi_rsp_t   (rel_sbr_obi_rsp_t),
    .obi_req_t      (sbr_obi_req_t),
    .obi_rsp_t      (sbr_obi_rsp_t)
  ) i_spi_relobi_decoder (
    .rel_req_i      (rel_spi_obi_req),
    .rel_rsp_o      (rel_spi_obi_rsp),
    .req_o          (spi_obi_req),
    .rsp_i          (spi_obi_rsp),
    .fault_o        ( )
  );

  spi #(
    .ObiCfg     (SbrObiCfg),
    .obi_req_t  (sbr_obi_req_t),
    .obi_rsp_t  (sbr_obi_rsp_t)
  ) i_spi (
    .clk_i,
    .rst_ni,
    .obi_req_i  (spi_obi_req),
    .obi_rsp_o  (spi_obi_rsp),

    .sclk_o     (spi_sclk_o),
    .mosi_o     (spi_mosi_o),
    .miso_i     (spi_miso_i),
    .cs_n_o     (spi_cs_n_o)
  );
  
endmodule
