# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Modified for TAICHIP-1 SoC by:
# - Natalia Cherezova (TalTech)

# Preparation for the synthesis flow
# A common setup to provide some functionality and define variables

# Global variables imported from environment variables (if set)
set proj_name  [expr {[info exists ::env(PROJ_NAME)]  ? $::env(PROJ_NAME)  : "taichip_soc"}]
set top_design [expr {[info exists ::env(TOP_DESIGN)] ? $::env(TOP_DESIGN) : "croc_chip"}]
set sv_flist   [expr {[info exists ::env(SV_FLIST)]   ? $::env(SV_FLIST)   : "src/taichip_soc.f"}]

# Set global variables
set out_dir    out
set tmp_dir    tmp
set rep_dir    reports

file mkdir $out_dir
file mkdir $tmp_dir
file mkdir $rep_dir

# process ABC script and write to temporary directory
proc processAbcScript {abc_script} {
    global tmp_dir
    set src_dir [file join [file dirname [info script]] ../src]
    set abc_out_path $tmp_dir/[file tail $abc_script]

    # substitute {STRING} placeholders with their value
    set raw [read -nonewline [open $abc_script r]]
    set abc_script_recaig [string map -nocase [list "{REC_AIG}" [subst "$src_dir/lazy_man_synth_library.aig"]] $raw]
    set abc_out [open $abc_out_path w]
    puts -nonewline $abc_out $abc_script_recaig

    flush $abc_out
    close $abc_out
    return $abc_out_path
}