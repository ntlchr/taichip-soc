#pragma once

#include <stdint.h>
#include "config.h"

#define SPI_CTRL        (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x000))  // control[7]? UNLIMITED_MODE: LENGTH_MODE, control[0] = ready flag
#define SPI_STATUS      (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x004))  // Number of bytes the SPI has transferred since it was started
#define SPI_TX          (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x008))  // write Bytes here to be transferred by SPI
#define SPI_RX          (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x00C))  // Read Bytes that the SPi received
#define SPI_LENGTH      (*(volatile uint16_t *)(SPI_BASE_ADDR + 0x018)) // Length of the transaction, to be set before ctrl flag
#define SPI_FIFOSTAT    (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x01C))  // returns status of tx and rx fifo buffer, 
                                                                        //                  READ-BUFFER                                   WRITE-BUFFER      
                                                                        // FULL | ALMOST_FULL | EMPTY | ALMOST EMPTY |      FULL | ALMOST_FULL | EMPTY | ALMOST EMPTY |

#define SPI_MODE_CTRL   (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x020))  // Controls SPI mode, mode_control[0] = CPOL, mode_control[1] = CPHA
#define SPI_BUSY        (*(volatile uint8_t *)(SPI_BASE_ADDR + 0x024))  // returns 1 if the spi is busy, else 0
#define SPI_FREQ        (*(volatile uint16_t *)(SPI_BASE_ADDR + 0x028)) // set the factor the clock is divided by fot SCLK



#define SPI_STATUS_RX_EMPTY_MASK            0x20
#define SPI_FIFOSTAT_OFFSET                 0x1C
#define SPI_STATUS_TX_ALMOST_FULL_MASK      0x3
#define SPI_TX_REG_OFFSET                   0x8
#define SPI_RX_REG_OFFSET                   0xC
#define SPI_STATUS_TX_ALMOST_FULL           0x4

#define SPI_MODE_0                          0x00
#define SPI_MODE_1                          0x02
#define SPI_MODE_2                          0x01
#define SPI_MODE_3                          0x03


// SPI read/write interface
void spi_read(uint8_t* destination_array, uint16_t num_bytes);
void spi_write(uint8_t* source_array, uint16_t num_bytes);
void spi_read_write(uint8_t* data_tx, uint8_t* data_rx,  uint16_t num_bytes);
void spi_empty_rx();
void spi_init(uint8_t spi_mode, uint16_t clk_divider);