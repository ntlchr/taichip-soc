# Copyright (c) 2026 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author:	Natalia Cherezova (TalTech)


# Project directory
PROJ_DIR  := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))

# PDK
PDK_ROOT  := $(PROJ_DIR)/ihp13
PDK := ihp-sg13cmos5l
PDK_DIR := $(PDK_ROOT)/sg13cmos5l

KLAYOUT_PATH := $(PDK_DIR)/libs.tech/klayout

PROJ_NAME := taichip_soc

default: help

# SIMULATION
## Run RTL simulation
vsim:
	cd vsim
	./run_vsim.sh
.PHONY: vsim


# SYNTHESIS AND PLACE & ROUTE
TOP_DESIGN ?= croc_chip

include yosys/yosys.mk
include openroad/openroad.mk


# GDS AND SIGN OFF

## Generate GDS file from DEF file
gds:
	./klayout/scripts/def2gds.sh
.PHONY: gds

## Generate and add a sealring
sealring:
	klayout -n sg13cmos5l -zz \
        -r $(KLAYOUT_PATH)/tech/scripts/sealring.py \
        -rd width=5000.0  \
        -rd height=4000.0 \
        -rd output=klayout/out/sealring.gds.gz
	klayout -zz \
        -rm klayout/scripts/add_sealring.py \
        -rd chip_gds=klayout/out/$(PROJ_NAME).gds.gz \
        -rd seal_gds=klayout/out/sealring.gds.gz \
        -rd out_gds=klayout/out/$(PROJ_NAME).sealed.gds.gz
.PHONY: sealring

## Metal density fill
fill:
	klayout -n sg13cmos5l -zz \
        -r $(KLAYOUT_PATH)/tech/scripts/filler.py \
        -rd output_file=klayout/out/$(PROJ_NAME).filled.gds.gz \
        klayout/out/$(PROJ_NAME).sealed.gds.gz
.PHONY: fill

## Perform DRC (no density)
drc:
	python3 $(KLAYOUT_PATH)/tech/drc/run_drc.py --path=klayout/out/$(PROJ_NAME).filled.gds.gz --run_mode=deep --topcell=$(TOP_DESIGN) --no_density --mp=12
.PHONY: drc

## Check density rules
drc-density:
	python3 $(KLAYOUT_PATH)/tech/drc/run_drc.py --path=klayout/out/$(PROJ_NAME).filled.gds.gz --run_mode=deep --topcell=$(TOP_DESIGN) --density_only --density_thr=10
.PHONY: drc-density

## Yosys - OpenRoad - GDS - Sealring - Fill
tapeout: yosys openroad gds sealring fill
.PHONY: tapeout


# AVAILABLE TARGETS
help: Makefile
	@printf "Available targets:\n------------------\n"
	@for mkfile in $(MAKEFILE_LIST); do \
		awk '/^[a-zA-Z\-0-9]+:/ { \
			helpMessage = match(lastLine, /^## (.*)/); \
			if (helpMessage) { \
				helpCommand = substr($$1, 0, index($$1, ":")-1); \
				helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
				printf "%-20s %s\n", helpCommand, helpMessage; \
			} \
		} \
		{ lastLine = $$0 }' $$mkfile; \
	done

.PHONY: help


# CLEAN
clean:
	$(MAKE) ys_clean
	$(MAKE) or_clean

.PHONY: clean