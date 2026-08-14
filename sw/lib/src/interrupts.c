#include "interrupts.h"
#include "dma.h"


// Implementations of all registered interrupt handlers.
// The interrupt vector table is defined in crt0.S
// Functions like handle_irq_## handle and turn off the interrupt
// Afterwards they call weak user functions, allowing the user to define
// custom instructions afterwards.

// --------------------------------------------------------------------------------
// IRQ 20: DMA INTERRUPT
// --------------------------------------------------------------------------------
void __attribute__((interrupt)) handle_irq_20(void) {
    *DMA_REG(DMA_INTERRUPT_OFFSET);  // clear interrupt
    dma_irq_handler_user();          // call user override
}

void __attribute__((weak)) dma_irq_handler_user(void) {
    // Default empty user handler for dma interrupts
}
// --------------------------------------------------------------------------------