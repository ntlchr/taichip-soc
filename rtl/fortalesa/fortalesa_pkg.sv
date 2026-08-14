// Copyright (c) 2026 Tallinn University of Technology.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author:	Natalia Cherezova (TalTech)
//
// Description: Package for FORTALESA systolic array accelerator


package fortalesa_pkg;

    // Config regs address width
    localparam int ADDR_WIDTH = 5;

    // Register offsets
    localparam logic [ADDR_WIDTH-1:0] FORTALESA_MODE_OFFSET = 5'h0;
    localparam logic [ADDR_WIDTH-1:0] FORTALESA_LENGTH_OFFSET = 5'h4;
    localparam logic [ADDR_WIDTH-1:0] FORTALESA_SCALE_OFFSET = 5'h8;
    localparam logic [ADDR_WIDTH-1:0] FORTALESA_CTRL_STATUS_OFFSET = 5'hc;
    localparam logic [ADDR_WIDTH-1:0] FORTALESA_ERROR_OFFSET = 5'h10;
    
    // Register index
    typedef enum int {
        FORTALESA_MODE,
        FORTALESA_LENGTH,
        FORTALESA_SCALE,
        FORTALESA_CTRL_STATUS,
        FORTALESA_ERROR
    } fortalesa_regs_e;
    
    // RW permission (1 - operation is not allowed)
    localparam logic [1:0] FORTALESA_REG_PERMIT [5] = '{
        2'b00, // index[0] FORTALESA_MODE
        2'b00, // index[1] FORTALESA_LENGTH
        2'b00, // index[2] FORTALESA_SCALE
        2'b00, // index[3] FORTALESA_CTRL_STATUS
        2'b01  // index[4] FORTALESA_ERROR
    };

endpackage
