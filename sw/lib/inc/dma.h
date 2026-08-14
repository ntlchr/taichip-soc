#ifndef DMA_H
#define DMA_H

#include <stdint.h>

// -----------------------------------------------------------------------------
// DMA Address Map
// -----------------------------------------------------------------------------
#define DMA_BASE_ADDR               0x50000000

#define DMA_SRC_REG_OFFSET          0x0
#define DMA_TGT_REG_OFFSET          0x4
#define DMA_CONTROL_REG_OFFSET      0x8
#define DMA_CONDITION_REG_OFFSET    0xC
#define DMA_INTERRUPT_OFFSET        0x10
#define DMA_ACTIVATE_OFFSET         0x14
#define DMA_STATUS_OFFSET           0x18

#define DMA_REG(offset) ((volatile uint32_t*)(DMA_BASE_ADDR + (offset)))

// -----------------------------------------------------------------------------
// DMA Options (Control Register)
// -----------------------------------------------------------------------------

// Bit positions
#define DMA_CTRL_SRC_OFFSET_SHIFT         24
#define DMA_CTRL_DST_OFFSET_SHIFT         16
#define DMA_CTRL_NUM_TRANSFERS_SHIFT      5
#define DMA_CTRL_IRQ_ENABLE_SHIFT         4
#define DMA_CTRL_INC_SRC_SHIFT            3
#define DMA_CTRL_INC_DEST_SHIFT           2
#define DMA_CTRL_TRANSFER_SIZE_SHIFT      1
#define DMA_CTRL_ACTIVATE_SHIFT           0

// Bit masks
#define DMA_CTRL_SRC_OFFSET_MASK          0xFF
#define DMA_CTRL_DST_OFFSET_MASK          0xFF
#define DMA_CTRL_NUM_TRANSFERS_MASK       0x7FF
#define DMA_CTRL_IRQ_ENABLE_MASK          0x1
#define DMA_CTRL_INC_MASK                 0x1
#define DMA_CTRL_TRANSFER_SIZE_MASK       0x1
#define DMA_CTRL_ACTIVATE_MASK            0x1

// DMA Transfer Size Enum
typedef enum {
    DMA_TRANSFER_WORD = 0,
    DMA_TRANSFER_BYTE = 1
} dma_transfer_size_t;

// DMA control word type from control macro
typedef uint32_t dma_control_t;

#define DMA_CTRL(src_off, dst_off, n_trans, irq, inc_s, inc_d, size, act) \
    (((src_off)     & DMA_CTRL_SRC_OFFSET_MASK)      << DMA_CTRL_SRC_OFFSET_SHIFT)     | \
    (((dst_off)     & DMA_CTRL_DST_OFFSET_MASK)      << DMA_CTRL_DST_OFFSET_SHIFT)     | \
    (((n_trans)     & DMA_CTRL_NUM_TRANSFERS_MASK)   << DMA_CTRL_NUM_TRANSFERS_SHIFT)  | \
    (((irq)         & DMA_CTRL_IRQ_ENABLE_MASK)      << DMA_CTRL_IRQ_ENABLE_SHIFT)     | \
    (((inc_s)       & DMA_CTRL_INC_MASK)             << DMA_CTRL_INC_SRC_SHIFT)        | \
    (((inc_d)       & DMA_CTRL_INC_MASK)             << DMA_CTRL_INC_DEST_SHIFT)       | \
    (((size)        & DMA_CTRL_TRANSFER_SIZE_MASK)   << DMA_CTRL_TRANSFER_SIZE_SHIFT)  | \
    (((act)         & DMA_CTRL_ACTIVATE_MASK)        << DMA_CTRL_ACTIVATE_SHIFT)


// -----------------------------------------------------------------------------
// DMA Condition (Condition Register)
// -----------------------------------------------------------------------------

// Bit positions
#define DMA_COND_OFFSET_SHIFT             24
#define DMA_COND_MASK_SHIFT               16
#define DMA_COND_BASE_ADDR_SHIFT          2
#define DMA_COND_NEGATE_SHIFT             1
#define DMA_COND_ENABLE_SHIFT             0

