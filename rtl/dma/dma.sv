// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Authors:
//    Lionel Noussi <lnoussi@ethz.ch> <lio.noussi@gmail.com>


module dma import dma_pkg::*; #(
  /// The OBI configuration for the subordinate ports
  parameter obi_pkg::obi_cfg_t           SbrObiCfg      = obi_pkg::ObiDefaultConfig,
  // The OBI configuration for the master ports
  parameter obi_pkg::obi_cfg_t           MgrObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The subordinate request struct.
  parameter type                         sbr_obi_req_t   = logic,
  /// The subordinate response struct.
  parameter type                         sbr_obi_rsp_t   = logic,
  /// The manager request struct.
  parameter type                         mgr_obi_req_t   = logic,
  /// The manager response struct.
  parameter type                         mgr_obi_rsp_t   = logic
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  // // Master port to periph_demux
  output  mgr_obi_req_t         dma_receive_obi_req_o,
  input   mgr_obi_rsp_t         dma_receive_obi_rsp_i,

  // // Master port to xbar
  output  mgr_obi_req_t         dma_transmit_obi_req_o,
  input   mgr_obi_rsp_t         dma_transmit_obi_rsp_i,

  // Slave port to enable setup by CPU/DEBUG
  input  sbr_obi_req_t          dma_subordinate_obi_req_i,
  output sbr_obi_rsp_t          dma_subordinate_obi_rsp_o,

  // Interrupt
  output logic                  dma_irq_o
);

// Interrupt Handler

// Internal signals to control DMA IRQ
logic activate_irq;
logic stop_irq;

// Instantiate the DMA Interrupt Handler
dma_interrupt_handler i_dma_interupt_handler (
  .clk_i         (clk_i),
  .rst_ni        (rst_ni),

  .activate_irq_i(activate_irq),
  .stop_irq_i    (stop_irq),

  .dma_irq_o     (dma_irq_o)
);


// DMA INTERNAL STATE REGISTERS AND SIGNALS
// -----------------------------------------------------------------------

// Registers to buffer incoming requests
logic req_d, req_q;
logic we_d, we_q;
logic [AddrW-1:0] addr_d, addr_q;
logic [DataW-1:0] wdata_d, wdata_q;
logic [SbrObiCfg.IdWidth-1:0] id_d, id_q; // Id of the request, must be same for the response

// Signals used to create the response
logic [DataW-1:0] rsp_data; // Data field of the obi response
logic rsp_err; // Error field of the obi response

// DMA internal-state-registers
logic[AddrW-1:0] src_base_addr_d, src_base_addr_q;
logic[AddrW-1:0] dst_base_addr_d, dst_base_addr_q;
logic[7:0]  src_offset_d, src_offset_q;
logic[7:0]  dst_offset_d, dst_offset_q;
logic[10:0] num_transfers_d, num_transfers_q;
logic       interrupt_enable_d, interrupt_enable_q;
logic           increment_src_d, increment_src_q;   // Should the source address be incremented after a read?
logic           increment_dst_d, increment_dst_q;   // Should the destination address be incremented after a send?
transfer_size_t transfer_size_d, transfer_size_q;   // Are we transfering Words(=0) or Bytes(=1)?
logic           activate_signal_d, activate_signal_q;   // Signal to the receiver and transmitter state machines to signal start
logic           interrupt_signal_d, interrupt_signal_q; // Signal to the receiver and transmitter state machines to signal stop

logic[7:0]        condition_offset_d, condition_offset_q;   // Condition offset is relative to either src or dst base address depending on condition type
logic[7:0]        condition_mask_d, condition_mask_q;       // 8-bit bit-mask to get relevant bit
condition_type_t  condition_type_d, condition_type_q; // If read condition, then offset is relative to source, else relative to the dst base addr
logic             condition_negate_d, condition_negate_q;
logic             condition_valid_d, condition_valid_q;


// RECEIVER STATE MACHINE REGISTERS AND SIGNALS
// -----------------------------------------------------------------------

dma_receiver_states_t receiver_state_d, receiver_state_q;
logic[10:0]      receiver_counter_d, receiver_counter_q;
logic            receiver_obi_req_d, receiver_obi_req_q;
logic[AddrW-1:0] receiver_obi_addr_d, receiver_obi_addr_q;
logic[AddrW-1:0] source_addr_d, source_addr_q;   // This address will get incremented, instead of overwriting the base address
logic[AddrW-1:0] condition_base_addr;
logic[AddrW-1:0] condition_address;

