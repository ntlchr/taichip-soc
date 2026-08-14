// interrupts.h
#ifndef INTERRUPTS_H
#define INTERRUPTS_H

// Header file to expose weak user irq handlers.
// The interrupt handlers called directly by the core, are not exposed
// and directly implemented in interrupts.c

// --------------------------------------------------------------------------------
// IRQ 19: DMA INTERRUPT
// --------------------------------------------------------------------------------

// Weak user handler for DMA IRQ, meant to be overridden by user code
void __attribute__((weak)) dma_irq_handler_user(void);

// --------------------------------------------------------------------------------

#endif // INTERRUPTS_H
