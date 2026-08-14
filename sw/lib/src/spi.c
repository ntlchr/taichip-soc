#include "spi.h"
#include "util.h"
#include "config.h"
#include <stdio.h>
#include <stdint.h>


// Write data via SPI, bytes sent into TX are shifted out in FIFO order
void spi_write(uint8_t *data, uint16_t length) {
    while(SPI_BUSY);
    uint8_t control = 0x1;
    uint16_t cnt = 0;
    while (!(SPI_FIFOSTAT & SPI_STATUS_TX_ALMOST_FULL) && (cnt <length)){
            SPI_TX =  data[cnt];
            cnt++;
    };
    SPI_LENGTH = length -1;
    SPI_CTRL = control;
    while (cnt <length){
        if(!(SPI_FIFOSTAT & SPI_STATUS_TX_ALMOST_FULL)){
            SPI_TX =  data[cnt];
            cnt++;
        }
    };
}


// Read data from SPI, bytes are received in FIFO order
void spi_read(uint8_t *data, uint16_t length) {
    while(SPI_BUSY);
    spi_empty_rx();
    uint8_t control = 0x1;
    SPI_LENGTH = length -1;
    SPI_CTRL = control;
    uint16_t cnt = 0;
    while(cnt < length){
        if(!(SPI_FIFOSTAT & SPI_STATUS_RX_EMPTY_MASK)){
            data[cnt] = SPI_RX;
            cnt ++;
        }
    }
}

void spi_read_write(uint8_t* data_tx, uint8_t* data_rx,  uint16_t num_bytes) {
    while(SPI_BUSY);
    spi_empty_rx();
    const uint8_t control = 0x1;
    SPI_LENGTH = num_bytes -1;
    uint16_t tx_cnt = 0;
    uint16_t rx_cnt = 0;

    while (!(SPI_FIFOSTAT & SPI_STATUS_TX_ALMOST_FULL) && (tx_cnt <num_bytes)){
            SPI_TX =  data_tx[tx_cnt];
            tx_cnt++;
    };
    SPI_CTRL = control;
    while ((tx_cnt < num_bytes) || (rx_cnt < num_bytes)){
        if(!(SPI_FIFOSTAT & SPI_STATUS_TX_ALMOST_FULL)) {
            SPI_TX=data_tx[tx_cnt];
            tx_cnt ++;
        }
        if(!(SPI_FIFOSTAT & SPI_STATUS_RX_EMPTY_MASK)){
            data_rx[rx_cnt] = SPI_RX;
            rx_cnt ++;
        }
    };
}

// clears the buffer only once, if you want to clear it after a write you need to wait for the write to be finished
void spi_empty_rx(){
    uint8_t dummy;
    while (!(SPI_FIFOSTAT & SPI_STATUS_RX_EMPTY_MASK)) {
            dummy = SPI_RX;
    }
}

void spi_init(uint8_t spi_mode, uint16_t clk_divider){
    SPI_FREQ = clk_divider;
    SPI_MODE_CTRL = spi_mode;
    
}