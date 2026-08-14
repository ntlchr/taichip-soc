# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author:
# - Natalia Cherezova (TalTech)


# Macro names as produced by the yosys synthesis
# Used for manual macro placement and JTAG constraints
set CROC i_croc_soc/i_croc
set JTAG $CROC/i_dmi_jtag

set JTAG_ASYNC_REQ [get_nets $JTAG/i_dmi_cdc.i_cdc_req/*async_*]
set JTAG_ASYNC_RSP [get_nets $JTAG/i_dmi_cdc.i_cdc_resp/*async_*]

set GEN_SRAM          i_croc_soc/i_croc/gen_sram_bank
set ACC_SRAM          i_croc_soc/i_croc/acc_sram_bank
set SRAM_256x32_1P    gen_256x32xBx1.i_cut
set SRAM_256x32_2P    gen_256x32xBx2.i_cut
set SRAM_256x8_1P     gen_256x8xBx1.i_cut
set SRAM_256x8_2P     gen_256x8xBx2.i_cut

# Memory banks (general)
set sram {\[0\].i_sram.i_bank.i_tc_sram/}
set gen_bank0_sram0 $GEN_SRAM$sram$SRAM_256x32_1P
set sram {\[0\].i_sram.i_bank_ecc.i_tc_sram/}
set gen_bank0_ecc_sram0 $GEN_SRAM$sram$SRAM_256x8_1P
set sram {\[1\].i_sram.i_bank.i_tc_sram/}
set gen_bank1_sram0 $GEN_SRAM$sram$SRAM_256x32_1P
set sram {\[1\].i_sram.i_bank_ecc.i_tc_sram/}
set gen_bank1_ecc_sram0 $GEN_SRAM$sram$SRAM_256x8_1P

# Memory banks (accelerator)
set sram {\[0\].i_sram.i_bank.i_tc_sram/}
set acc_bank0_sram0 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[0\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank0_ecc_sram0 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[1\].i_sram.i_bank.i_tc_sram/}
set acc_bank0_sram1 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[1\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank0_ecc_sram1 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[2\].i_sram.i_bank.i_tc_sram/}
set acc_bank0_sram2 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[2\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank0_ecc_sram2 $ACC_SRAM$sram$SRAM_256x8_2P

set sram {\[3\].i_sram.i_bank.i_tc_sram/}
set acc_bank1_sram0 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[3\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank1_ecc_sram0 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[4\].i_sram.i_bank.i_tc_sram/}
set acc_bank1_sram1 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[4\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank1_ecc_sram1 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[5\].i_sram.i_bank.i_tc_sram/}
set acc_bank1_sram2 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[5\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank1_ecc_sram2 $ACC_SRAM$sram$SRAM_256x8_2P

set sram {\[6\].i_sram.i_bank.i_tc_sram/}
set acc_bank2_sram0 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[6\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank2_ecc_sram0 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[7\].i_sram.i_bank.i_tc_sram/}
set acc_bank2_sram1 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[7\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank2_ecc_sram1 $ACC_SRAM$sram$SRAM_256x8_2P
set sram {\[8\].i_sram.i_bank.i_tc_sram/}
set acc_bank2_sram2 $ACC_SRAM$sram$SRAM_256x32_2P
set sram {\[8\].i_sram.i_bank_ecc.i_tc_sram/}
set acc_bank2_ecc_sram2 $ACC_SRAM$sram$SRAM_256x8_2P