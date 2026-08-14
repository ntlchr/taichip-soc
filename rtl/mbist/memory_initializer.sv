////////////////////////////////////////////////////////////////////////////////
// @file     memory_initializer.sv
// @brief    Initilizes all memory addresses in range
// @details  
// -----------------------------------------------------------------------------
// @par      Project: Taichip1.1
// @author   André Lucas Chinazzo
// @date     19#05#2026
// @par          Language: SystemVerilog
// @revision:    0.1
//------------------------------------------------------------------------------
// @copyright IHP\n
//     Im Technologiepark 25,\n
//     15236 Frankfurt Oder,\n
//     Germany,\n
//     All rights reserved.
////////////////////////////////////////////////////////////////////////////////

module memory_initializer 
    #(
        parameter MEM_DATA_BW = 128,
        parameter MEM_ADDR_BW =  13,
        parameter PATTERN_BW  =  16,
        parameter CMD_SPD_BW  =   4
    )(
        input  logic                   clk_i,
		input  logic                   rst_ni,
		input  logic                   start_init_i,
		input  logic [PATTERN_BW-1:0]  pattern_i,
		input  logic [CMD_SPD_BW-1:0]  cmd_speed_i,
		input  logic [MEM_DATA_BW-1:0] data_i,

		output logic                   active_o,
		output logic                   wen_o,
		output logic                   ren_o,
		output logic [MEM_ADDR_BW-1:0] addr_o,
		output logic [MEM_DATA_BW-1:0] data_o,
		output logic                   match_o,
		output logic                   done_o
    );

    localparam PATT_PER_ADDR = (MEM_DATA_BW % PATTERN_BW) ? ((MEM_DATA_BW / PATTERN_BW)+1) : (MEM_DATA_BW / PATTERN_BW);
    localparam MAX_CMD_PER = 2**CMD_SPD_BW - 1;

    typedef enum logic [1:0] {
        IDLE,
        WRITE,
        READ,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    logic [MEM_ADDR_BW-1:0] addr_cntr;
    logic [MEM_DATA_BW-1:0] expected_data;
    logic                   match;

    logic [CMD_SPD_BW-1:0] cmd_period;
    logic [CMD_SPD_BW-1:0] cmd_timer;
    logic                  cmd_ready;

    logic last_done;
    logic last_ren;

    // Generate the full-width pattern
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            last_done <= '0;
        else if (state == DONE_STATE)
            last_done <= '1;
        else if (state == IDLE)
            last_done <= last_done;
        else
            last_done <= '0;
    end

    // Generate the full-width pattern
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            expected_data <= '0;
        else
            expected_data <= (state == IDLE && start_init_i) ? MEM_DATA_BW'({PATT_PER_ADDR{pattern_i}}) : expected_data;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            cmd_period <= MAX_CMD_PER;
        else if (state == IDLE && start_init_i)
            cmd_period <= MAX_CMD_PER - cmd_speed_i;
        else
            cmd_period <= cmd_period;
    end

    // Command delay logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            cmd_timer <= '0;
        else if (state == WRITE || state == READ) begin
            if (cmd_timer == cmd_period) 
                cmd_timer <= '0;
            else
                cmd_timer <= cmd_timer + 1'b1;
        end else begin
            cmd_timer <= '0;
        end
    end
    assign cmd_ready = (cmd_timer == cmd_period);

    // State register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM next state logic
    always_comb begin
        case (state)
            IDLE:       next_state = start_init_i ? WRITE : IDLE;
            WRITE:      next_state = (addr_cntr == (1 << MEM_ADDR_BW) - 1) && cmd_ready ? READ : WRITE;
            READ:       next_state = (addr_cntr == '0) && last_ren ? DONE_STATE : READ;
            DONE_STATE: next_state = IDLE;
            default:    next_state = IDLE;
        endcase
    end

    // Address counter
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            addr_cntr <= '0;
        else if ((state == WRITE || state == READ))
            addr_cntr <=  cmd_ready ? addr_cntr + 1 : addr_cntr;
        else
            addr_cntr <= '0;
    end

    // Write/Read control signals
    always_comb begin
        wen_o  = (state == WRITE) && cmd_ready;
        ren_o  = (state == READ) && cmd_ready && (next_state == READ);
        addr_o = addr_cntr;
        data_o = expected_data;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            last_ren <= '0;
        else
            last_ren <= ren_o;
    end

    // Match check
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            match <= 1'b1;
        end else if (state == READ && last_ren) begin
            if (data_i !== expected_data)
                match <= 1'b0;
        end else if (state == WRITE) begin
            match <= 1'b1;
        end
    end

    // Outputs
    assign active_o = (state != IDLE) | start_init_i;
    assign match_o	= (state == IDLE) & last_done & match;
    assign done_o   = (state == IDLE) & last_done;
endmodule
