// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Authors:
//    Lionel Noussi <lnoussi@ethz.ch> <lio.noussi@gmail.com>


module dma_interrupt_handler (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic activate_irq_i,  // signal from DMA logic to raise IRQ
  input  logic stop_irq_i,      // signal from DMA logic or CPU to clear IRQ

  output logic dma_irq_o        // output interrupt line
);

  logic dma_irq_d, dma_irq_q;

  always_comb begin
    dma_irq_d = dma_irq_q; // default hold current state

    if (activate_irq_i) begin
      dma_irq_d = 1'b1;   // raise IRQ
    end else if (stop_irq_i) begin
      dma_irq_d = 1'b0;   // clear IRQ
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dma_irq_q <= '0;
    end else begin
      dma_irq_q <= dma_irq_d;
    end
  end

  assign dma_irq_o = dma_irq_q;

endmodule
