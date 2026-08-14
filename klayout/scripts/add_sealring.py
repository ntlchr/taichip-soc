# Copyright (c) 2025 Tallinn University of Technology.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author:	Natalia Cherezova (TalTech)
#
# Description: Add sealring to the chip layout

import sys
import pya

def add_sealring(chip_gds, seal_gds, out_gds):

    # Read input gds
    chip = pya.Layout()
    chip.read(chip_gds)
    chip.read(seal_gds)
    chip_top = chip.top_cells()[0]
    seal_top = chip.top_cells()[1]
    
    # Insert sealring with the offset (-109,-109)
    #sealring = layout.cell("sealring")
    chip_top.insert(pya.DCellInstArray(seal_top.cell_index(), pya.DTrans(pya.DTrans.R0, pya.DPoint(-109, -109))))
    
    # Shift the whole layout to the origin point
    chip.transform(pya.DTrans(pya.DTrans.R0, pya.DPoint(109, 109)))
        
    # Write output
    tech = pya.Technology.technology_by_name("")
    options = tech.save_layout_options
    options.write_context_info = False
    chip.write(out_gds, options=options)


    
add_sealring(chip_gds, seal_gds, out_gds)
