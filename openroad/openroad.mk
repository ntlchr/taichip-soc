# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Tools
OPENROAD 		?= openroad

# Directory of the path to the last called Makefile (this one)
OR_DIR    := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))

# Project variables
# if you are running the entire flow these are set by the top level Makefile
# in that case do not change them here
TOP_DESIGN 	?= croc_chip
PROJ_NAME	?= taichip_soc
NETLIST		?= $(realpath $(OR_DIR)/../yosys/out/$(PROJ_NAME)_yosys.v)

SAVE	 	 ?= $(OR_DIR)/save
REPORTS	 	 ?= $(OR_DIR)/reports
OR_OUT  	 ?= $(OR_DIR)/out
OR_OUT_FILES  = $(OR_OUT)/$(PROJ_NAME).def $(OR_OUT)/$(PROJ_NAME).v $(OR_OUT)/$(PROJ_NAME).sdc $(OR_OUT)/$(PROJ_NAME).odb


## Place & Route flow using OpenROAD
openroad: $(OR_OUT)/$(PROJ_NAME).def
	mkdir -p $(SAVE)
	mkdir -p $(REPORTS)
	mkdir -p $(OR_OUT)
	cd $(OR_DIR) && \
	NETLIST="$(NETLIST)" \
	TOP_DESIGN="$(TOP_DESIGN)" \
	PROJ_NAME="$(PROJ_NAME)" \
	SAVE="$(SAVE)" \
	REPORTS="$(REPORTS)" \
	PDK="$(OR_DIR)/../ihp13/sg13cmos5l" \
	$(OPENROAD) scripts/chip.tcl \
		-log $(PROJ_NAME).log \
		2>&1 | TZ=UTC gawk '{ print strftime("[%Y-%m-%d %H:%M %Z]"), $$0 }';

or_clean:
	rm -rf $(SAVE)
	rm -rf $(REPORTS)
	rm -rf $(OR_OUT) 
	rm -f $(PROJ_NAME).log

.PHONY: openroad or_clean