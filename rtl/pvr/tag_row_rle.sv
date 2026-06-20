`timescale 1ns / 1ps
`default_nettype none

module tag_row_rle #(
    parameter TAG_WIDTH = 12,
    parameter NUM_ENTRIES = 32
)(
    input  logic                     clk,
    input  logic                     rst,

    // Write interface for each primitive hitting this row
    input  logic                     write_enable,
    input  logic [TAG_WIDTH-1:0]     prim_tag,
    input  logic [31:0]              inTri,

    // Begin flush of row to texturing stage
    input  logic                     flush,
    input  logic [4:0]               row_index,

    // Output: valid RLE spans during flush
    output logic                     valid_out,
    output logic [TAG_WIDTH-1:0]     rle_tag,
    output logic [4:0]               rle_row,
    output logic [4:0]               rle_start_x,
    output logic [4:0]               rle_length
);

    typedef struct packed {
        logic [TAG_WIDTH-1:0] tag;
        logic [31:0]          mask;
    } tag_entry_t;

    tag_entry_t tag_table [0:NUM_ENTRIES-1];

    // Internal state for insertion and flushing
    integer i;

    // Flush state
    logic [5:0] flush_entry_idx; // up to 32 entries
    logic [5:0] flush_bit_idx;
    logic [4:0] run_start;
    logic       in_run;
    logic       flushing;
	
	logic found = 0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_ENTRIES; i++) begin
                tag_table[i].tag  <= 0;
                tag_table[i].mask <= 0;
            end
            flush_entry_idx <= 0;
            flush_bit_idx   <= 0;
            in_run          <= 0;
            flushing        <= 0;
            valid_out       <= 0;
        end else begin
            if (write_enable) begin
                // Step 1: Clear overlapping pixels
                for (i = 0; i < NUM_ENTRIES; i++) begin
                    tag_table[i].mask <= tag_table[i].mask & ~inTri;
                end

                // Step 2: Insert or update tag
                for (i = 0; i < NUM_ENTRIES; i++) begin
                    if (tag_table[i].tag == prim_tag && tag_table[i].mask != 0) begin
                        tag_table[i].mask <= tag_table[i].mask | inTri;
                        found = 1;
                    end
                end
                if (!found) begin
                    for (i = 0; i < NUM_ENTRIES; i++) begin
                        if (tag_table[i].mask == 0) begin
                            tag_table[i].tag  <= prim_tag;
                            tag_table[i].mask <= inTri;
                            break;
                        end
                    end
                end
            end

            // Start flush
            if (flush) begin
                flush_entry_idx <= 0;
                flush_bit_idx   <= 0;
                in_run          <= 0;
                flushing        <= 1;
                valid_out       <= 0;
            end else if (flushing) begin
                logic [31:0] mask = tag_table[flush_entry_idx].mask;

                if (flush_bit_idx < 32) begin
                    logic current_bit = mask[flush_bit_idx];

                    if (current_bit && !in_run) begin
                        in_run    <= 1;
                        run_start <= flush_bit_idx;
                    end else if (!current_bit && in_run) begin
                        // End of run — emit RLE
                        in_run     <= 0;
                        valid_out  <= 1;
                        rle_tag    <= tag_table[flush_entry_idx].tag;
                        rle_row    <= row_index;
                        rle_start_x<= run_start;
                        rle_length <= flush_bit_idx - run_start;
                    end

                    flush_bit_idx <= flush_bit_idx + 1;

                    // Handle end-of-mask
                    if (flush_bit_idx == 31) begin
                        if (in_run) begin
                            // Finish final run
                            valid_out  <= 1;
                            rle_tag    <= tag_table[flush_entry_idx].tag;
                            rle_row    <= row_index;
                            rle_start_x<= run_start;
                            rle_length <= 32 - run_start;
                            in_run     <= 0;
                        end
                        flush_bit_idx <= 0;
                        flush_entry_idx <= flush_entry_idx + 1;
                    end

                    // End flush
                    if (flush_entry_idx >= NUM_ENTRIES - 1 && flush_bit_idx == 31) begin
                        flushing <= 0;
                    end else if (mask == 0 && flush_bit_idx == 0) begin
                        // Skip empty entry
                        flush_entry_idx <= flush_entry_idx + 1;
                    end

                end else begin
                    // Skip empty masks
                    flush_entry_idx <= flush_entry_idx + 1;
                    flush_bit_idx   <= 0;
                end
            end else begin
                valid_out <= 0;
            end
        end
    end

endmodule
