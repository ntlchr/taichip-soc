// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Copyright (c) 2025 Tallinn University of Technology.
// Updated for dual-port SRAM blocks by:
// - Natalia Cherezova (TalTech)
//
// ECC-protected SRAM, with enconding and decoding (if needed), bytewise access, and scrubbing
// Updated to support dual-port SRAM blocks


module ecc_sram_dual_port #(
  parameter  int unsigned NumWords         = 256,
  parameter  int unsigned UnprotectedWidth = 32,
  parameter  int unsigned ProtectedWidth   = 39,
  parameter  int unsigned ByteWidth        = 8,
  parameter  int unsigned NumPorts     	   = 2, // Number of read and write ports
  parameter  bit          InputECC         = 0, // 0: no ECC on input
                                                // 1: SECDED on input
  parameter  int unsigned NumRMWCuts       = 0, // Number of cuts in the read-modify-write path
  parameter               SimInit          = "random", // ("zeros", "ones", "random", "none")
  parameter type         impl_in_t    = logic, // Type for implementation inputs
  parameter type         impl_out_t   = logic, // Type for implementation outputs
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned DataWidth = InputECC ? ProtectedWidth : UnprotectedWidth,
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (UnprotectedWidth + ByteWidth - 32'd1) / ByteWidth, // ceil_div
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  
  input  impl_in_t             impl_i,
  output impl_out_t            impl_o,
  
  input  logic				   ecc_enable_i,	// Enable/disable ECC

  input  logic                 scrub_trigger_i, // Set to 1'b0 to disable scrubber
  output logic                 scrubber_fix_o,
  output logic                 scrub_uncorrectable_o,

  input  data_t [NumPorts-1:0] wdata_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o,
  output logic                 gnt_o,

  output logic                 single_error_o,
  output logic                 multi_error_o
);

  logic [NumPorts-1:0]                     internal_we;
  logic [NumPorts-1:0]                     bank_req;
  logic [NumPorts-1:0]                     bank_we;
  logic [NumPorts-1:0][AddrWidth-1:0]      bank_addr;
  logic [NumPorts-1:0][ProtectedWidth-1:0] bank_wdata;
  logic [NumPorts-1:0][ProtectedWidth-1:0] bank_rdata;
  
  logic                      bank_scrub_req;
  logic                      bank_scrub_we;
  logic [AddrWidth-1:0]      bank_scrub_addr;
  logic [ProtectedWidth-1:0] bank_scrub_wdata;
  logic [ProtectedWidth-1:0] bank_scrub_rdata;
  
  logic [NumPorts-1:0]                sram_mem_req;
  logic [NumPorts-1:0]                sram_mem_we;
  logic [NumPorts-1:0][BeWidth-1:0]   sram_mem_be;
  logic [NumPorts-1:0][AddrWidth-1:0] sram_mem_addr;
  logic [NumPorts-1:0][UnprotectedWidth-1:0] sram_mem_wdata;
  logic [NumPorts-1:0][UnprotectedWidth-1:0] sram_mem_rdata;
  
  logic [NumPorts-1:0]                sram_ecc_req;
  logic [NumPorts-1:0]                sram_ecc_we;
  logic [NumPorts-1:0]                sram_ecc_be;
  logic [NumPorts-1:0][AddrWidth-1:0] sram_ecc_addr;
  logic [NumPorts-1:0][7:0] sram_ecc_wdata;
  logic [NumPorts-1:0][7:0] sram_ecc_rdata;
  
  logic [NumPorts-1:0] single_error;
  logic [NumPorts-1:0] multi_error;
  logic [NumPorts-1:0] gnt;
  
  assign single_error_o = |single_error;
  assign multi_error_o = |multi_error;
  assign gnt_o = gnt[0];
  
  logic [NumPorts-1:0][DataWidth-1:0] rdata_with_ecc;
  
  assign rdata_o = ecc_enable_i ? rdata_with_ecc : sram_mem_rdata;
  
  for (genvar i = 0; i < NumPorts; i++) begin : gen_num_ports
	  logic [1:0] ecc_error;
	  logic       valid_read_d, valid_read_q;

	  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_valid_read
		if(~rst_ni) begin
		  valid_read_q <= '0;
		end else begin
		  valid_read_q <= valid_read_d;
		end
	  end

	  assign valid_read_d = req_i[i] && gnt[i] &&
							(~we_i[i] || (be_i[i] != {BeWidth{1'b1}}));
	  assign single_error[i] = ecc_error[0] && valid_read_q;
	  assign multi_error[i]  = ecc_error[1] && valid_read_q;

	`ifndef TARGET_SYNTHESIS
	  always @(posedge clk_i) begin
		if ((ecc_error[0] && valid_read_q && ecc_enable_i) == 1)
		  $display("[ECC] %t - single error detected", $realtime);
		if ((ecc_error[1] && valid_read_q && ecc_enable_i) == 1)
		  $display("[ECC] %t - multi error detected", $realtime);
	  end
	`endif

	  typedef enum logic { NORMAL, READ_MODIFY_WRITE } store_state_e;
	  store_state_e store_state_d, store_state_q;

	  typedef logic [cf_math_pkg::idx_width(NumRMWCuts)-1:0] rmw_count_t;
	  rmw_count_t rmw_count_d, rmw_count_q;

	  logic [DataWidth-1:0] input_buffer_d, input_buffer_q;
	  logic [AddrWidth-1:0] addr_buffer_d,  addr_buffer_q;
	  logic [  BeWidth-1:0] be_buffer_d,    be_buffer_q;

	  logic [UnprotectedWidth-1:0] be_selector;
	  for (genvar i = 0; i < BeWidth; i++) begin : gen_be_sel
		assign be_selector [i*ByteWidth +: ByteWidth] = {ByteWidth{be_buffer_q[i]}};
	  end

	  logic [ProtectedWidth-1:0] rmw_buffer_end;
	  logic [ProtectedWidth-1:0] rmw_buffer_0;
	  assign rmw_buffer_0 = bank_rdata[i];
	  shift_reg #(
		.dtype(logic[ProtectedWidth-1:0]),
		.Depth(NumRMWCuts)
	  ) i_rmw_buffer (
		.clk_i,
		.rst_ni,
		.d_i   (rmw_buffer_0),
		.d_o   (rmw_buffer_end)
	  );

	  if ( !InputECC ) begin : gen_no_ecc_input
		// Loads  -> loads full data
		// Stores ->
		//   If be_i == '1: adds ECC and stores directly
		//   If be_i != '1: loads stored and buffers input (responds success to store command)
		//                  re-calculates ECC and stores correctly

		logic [DataWidth-1:0] to_store;
		logic [cf_math_pkg::idx_width(NumRMWCuts)-1:0][DataWidth-1:0] loaded;

		logic [ProtectedWidth-1:0] decoder_in;

		assign decoder_in = store_state_q == NORMAL ? bank_rdata[i] : rmw_buffer_end;

		hsiao_ecc_dec #(
		  .DataWidth (UnprotectedWidth),
		  .ProtWidth (ProtectedWidth - UnprotectedWidth)
		) ecc_decode (
		  .in        ( decoder_in ),
		  .out       ( loaded ),
		  .syndrome_o(),
		  .err_o     ( ecc_error )
		);

		hsiao_ecc_enc #(
		  .DataWidth (UnprotectedWidth),
		  .ProtWidth (ProtectedWidth - UnprotectedWidth)
		) ecc_encode (
		  .in  ( to_store   ),
		  .out ( bank_wdata[i] )
		);

		assign rdata_with_ecc[i] = loaded;

		assign to_store = store_state_q == NORMAL ? wdata_i[i] :
						  (be_selector & input_buffer_q) | (~be_selector & loaded);
	  end else begin : gen_ecc_input
		assign ecc_error = '0;
		logic [  ProtectedWidth-1:0] lns_wdata;
		logic [UnprotectedWidth-1:0] intermediate_data_ld, intermediate_data_st;

		assign bank_wdata[i] = store_state_q == NORMAL ? wdata_i[i] : lns_wdata;
		assign rdata_with_ecc[i] = bank_rdata[i];

		hsiao_ecc_dec #(
		  .DataWidth (UnprotectedWidth),
		  .ProtWidth (ProtectedWidth - UnprotectedWidth)
		) ld_decode (
		  .in        ( rmw_buffer_end ),
		  .out       ( intermediate_data_ld ),
		  .syndrome_o(),
		  .err_o     ()
		);

		hsiao_ecc_dec #(
		  .DataWidth (UnprotectedWidth),
		  .ProtWidth (ProtectedWidth - UnprotectedWidth)
		) st_decode (
		  .in        ( input_buffer_q ),
		  .out       ( intermediate_data_st ),
		  .syndrome_o(),
		  .err_o     ()
		);

		hsiao_ecc_enc #(
		  .DataWidth (UnprotectedWidth),
		  .ProtWidth (ProtectedWidth - UnprotectedWidth)
		) lns_encode (
		  .in  ( (be_selector & intermediate_data_st) | (~be_selector & intermediate_data_ld)   ),
		  .out ( lns_wdata )
		);
	  end

	  // It might happen (especially with HWPEs driving part of the byte enable to zero) that sometimes
	  // a write happens with be_i = '0 but with a non-zero data on the wdata_i bus. In this particular
	  // case, the following FSM will still detect a RMW case, leading to either write of unproer data
	  // into the TCDM, or to deadlock conditions. We thus introduce a new signal that makes the write
	  // enable bus asserted only if the be_i is not all zero during a write operation, and use this to
	  // decide if we need to make a RMW or not.
	  assign internal_we[i] = we_i[i] & (be_i[i] != '0);

	  always_comb begin
		store_state_d  = NORMAL;
		gnt[i]         = 1'b1;
		bank_addr[i]   = addr_i[i];
		bank_we[i]     = internal_we[i];
		input_buffer_d = wdata_i[i];
		addr_buffer_d  = addr_i[i];
		be_buffer_d    = be_i[i];
		bank_req[i]    = req_i[i];
		rmw_count_d    = rmw_count_q;
		if (store_state_q == NORMAL) begin
		  if (req_i[i] & (be_i[i] != {BeWidth{1'b1}}) & internal_we[i]) begin
			store_state_d = READ_MODIFY_WRITE;
			bank_we[i]    = 1'b0;
			rmw_count_d   = rmw_count_t'(NumRMWCuts);
		  end
		end else begin
		  gnt[i]          = 1'b0;
		  bank_addr[i]    = addr_buffer_q;
		  bank_we[i]      = 1'b1;
		  input_buffer_d  = input_buffer_q;
		  addr_buffer_d   = addr_buffer_q;
		  be_buffer_d     = be_buffer_q;
		  if (rmw_count_q == '0) begin
			bank_req[i]   = 1'b1;
		  end else begin
			bank_req[i]   = 1'b0;
			rmw_count_d   = rmw_count_q - 1;
			store_state_d = READ_MODIFY_WRITE;
		  end
		end
	  end

	  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_read_modify_write_ff
		if(!rst_ni) begin
		  store_state_q  <= NORMAL;
		  addr_buffer_q  <= '0;
		  input_buffer_q <= '0;
		  be_buffer_q    <= '0;
		  rmw_count_q    <= '0;
		end else begin
		  store_state_q  <= store_state_d;
		  addr_buffer_q  <= addr_buffer_d;
		  input_buffer_q <= input_buffer_d;
		  be_buffer_q    <= be_buffer_d;
		  rmw_count_q    <= rmw_count_d;
		end
	  end
  end

  ecc_scrubber #(
    .BankSize       ( NumWords       ),
    .UseExternalECC ( 0              ),
    .DataWidth      ( ProtectedWidth )
  ) i_scrubber (
    .clk_i,
    .rst_ni,

    .scrub_trigger_i ( scrub_trigger_i       ),
    .bit_corrected_o ( scrubber_fix_o        ),
    .uncorrectable_o ( scrub_uncorrectable_o ),

    .intc_req_i      ( bank_req[0]           ),
    .intc_we_i       ( bank_we[0]            ),
    .intc_add_i      ( bank_addr[0]          ),
    .intc_wdata_i    ( bank_wdata[0]         ),
    .intc_rdata_o    ( bank_rdata[0]         ),

    .bank_req_o      ( bank_scrub_req        ),
    .bank_we_o       ( bank_scrub_we         ),
    .bank_add_o      ( bank_scrub_addr       ),
    .bank_wdata_o    ( bank_scrub_wdata      ),
    .bank_rdata_i    ( bank_scrub_rdata      ),

    .ecc_out_o       (),
    .ecc_in_i        ( '0 ),
    .ecc_err_i       ( '0 )
  );


  assign sram_mem_req[0]   = bank_scrub_req;
  assign sram_mem_we[0]    = bank_scrub_we;
  assign sram_mem_be[0]    = '1;
  assign sram_mem_addr[0]  = bank_scrub_addr;
  assign sram_mem_wdata[0] = bank_scrub_wdata[UnprotectedWidth-1:0];
  
  assign sram_ecc_req[0]   = bank_scrub_req;
  assign sram_ecc_we[0]    = bank_scrub_we;
  assign sram_ecc_be[0]    = '1;
  assign sram_ecc_addr[0]  = bank_scrub_addr;
  assign sram_ecc_wdata[0] = {1'b0,bank_scrub_wdata[ProtectedWidth-1:UnprotectedWidth]};
  
  assign bank_scrub_rdata  = {sram_ecc_rdata[0][6:0],sram_mem_rdata[0]};
  
  if (NumPorts == 2) begin
	assign sram_mem_req[1]   = bank_req[1];
	assign sram_mem_we[1]    = bank_we[1];
	assign sram_mem_be[1]    = '1;
	assign sram_mem_addr[1]  = bank_addr[1];
	assign sram_mem_wdata[1] = bank_wdata[1][UnprotectedWidth-1:0];
	
	assign sram_ecc_req[1]   = bank_req[1];
	assign sram_ecc_we[1]    = bank_we[1];
	assign sram_ecc_be[1]    = '1;
	assign sram_ecc_addr[1]  = bank_addr[1];
	assign sram_ecc_wdata[1] = {1'b0,bank_wdata[1][ProtectedWidth-1:UnprotectedWidth]};
	
	assign bank_rdata[1] = {sram_ecc_rdata[1][6:0],sram_mem_rdata[1]};
  end
  
  tc_sram_impl #(
      .NumWords  ( NumWords ),
      .DataWidth ( UnprotectedWidth ),
      .NumPorts  ( NumPorts ),
      .Latency   (  1 ),
      .SimInit   ( SimInit )
    ) i_bank (
      .clk_i,
      .rst_ni,

      .impl_i  ( impl_i         ),
      .impl_o  ( impl_o 	    ),

      .req_i   ( sram_mem_req   ),
      .we_i    ( sram_mem_we    ),
      .addr_i  ( sram_mem_addr  ),

      .wdata_i ( sram_mem_wdata ),
      .be_i    ( sram_mem_be    ),
      .rdata_o ( sram_mem_rdata )
    );

  logic dummy_wire;
  tc_sram_impl #(
      .NumWords  ( NumWords ),
      .DataWidth ( 8 ),
      .NumPorts  ( NumPorts ),
      .Latency   ( 1 ),
      .SimInit   ( SimInit )
    ) i_bank_ecc (
      .clk_i,
      .rst_ni,

      .impl_i  ( impl_i         ),
      .impl_o  ( ), // not connected

      .req_i   ( sram_ecc_req   ),
      .we_i    ( sram_ecc_we    ),
      .addr_i  ( sram_ecc_addr  ),

      .wdata_i ( sram_ecc_wdata ),
      .be_i    ( sram_ecc_be    ),
      .rdata_o ( sram_ecc_rdata )
    );

endmodule
