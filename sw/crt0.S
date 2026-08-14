# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Paul Scheffler <paulsc@iis.ee.ethz.ch>
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

.globl _start
.section .text._start
_start:
  # Global pointer
  .option push
  .option norelax
  la      x3, __global_pointer$
  .option pop
  # Stack pointer
  la      x2, __stack_pointer$
  # Reset vector
  li      x1, 0
  li      x4, 0
  li      x5, 0
  li      x6, 0
  li      x7, 0
  li      x8, 0
  li      x9, 0
  li      x10, 0
  li      x11, 0
  li      x12, 0
  li      x13, 0
  li      x14, 0
  li      x15, 0
  # Setup interrupt handlers
  la      t0, __interupt_table
  ori  t0, t0, 1
  csrw    mtvec, t0  # Set mtvec to point to our vector table
  # Call Main Function
  call main
  j _eoc

.globl _eoc
_eoc:
  la      t0, status
  sw      a0, 0(t0)
  wfi



// ------------------------------------------------------------------------------------
// INTERRUPTS
// ------------------------------------------------------------------------------------

# mtvec will point to the beginning of this table
# when an interrupt or exception occurs, it will jump to mtvec + exception id
# exception IDs can be found in cve2_pkg.sv
# interrupt handlers are implemented in interrupts.c
.section .text.__interupt_table
.globl __interupt_table
.align 8
__interupt_table:
  j _eoc            # IRQ 0
  j _eoc            # IRQ 1
  j _eoc            # IRQ 2
  j _eoc            # IRQ 3
  j _eoc            # IRQ 4
  j _eoc            # IRQ 5
  j _eoc            # IRQ 6
  j _eoc            # IRQ 7
  j _eoc            # IRQ 8
  j _eoc            # IRQ 9
  j _eoc            # IRQ 10
  j _eoc            # IRQ 11
  j _eoc            # IRQ 12
  j _eoc            # IRQ 13
  j _eoc            # IRQ 14
  j _eoc            # IRQ 15
  j _eoc            # IRQ 16
  j _eoc            # IRQ 17
  j _eoc            # IRQ 18
  j _eoc            # IRQ 19
  j handle_irq_20   # IRQ 20
  j _eoc            # IRQ 21
  j _eoc            # IRQ 22
  j _eoc            # IRQ 23
  j _eoc            # IRQ 24
  j _eoc            # IRQ 25
  j _eoc            # IRQ 26
  j _eoc            # IRQ 27
  j _eoc            # IRQ 28
  j _eoc            # IRQ 29
  j _eoc            # IRQ 30
  j _eoc            # IRQ 31