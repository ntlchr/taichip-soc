#include "spi_ram.h"
#include "spi.h"
#include "dma.h"
#include "config.h"
#include <stdint.h>

// Command opcodes (2-bit cmd field) -- must match rtl/spi/spi_slave_ram.sv.
#define SPI_RAM_CMD_WRITE  0x1
#define SPI_RAM_CMD_READ   0x2

// Address bytes in the frame; must match ADDR_BYTES = ceil(ADDR_WIDTH/8).
#define SPI_RAM_ADDR_BYTES 2

// Bytes clocked before the data phase.
#define SPI_RAM_CMD_BYTES  2                                  // {cmd, length} word
#define SPI_RAM_WRITE_HDR  (SPI_RAM_CMD_BYTES + SPI_RAM_ADDR_BYTES)   // 4



static inline void spi_ram_push_read_header(uint16_t addr, uint16_t len) {
    uint8_t tx_data[5];
    tx_data[0] = (uint8_t)((SPI_RAM_CMD_READ << 6) | ((len >> 8) & 0x3F));
    tx_data[1] = (uint8_t)(len & 0xFF);
    tx_data[2] = (uint8_t)(addr >> 8);
    tx_data[3] = (uint8_t)(addr & 0xFF);
    tx_data[4] = 0xff;  // dummy turnaround: slave needs it before driving data
    spi_write(tx_data, 5);
}


void spi_ram_write_dma(uint16_t addr, const uint8_t *src, uint16_t len) {
    while (SPI_BUSY);
    spi_empty_rx();

    // Header must be queued before the transfer starts: if SPI and DMA start
    // together on an empty FIFO the master shifts a garbage byte before the DMA
    // can fill it, landing in mem[0] and shifting the whole payload by one.
    SPI_TX = (uint8_t)((SPI_RAM_CMD_WRITE << 6) | ((len >> 8) & 0x3F));
    SPI_TX = (uint8_t)(len & 0xFF);
    SPI_TX = (uint8_t)(addr >> 8);
    SPI_TX = (uint8_t)(addr & 0xFF);

    // Non-blocking: IRQ enabled, returns immediately -- poll dma_busy()/SPI_BUSY.
    *DMA_REG(DMA_SRC_REG_OFFSET)       = (uint32_t) src;
    *DMA_REG(DMA_TGT_REG_OFFSET)       = (uint32_t) SPI_BASE_ADDR;
    *DMA_REG(DMA_CONDITION_REG_OFFSET) =
        DMA_COND(SPI_FIFOSTAT_OFFSET, SPI_STATUS_TX_ALMOST_FULL_MASK, DMA_COND_DST_BASE, 0, 1);
    *DMA_REG(DMA_CONTROL_REG_OFFSET)   =
        DMA_CTRL(0, SPI_TX_REG_OFFSET, len, 1, 1, 0, DMA_TRANSFER_BYTE, 1);

    SPI_LENGTH = (SPI_RAM_WRITE_HDR + len) - 1;
    SPI_CTRL   = 0x1;
}


void spi_ram_read_dma(uint16_t addr, uint8_t *dst, uint16_t len) {
    while (SPI_BUSY);
    spi_ram_push_read_header(addr, len);
    while (SPI_BUSY);
    spi_empty_rx();

    // Split transaction: the header is clocked above, then a second transfer
    // captures only the payload so it lands at dst[0]. Relies on the slave
    // holding parser state across CS windows (no cs_falling reset in RTL).
    // Non-blocking: IRQ enabled, returns immediately -- poll dma_busy()/SPI_BUSY.
    *DMA_REG(DMA_SRC_REG_OFFSET)       = (uint32_t) SPI_BASE_ADDR;
    *DMA_REG(DMA_TGT_REG_OFFSET)       = (uint32_t) dst;
    *DMA_REG(DMA_CONDITION_REG_OFFSET) =
        DMA_COND(SPI_FIFOSTAT_OFFSET, SPI_STATUS_RX_EMPTY_MASK, DMA_COND_SRC_BASE, 1, 1);
    *DMA_REG(DMA_CONTROL_REG_OFFSET)   =
        DMA_CTRL(SPI_RX_REG_OFFSET, 0, len, 1, 0, 1, DMA_TRANSFER_BYTE, 1);

    SPI_LENGTH = len - 1;
    SPI_CTRL   = 0x1;
}