assign condition_base_addr = (condition_type_q == WRITE_CONDITION) ? dst_base_addr_q : src_base_addr_q;
assign condition_address   = condition_base_addr + condition_offset_q;

logic receiver_condition_enable;
assign receiver_condition_enable = condition_valid_q; //(condition_valid_q & !condition_type_q);

// Assign DMA receiver obi request signals
assign dma_receive_obi_req_o.a.we = 1'b0;
assign dma_receive_obi_req_o.req = receiver_obi_req_q;
assign dma_receive_obi_req_o.a.be = 4'b1111;
assign dma_receive_obi_req_o.a.wdata = '0;
assign dma_receive_obi_req_o.a.addr = receiver_obi_addr_q;
assign dma_receive_obi_req_o.a.a_optional = '0;
assign dma_receive_obi_req_o.a.aid = '0;

// FIFO BUFFER REGISTERS, SIGNALS AND INSTANTIATION
// -----------------------------------------------------------------------

// FIFO write side (inputs)
logic fifo_wr_en_d, fifo_wr_en_q;
logic [DataW-1:0] fifo_wr_data_d, fifo_wr_data_q;

// FIFO read side (inputs)
logic fifo_rd_en;

// FIFO outputs
logic fifo_full;
logic fifo_almost_full;
logic fifo_empty;
logic fifo_almost_empty;
logic [DataW-1:0] fifo_rd_data;

logic reset_fifo;
assign reset_fifo = activate_signal_q;

dma_fifo_buffer #(
  .DEPTH(2),
  .DATA_WIDTH(DataW)
) i_dma_fifo_buffer (
  .clk_i          (clk_i),
  .rst_ni         (rst_ni),

  .wr_en_i        (fifo_wr_en_q),
  .wr_data_i      (fifo_wr_data_q),
  .full_o         (fifo_full),
  .almost_full_o  (fifo_almost_full),

  .rd_en_i        (fifo_rd_en),
  .rd_data_o      (fifo_rd_data),
  .empty_o        (fifo_empty),
  .almost_empty_o (fifo_almost_empty),

  .reset_i        (reset_fifo)
);

logic inputs_ready;
assign inputs_ready = !fifo_empty;

// TRANSMITTER STATE MACHINE REGISTERS AND SIGNALS
// -----------------------------------------------------------------------

dma_transmitter_states_t transmitter_state_d, transmitter_state_q;
logic[10:0]       transmitter_counter_d, transmitter_counter_q;
logic             transmitter_obi_req_d, transmitter_obi_req_q;
logic[3:0]        transmitter_obi_be_d, transmitter_obi_be_q;
logic[DataW-1:0]  transmitter_obi_wdata_d, transmitter_obi_wdata_q;
logic[AddrW-1:0]  transmitter_obi_addr_d, transmitter_obi_addr_q;

logic             dma_is_active;
assign            dma_is_active = (transmitter_state_q != TRANSMITTER_IDLE);

// Assign DMA obi transmitter request signal
assign dma_transmit_obi_req_o.a.we = 1'b1;
assign dma_transmit_obi_req_o.req = transmitter_obi_req_q;
assign dma_transmit_obi_req_o.a.be = transmitter_obi_be_q;
assign dma_transmit_obi_req_o.a.wdata = transmitter_obi_wdata_q;
assign dma_transmit_obi_req_o.a.addr = transmitter_obi_addr_q;
assign dma_transmit_obi_req_o.a.a_optional = '0;
assign dma_transmit_obi_req_o.a.aid = '0;


// #############################################################################################################

// ------- PROCESS INCOMING REQUEST TO SETUP THE DMA OR READ STATUS REGISTERS -------------

// Wire the request into the internal buffers
assign req_d    = dma_subordinate_obi_req_i.req;
assign id_d     = dma_subordinate_obi_req_i.a.aid;
assign we_d     = dma_subordinate_obi_req_i.a.we;
assign addr_d   = dma_subordinate_obi_req_i.a.addr;
assign wdata_d  = dma_subordinate_obi_req_i.a.wdata;

always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
  if (!rst_ni) begin
    req_q     <= '0;
    id_q      <= '0;
    we_q      <= '0;
    addr_q    <= '0;
    wdata_q   <= '0;
  end else begin
    req_q     <= req_d;
    id_q      <= id_d;
    we_q      <= we_d;
    addr_q    <= addr_d;
    wdata_q   <= wdata_d;
  end
