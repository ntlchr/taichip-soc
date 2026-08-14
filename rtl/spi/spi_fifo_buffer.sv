module spi_fifo_buffer #(
    parameter DEPTH = 16,  // Must be power of 2
    parameter DATA_WIDTH = 8
)(
    input  logic        clk_i,
    input  logic        rst_ni,

    // Write interface
    input  logic        spi_write_i,
    input  logic [7:0]  spi_data_i,
    output logic        full_o,
    output logic        almost_full_o,

    // Read interface
    input  logic        obi_read_en, //obi triggers read
    output logic [7:0] rd_data_o,
    output logic        empty_o,
    output logic        almost_empty_o
);

    // Internal memory
    logic [DATA_WIDTH-1:0] mem_q [0:DEPTH-1];

    // Pointers and counter
    localparam PTR_W = $clog2(DEPTH);
    logic [PTR_W-1:0] wr_ptr_d, wr_ptr_q;
    logic [PTR_W-1:0] rd_ptr_d, rd_ptr_q;
    logic [PTR_W:0]   count_d, count_q;

    // -------------------------------
    // Combinational: next-state logic
    // -------------------------------
    always_comb begin
        wr_ptr_d   = wr_ptr_q;
        rd_ptr_d   = rd_ptr_q;
        count_d    = count_q;

        if (spi_write_i && !full_o) begin
            wr_ptr_d = (wr_ptr_q + 1) % DEPTH;
        end

        if (obi_read_en && !empty_o) begin
            rd_ptr_d  = (rd_ptr_q + 1) % DEPTH;
        end

        unique case ({spi_write_i && !full_o, obi_read_en && !empty_o})
            2'b10: count_d = count_q + 1;
            2'b01: count_d = count_q - 1;
            2'b11: count_d = count_q;
            default: count_d = count_q;
        endcase
    end

    // -------------------------------
    // Sequential logic
    // -------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        
        if (!rst_ni) begin
            wr_ptr_q   <= '0;
            rd_ptr_q   <= '0;
            count_q    <= '0;
        end else begin
            wr_ptr_q   <= wr_ptr_d;
            rd_ptr_q   <= rd_ptr_d;
            count_q    <= count_d;
        end
    end

    // -------------------------------
    // Synchronous memory write
    // -------------------------------
    always_ff @(posedge clk_i) begin
        if (spi_write_i && !full_o) begin
            mem_q[wr_ptr_q] <= spi_data_i;
        end
    end
    
    assign rd_data_o        = mem_q[rd_ptr_q];
    assign full_o           = (count_q == DEPTH);
    assign almost_full_o    = (count_q == DEPTH - 1);
    assign empty_o          = (count_q == 0);
    assign almost_empty_o   = (count_q == 1);

endmodule
