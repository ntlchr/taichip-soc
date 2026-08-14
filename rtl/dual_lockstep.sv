// Copyright (c) 2025 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
//--------------------------------------------------------------------------------
// Module    : dual_core_lockstep
// Project   : TAICHIP-1
//
// Description:
//   Implements a dual-core lockstep architecture for functional safety.
//   Two identical CVE2 cores (main and shadow) execute the same instruction
//   stream. The shadow core runs LockstepOffset cycles behind the main core,
//   receiving delayed inputs through a shift-register pipeline.
//
//   After LockstepOffset cycles post-reset, the shadow core is released from
//   reset and begins execution. Once both cores are aligned, their outputs
//   are compared every cycle. Any mismatch latches lockstep_error_o high
//   permanently (sticky), indicating a fault in one of the cores.
//
// Architecture:
//   - Main core    : Drives all real external outputs, runs on live inputs
//   - Shadow core  : Runs on inputs delayed by LockstepOffset cycles
//   - Input delay  : shift register of depth LockstepOffset (shadow_inputs_q)
//   - Output delay : shift register of depth LockstepOffset+1 (main_outputs_q)
//   - Shadow output: registered once (shadow_outputs_q) before comparison
//   - Comparator   : single struct equality check, gated by cmp_enable_q
//
// Timing:
//   - shadow_rst_ni  : released LockstepOffset cycles after rst_ni
//   - cmp_enable_q   : enabled 1 cycle after shadow_rst_ni (= LockstepOffset+1)
//   - Comparison     : main_outputs_q[0] vs shadow_outputs_q (both registered)
//
// Author    : Ashwin Santhosh (TalTech)
//--------------------------------------------------------------------------------


  module dual_core_lockstep import cve2_pkg::*; #(
    parameter int unsigned LockstepOffset = 3,

    parameter bit          PMPEnable         = 1'b0,
    parameter int unsigned PMPGranularity    = 0,
    parameter int unsigned PMPNumRegions     = 4,
    parameter int unsigned MHPMCounterNum    = 10,
    parameter int unsigned MHPMCounterWidth  = 40,
    parameter bit          RV32E             = 1'b0,
    parameter rv32m_e      RV32M             = RV32MFast,
    parameter rv32b_e      RV32B             = RV32BNone,
    parameter bit          DbgTriggerEn      = 1'b0,
    parameter int unsigned DbgHwBreakNum     = 1,
    parameter bit          XInterface        = 1'b0
  ) (
    // Clock and Reset
    input  logic        clk_i,
    input  logic        rst_ni,

    // Test / static configuration
    input  logic        test_en_i,
    input  logic [31:0] hart_id_i,
    input  logic [31:0] boot_addr_i,

    // Instruction memory interface
    input  logic        instr_gnt_i,
    input  logic        instr_rvalid_i,
    input  logic [31:0] instr_rdata_i,
    input  logic        instr_err_i,
    output logic        instr_req_o,
    output logic [31:0] instr_addr_o,

    // Data memory interface
    input  logic        data_gnt_i,
    input  logic        data_rvalid_i,
    input  logic [31:0] data_rdata_i,
    input  logic        data_err_i,
    output logic        data_req_o,
    output logic        data_we_o,
    output logic [3:0]  data_be_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,

    // Core-V Extension Interface
    output logic        x_issue_valid_o,
    input  logic        x_issue_ready_i,
    output x_issue_req_t x_issue_req_o,
    input  x_issue_resp_t x_issue_resp_i,

    output x_register_t x_register_o,

    output logic        x_commit_valid_o,
    output x_commit_t   x_commit_o,

    input  logic        x_result_valid_i,
    output logic        x_result_ready_o,
    input  x_result_t   x_result_i,

    // Interrupt inputs
    input  logic        irq_software_i,
    input  logic        irq_timer_i,
    input  logic        irq_external_i,
    input  logic [15:0] irq_fast_i,
    input  logic        irq_nm_i,
    output logic        irq_pending_o,

    // Debug interface
    input  logic        debug_req_i,
    output logic        debug_halted_o,
    input  logic [31:0] dm_halt_addr_i,
    input  logic [31:0] dm_exception_addr_i,
    output crash_dump_t crash_dump_o,

    // CPU control
    input  logic        fetch_enable_i,
    output logic        core_busy_o,

    // Lockstep status
    output logic        lockstep_error_o
  );

  localparam int unsigned OutputsOffset = LockstepOffset + 1;

  // =========================================================================
  // Shadow reset release after LockstepOffset cycles
  // =========================================================================
  localparam int unsigned CntWidth = $clog2(LockstepOffset + 1);
  logic [CntWidth-1:0] shadow_reset_cnt_q;
  logic shadow_rst_ni;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      shadow_reset_cnt_q <= '0;
    else if (shadow_reset_cnt_q < LockstepOffset)
      shadow_reset_cnt_q <= shadow_reset_cnt_q + 1'b1;
  end

  assign shadow_rst_ni = rst_ni & (shadow_reset_cnt_q == LockstepOffset);

  // =========================================================================
  // Comparator enable after lockstep alignment
  // =========================================================================
  logic                    cmp_enable_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      cmp_enable_q <= 1'b0;
    else
      cmp_enable_q <= shadow_rst_ni;  // one cycle after shadow reset releases
  end


  // -------------------------------------------------------------------------
  // Main core output/internal signals
  // -------------------------------------------------------------------------
  logic        instr_req_main;
  logic [31:0] instr_addr_main;

  logic        data_req_main;
  logic        data_we_main;
  logic [3:0]  data_be_main;
  logic [31:0] data_addr_main;
  logic [31:0] data_wdata_main;

  logic        core_busy_main;
  logic        irq_pending_main;
  logic        debug_halted_main;

  crash_dump_t   crash_dump_main;

  logic          x_issue_valid_main;
  x_issue_req_t  x_issue_req_main;
  x_register_t   x_register_main;
  logic          x_commit_valid_main;
  x_commit_t     x_commit_main;
  logic          x_result_ready_main;


  // -------------------------------------------------------------------------
  // Shadow core output/internal signals
  // -------------------------------------------------------------------------
  logic        instr_req_shadow;
  logic [31:0] instr_addr_shadow;

  logic        data_req_shadow;
  logic        data_we_shadow;
  logic [3:0]  data_be_shadow;
  logic [31:0] data_addr_shadow;
  logic [31:0] data_wdata_shadow;

  logic        core_busy_shadow;
  logic        irq_pending_shadow;
  logic        debug_halted_shadow;

  crash_dump_t   crash_dump_shadow;

  logic          x_issue_valid_shadow;
  x_issue_req_t  x_issue_req_shadow;
  x_register_t   x_register_shadow;
  logic          x_commit_valid_shadow;
  x_commit_t     x_commit_shadow;
  logic          x_result_ready_shadow;

  // -------------------------------------------------------------------------
  // Main core drives real external outputs
  // -------------------------------------------------------------------------
  assign instr_req_o       = instr_req_main;
  assign instr_addr_o      = instr_addr_main;

  assign data_req_o        = data_req_main;
  assign data_we_o         = data_we_main;
  assign data_be_o         = data_be_main;
  assign data_addr_o       = data_addr_main;
  assign data_wdata_o      = data_wdata_main;

  assign x_issue_valid_o   = x_issue_valid_main;
  assign x_issue_req_o     = x_issue_req_main;
  assign x_register_o      = x_register_main;
  assign x_commit_valid_o  = x_commit_valid_main;
  assign x_commit_o        = x_commit_main;
  assign x_result_ready_o  = x_result_ready_main;

  assign irq_pending_o     = irq_pending_main;
  assign debug_halted_o    = debug_halted_main;
  assign crash_dump_o      = crash_dump_main;

  assign core_busy_o       = core_busy_main;


  // -------------------------------------------------------------------------
  // Shadow input delay pipeline
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic          instr_gnt;
    logic          instr_rvalid;
    logic [31:0]   instr_rdata;
    logic          instr_err;

    logic          data_gnt;
    logic          data_rvalid;
    logic [31:0]   data_rdata;
    logic          data_err;

    logic          fetch_enable;
    logic          debug_req;

    logic          irq_software;
    logic          irq_timer;
    logic          irq_external;
    logic [15:0]   irq_fast;
    logic          irq_nm;

    logic          x_issue_ready;
    x_issue_resp_t x_issue_resp;

    logic          x_result_valid;
    x_result_t     x_result;
  } core_inputs_t;

  core_inputs_t shadow_inputs_in;
  core_inputs_t shadow_inputs_q [LockstepOffset-1:0];

  
  assign shadow_inputs_in.instr_gnt       = instr_gnt_i;
  assign shadow_inputs_in.instr_rvalid    = instr_rvalid_i;
  assign shadow_inputs_in.instr_rdata     = instr_rdata_i;
  assign shadow_inputs_in.instr_err       = instr_err_i;

  assign shadow_inputs_in.data_gnt        = data_gnt_i;
  assign shadow_inputs_in.data_rvalid     = data_rvalid_i;
  assign shadow_inputs_in.data_rdata      = data_rdata_i;
  assign shadow_inputs_in.data_err        = data_err_i;

  assign shadow_inputs_in.fetch_enable    = fetch_enable_i;
  assign shadow_inputs_in.debug_req       = debug_req_i;

  assign shadow_inputs_in.irq_software    = irq_software_i;
  assign shadow_inputs_in.irq_timer       = irq_timer_i;
  assign shadow_inputs_in.irq_external    = irq_external_i;
  assign shadow_inputs_in.irq_fast        = irq_fast_i;
  assign shadow_inputs_in.irq_nm          = irq_nm_i;

  assign shadow_inputs_in.x_issue_ready   = x_issue_ready_i;
  assign shadow_inputs_in.x_issue_resp    = x_issue_resp_i;

  assign shadow_inputs_in.x_result_valid  = x_result_valid_i;
  assign shadow_inputs_in.x_result        = x_result_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned i = 0; i < LockstepOffset; i++) begin
        shadow_inputs_q[i] <= '0;
      end
    end else begin
      for (int unsigned i = 0; i < LockstepOffset-1; i++) begin
        shadow_inputs_q[i] <= shadow_inputs_q[i+1];
      end

      shadow_inputs_q[LockstepOffset-1] <= shadow_inputs_in;
    end
  end

  // -------------------------------------------------------------------------
  // Delay main core outputs by LockstepOffset cycles
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic          instr_req;
    logic [31:0]   instr_addr;

    logic          data_req;
    logic          data_we;
    logic [3:0]    data_be;
    logic [31:0]   data_addr;
    logic [31:0]   data_wdata;

    logic          core_busy;
    logic          irq_pending;
    logic          debug_halted;

    logic          x_issue_valid;
    x_issue_req_t  x_issue_req;
    x_register_t   x_register;

    logic          x_commit_valid;
    x_commit_t     x_commit;

    logic          x_result_ready;

    crash_dump_t   crash_dump;
  } core_outputs_t;

  core_outputs_t main_outputs_in;
  core_outputs_t main_outputs_q [OutputsOffset-1:0]; 

  

  assign main_outputs_in.instr_req       = instr_req_main;
  assign main_outputs_in.instr_addr      = instr_addr_main;

  assign main_outputs_in.data_req        = data_req_main;
  assign main_outputs_in.data_we         = data_we_main;
  assign main_outputs_in.data_be         = data_be_main;
  assign main_outputs_in.data_addr       = data_addr_main;
  assign main_outputs_in.data_wdata      = data_wdata_main;

  assign main_outputs_in.core_busy       = core_busy_main;
  assign main_outputs_in.irq_pending     = irq_pending_main;
  assign main_outputs_in.debug_halted    = debug_halted_main;

  assign main_outputs_in.x_issue_valid   = x_issue_valid_main;
  assign main_outputs_in.x_issue_req     = x_issue_req_main;
  assign main_outputs_in.x_register      = x_register_main;

  assign main_outputs_in.x_commit_valid  = x_commit_valid_main;
  assign main_outputs_in.x_commit        = x_commit_main;

  assign main_outputs_in.x_result_ready  = x_result_ready_main;

  assign main_outputs_in.crash_dump      = crash_dump_main;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned i = 0; i < OutputsOffset; i++) begin
        main_outputs_q[i] <= '0;
      end
    end else begin
      for (int unsigned i = 0; i < OutputsOffset-1; i++) begin
        main_outputs_q[i] <= main_outputs_q[i+1];
      end

      main_outputs_q[OutputsOffset-1] <= main_outputs_in;
    end
  end

 
  core_outputs_t shadow_outputs_d;
  core_outputs_t shadow_outputs_q;


  assign shadow_outputs_d.instr_req     = instr_req_shadow;
  assign shadow_outputs_d.instr_addr    = instr_addr_shadow;
  assign shadow_outputs_d.data_req      = data_req_shadow;
  assign shadow_outputs_d.data_we       = data_we_shadow;
  assign shadow_outputs_d.data_be       = data_be_shadow;
  assign shadow_outputs_d.data_addr     = data_addr_shadow;
  assign shadow_outputs_d.data_wdata    = data_wdata_shadow;
  assign shadow_outputs_d.core_busy     = core_busy_shadow;
  assign shadow_outputs_d.irq_pending   = irq_pending_shadow;
  assign shadow_outputs_d.debug_halted  = debug_halted_shadow;
  assign shadow_outputs_d.x_issue_valid = x_issue_valid_shadow;
  assign shadow_outputs_d.x_issue_req   = x_issue_req_shadow;
  assign shadow_outputs_d.x_register    = x_register_shadow;
  assign shadow_outputs_d.x_commit_valid= x_commit_valid_shadow;
  assign shadow_outputs_d.x_commit      = x_commit_shadow;
  assign shadow_outputs_d.x_result_ready= x_result_ready_shadow;
  assign shadow_outputs_d.crash_dump    = crash_dump_shadow;

  always_ff @(posedge clk_i) begin
    shadow_outputs_q <= shadow_outputs_d;
  end

  // -------------------------------------------------------------------------
  // Comparator
  // -------------------------------------------------------------------------
  logic mismatch;
  assign mismatch = cmp_enable_q & (shadow_outputs_q != main_outputs_q[0]);
  // -------------------------------------------------------------------------
  // Sticky lockstep error or pulse error 
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lockstep_error_o <= 1'b0;
    end else if (mismatch) begin
      lockstep_error_o <= 1'b1;
    end
  end 

