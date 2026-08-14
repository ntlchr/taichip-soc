// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Thomas Benz <tbenz@iis.ee.ethz.ch>
// - Tobias Senti <tsenti@student.ethz.ch>
// - Paul Scheffler <paulsc@iis.ee.ethz.ch>
//
// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for TAICHIP-1 SoC (added support for required SRAM macros) by:
// - Natalia Cherezova (TalTech)

module tc_sram_blackbox #(
  parameter int unsigned NumWords     = 32'd0,
  parameter int unsigned DataWidth    = 32'd0,
  parameter int unsigned ByteWidth    = 32'd0,
  parameter int unsigned NumPorts     = 32'd0,
  parameter int unsigned Latency      = 32'd0,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none"
) ();
endmodule

// one tie-off per macro to avoid port size mismatch warnings
`define IHP13_TC_SRAM_64x64_TIEOFF \
  .A_BIST_CLK   (  1'b0 ), \
  .A_BIST_ADDR  (  6'd0 ), \
  .A_BIST_DIN   ( 64'd0 ), \
  .A_BIST_BM    ( 64'd0 ), \
  .A_BIST_MEN   (  1'b0 ), \
  .A_BIST_WEN   (  1'b0 ), \
  .A_BIST_REN   (  1'b0 ), \
  .A_BIST_EN    (  1'b0 )

`define IHP13_TC_SRAM_256x64_TIEOFF \
  .A_BIST_CLK   (  1'b0 ), \
  .A_BIST_ADDR  (  8'd0 ), \
  .A_BIST_DIN   ( 64'd0 ), \
  .A_BIST_BM    ( 64'd0 ), \
  .A_BIST_MEN   (  1'b0 ), \
  .A_BIST_WEN   (  1'b0 ), \
  .A_BIST_REN   (  1'b0 ), \
  .A_BIST_EN    (  1'b0 )

`define IHP13_TC_SRAM_512x64_TIEOFF \
  .A_BIST_CLK   (  1'b0 ), \
  .A_BIST_ADDR  (  9'd0 ), \
  .A_BIST_DIN   ( 64'd0 ), \
  .A_BIST_BM    ( 64'd0 ), \
  .A_BIST_MEN   (  1'b0 ), \
  .A_BIST_WEN   (  1'b0 ), \
  .A_BIST_REN   (  1'b0 ), \
  .A_BIST_EN    (  1'b0 )

`define IHP13_TC_SRAM_1024x64_TIEOFF \
  .A_BIST_CLK   (  1'b0 ), \
  .A_BIST_ADDR  ( 10'd0 ), \
  .A_BIST_DIN   ( 64'd0 ), \
  .A_BIST_BM    ( 64'd0 ), \
  .A_BIST_MEN   (  1'b0 ), \
  .A_BIST_WEN   (  1'b0 ), \
  .A_BIST_REN   (  1'b0 ), \
  .A_BIST_EN    (  1'b0 )

