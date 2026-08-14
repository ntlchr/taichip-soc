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
// ECC-protected SRAM, with enconding and decoding (if needed), bytewise access, and scrubbing

module ecc_sram #(
  parameter  int unsigned NumWords         = 256,
  parameter  int unsigned UnprotectedWidth = 32,
  parameter  int unsigned ProtectedWidth   = 39,
  parameter  int unsigned ByteWidth        = 8,
  parameter  bit          InputECC         = 0, // 0: no ECC on input
                                                // 1: SECDED on input
  parameter  int unsigned NumRMWCuts       = 0, // Number of cuts in the read-modify-write path
  parameter               SimInit          = "random", // ("zeros", "ones", "random", "none")
  parameter type         impl_in_t    = logic, // Type for implementation inputs
  parameter type         impl_out_t   = logic, // Type for implementation outputs
  // Set params
  localparam int unsigned DataInWidth      = InputECC ? ProtectedWidth : UnprotectedWidth,
  localparam int unsigned ByteEnWidth      = UnprotectedWidth/ByteWidth,
  localparam int unsigned BankAddrWidth    = $clog2(NumWords)
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  
  input  impl_in_t                 impl_i,
  output impl_out_t                impl_o,
  
  input  logic					   ecc_enable_i,	// Enable/disable ECC

  input  logic                     scrub_trigger_i, // Set to 1'b0 to disable scrubber
  output logic                     scrubber_fix_o,
  output logic                     scrub_uncorrectable_o,

  input  logic [  DataInWidth-1:0] wdata_i,
  input  logic [BankAddrWidth-1:0] addr_i,
  input  logic                     req_i,
  input  logic                     we_i,
  input  logic [  ByteEnWidth-1:0] be_i,
  output logic [  DataInWidth-1:0] rdata_o,
  output logic                     gnt_o,

  output logic                     single_error_o,
  output logic                     multi_error_o
);

  logic [1:0] ecc_error;
  logic       valid_read_d, valid_read_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_valid_read
    if(~rst_ni) begin
      valid_read_q <= '0;
    end else begin
      valid_read_q <= valid_read_d;
    end
  end

  assign valid_read_d = req_i && gnt_o &&
                        (~we_i || (be_i != {ByteEnWidth{1'b1}}));
  assign single_error_o = ecc_error[0] && valid_read_q;
  assign multi_error_o  = ecc_error[1] && valid_read_q;

`ifndef TARGET_SYNTHESIS
  always @(posedge clk_i) begin
    if ((ecc_error[0] && valid_read_q && ecc_enable_i) == 1)
      $display("[ECC] %t - single error detected", $realtime);
    if ((ecc_error[1] && valid_read_q && ecc_enable_i) == 1)
      $display("[ECC] %t - multi error detected", $realtime);
  end
`endif

  logic                      internal_we;
  logic                      bank_req;
  logic                      bank_we;
  logic [ BankAddrWidth-1:0] bank_addr;
  logic [ProtectedWidth-1:0] bank_wdata;
  logic [ProtectedWidth-1:0] bank_rdata;

  logic                      bank_scrub_req;
  logic                      bank_scrub_we;
  logic [ BankAddrWidth-1:0] bank_scrub_addr;
  logic [ProtectedWidth-1:0] bank_scrub_wdata;
  logic [ProtectedWidth-1:0] bank_scrub_rdata;
  
  logic                        sram_mem_req;
  logic                        sram_mem_we;
  logic [     ByteEnWidth-1:0] sram_mem_be;
  logic [   BankAddrWidth-1:0] sram_mem_addr;
  logic [UnprotectedWidth-1:0] sram_mem_wdata;
  
  logic                      sram_ecc_req;
  logic                      sram_ecc_we;
  logic                      sram_ecc_be;
  logic [ BankAddrWidth-1:0] sram_ecc_addr;
  logic [7:0] 				 sram_ecc_wdata;
  
  logic [DataInWidth-1:0] rdata_with_ecc;
  
  assign rdata_o = ecc_enable_i ? rdata_with_ecc : bank_scrub_rdata[UnprotectedWidth-1:0];

  typedef enum logic { NORMAL, READ_MODIFY_WRITE } store_state_e;
  store_state_e store_state_d, store_state_q;

  typedef logic [cf_math_pkg::idx_width(NumRMWCuts)-1:0] rmw_count_t;
  rmw_count_t rmw_count_d, rmw_count_q;

  logic [  DataInWidth-1:0] input_buffer_d, input_buffer_q;
  logic [BankAddrWidth-1:0] addr_buffer_d,  addr_buffer_q;
  logic [  ByteEnWidth-1:0] be_buffer_d,    be_buffer_q;

  logic [UnprotectedWidth-1:0] be_selector;
  for (genvar i = 0; i < ByteEnWidth; i++) begin : gen_be_sel
    assign be_selector [i*ByteWidth +: ByteWidth] = {ByteWidth{be_buffer_q[i]}};
  end

  logic [ProtectedWidth-1:0] rmw_buffer_end;
  logic [ProtectedWidth-1:0] rmw_buffer_0;
  assign rmw_buffer_0 = bank_rdata;
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

    logic [DataInWidth-1:0] to_store;
    logic [cf_math_pkg::idx_width(NumRMWCuts)-1:0][DataInWidth-1:0] loaded;

    logic [ProtectedWidth-1:0] decoder_in;

    assign decoder_in = store_state_q == NORMAL ? bank_rdata : rmw_buffer_end;

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
      .out ( bank_wdata )
    );

    assign rdata_with_ecc = loaded;

    assign to_store = store_state_q == NORMAL ?
                      wdata_i :
                      (be_selector & input_buffer_q) | (~be_selector & loaded);

  end else begin : gen_ecc_input

    assign ecc_error = '0;
    logic [  ProtectedWidth-1:0] lns_wdata;
    logic [UnprotectedWidth-1:0] intermediate_data_ld, intermediate_data_st;

    assign bank_wdata = store_state_q == NORMAL ? wdata_i : lns_wdata;
    assign rdata_with_ecc = bank_rdata;

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
  assign internal_we = we_i & (be_i != '0);

  always_comb begin
    store_state_d  = NORMAL;
    gnt_o          = 1'b1;
    bank_addr      = addr_i;
    bank_we        = internal_we;
    input_buffer_d = wdata_i;
    addr_buffer_d  = addr_i;
    be_buffer_d    = be_i;
    bank_req       = req_i;
    rmw_count_d    = rmw_count_q;
    if (store_state_q == NORMAL) begin
      if (req_i & (be_i != {ByteEnWidth{1'b1}}) & internal_we) begin
        store_state_d = READ_MODIFY_WRITE;
        bank_we       = 1'b0;
        rmw_count_d   = rmw_count_t'(NumRMWCuts);
      end
    end else begin
      gnt_o           = 1'b0;
      bank_addr       = addr_buffer_q;
      bank_we         = 1'b1;
      input_buffer_d  = input_buffer_q;
      addr_buffer_d   = addr_buffer_q;
      be_buffer_d     = be_buffer_q;
      if (rmw_count_q == '0) begin
        bank_req      = 1'b1;
      end else begin
        bank_req      = 1'b0;
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

    .intc_req_i      ( bank_req              ),
    .intc_we_i       ( bank_we               ),
    .intc_add_i      ( bank_addr             ),
    .intc_wdata_i    ( bank_wdata            ),
    .intc_rdata_o    ( bank_rdata            ),

    .bank_req_o      ( bank_scrub_req        ),
    .bank_we_o       ( bank_scrub_we         ),
    .bank_add_o      ( bank_scrub_addr       ),
    .bank_wdata_o    ( bank_scrub_wdata      ),
    .bank_rdata_i    ( bank_scrub_rdata      ),

    .ecc_out_o       (),
    .ecc_in_i        ( '0 ),
    .ecc_err_i       ( '0 )
  );

  assign sram_mem_req   = bank_scrub_req;
  assign sram_mem_we    = bank_scrub_we;
  assign sram_mem_be    = '1;
  assign sram_mem_addr  = bank_scrub_addr;
  assign sram_mem_wdata = bank_scrub_wdata[UnprotectedWidth-1:0];
  
  assign sram_ecc_req   = bank_scrub_req;
  assign sram_ecc_we    = bank_scrub_we;
  assign sram_ecc_be    = '1;
  assign sram_ecc_addr  = bank_scrub_addr;
  assign sram_ecc_wdata = {1'b0,bank_scrub_wdata[ProtectedWidth-1:UnprotectedWidth]};
  
  tc_sram_impl #(
      .NumWords  ( NumWords ),
      .DataWidth ( UnprotectedWidth ),
      .NumPorts  (  1 ),
      .Latency   (  1 ),
      .SimInit   ( SimInit )
    ) i_bank (
      .clk_i,
      .rst_ni,

      .impl_i  ( impl_i         ),
      .impl_o  ( impl_o         ),

      .req_i   ( sram_mem_req   ),
      .we_i    ( sram_mem_we    ),
      .addr_i  ( sram_mem_addr  ),

      .wdata_i ( sram_mem_wdata ),
      .be_i    ( sram_mem_be    ),
      .rdata_o ( bank_scrub_rdata[UnprotectedWidth-1:0] )
    );

  logic dummy_wire;
  tc_sram_impl #(
      .NumWords  ( NumWords ),
      .DataWidth ( 8 ),
      .NumPorts  ( 1 ),
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
      .rdata_o ( {dummy_wire,bank_scrub_rdata[ProtectedWidth-1:UnprotectedWidth]} )
    );

endmodule