end

// DMA SETUP LOGIC: Process Incoming Data from Slave Port
// ------------------------------------------------------

// Assign Slave Response Signals
// Always grant immediately, and throw errors if a bad request happened instead
assign dma_subordinate_obi_rsp_o.gnt = dma_subordinate_obi_req_i.req;
assign dma_subordinate_obi_rsp_o.rvalid = req_q;
assign dma_subordinate_obi_rsp_o.r.rdata = rsp_data;
assign dma_subordinate_obi_rsp_o.r.err = rsp_err;
assign dma_subordinate_obi_rsp_o.r.rid = id_q;
assign dma_subordinate_obi_rsp_o.r.r_optional = '0;

// Process Incoming Requests: Update state or send response
logic[7:0] reg_addr;
assign reg_addr = addr_q[9:2] << 2;  // Keep word alignment, supports 256B total space

always_comb begin
  // Internal State
  src_base_addr_d = src_base_addr_q;
  dst_base_addr_d = dst_base_addr_q;
  src_offset_d = src_offset_q;
  dst_offset_d = dst_offset_q;
  num_transfers_d = num_transfers_q;
  interrupt_enable_d = interrupt_enable_q;
  increment_src_d = increment_src_q;
  increment_dst_d = increment_dst_q;
  transfer_size_d = transfer_size_q;

  condition_offset_d = condition_offset_q;
  condition_mask_d = condition_mask_q;
  condition_type_d = condition_type_q;
  condition_negate_d = condition_negate_q;
  condition_valid_d = condition_valid_q;
  
  // Signals to Receiver and Transmitter State Machines
  activate_signal_d = '0;
  interrupt_signal_d = '0;

  // Obi Response Signals
  rsp_data = '0;
  rsp_err = '0;

  stop_irq = '0;

  // If there is a request
  if (req_q) begin
    stop_irq = 1'b1;  // Any read or write to the DMA stops active interrupts if there is one

    // Process write requests
    if (we_q) begin
      if (dma_is_active && reg_addr != REG_INTERRUPT) begin
        rsp_err = 1'b1; // Block writes while DMA is active, unless it's an interrupt
      end else begin
        case (reg_addr)
          REG_SRC_ADDR:     src_base_addr_d = wdata_q;
          REG_DST_ADDR:     dst_base_addr_d = wdata_q;
          REG_CONTROL: begin
            src_offset_d        = wdata_q[31:24];
            dst_offset_d        = wdata_q[23:16];
            num_transfers_d     = wdata_q[15:5];
            interrupt_enable_d  = wdata_q[4];
            increment_src_d     = wdata_q[3];
            increment_dst_d     = wdata_q[2];
            transfer_size_d     = wdata_q[1] ? BYTE : WORD;
            activate_signal_d   = wdata_q[0];
          end
          REG_CONDITION: begin
            condition_offset_d    = wdata_q[31:24];
            condition_mask_d      = wdata_q[23:16];
            condition_type_d      = wdata_q[2] ? WRITE_CONDITION : READ_CONDITION;
            condition_negate_d    = wdata_q[1];
            condition_valid_d     = wdata_q[0];
          end
          REG_INTERRUPT: interrupt_signal_d = 1'b1;
          REG_ACTIVATE:  activate_signal_d = 1'b1;
          default: rsp_err = 1'b1;
        endcase
      end

    // Process read requests
    end else begin
      case (reg_addr)
        REG_SRC_ADDR:   rsp_data = src_base_addr_q;
        REG_DST_ADDR:   rsp_data = dst_base_addr_q;
        REG_CONTROL:    rsp_data = {src_offset_q, dst_offset_q, num_transfers_q, interrupt_enable_q, increment_src_q, increment_dst_q, transfer_size_q, dma_is_active};
        REG_CONDITION:  rsp_data = {condition_offset_q, condition_mask_q, 13'b0, condition_type_q, condition_negate_q, condition_valid_q};
        REG_INTERRUPT:  rsp_data = 32'd1;
        REG_STATUS:     rsp_data = {receiver_counter_q, transmitter_counter_q, 9'b0, dma_is_active};
        default: rsp_err = 1'b1;
      endcase
    end
  end
end

// Internal-State Registers
always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
  if (!rst_ni) begin
    src_base_addr_q         <= '0;
    dst_base_addr_q         <= '0;
    src_offset_q            <= '0;
    dst_offset_q            <= '0;
    num_transfers_q         <= '0;
    interrupt_enable_q      <= '0;
    increment_src_q         <= '0;
    increment_dst_q         <= '0;
    transfer_size_q         <= WORD;

    condition_offset_q      <= '0;
    condition_mask_q        <= '0;
    condition_type_q        <= READ_CONDITION;
    condition_negate_q      <= '0;
    condition_valid_q       <= '0;
    
    activate_signal_q       <= '0;
    interrupt_signal_q      <= '0;
  end else begin
    src_base_addr_q           <= src_base_addr_d;
    dst_base_addr_q           <= dst_base_addr_d;
    src_offset_q              <= src_offset_d;
    dst_offset_q              <= dst_offset_d;
    num_transfers_q           <= num_transfers_d;
    interrupt_enable_q        <= interrupt_enable_d;
    increment_src_q           <= increment_src_d;
    increment_dst_q           <= increment_dst_d;
    transfer_size_q           <= transfer_size_d;

    condition_offset_q        <= condition_offset_d;
    condition_mask_q          <= condition_mask_d;
    condition_type_q          <= condition_type_d;
    condition_negate_q        <= condition_negate_d;
    condition_valid_q         <= condition_valid_d;
    
    activate_signal_q         <= activate_signal_d;
    interrupt_signal_q        <= interrupt_signal_d;
  end
end

// -------- RECEIVER STATE MACHINE -------------

logic[7:0] rcv_condition_satisfied;
always_comb begin: RECEIVER_STATE_MACHINE
  receiver_state_d = receiver_state_q;
  receiver_counter_d = receiver_counter_q;
  receiver_obi_req_d = '0;
  receiver_obi_addr_d = receiver_obi_addr_q;
  source_addr_d = source_addr_q;
  
  fifo_wr_en_d = '0;
  fifo_wr_data_d = fifo_wr_data_q;

  rcv_condition_satisfied = '0;

  case (receiver_state_q)
    REICEIVER_IDLE: begin
      if (activate_signal_q) begin
        if (receiver_condition_enable) begin
          receiver_state_d = RECEIVER_WAIT_FOR_COND_GNT;
          receiver_obi_addr_d = condition_address;
        end else begin
          receiver_state_d = RECEIVER_WAIT_FOR_GNT;
          receiver_obi_addr_d = src_base_addr_q + src_offset_q;
        end
        source_addr_d = src_base_addr_q + src_offset_q;
        receiver_obi_req_d = 1'b1;
        receiver_counter_d = 1'b1;
      end
    end

    REICEVER_WAIT_FOR_FIFO_SPACE: begin
      if (interrupt_signal_q) begin
        receiver_state_d = REICEIVER_IDLE;
      end else begin
        if (!fifo_full) begin
          if (receiver_condition_enable) begin
            receiver_obi_addr_d = condition_address;
            receiver_state_d = RECEIVER_WAIT_FOR_COND_GNT;
          end else begin
            receiver_obi_addr_d = source_addr_q;
            receiver_state_d = RECEIVER_WAIT_FOR_GNT;
          end
          receiver_obi_req_d = 1'b1;
        end
      end
    end

    RECEIVER_WAIT_FOR_COND_GNT: begin
      if (interrupt_signal_q) begin
        receiver_state_d = REICEIVER_IDLE;
      end else begin
        if (dma_receive_obi_rsp_i.gnt) begin
          receiver_state_d = RECEIVER_WAIT_FOR_COND_RVALID;
        end else begin // request hasn't been granted yet, request again
          receiver_obi_req_d = 1'b1;
        end
      end
    end

    RECEIVER_WAIT_FOR_COND_RVALID: begin
      if (interrupt_signal_q) begin
        receiver_state_d = REICEIVER_IDLE;
      end else begin
        if (dma_receive_obi_rsp_i.rvalid && !dma_receive_obi_rsp_i.r.err) begin
          rcv_condition_satisfied = dma_receive_obi_rsp_i.r.rdata >> (8 * receiver_obi_addr_q[1:0]) & 8'hFF;

          rcv_condition_satisfied = rcv_condition_satisfied & condition_mask_q;
          if (condition_negate_q) begin
            rcv_condition_satisfied = !rcv_condition_satisfied;
          end

          if (rcv_condition_satisfied) begin
            receiver_state_d = RECEIVER_WAIT_FOR_GNT;
            receiver_obi_addr_d = source_addr_q;
          end else begin
            receiver_state_d = RECEIVER_WAIT_FOR_COND_GNT;
          end
          receiver_obi_req_d = 1'b1;
        end
      end
    end

    RECEIVER_WAIT_FOR_GNT: begin
      if (interrupt_signal_q) begin
        receiver_state_d = REICEIVER_IDLE;
      end else begin
        if (dma_receive_obi_rsp_i.gnt) begin
          receiver_state_d = REICEVER_WAIT_FOR_RVALID;
        end else begin // request hasn't been granted yet, request again
          receiver_obi_req_d = 1'b1;
        end
      end
    end

    REICEVER_WAIT_FOR_RVALID: begin
      if (interrupt_signal_q) begin
        receiver_state_d = REICEIVER_IDLE;
      end else begin
        if (dma_receive_obi_rsp_i.rvalid && !dma_receive_obi_rsp_i.r.err) begin
          fifo_wr_en_d = 1'b1;
          if (transfer_size_q == BYTE) begin
            // fifo_wr_data_d = (dma_receive_obi_rsp_i.r.rdata >> (8 * (source_addr_q % 4))) & 32'hFF;
            // fifo_wr_data_d = (dma_receive_obi_rsp_i.r.rdata >> (source_addr_q[1:0] << 3)) & 32'hFF;
            case (source_addr_q[1:0])
              2'b00: fifo_wr_data_d = {24'b0, dma_receive_obi_rsp_i.r.rdata[7:0]};
              2'b01: fifo_wr_data_d = {24'b0, dma_receive_obi_rsp_i.r.rdata[15:8]};
              2'b10: fifo_wr_data_d = {24'b0, dma_receive_obi_rsp_i.r.rdata[23:16]};
              2'b11: fifo_wr_data_d = {24'b0, dma_receive_obi_rsp_i.r.rdata[31:24]};
              default: fifo_wr_data_d = fifo_wr_data_q;
            endcase
          end else begin
            fifo_wr_data_d = dma_receive_obi_rsp_i.r.rdata;
          end

          receiver_counter_d = receiver_counter_q + 1;
          if (increment_src_q) begin
            if (transfer_size_q == BYTE) source_addr_d = source_addr_q + 1;
            else                         source_addr_d = source_addr_q + 4;
          end

          if (receiver_counter_q == num_transfers_q) begin
            receiver_state_d = REICEIVER_IDLE;
          end else if (!fifo_almost_full) begin

            if (receiver_condition_enable) begin
              receiver_state_d = RECEIVER_WAIT_FOR_COND_GNT;
              receiver_obi_addr_d = condition_address;
            end else begin
              receiver_state_d = RECEIVER_WAIT_FOR_GNT;
              receiver_obi_addr_d = source_addr_d;
            end

            receiver_obi_req_d = 1'b1;

          end else begin
            receiver_state_d = REICEVER_WAIT_FOR_FIFO_SPACE;
          end
        end
      end
    end

    default: receiver_state_d = REICEIVER_IDLE;
  endcase
