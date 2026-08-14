# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Paul Scheffler <paulsc@iis.ee.ethz.ch>
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>


# Toolchain
RISCV_XLEN    ?= 32
RISCV_MARCH   ?= rv$(RISCV_XLEN)i_zicsr
RISCV_MABI    ?= ilp32
RISCV_PREFIX  ?= riscv64-unknown-elf-
RISCV_CC      ?= $(RISCV_PREFIX)gcc
RISCV_CXX     ?= $(RISCV_PREFIX)g++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_AS      ?= $(RISCV_PREFIX)as
RISCV_AR      ?= $(RISCV_PREFIX)ar
RISCV_LD      ?= $(RISCV_PREFIX)ld
RISCV_STRIP   ?= $(RISCV_PREFIX)strip
RISCV_SIZE    ?= $(RISCV_PREFIX)size

# Compiler and linker flags
RISCV_FLAGS    ?= -march=$(RISCV_MARCH) -mabi=$(RISCV_MABI) -mcmodel=medany -static -std=gnu99 -Os -nostdlib -fno-builtin -ffreestanding
RISCV_CCFLAGS  ?= $(RISCV_FLAGS) -Iinclude -I$(INCDIR) -I$(CURDIR)
RISCV_LDFLAGS  ?= -static -nostartfiles -lm -lgcc $(RISCV_FLAGS)

# Building defaults
BINDIR 	 ?= bin
BUILDDIR ?= build
HEXDIR   ?= hex
CRT0 	 ?= crt0.S
LINK 	 ?= link.ld
SRCDIR   ?= lib/src
INCDIR   ?= lib/inc

# Sources
LIBDIR      ?= lib
LIB_SOURCES := $(wildcard $(SRCDIR)/*.[cS])
STATIC_LIB  := $(LIBDIR)/libcroc.a

TOP_SOURCES ?= $(filter-out $(CRT0), $(wildcard *.[cS]))
PROG_NAMES  := $(basename $(TOP_SOURCES))

# Objects
CRT0_OBJ  := $(BUILDDIR)/$(basename $(CRT0)).o
LIB_OBJS  := $(addsuffix .o, $(addprefix $(BUILDDIR)/, \
	         $(basename $(LIB_SOURCES))))
PROG_OBJS := $(addsuffix .o, $(addprefix $(BUILDDIR)/, \
	         $(basename $(PROG_SOURCES))))


ALL_TARGETS := $(PROG_NAMES:%=$(BINDIR)/%.elf) $(PROG_NAMES:%=$(BINDIR)/%.dump) $(PROG_NAMES:%=$(HEXDIR)/%.hex)

# Ensure intermediate object files are not deleted after linking
.SECONDARY: $(CRT0_OBJ) $(LIB_OBJS) $(PROG_OBJS)

all: compile

$(BINDIR):
	mkdir -p $(BINDIR)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.S.o: $(SRCDIR)/%.S | $(BUILDDIR)
	$(RISCV_CC) -ffunction-sections -fdata-sections $(RISCV_CCFLAGS) -c $< -o $@

$(BUILDDIR)/%.c.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(RISCV_CC) -ffunction-sections -fdata-sections $(RISCV_CCFLAGS) -c $< -o $@

%.S.o: %.S
	$(RISCV_CC) -ffunction-sections -fdata-sections $(RISCV_CCFLAGS) -c $< -o $@

%.c.o: %.c
	$(RISCV_CC) -ffunction-sections -fdata-sections $(RISCV_CCFLAGS) -c $< -o $@

# Linking
$(BINDIR)/%.elf: %.c.o $(CRT0).o $(STATIC_LIB) | $(BINDIR)
	$(RISCV_CC) -o $@ $< $(CRT0).o -Wl,--gc-sections -Wl,--start-group $(STATIC_LIB) -Wl,--end-group $(RISCV_LDFLAGS) -T$(LINK)
	$(RISCV_SIZE) $@

$(STATIC_LIB): $(LIB_OBJS)
	$(RISCV_AR) rcs $@ $^

$(BINDIR)/%.dump: $(BINDIR)/%.elf
	$(RISCV_OBJDUMP) -D -s $< >$@

$(HEXDIR)/%.hex: $(BINDIR)/%.elf | $(HEXDIR)
	$(RISCV_OBJCOPY) -O verilog $< $@

# Phonies
.PHONY: all clean compile

clean:
	rm -rf $(BINDIR) $(BUILDDIR) $(HEXDIR)

compile: $(BINDIR) $(BUILDDIR) $(HEXDIR) $(ALL_TARGETS)