`define IHP13_TC_SRAM_2048x64_TIEOFF \
  .A_BIST_CLK   (  1'b0 ), \
  .A_BIST_ADDR  ( 11'd0 ), \
  .A_BIST_DIN   ( 64'd0 ), \
  .A_BIST_BM    ( 64'd0 ), \
  .A_BIST_MEN   (  1'b0 ), \
  .A_BIST_WEN   (  1'b0 ), \
  .A_BIST_REN   (  1'b0 ), \
  .A_BIST_EN    (  1'b0 )

module tc_sram #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  parameter type         impl_in_t    = logic,
  parameter type         impl_out_t   = logic,
  parameter impl_out_t   ImplOutSim   = 'X,
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  impl_in_t             impl_i,
  output impl_out_t            impl_o,

  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,

  output data_t [NumPorts-1:0] rdata_o
);

  localparam P1L1 = (NumPorts == 1 & Latency == 1);
  localparam P2L1 = (NumPorts == 2 & Latency == 1);

  // Assemble bit mask
  data_t [NumPorts-1:0] bm;

  for (genvar p = 0; p < NumPorts; ++p) begin : gen_bm_ports
      for (genvar b = 0; b < DataWidth; ++b) begin : gen_bm_bits
        assign bm[p][b] = be_i[p][b/ByteWidth];
      end
  end

  // We drive a static value for `impl_o` in behavioral simulation.
  assign impl_o = ImplOutSim;

  // Generate desired cuts
  if (NumWords == 256 && DataWidth == 32 && P1L1) begin: gen_256x32xBx1
	logic [31:0] wdata32, rdata32, bm32;
    
    assign rdata_o = rdata32;
    assign wdata32  = wdata_i;
    assign bm32     = bm;
	
	RM_IHPSG13_1P_256x32_c2_bm_bist i_cut (
	  .A_CLK     ( clk_i    ),
	  .A_DLY     ( impl_i   ),
      .A_ADDR    ( addr_i[0][7:0] ),
      .A_BM      ( bm32     ),
      .A_MEN     ( req_i    ),
      .A_WEN     ( we_i     ),
      .A_REN     ( ~we_i    ),
      .A_DIN     ( wdata32  ),
      .A_DOUT    ( rdata32  ),
	  .A_BIST_CLK   (  1'b0 ),
	  .A_BIST_ADDR  (  8'd0 ),
	  .A_BIST_DIN   ( 32'd0 ),
	  .A_BIST_BM    ( 32'd0 ),
	  .A_BIST_MEN   (  1'b0 ),
	  .A_BIST_WEN   (  1'b0 ),
	  .A_BIST_REN   (  1'b0 ),
	  .A_BIST_EN    (  1'b0 )
	);
	
  end else if (NumWords == 256 && DataWidth == 32 && P2L1) begin: gen_256x32xBx2
  
	logic [31:0] a_wdata32, a_rdata32, a_bm32;
	logic [31:0] b_wdata32, b_rdata32, b_bm32;
    
    assign rdata_o[0] = a_rdata32;
    assign a_wdata32  = wdata_i[0];
    assign a_bm32     = bm[0];
	
	assign rdata_o[1] = b_rdata32;
    assign b_wdata32  = wdata_i[1];
    assign b_bm32     = bm[1];
	
	
	RM_IHPSG13_2P_256x32_c2_bm_bist i_cut (
	  .A_CLK   ( clk_i      ),
	  .A_DLY   ( impl_i     ),
      .A_ADDR  ( addr_i[0][7:0] ),
      .A_BM    ( a_bm32     ),
      .A_MEN   ( req_i[0]   ),
      .A_WEN   ( we_i[0]    ),
      .A_REN   ( ~we_i[0]   ),
      .A_DIN   ( a_wdata32  ),
      .A_DOUT  ( a_rdata32  ),
	  .A_BIST_CLK   (  1'b0 ),
	  .A_BIST_ADDR  (  8'd0 ),
	  .A_BIST_DIN   ( 32'd0 ),
	  .A_BIST_BM    ( 32'd0 ),
	  .A_BIST_MEN   (  1'b0 ),
	  .A_BIST_WEN   (  1'b0 ),
	  .A_BIST_REN   (  1'b0 ),
	  .A_BIST_EN    (  1'b0 ),
	  .B_CLK   ( clk_i      ),
	  .B_DLY   ( impl_i     ),
      .B_ADDR  ( addr_i[1][7:0] ),
      .B_BM    ( b_bm32     ),
      .B_MEN   ( req_i[1]   ),
      .B_WEN   ( we_i[1]    ),
      .B_REN   ( ~we_i[1]   ),
      .B_DIN   ( b_wdata32  ),
      .B_DOUT  ( b_rdata32  ),
	  .B_BIST_CLK   (  1'b0 ),
	  .B_BIST_ADDR  (  8'd0 ),
	  .B_BIST_DIN   ( 32'd0 ),
	  .B_BIST_BM    ( 32'd0 ),
	  .B_BIST_MEN   (  1'b0 ),
	  .B_BIST_WEN   (  1'b0 ),
	  .B_BIST_REN   (  1'b0 ),
	  .B_BIST_EN    (  1'b0 )
	);
  
  end else if (NumWords == 256 && DataWidth == 8 && P1L1) begin: gen_256x8xBx1
	logic [7:0] wdata8, rdata8, bm8;
    
    assign rdata_o = rdata8;
    assign wdata8  = wdata_i;
    assign bm8     = bm;
	
	RM_IHPSG13_1P_256x8_c3_bm_bist i_cut (
	  .A_CLK     ( clk_i   ),
	  .A_DLY     ( impl_i  ),
      .A_ADDR    ( addr_i[0][7:0] ),
      .A_BM      ( bm8     ),
      .A_MEN     ( req_i   ),
      .A_WEN     ( we_i    ),
      .A_REN     ( ~we_i   ),
      .A_DIN     ( wdata8  ),
      .A_DOUT    ( rdata8  ),
	  .A_BIST_CLK   ( 1'b0 ),
	  .A_BIST_ADDR  ( 8'd0 ),
	  .A_BIST_DIN   ( 8'd0 ),
	  .A_BIST_BM    ( 8'd0 ),
	  .A_BIST_MEN   ( 1'b0 ),
	  .A_BIST_WEN   ( 1'b0 ),
	  .A_BIST_REN   ( 1'b0 ),
	  .A_BIST_EN    ( 1'b0 )
	);
  
  end else if (NumWords == 256 && DataWidth == 8 && P2L1) begin: gen_256x8xBx2
	logic [7:0] a_wdata8, a_rdata8, a_bm8;
	logic [7:0] b_wdata8, b_rdata8, b_bm8;
    
    assign rdata_o[0] = a_rdata8;
    assign a_wdata8   = wdata_i[0];
    assign a_bm8      = bm[0];
	
	assign rdata_o[1] = b_rdata8;
    assign b_wdata8   = wdata_i[1];
    assign b_bm8      = bm[1];
	
	RM_IHPSG13_2P_256x8_c2_bm_bist i_cut (
	  .A_CLK   ( clk_i      ),
	  .A_DLY   ( impl_i     ),
      .A_ADDR  ( addr_i[0][7:0] ),
      .A_BM    ( a_bm8      ),
      .A_MEN   ( req_i[0]   ),
      .A_WEN   ( we_i[0]    ),
      .A_REN   ( ~we_i[0]   ),
      .A_DIN   ( a_wdata8   ),
      .A_DOUT  ( a_rdata8   ),
	  .A_BIST_CLK   (  1'b0 ),
	  .A_BIST_ADDR  (  8'd0 ),
	  .A_BIST_DIN   (  8'd0 ),
	  .A_BIST_BM    (  8'd0 ),
	  .A_BIST_MEN   (  1'b0 ),
	  .A_BIST_WEN   (  1'b0 ),
	  .A_BIST_REN   (  1'b0 ),
	  .A_BIST_EN    (  1'b0 ),
	  .B_CLK   ( clk_i      ),
	  .B_DLY   ( impl_i     ),
      .B_ADDR  ( addr_i[1][7:0] ),
      .B_BM    ( b_bm8      ),
      .B_MEN   ( req_i[1]   ),
      .B_WEN   ( we_i[1]    ),
      .B_REN   ( ~we_i[1]   ),
      .B_DIN   ( b_wdata8   ),
      .B_DOUT  ( b_rdata8   ),
	  .B_BIST_CLK   (  1'b0 ),
	  .B_BIST_ADDR  (  8'd0 ),
	  .B_BIST_DIN   (  8'd0 ),
	  .B_BIST_BM    (  8'd0 ),
	  .B_BIST_MEN   (  1'b0 ),
	  .B_BIST_WEN   (  1'b0 ),
	  .B_BIST_REN   (  1'b0 ),
	  .B_BIST_EN    (  1'b0 )
	);
  
  end else if (NumWords == 64 && DataWidth == 64 && P1L1) begin: gen_64x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;
    

    RM_IHPSG13_1P_64x64_c2_bm_bist i_cut (
      .A_CLK   ( clk_i    ),
      .A_DLY   ( impl_i  ),
      .A_ADDR  ( addr_i [0][5:0] ),
      .A_BM    ( bm64     ),
      .A_MEN   ( req_i    ),
      .A_WEN   ( we_i     ),
      .A_REN   ( ~we_i    ),
      .A_DIN   ( wdata64  ),
      .A_DOUT  ( rdata64  ),
     `IHP13_TC_SRAM_64x64_TIEOFF
    );

  end else if (NumWords == 256 && DataWidth == 64 && P1L1) begin : gen_256x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;

    RM_IHPSG13_1P_256x64_c2_bm_bist i_cut (
      .A_CLK   ( clk_i    ),
      .A_DLY   ( impl_i  ),
      .A_ADDR  ( addr_i [0][7:0] ),
      .A_BM    ( bm64     ),
      .A_MEN   ( req_i    ),
      .A_WEN   ( we_i     ),
      .A_REN   ( ~we_i    ),
      .A_DIN   ( wdata64  ),
      .A_DOUT  ( rdata64  ),
     `IHP13_TC_SRAM_256x64_TIEOFF
    );

  end else if (NumWords == 512 & DataWidth == 64 & P1L1) begin : gen_512x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;

    RM_IHPSG13_1P_512x64_c2_bm_bist i_cut (
      .A_CLK   ( clk_i    ),
      .A_DLY   ( impl_i  ),
      .A_ADDR  ( addr_i [0][8:0] ),
      .A_BM    ( bm64     ),
      .A_MEN   ( req_i    ),
      .A_WEN   ( we_i     ),
      .A_REN   ( ~we_i    ),
      .A_DIN   ( wdata64  ),
      .A_DOUT  ( rdata64  ),
     `IHP13_TC_SRAM_512x64_TIEOFF
    );

  end else if (NumWords == 1024 & DataWidth == 64 & P1L1) begin : gen_1024x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;

    RM_IHPSG13_1P_1024x64_c2_bm_bist i_cut (
       .A_CLK   ( clk_i    ),
       .A_DLY   ( impl_i  ),
       .A_ADDR  ( addr_i [0][9:0] ),
       .A_BM    ( bm64     ),
       .A_MEN   ( req_i    ),
       .A_WEN   ( we_i     ),
       .A_REN   ( ~we_i    ),
       .A_DIN   ( wdata64  ),
       .A_DOUT  ( rdata64  ),
       `IHP13_TC_SRAM_1024x64_TIEOFF
      );

  end else if (NumWords == 2048 & DataWidth == 64 & P1L1) begin : gen_2048x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;

    RM_IHPSG13_1P_2048x64_c2_bm_bist i_cut (
       .A_CLK   ( clk_i    ),
       .A_DLY   ( impl_i   ),
       .A_ADDR  ( addr_i [0][10:0] ),
       .A_BM    ( bm64     ),
       .A_MEN   ( req_i    ),
       .A_WEN   ( we_i     ),
       .A_REN   ( ~we_i    ),
       .A_DIN   ( wdata64  ),
       .A_DOUT  ( rdata64  ),
       `IHP13_TC_SRAM_2048x64_TIEOFF
      );
  end else if (NumWords == 512 && DataWidth == 32 && P1L1) begin: gen_512x32xBx1
    logic [63:0] wdata64, rdata64, bm64;
    logic sel_d, sel_q;

    // muxing neighboring bits instead of upper/lower 32bit reduces routing
    always_comb begin : gen_bit_interleaving
      for (int i = 0; i < 32; i++) begin
          // duplicate each bit
          wdata64[2*i]   = wdata_i[0][i]; // even bits (active if addr LSB is 0)
          bm64[2*i]      = bm[0][i] & ~addr_i[0][0];
          wdata64[2*i+1] = wdata_i[0][i]; // odd bits  (active if addr LSB is 1)
          bm64[2*i+1]    = bm[0][i] & addr_i[0][0];

          if(~sel_q) begin
            rdata_o[0][i] = rdata64[2*i];   // even bits
          end else begin
            rdata_o[0][i] = rdata64[2*i+1]; // odd bitss
          end
      end
    end

    // LSB needed for read in next cycle
    assign sel_d = addr_i[0][0];

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_mem_sel_q
      if(~rst_ni)             sel_q <= '0;
      else if (req_i & ~we_i) sel_q <= sel_d;
    end

    RM_IHPSG13_1P_256x64_c2_bm_bist i_cut (
     .A_CLK   ( clk_i   ),
     .A_DLY   ( impl_i  ),
     .A_ADDR  ( addr_i [0][8:1] ),
     .A_BM    ( bm64    ),
     .A_MEN   ( req_i   ),
     .A_WEN   ( we_i    ),
     .A_REN   ( ~we_i   ),
     .A_DIN   ( wdata64 ),
     .A_DOUT  ( rdata64 ),
     `IHP13_TC_SRAM_256x64_TIEOFF
    );

  end else if (NumWords == 1024 && DataWidth == 32 && P1L1) begin: gen_1024x32xBx1
    logic [63:0] wdata64, rdata64, bm64;
    logic sel_d, sel_q;

    // muxing neighboring bits instead of upper/lower 32bit reduces routing
    always_comb begin : gen_bit_interleaving
      for (int i = 0; i < 32; i++) begin
          // duplicate each bit
          wdata64[2*i]   = wdata_i[0][i]; // even bits (active if addr LSB is 0)
          bm64[2*i]      = bm[0][i] & ~addr_i[0][0];
          wdata64[2*i+1] = wdata_i[0][i]; // odd bits  (active if addr LSB is 1)
          bm64[2*i+1]    = bm[0][i] & addr_i[0][0];

          if(~sel_q) begin
            rdata_o[0][i] = rdata64[2*i];   // even bits
          end else begin
            rdata_o[0][i] = rdata64[2*i+1]; // odd bits
          end
      end
    end

    // LSB needed for read in next cycle
    assign sel_d = addr_i[0][0];

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_mem_sel_q
      if(~rst_ni)             sel_q <= '0;
      else if (req_i & ~we_i) sel_q <= sel_d;
    end

    RM_IHPSG13_1P_512x64_c2_bm_bist i_cut (
     .A_CLK   ( clk_i   ),
     .A_DLY   ( impl_i  ),
     .A_ADDR  ( addr_i [0][9:1] ),
     .A_BM    ( bm64    ),
     .A_MEN   ( req_i   ),
     .A_WEN   ( we_i    ),
     .A_REN   ( ~we_i   ),
     .A_DIN   ( wdata64 ),
     .A_DOUT  ( rdata64 ),
     `IHP13_TC_SRAM_512x64_TIEOFF
    );
  end else if (NumWords == 2048 && DataWidth == 32 && P1L1) begin: gen_2048x32xBx1
    logic [63:0] wdata64, rdata64, bm64;
    logic sel_d, sel_q;

    // muxing neighboring bits instead of upper/lower 32bit reduces routing
    always_comb begin : gen_bit_interleaving
      for (int i = 0; i < 32; i++) begin
          // duplicate each bit
          wdata64[2*i]   = wdata_i[0][i]; // even bits (active if addr LSB is 0)
          bm64[2*i]      = bm[0][i] & ~addr_i[0][0];
          wdata64[2*i+1] = wdata_i[0][i]; // odd bits  (active if addr LSB is 1)
          bm64[2*i+1]    = bm[0][i] & addr_i[0][0];

          if(~sel_q) begin
            rdata_o[0][i] = rdata64[2*i];   // even bits
          end else begin
            rdata_o[0][i] = rdata64[2*i+1]; // odd bits
          end
      end
    end

    // LSB needed for read in next cycle
    assign sel_d = addr_i[0][0];

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_mem_sel_q
      if(~rst_ni)             sel_q <= '0;
      else if (req_i & ~we_i) sel_q <= sel_d;
    end

    RM_IHPSG13_1P_1024x64_c2_bm_bist i_cut (
     .A_CLK   ( clk_i   ),
     .A_DLY   ( impl_i  ),
     .A_ADDR  ( addr_i [0][10:1] ),
     .A_BM    ( bm64    ),
     .A_MEN   ( req_i   ),
     .A_WEN   ( we_i    ),
     .A_REN   ( ~we_i   ),
     .A_DIN   ( wdata64 ),
     .A_DOUT  ( rdata64 ),
     `IHP13_TC_SRAM_1024x64_TIEOFF
    );

  end else if (NumWords == 2048 & DataWidth == 64 & P1L1) begin : gen_2048x64xBx1
    logic [63:0] wdata64, rdata64, bm64;
    
    assign rdata_o = rdata64;
    assign wdata64 = wdata_i;
    assign bm64    = bm;

    RM_IHPSG13_1P_2048x64_c2_bm_bist i_cut (
       .A_CLK   ( clk_i    ),
       .A_DLY   ( impl_i   ),
       .A_ADDR  ( addr_i [0][10:0] ),
       .A_BM    ( bm64     ),
       .A_MEN   ( req_i    ),
       .A_WEN   ( we_i     ),
       .A_REN   ( ~we_i    ),
       .A_DIN   ( wdata64  ),
       .A_DOUT  ( rdata64  ),
       `IHP13_TC_SRAM_2048x64_TIEOFF
      );

  end else begin : gen_blackbox

  `ifndef SYNTHESIS
    initial $fatal("No tc_sram for %m: NumWords %0d, DataWidth %0d NumPorts %0d, Latency %0d",
        NumWords, DataWidth, NumPorts);
  `endif

  // Instantiate a non-linkable blackbox with parameters for debugging
  `ifdef SYNTHESIS
    (* dont_touch = "true" *)
    tc_sram_blackbox #(
      .NumWords     ( NumWords    ),
      .DataWidth    ( DataWidth   ),
      .ByteWidth    ( ByteWidth   ),
      .NumPorts     ( NumPorts    ),
      .Latency      ( Latency     ),
      .SimInit      ( SimInit     ),
      .PrintSimCfg  ( PrintSimCfg ),
      .ImplKey      ( ImplKey     )
    ) i_sram_blackbox ();
  `endif

end

endmodule
