// Generated register defines for safety_soc_ctrl

// Copyright information found in source file:
// Copyright 2024 ETH Zurich and University of Bologna

// Licensing information found in source file:
// SPDX-License-Identifier: SHL-0.51

// Modified for TAICHIP-1 SoC by:
// - Natalia Cherezova (TalTech)

#ifndef _SOC_CTRL_REG_DEFS_
#define _SOC_CTRL_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define SOC_CTRL_PARAM_REG_WIDTH 32

// Core Boot Address
#define SOC_CTRL_BOOTADDR_REG_OFFSET 0x0

// Core Fetch Enable
#define SOC_CTRL_FETCHEN_REG_OFFSET 0x4
#define SOC_CTRL_FETCHEN_FETCHEN_BIT 0

// Core Return Status (return value, EOC)
#define SOC_CTRL_CORESTATUS_REG_OFFSET 0x8

// Core Boot Mode
#define SOC_CTRL_BOOTMODE_REG_OFFSET 0xc
#define SOC_CTRL_BOOTMODE_BOOTMODE_MASK 0x3
#define SOC_CTRL_BOOTMODE_BOOTMODE_OFFSET 0
#define SOC_CTRL_BOOTMODE_BOOTMODE_FIELD \
  ((bitfield_field32_t) { .mask = SOC_CTRL_BOOTMODE_BOOTMODE_MASK, .index = SOC_CTRL_BOOTMODE_BOOTMODE_OFFSET })

// MBIST Pattern
#define SOC_CTRL_MBIST_PATTERN_REG_OFFSET 0x14

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _SOC_CTRL_REG_DEFS_
// End generated register defines for safety_soc_ctrl