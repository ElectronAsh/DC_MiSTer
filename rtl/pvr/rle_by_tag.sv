`timescale 1ns / 1ps
`default_nettype none

module rle_by_tag (
    input  wire        clk,
    input  wire        rst,
	
    input  wire        rle_start,

    output reg  [4:0]  rle_row_sel,
    output reg  [4:0]  rle_col_sel,
    input  wire [11:0] tag_in,
	
	output reg         transfer_z,

    output reg  [11:0] rle_tag,
    output reg  [9:0]  rle_count,
    output reg  [4:0]  rle_row_start,
    output reg  [4:0]  rle_col_start,
    output reg         rle_valid,
    output wire        rle_busy,
	
	output 	reg        rle_param_load,
	
    output reg         rle_done
);

    typedef enum logic [2:0] {
        IDLE, WAIT, WAIT2, SCAN, EMIT
    } state_t;
    state_t  state;

    assign rle_busy = (state != IDLE);

    typedef struct packed {
        logic [11:0] tag;
        logic [9:0]  count;
        logic [4:0]  row;
        logic [4:0]  col;
    } run_t;

    // Configurable max tags and runs per tag
    localparam MAX_TAGS = 16;
    localparam MAX_RUNS = 64;

    // Track discovered tags
    reg [11:0] tag_map [0:MAX_TAGS-1];
    reg [3:0]  tag_count;

    // Run buffers grouped by tag index
    run_t run_groups [0:MAX_TAGS-1][0:MAX_RUNS-1];
    reg [5:0] run_group_count [0:MAX_TAGS-1];

    // For storing in scan phase
    reg [11:0] prev_tag;
    reg [9:0]  curr_len;
    reg [4:0]  start_row, start_col;

    // Emit phase
    reg [3:0] emit_tag_idx;
    reg [5:0] emit_run_idx;

	int tag_idx;
	
	wire last_pixel = (rle_col_sel == 31 && rle_row_sel == 31);
	
    // Find or allocate tag index
    function automatic [3:0] get_tag_index(input logic [11:0] tag);
        integer i;
        begin
            get_tag_index = 4'd15; // invalid default
            for (i = 0; i < tag_count; i = i + 1) begin
                if (tag_map[i] == tag) begin
                    get_tag_index = i;
                end
            end
            if (get_tag_index == 4'd15 && tag_count < MAX_TAGS) begin
                tag_map[tag_count] = tag;
                get_tag_index = tag_count;
                tag_count <= tag_count + 1;
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            rle_row_sel <= 0;
            rle_col_sel <= 0;
			transfer_z <= 1'b0;
            rle_valid <= 0;
            rle_done <= 0;
            tag_count <= 0;
            emit_tag_idx <= 0;
            emit_run_idx <= 0;
			rle_param_load <= 0;
        end
		else begin
			transfer_z <= 1'b0;
            rle_valid <= 0;
			rle_param_load <= 1'b0;
            rle_done <= 0;
			
            case (state)
                IDLE: begin
                    if (rle_start) begin
                        rle_row_sel <= 0;
                        rle_col_sel <= 0;
                        tag_count <= 0;
                        prev_tag <= tag_in;
                        curr_len <= 0;
                        start_row <= 0;
                        start_col <= 0;
                        //for (int i = 0; i < MAX_TAGS; i++) begin
                            //run_group_count[i] <= 0;
                            run_group_count[00] <= 0;
                            run_group_count[01] <= 0;
                            run_group_count[02] <= 0;
                            run_group_count[03] <= 0;
                            run_group_count[04] <= 0;
                            run_group_count[05] <= 0;
                            run_group_count[06] <= 0;
                            run_group_count[07] <= 0;
                            run_group_count[08] <= 0;
                            run_group_count[09] <= 0;
                            run_group_count[10] <= 0;
                            run_group_count[11] <= 0;
                            run_group_count[12] <= 0;
                            run_group_count[13] <= 0;
                            run_group_count[14] <= 0;
                            run_group_count[15] <= 0;
                        //end
                        state <= WAIT;			// Needs a delay, for the Tag buffer output to update.
                    end
                end
				
				WAIT: begin
					state <= WAIT2;
				end
				
				WAIT2: begin
					state <= SCAN;
				end

                SCAN: begin
                    if (curr_len == 0) begin	// Read the first (top-left pixel) Tag.
                        prev_tag <= tag_in;
                        curr_len <= 1;
                        start_row <= rle_row_sel;
                        start_col <= rle_col_sel;
                    end
					else if (tag_in == prev_tag) begin	// Tag stayed the same: Continuation of a run.
                        curr_len <= curr_len + 1;
                    end
					
					// Tag value has changed (or we're on the last lower-right pixel): Start of a new run.
					if ((tag_in != prev_tag) || last_pixel) begin
                        tag_idx = get_tag_index(prev_tag);
                        if (tag_idx < MAX_TAGS && run_group_count[tag_idx] < MAX_RUNS) begin
                            run_groups[tag_idx][run_group_count[tag_idx]] <= '{tag: prev_tag, count: curr_len, row: start_row, col: start_col};
                            run_group_count[tag_idx] <= run_group_count[tag_idx] + 1;	// Increment the Tag index.
                        end
                        prev_tag <= tag_in;
                        curr_len <= 1;	// (curr_len reset to 1)...
                        start_row <= rle_row_sel;
                        start_col <= rle_col_sel;
						
						rle_param_load <= 1'b1;	// Not really needed atm. Params get loaded via prim_tag_out from the Tag/Z-buffer anyway.
						state <= WAIT;			// But we need a delay of one clock, for the new params to load. May need more delay, due to UV interp latency!
                    end
					
					transfer_z <= 1'b1;
					
                    if (rle_col_sel == 31) begin	// Check if we're on the last column...
                        rle_col_sel <= 0;			// Reset to first column.
                        if (rle_row_sel == 31) begin	// Check if we're on the last row...
                            rle_row_sel <= 0;			// Reset to the first row (ready for the SCAN of the next prim?)
                            emit_tag_idx <= 0;
                            emit_run_idx <= 0;
							// Kludge. Update the RLE outputs early (don't assert rle_valid), so we can compare in the EMIT state.
							// This is so I can check when an rle_tag value changes, to know when to transfer new Params from the Param Buffer to the TSP FIFO.
                            rle_tag       <= run_groups[0][0].tag;
                            rle_count     <= run_groups[0][0].count;
                            rle_row_start <= run_groups[0][0].row;
                            rle_col_start <= run_groups[0][0].col;
                            //rle_valid <= 1;
                            state <= EMIT;
                        end
						else begin
                            rle_row_sel <= rle_row_sel + 1;	// Increment to the next Tag buffer row.
							state <= WAIT;			// Needs a delay, for the Tag buffer output to update.
                        end
                    end
					else begin
                        rle_col_sel <= rle_col_sel + 1;	// Increment through each pixel in the current Tag buffer row.
                    end
                end

                EMIT: begin
                    if (emit_tag_idx < tag_count) begin
                        if (emit_run_idx < run_group_count[emit_tag_idx]) begin
                            rle_tag       <= run_groups[emit_tag_idx][emit_run_idx].tag;
                            rle_count     <= run_groups[emit_tag_idx][emit_run_idx].count;
                            rle_row_start <= run_groups[emit_tag_idx][emit_run_idx].row;
                            rle_col_start <= run_groups[emit_tag_idx][emit_run_idx].col;
                            rle_valid <= 1;
                            emit_run_idx <= emit_run_idx + 1;
                        end
						else begin
                            emit_run_idx <= 0;
                            emit_tag_idx <= emit_tag_idx + 1;
                        end
                    end
					else begin
						rle_done <= 1;
						state <= IDLE;
                    end
                end
				
				default: ;
            endcase
        end
    end
endmodule