`ifndef SYNTHESIS

  // -------------------------------------------------------------------------
  // Debug prints
  // -------------------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst_ni && mismatch) begin
      $display("[%0t] MISMATCH DETECTED", $time);
      $display("main instr_addr   = %h", main_outputs_q[0].instr_addr);
      $display("shadow instr_addr = %h", shadow_outputs_q.instr_addr);

      $display("main instr_req    = %b", main_outputs_q[0].instr_req);
      $display("shadow instr_req  = %b", shadow_outputs_q.instr_req);

      $display("main data_addr    = %h", main_outputs_q[0].data_addr);
      $display("shadow data_addr  = %h", shadow_outputs_q.data_addr);

      $display("cmp_enable_q      = %b", cmp_enable_q);
    end
  end

  //always @(posedge clk_i) begin
  //  if (rst_ni) begin
  //    $display("[%0t] mismatch=%b cmp_enable=%b lockstep_error=%b",
  //             $time, mismatch, cmp_enable_q, lockstep_error_o);
  //  end
  //end

`endif

  // =========================================================================
  // Main CVE2 core
  // =========================================================================
  cve2_core #(
    .PMPEnable         (PMPEnable),
    .PMPGranularity    (PMPGranularity),
    .PMPNumRegions     (PMPNumRegions),
    .MHPMCounterNum    (MHPMCounterNum),
    .MHPMCounterWidth  (MHPMCounterWidth),
    .RV32E             (RV32E),
    .RV32M             (RV32M),
    .RV32B             (RV32B),
    .DbgTriggerEn      (DbgTriggerEn),
    .DbgHwBreakNum     (DbgHwBreakNum),
    .XInterface        (XInterface)
  ) u_main_core (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    .test_en_i            (test_en_i),
    .hart_id_i            (hart_id_i),
    .boot_addr_i          (boot_addr_i),

    // Instruction interface
    .instr_req_o          (instr_req_main),
    .instr_gnt_i          (instr_gnt_i),
    .instr_rvalid_i       (instr_rvalid_i),
    .instr_addr_o         (instr_addr_main),
    .instr_rdata_i        (instr_rdata_i),
    .instr_err_i          (instr_err_i),

    // Data interface
    .data_req_o           (data_req_main),
    .data_gnt_i           (data_gnt_i),
    .data_rvalid_i        (data_rvalid_i),
    .data_we_o            (data_we_main),
    .data_be_o            (data_be_main),
    .data_addr_o          (data_addr_main),
    .data_wdata_o         (data_wdata_main),
    .data_rdata_i         (data_rdata_i),
    .data_err_i           (data_err_i),

    // CV-X-IF
    .x_issue_valid_o      (x_issue_valid_main),
    .x_issue_ready_i      (x_issue_ready_i),
    .x_issue_req_o        (x_issue_req_main),
    .x_issue_resp_i       (x_issue_resp_i),

    .x_register_o         (x_register_main),

    .x_commit_valid_o     (x_commit_valid_main),
    .x_commit_o           (x_commit_main),

    .x_result_valid_i     (x_result_valid_i),
    .x_result_ready_o     (x_result_ready_main),
    .x_result_i           (x_result_i),

    // Interrupts
    .irq_software_i       (irq_software_i),
    .irq_timer_i          (irq_timer_i),
    .irq_external_i       (irq_external_i),
    .irq_fast_i           (irq_fast_i),
    .irq_nm_i             (irq_nm_i),
    .irq_pending_o        (irq_pending_main),

    // Debug
    .debug_req_i          (debug_req_i),
    .debug_halted_o       (debug_halted_main),

    .dm_halt_addr_i       (dm_halt_addr_i),
    .dm_exception_addr_i  (dm_exception_addr_i),

    // Control
    .fetch_enable_i       (fetch_enable_i),
    .core_busy_o          (core_busy_main),

    .crash_dump_o         (crash_dump_main)
  );


  // =========================================================================
  // Shadow CVE2 core
  // =========================================================================
  cve2_core #(
    .PMPEnable         (PMPEnable),
    .PMPGranularity    (PMPGranularity),
    .PMPNumRegions     (PMPNumRegions),
    .MHPMCounterNum    (MHPMCounterNum),
    .MHPMCounterWidth  (MHPMCounterWidth),
    .RV32E             (RV32E),
    .RV32M             (RV32M),
    .RV32B             (RV32B),
    .DbgTriggerEn      (DbgTriggerEn),
    .DbgHwBreakNum     (DbgHwBreakNum),
    .XInterface        (XInterface)
  ) u_shadow_core (
    .clk_i                (clk_i),
    .rst_ni               (shadow_rst_ni),

    .test_en_i            (test_en_i),
    .hart_id_i            (hart_id_i),
    .boot_addr_i          (boot_addr_i),

    // Instruction interface
    .instr_req_o          (instr_req_shadow),
    .instr_gnt_i          (shadow_inputs_q[0].instr_gnt),
    .instr_rvalid_i       (shadow_inputs_q[0].instr_rvalid),
    .instr_addr_o         (instr_addr_shadow),
    .instr_rdata_i        (shadow_inputs_q[0].instr_rdata),
    .instr_err_i          (shadow_inputs_q[0].instr_err),

    // Data interface
    .data_req_o           (data_req_shadow),
    .data_gnt_i           (shadow_inputs_q[0].data_gnt),
    .data_rvalid_i        (shadow_inputs_q[0].data_rvalid),
    .data_we_o            (data_we_shadow),
    .data_be_o            (data_be_shadow),
    .data_addr_o          (data_addr_shadow),
    .data_wdata_o         (data_wdata_shadow),
    .data_rdata_i         (shadow_inputs_q[0].data_rdata),
    .data_err_i           (shadow_inputs_q[0].data_err),

    // CV-X-IF
    .x_issue_valid_o      (x_issue_valid_shadow),
    .x_issue_ready_i      (shadow_inputs_q[0].x_issue_ready),
    .x_issue_req_o        (x_issue_req_shadow),
    .x_issue_resp_i       (shadow_inputs_q[0].x_issue_resp),

    .x_register_o         (x_register_shadow),

    .x_commit_valid_o     (x_commit_valid_shadow),
    .x_commit_o           (x_commit_shadow),

    .x_result_valid_i     (shadow_inputs_q[0].x_result_valid),
    .x_result_ready_o     (x_result_ready_shadow),
    .x_result_i           (shadow_inputs_q[0].x_result),

    // Interrupts
    .irq_software_i       (shadow_inputs_q[0].irq_software),
    .irq_timer_i          (shadow_inputs_q[0].irq_timer),
    .irq_external_i       (shadow_inputs_q[0].irq_external),
    .irq_fast_i           (shadow_inputs_q[0].irq_fast),
    .irq_nm_i             (shadow_inputs_q[0].irq_nm),
    .irq_pending_o        (irq_pending_shadow),

    // Debug
    .debug_req_i          (shadow_inputs_q[0].debug_req),
    .debug_halted_o       (debug_halted_shadow),

    .dm_halt_addr_i       (dm_halt_addr_i),
    .dm_exception_addr_i  (dm_exception_addr_i),

    // Control
    .fetch_enable_i       (shadow_inputs_q[0].fetch_enable),
    .core_busy_o          (core_busy_shadow),

    .crash_dump_o         (crash_dump_shadow)
  );

endmodule