// Bit masks
#define DMA_COND_OFFSET_MASK              0xFF
#define DMA_COND_MASK_MASK                0xFF
#define DMA_COND_BASE_ADDR_MASK           0x1
#define DMA_COND_NEGATE_MASK              0x1
#define DMA_COND_ENABLE_MASK              0x1

// Condition Type Enum
typedef enum {
    DMA_COND_SRC_BASE = 0,
    DMA_COND_DST_BASE = 1
} cond_base_addr_t;

// DMA condition word from condition macro
typedef uint32_t dma_condition_t;

#define DMA_COND(addr_off, mask, base, neg, en) \
    (((addr_off) & DMA_COND_OFFSET_MASK)        << DMA_COND_OFFSET_SHIFT)     | \
    (((mask)     & DMA_COND_MASK_MASK)          << DMA_COND_MASK_SHIFT)       | \
    (((base)     & DMA_COND_BASE_ADDR_MASK)     << DMA_COND_BASE_ADDR_SHIFT)  | \
    (((neg)      & DMA_COND_NEGATE_MASK)        << DMA_COND_NEGATE_SHIFT)     | \
    (((en)       & DMA_COND_ENABLE_MASK)        << DMA_COND_ENABLE_SHIFT)

// -----------------------------------------------------------------------------
// DMA STATUS
// -----------------------------------------------------------------------------

// Bit positions
#define DMA_STATUS_ACTIVE_MASK          0x1
#define DMA_STATUS_COMPLETED_RCVS_MASK  0X7FF
#define DMA_STATUS_COMPLETED_TRMS_MASK  0X7FF

// Bit masks
#define DMA_STATUS_ACTIVE_SHIFT         0
#define DMA_STATUS_COMPLETED_RCVS_SHIFT 21
#define DMA_STATUS_COMPLETED_TRMS_SHIFT 10

// Status Information Struct
typedef struct {
    uint16_t completed_receives;
    uint16_t completed_transmissions;
    uint8_t  active;
} dma_status_t;

// -----------------------------------------------------------------------------
// General Purpose API
// -----------------------------------------------------------------------------

// Programs the DMA engine.
// Throws an error if the dma is currently busy
void program_dma(uint32_t src_addr, uint32_t dst_addr, dma_control_t controls, dma_condition_t condition);

// Only overwrite the controls of the dma
static inline void control_dma(dma_control_t controls) {
    *DMA_REG(DMA_CONTROL_REG_OFFSET) = controls;
}

// Activate the dma (without having to specify any options)
// Throws an error if the DMA is currently busy
void activate_dma();

// Stop the DMA.
void interrupt_dma();

// Read the dma status
dma_status_t read_dma_status();

// Returns true if the dma is currently working
static inline int dma_busy() {
    return (*DMA_REG(DMA_STATUS_OFFSET) >> DMA_STATUS_ACTIVE_SHIFT) & DMA_STATUS_ACTIVE_MASK;
}

// -----------------------------------------------------------------------------
// Interrupts
// -----------------------------------------------------------------------------

// Machine-Interrupt-Enable Direct-Memory-Access Interrupt-Request Bit 
#define MIE_DMA_IRQ_BIT (1 << 20)

static inline void enable_dma_irq(void) {
    // Enable DMA fast interrupt bit 3
    asm volatile("csrs mie, %0" ::"r"(MIE_DMA_IRQ_BIT));
    // Enable global interrupts
    // asm volatile("csrsi mstatus, 8" ::: "memory");
}

static inline void disable_dma_irq(void) {
    asm volatile("csrc mie, %0" ::"r"(MIE_DMA_IRQ_BIT));
}

// -----------------------------------------------------------------------------
// UART API
// -----------------------------------------------------------------------------

void uart_read_dma(uint8_t* destination_array, uint8_t num_bytes);

void uart_write_dma(uint8_t* source_array, uint8_t num_bytes);

// -----------------------------------------------------------------------------
// SPI API
// -----------------------------------------------------------------------------

void spi_write_dma(uint8_t*source_array, uint16_t num_bytes);

void spi_read_dma(uint8_t*source_array, uint16_t num_bytes);

// -----------------------------------------------------------------------------
// DMA MEMCPY & MEMSET
// -----------------------------------------------------------------------------

void* memcpy_dma(void* dst, const void* src, unsigned num_bytes);

void* memset_dma(void* ptr, int value, unsigned num);

#endif // DMA_H
