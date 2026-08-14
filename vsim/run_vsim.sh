#!/bin/bash -f
# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author:
# - Natalia Cherezova (TalTech)

source compile.do
vopt +acc=npr -l elaborate.log tb_croc_soc -o tb_croc_soc_opt
vsim -c -t 1fs tb_croc_soc_opt -suppress vsim-3009 -suppress vsim-8386 -do "run -all; quit" -l simulate.log