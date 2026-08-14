// Copyright (c) 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0/
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
//
// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for TAICHIP-1 SoC by:
// - Abdelmadjid Dahmani (TalTech)
// - Natalia Cherezova (TalTech)

#include "spi.h"
#include "spi_ram.h"
#include "uart.h"
#include "print.h"
#include "timer.h"
#include "gpio.h"
#include "util.h"
#include "dma.h"
#include <stdint.h>

void print_array(uint8_t* arr, uint16_t len) {
    uart_write('[');
    for (int i = 0; i < len - 1; i++) {
        uart_write(arr[i]);
        uart_write(',');
        uart_write(' ');
    }
    uart_write(arr[len-1]);
    uart_write(']');
    uart_write('\n');
}

uint8_t buffer[4];
uint8_t buffer2[4];


int main() {
	// UART setup
    uart_init();
    // Simple printf support (prints only text and hex numbers)
    printf("Hello World!\n");
    // Wait until UART has finished sending
    uart_write_flush();
	
	// GPIO test
    gpio_set_direction(0xFFFF, 0x000F); // Set the first four as outputs
    gpio_write(0x0A);  // Output pattern
    gpio_enable(0xFF); // Enable the first eight
    // Wait a few cycles to give GPIO signal time to propagate
    asm volatile ("nop; nop; nop; nop; nop;");
    printf("GPIO test (expect 0xA0): 0x%x\n", gpio_read());

    // SPI + DMA test
    spi_init(SPI_MODE_0, 8);

    enable_dma_irq();
    spi_ram_read_dma(0, buffer, 3);
    while (dma_busy()) {
        wfi();
    }       

    printf("SPI + DMA test read (expect AB CD EF): %x %x %x\n", buffer[0], buffer[1], buffer[2]);
    uart_write_flush();

    for (int i = 0; i < 4; ++i) {
        buffer[i] = i;
    }

    enable_dma_irq();
    spi_ram_write_dma(0, buffer, 4);
    while (dma_busy()) {
        wfi();
    }

    enable_dma_irq();
    spi_ram_read_dma(0, buffer2, 4);
    while (dma_busy()) {
        wfi();
    }       

    printf("SPI + DMA test write and read (expect 0 to 3): %u %u %u %u\n", buffer2[0], buffer2[1], buffer2[2], buffer2[3]);
    uart_write_flush();

    return 1;
}
