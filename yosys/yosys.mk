# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)

# Tools
YOSYS    ?= yosys

# Directories
YOSYS_DIR 		:= $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
YOSYS_OUT		:= $(YOSYS_DIR)/out
YOSYS_TMP		:= $(YOSYS_DIR)/tmp
YOSYS_REPORTS	:= $(YOSYS_DIR)/reports

# Top level design and project name
TOP_DESIGN		?= croc_chip
PROJ_NAME		?= taichip_soc

# File containing include dirs, defines and paths to all source files
SV_FLIST    	:= $(YOSYS_DIR)/src/$(PROJ_NAME).f

# Path to the resulting netlists (debug preserves multibit signals)
NETLIST			:= $(YOSYS_OUT)/$(PROJ_NAME)_yosys.v
NETLIST_DEBUG	:= $(YOSYS_OUT)/$(PROJ_NAME)_debug_yosys.v


## Synthesize netlist using Yosys
yosys:
	@mkdir -p $(YOSYS_OUT)
	@mkdir -p $(YOSYS_TMP)
	@mkdir -p $(YOSYS_REPORTS)
	cd $(YOSYS_DIR) && \
	SV_FLIST="$(SV_FLIST)" \
	TOP_DESIGN="$(TOP_DESIGN)" \
	PROJ_NAME="$(PROJ_NAME)" \
	TMP="$(YOSYS_TMP)" \
	OUT="$(YOSYS_OUT)" \
	REPORTS="$(YOSYS_REPORTS)" \
	$(YOSYS) -c $(YOSYS_DIR)/scripts/yosys_synthesis.tcl \
		2>&1 | TZ=UTC gawk '{ print strftime("[%Y-%m-%d %H:%M %Z]"), $$0 }' \
		     | tee "$(YOSYS_DIR)/$(TOP_DESIGN).log" \
		     | gawk -f $(YOSYS_DIR)/scripts/filter_output.awk;
		

ys_clean:
	rm -rf $(YOSYS_OUT)
	rm -rf $(YOSYS_TMP)
	rm -rf $(YOSYS_REPORTS) 
	rm -f $(YOSYS_DIR)/$(TOP_DESIGN).log

.PHONY: ys_clean yosys