#include "dma.h"
#include "util.h"
#include "config.h"
#include "uart.h"
#include "spi.h"


static volatile uint32_t* const dma_src_reg         = DMA_REG(DMA_SRC_REG_OFFSET);
static volatile uint32_t* const dma_dst_reg         = DMA_REG(DMA_TGT_REG_OFFSET);
static volatile uint32_t* const dma_ctrl_reg        = DMA_REG(DMA_CONTROL_REG_OFFSET);
static volatile uint32_t* const dma_cond_reg        = DMA_REG(DMA_CONDITION_REG_OFFSET);
static volatile uint32_t* const dma_activate_reg    = DMA_REG(DMA_ACTIVATE_OFFSET);
static volatile uint32_t* const dma_irq_reg         = DMA_REG(DMA_INTERRUPT_OFFSET);
static volatile uint32_t* const dma_status_reg      = DMA_REG(DMA_STATUS_OFFSET);


void program_dma(uint32_t src_addr, uint32_t dst_addr, dma_control_t controls, dma_condition_t condition) {
    *dma_src_reg    = src_addr;
    *dma_dst_reg    = dst_addr;
    *dma_cond_reg   = condition;
    *dma_ctrl_reg   = controls;
}


void activate_dma() {
    *dma_activate_reg = 1;
}


void interrupt_dma() {
    do {
        *dma_irq_reg = 1;
    } while (dma_busy());
}


dma_status_t read_dma_status() {
    uint32_t raw_status = *dma_status_reg;

    dma_status_t status = {
        .completed_receives =      (raw_status >> DMA_STATUS_COMPLETED_RCVS_SHIFT) & DMA_STATUS_COMPLETED_RCVS_MASK -1,
        .completed_transmissions = (raw_status >> DMA_STATUS_COMPLETED_TRMS_SHIFT) & DMA_STATUS_COMPLETED_TRMS_MASK -1,
        .active =                  (raw_status >> DMA_STATUS_ACTIVE_SHIFT) & DMA_STATUS_ACTIVE_MASK
    };

    return status;
}


void uart_read_dma(uint8_t* destination_array, uint8_t num_bytes) {
    *dma_src_reg = UART_BASE_ADDR;
    *dma_dst_reg = (uint32_t) destination_array;
    *dma_cond_reg = DMA_COND(UART_LINE_STATUS_REG_OFFSET, 1 << UART_LINE_STATUS_DATA_READY_BIT, DMA_COND_SRC_BASE, 0, 1);
    *dma_ctrl_reg = DMA_CTRL(UART_RBR_REG_OFFSET, 0, num_bytes, 1, 0, 1, DMA_TRANSFER_BYTE, 1);
}


void uart_write_dma(uint8_t* source_array, uint8_t num_bytes) {
    *dma_src_reg = (uint32_t) source_array;
    *dma_dst_reg = UART_BASE_ADDR;
    *dma_cond_reg = DMA_COND(UART_LINE_STATUS_REG_OFFSET, 1 << UART_LINE_STATUS_THR_EMPTY_BIT, DMA_COND_DST_BASE, 0, 1);
    *dma_ctrl_reg = DMA_CTRL(0, UART_THR_REG_OFFSET, num_bytes, 1, 1, 0, DMA_TRANSFER_BYTE, 1);
}


void spi_write_dma(uint8_t* source_array, uint16_t num_bytes) {
    while(SPI_BUSY);

    // Configure and start DMA
    *dma_src_reg = (uint32_t) source_array;
    *dma_dst_reg = (uint32_t) SPI_BASE_ADDR;
    *dma_cond_reg = DMA_COND(SPI_FIFOSTAT_OFFSET, SPI_STATUS_TX_ALMOST_FULL_MASK, DMA_COND_DST_BASE, 0, 1);
    *dma_ctrl_reg = DMA_CTRL(0, SPI_TX_REG_OFFSET, num_bytes, 1, 1, 0, DMA_TRANSFER_BYTE, 1);

    // Configure and start SPI
    SPI_LENGTH = num_bytes - 1;
    SPI_CTRL = 0x1;
}


// initialize the SPI with spi_init()
void spi_read_dma(uint8_t* destination_array, uint16_t num_bytes) {
    while(SPI_BUSY);
    spi_empty_rx();
    
    // Configure and start DMA
    *dma_src_reg = (uint32_t) SPI_BASE_ADDR;
    *dma_dst_reg = (uint32_t) destination_array;
    *dma_cond_reg = DMA_COND(SPI_FIFOSTAT_OFFSET, SPI_STATUS_RX_EMPTY_MASK, DMA_COND_SRC_BASE, 1, 1);
    *dma_ctrl_reg = DMA_CTRL(SPI_RX_REG_OFFSET, 0, num_bytes, 1, 0, 1, DMA_TRANSFER_BYTE, 1);
    
    // Configure and start SPI
    SPI_LENGTH = num_bytes - 1;
    SPI_CTRL = 0x1;
}


void* memcpy_dma(void* dst, const void* src, unsigned num_bytes) {
    dma_control_t controls;

    if ((num_bytes & 3) == 0 && (((uint32_t) src & 3) == 0) && (((uint32_t) dst & 3) == 0)) {
        unsigned num_words = num_bytes >> 2;
        controls = DMA_CTRL(0, 0, num_words, 1, 1, 1, DMA_TRANSFER_WORD, 1);
    } else {
        controls = DMA_CTRL(0, 0, num_bytes, 1, 1, 1, DMA_TRANSFER_BYTE, 1);
    }

    *dma_src_reg = (uint32_t) src;
    *dma_dst_reg = (uint32_t) dst;
    *dma_cond_reg = 0;
    *dma_ctrl_reg = controls;
    return dst;
}


static volatile uint8_t dma_memset_fill_value;
void* memset_dma(void* ptr, int value, unsigned num) {
    dma_memset_fill_value = value;
    *dma_src_reg = (uint32_t) &dma_memset_fill_value;
    *dma_dst_reg = (uint32_t) ptr;
    *dma_cond_reg = 0;
    *dma_ctrl_reg = DMA_CTRL(0, 0, num, 1, 0, 1, DMA_TRANSFER_BYTE, 1);
    return ptr;
}