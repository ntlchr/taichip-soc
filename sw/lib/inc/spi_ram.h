#pragma once

#include <stdint.h>

// Driver for the spi_slave_ram RTL device (see rtl/spi/spi_slave_ram.sv).
//
// Length-counted wire frame (no CS-rise delimiter):
//
//   [cmd_word_hi][cmd_word_lo][addr_hi][addr_lo][data ...]
//     cmd_word = {cmd[1:0], length[13:0]} (big-endian), length = data byte count
//
// Both calls arm the DMA with its completion IRQ enabled and return WITHOUT
// blocking on the transfer (just like dma.c's spi_*_dma). Wait for completion
// from the caller via wfi (DMA IRQ 20) or by polling dma_busy() / SPI_BUSY.
//
// Assumes the slave is built with ADDR_WIDTH = 16 (2 address bytes).
// Call spi_init(SPI_MODE_0, clk_divider) once before using these.
//
// Note: the DMA num_transfers field is 11 bits, so a single call moves at most
// 2047 bytes (header included); chunk larger transfers in the caller.

// Number of header/dummy bytes in the READ frame (internal, not visible to
// caller). = {cmd,len}(2) + address(2) + dummy(1).
#define SPI_RAM_READ_HDR  5

// Write `len` bytes from `src` into the SPI RAM starting at `addr`.
// Non-blocking: arms the DMA (IRQ enabled) and returns.
void spi_ram_write_dma(uint16_t addr, const uint8_t *src, uint16_t len);

// Read `len` bytes from the SPI RAM starting at `addr`.
// Non-blocking: arms the DMA (IRQ enabled) and returns.
// `dst` must hold `len` bytes; on completion the payload is at dst[0].
void spi_ram_read_dma(uint16_t addr, uint8_t *dst, uint16_t len);