end

always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
  if (!rst_ni) begin
    receiver_state_q    <= REICEIVER_IDLE;
    receiver_counter_q  <= '0;
    receiver_obi_req_q  <= '0;
    receiver_obi_addr_q <= '0;
    source_addr_q       <= '0;
    
    fifo_wr_en_q        <= '0;
    fifo_wr_data_q      <= '0;
  end else begin
    receiver_state_q    <= receiver_state_d;
    receiver_counter_q  <= receiver_counter_d;
    receiver_obi_req_q  <= receiver_obi_req_d;
    receiver_obi_addr_q <= receiver_obi_addr_d;
    source_addr_q       <= source_addr_d;

    fifo_wr_en_q        <= fifo_wr_en_d;
    fifo_wr_data_q      <= fifo_wr_data_d;
  end
end

// -------- TRANSMITTER STATE MACHINE -----------

always_comb begin: TRANSMITTER_STATE_MACHINE
  transmitter_state_d = transmitter_state_q;
  transmitter_counter_d = transmitter_counter_q;
  transmitter_obi_req_d = '0;
  transmitter_obi_be_d = transmitter_obi_be_q;
  transmitter_obi_wdata_d = transmitter_obi_wdata_q;

  transmitter_obi_addr_d = transmitter_obi_addr_q;

  activate_irq = '0;
  fifo_rd_en = '0;

  case (transmitter_state_q)

    TRANSMITTER_IDLE: begin
      if (activate_signal_q) begin
        transmitter_counter_d = 11'd1;
        transmitter_state_d = TRANSMITTER_WAIT_FOR_NEW_INPUTS;
        transmitter_obi_addr_d = dst_base_addr_q + dst_offset_q;
      end
    end

    TRANSMITTER_WAIT_FOR_NEW_INPUTS: begin
      if (interrupt_signal_q) begin
        transmitter_state_d = TRANSMITTER_IDLE;
      end else if (inputs_ready) begin

        // Read the inputs from the fifo buffer and set correct byte enable
        if (transfer_size_q == BYTE) begin
          transmitter_obi_wdata_d = {fifo_rd_data[7:0], fifo_rd_data[7:0], fifo_rd_data[7:0], fifo_rd_data[7:0]};
          transmitter_obi_be_d = 4'b0001 << (transmitter_obi_addr_q % 4);
        end else begin
          transmitter_obi_wdata_d = fifo_rd_data;
          transmitter_obi_be_d = 4'b1111;
        end
        
        fifo_rd_en = 1'b1;  // Tell the fifo that we read the inputs.
        transmitter_obi_req_d = 1'b1;  // Send a write request
        transmitter_state_d = TRANSMITTER_WAIT_FOR_GNT;  // Switch to state which waits until the write request is granted

      end else begin
        transmitter_state_d = TRANSMITTER_WAIT_FOR_NEW_INPUTS;
      end
    end

    TRANSMITTER_WAIT_FOR_GNT: begin
      if (interrupt_signal_q) begin
        transmitter_state_d = TRANSMITTER_IDLE;
      end else begin

        // Write request has been granted.
        // Update counters and setup next phase
        if (dma_transmit_obi_rsp_i.gnt) begin

          // Increase counter to check if finished
          transmitter_counter_d = transmitter_counter_q + 1;

          // Increase address and set proper byte_enable
          if (increment_dst_q) begin
            if (transfer_size_q == BYTE) begin
              transmitter_obi_addr_d = transmitter_obi_addr_q + 1;
              transmitter_obi_be_d = 4'b0001 << ((transmitter_obi_addr_q + 1) % 4);
            end else begin
              transmitter_obi_addr_d = transmitter_obi_addr_q + 4;
            end
          end

          // Check if finished or if new inputs are ready
          if (transmitter_counter_q == num_transfers_q) begin
            transmitter_state_d = TRANSMITTER_IDLE;
            if (interrupt_enable_q) begin
              activate_irq = 1'b1;
            end
          end else if (inputs_ready) begin

            // Read the inputs from the fifo buffer and set correct byte enable
            if (transfer_size_q == BYTE) begin
              transmitter_obi_wdata_d = {fifo_rd_data[7:0], fifo_rd_data[7:0], fifo_rd_data[7:0], fifo_rd_data[7:0]};
            end else begin
              transmitter_obi_wdata_d = fifo_rd_data;
            end

            fifo_rd_en = 1'b1;  // Tell the fifo that we read the inputs.
            transmitter_obi_req_d = 1'b1;  // Send an obi request.
            transmitter_state_d = TRANSMITTER_WAIT_FOR_GNT;
          end else begin
            transmitter_obi_req_d = 1'b0;
            transmitter_state_d = TRANSMITTER_WAIT_FOR_NEW_INPUTS;
          end
        
        // Else still waiting for grant, so keep requesting with same data
        end else begin
          transmitter_obi_req_d = 1'b1;
        end
      end
    end

    default: transmitter_state_d = TRANSMITTER_IDLE;
  endcase
end

always_ff @(posedge (clk_i) or negedge (rst_ni)) begin

  if (!rst_ni) begin
    transmitter_state_q       <= TRANSMITTER_IDLE;
    transmitter_counter_q     <= '0;
    transmitter_obi_req_q     <= '0;
    transmitter_obi_be_q      <= '0;
    transmitter_obi_wdata_q   <= '0;
    transmitter_obi_addr_q    <= '0;
  end else begin
    transmitter_state_q       <= transmitter_state_d;
    transmitter_counter_q     <= transmitter_counter_d;
    transmitter_obi_req_q     <= transmitter_obi_req_d;
    transmitter_obi_be_q      <= transmitter_obi_be_d;
    transmitter_obi_wdata_q   <= transmitter_obi_wdata_d;
    transmitter_obi_addr_q    <= transmitter_obi_addr_d;
  end

end

endmodule