// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Wrapper for peripheral RelOBI demux and triplicated address decoder for Taichip SoC


module relobi_periph_demux #(
  /// The OBI configuration for the ports.
  parameter obi_pkg::obi_cfg_t ObiCfg    = obi_pkg::ObiDefaultConfig,
  /// The request struct for the ports.
  parameter type               obi_req_t = logic,
  /// The response struct for the ports.
  parameter type               obi_rsp_t = logic,
  /// The R channel struct for the ports.
  parameter type               obi_r_chan_t = logic,
  /// The A channel optionals struct for all ports.
  parameter type               a_optional_t = logic,
  /// The R channel optionals struct for all ports.
  parameter type               r_optional_t = logic,
  /// The number of manager ports (output ports).
  parameter int unsigned       NumMgrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// The number of address rules.
  parameter int unsigned       NumAddrRules       = 32'd0,
  /// The address map rule type.
  parameter type               addr_map_rule_t    = logic,
  /// Use TMR for addr map signal
  parameter bit                TmrMap      = 1'b1,
  parameter int unsigned       MapWidth    = TmrMap ? 3 : 1,
  parameter bit                DecodeAbort = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  obi_req_t sbr_port_req_i,
  output obi_rsp_t sbr_port_rsp_o,

  output obi_req_t [NumMgrPorts-1:0] mgr_ports_req_o,
  input  obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp_i,

  input  addr_map_rule_t [MapWidth-1:0][NumAddrRules-1:0]   addr_map_i,
  input  logic [MapWidth-1:0]              					en_default_idx_i,
  input  logic [MapWidth-1:0][$clog2(NumMgrPorts)-1:0] 		default_idx_i,

  output logic [1:0] fault_o
);

  logic [3:0][1:0] faults;
  logic [1:0][3:0] faults_transpose;
  for (genvar i = 0; i < 4; i++) begin : gen_faults_transpose
    for (genvar j = 0; j < 2; j++) begin : gen_faults_transpose_inner
      assign faults_transpose[j][i] = faults[i][j];
    end
  end
  assign fault_o[0] = |faults_transpose[0];
  assign fault_o[1] = |faults_transpose[1];

  logic [MapWidth-1:0][$clog2(NumMgrPorts)-1:0] sbr_port_select;
  logic [2:0] decode_abort;

  for (genvar i = 0; i < 3; i++) begin : gen_tmr_part
    relobi_periph_demux_tmr_part #(
      .NumMgrPorts ( NumMgrPorts      ),
      .AddrWidth   ( ObiCfg.AddrWidth ),
      .EccAddrWidth( ObiCfg.AddrWidth + hsiao_ecc_pkg::min_ecc(ObiCfg.AddrWidth) ),
      .NumAddrRules( NumAddrRules       ),
      .addr_map_rule_t( addr_map_rule_t ),
      .DecodeAbort( DecodeAbort )
    ) i_tmr_part (
      .addr_i             ( sbr_port_req_i.a.addr ),
      .addr_map_i         ( TmrMap ? addr_map_i[i] : addr_map_i[0] ),
      .en_default_idx_i   ( TmrMap ? en_default_idx_i[i] : en_default_idx_i[0] ),
      .default_idx_i      ( TmrMap ? default_idx_i[i] : default_idx_i[0] ),
      .sbr_port_select    ( sbr_port_select[i] ),
      .faults             ( faults[i] ),
      .decode_abort_o     ( decode_abort[i] )
    );
  end

  relobi_demux #(
    .ObiCfg       ( ObiCfg    ),
    .obi_req_t    ( obi_req_t ),
    .obi_rsp_t    ( obi_rsp_t ),
    .obi_r_chan_t ( obi_r_chan_t ),
    .NumMgrPorts  ( NumMgrPorts ),
    .NumMaxTrans  ( NumMaxTrans ),
    .TmrSelect    ( 1'b1        )
  ) i_obi_demux (
    .clk_i,
    .rst_ni,

    .sbr_port_select_i ( sbr_port_select ),
    .sbr_port_req_i    ( sbr_port_req_i  ),
    .sbr_port_rsp_o    ( sbr_port_rsp_o  ),

    .mgr_ports_req_o   ( mgr_ports_req_o ),
    .mgr_ports_rsp_i   ( mgr_ports_rsp_i ),
    
    .fault_o           ( faults[3] )
  );
  

endmodule

(* no_ungroup *)
(* no_boundary_optimization *)
module relobi_periph_demux_tmr_part #(
  parameter int unsigned NumMgrPorts = 32'd0,
  parameter int unsigned AddrWidth = 32'd0,
  parameter int unsigned EccAddrWidth = AddrWidth + hsiao_ecc_pkg::min_ecc(AddrWidth),
  parameter int unsigned NumAddrRules = 32'd0,
  parameter type addr_map_rule_t = logic,
  parameter bit DecodeAbort = 1'b0
) (
  input logic [EccAddrWidth-1:0] addr_i,
  input addr_map_rule_t [NumAddrRules-1:0] addr_map_i,
  input logic en_default_idx_i,
  input logic [$clog2(NumMgrPorts)-1:0] default_idx_i,
  output logic [$clog2(NumMgrPorts)-1:0] sbr_port_select,
  output logic [1:0] faults,
  output logic decode_abort_o
);
  logic [AddrWidth-1:0] addr, addr_dec;

  hsiao_ecc_dec #(
	.DataWidth ( AddrWidth )
  ) i_addr_dec (
	.in        ( addr_i ),
	.out       ( addr_dec ),
	.syndrome_o( ),
	.err_o     ( faults )
  );

  if (DecodeAbort) begin : gen_decode_abort
    assign addr = addr_i[AddrWidth-1:0];
    assign decode_abort_o = faults[0];// | faults[1];
  end else begin : gen_no_decode_abort
    assign addr = addr_dec;
    assign decode_abort_o = '0;
  end

    addr_decode #(
      .NoIndices ( NumMgrPorts           ),
      .NoRules   ( NumAddrRules          ),
      .addr_t    ( logic [AddrWidth-1:0] ),
      .rule_t    ( addr_map_rule_t       ),
	  .Napot	 ( 1'b0 				 )
    ) i_addr_decode (
      .addr_i          ( addr             ),
      .addr_map_i      ( addr_map_i       ),
      .idx_o           ( sbr_port_select  ),
      .dec_valid_o     ( ),
      .dec_error_o     ( ),
      .en_default_idx_i( en_default_idx_i ),
      .default_idx_i   ( default_idx_i    )
    );

endmodule
