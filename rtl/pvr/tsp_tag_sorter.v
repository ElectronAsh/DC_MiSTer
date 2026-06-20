`timescale 1ns / 1ps
`default_nettype none

module tsp_tag_sorter (
    input wire clk,
    input wire reset,
    input wire rle_start,
    output reg rle_busy,
    
    // Tag buffer interface
    input wire [9:0] prim_tag,
    output reg [4:0] rle_row_sel,
    output reg [4:0] rle_col_sel,
    
    input wire [127:0] param_data,
	input wire [4:0] tile_x,
	input wire [4:0] tile_y,
	input wire [2:0] type_cnt,
    
    // RLE Output grouped by tag
	output reg [4:0] rle_tile_x,
	output reg [4:0] rle_tile_y,
	output reg [4:0] rle_prim_type,	
    output reg [9:0] rle_start_addr,    // y*32 + x
    output reg [10:0] rle_run_length,   // Number of consecutive pixels. (starts from 1, so needs to be 11-bits, for max value of 1,024).
    output reg [9:0] rle_tag,           // Primitive tag
    output reg [127:0] rle_params,      // Texture parameters
    output reg rle_valid,               // RLE output valid
    output reg param_request,           // Request parameters
    output reg [5:0] requested_tag,     // Tag needing parameters
    
    output reg rle_done
);

// Tag presence bitmap and parameter cache
reg [1023:0] tag_present;  // 1024 bits for 1024 possible tags (10-bit tags)
reg [127:0] param_cache [0:1023];
reg [1023:0] param_cache_valid;

// Current tag being processed
reg [9:0] processing_tag;

// RLE state tracking within a tag
reg [9:0] current_run_start;
reg [10:0] current_run_length;	// (starts from 1, so needs to be 11-bits, for max value of 1,024).
reg current_run_active;

// Processing state
typedef enum {
    IDLE,
    SCAN_TILE_FOR_TAGS,
    SELECT_TAG,
    REQUEST_PARAMS,
    SCAN_TAG_RLE,
	ROW_CHANGE_DELAY,
    OUTPUT_RUN,
    TAG_COMPLETE,
    TILE_COMPLETE
} state_t;

state_t state;

// Find next tag function
function [9:0] find_next_tag;
    input [9:0] current;
    integer i;
    begin
        find_next_tag = 10'h3FF; // Invalid tag
        for (i = current + 1; i < 1024; i = i + 1) begin
            if (tag_present[i]) begin
                find_next_tag = i;
                break;
            end
        end
        // If no next tag found, return invalid
    end
endfunction

/*
always @(posedge clk) begin
    if (state == SCAN_TAG_RLE) begin
        $display("SCAN_PROGRESS: row=%02d, col=%02d, total_pixels=%04d", 
                 rle_row_sel, rle_col_sel, (rle_row_sel * 32 + rle_col_sel));
    end
end

// Check for infinite loop
reg [15:0] scan_cycle_count;
always @(posedge clk) begin
    if (state == SCAN_TAG_RLE) begin
        scan_cycle_count <= scan_cycle_count + 1;
        if (scan_cycle_count > 1024) begin
            $display("ERROR: Possible infinite loop in SCAN_TAG_RLE");
            $finish;
        end
    end else begin
        scan_cycle_count <= 0;
    end
end
*/

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
        tag_present <= 0;
        param_cache_valid <= 0;
        rle_done <= 0;
        rle_busy <= 0;
        rle_row_sel <= 0;
        rle_col_sel <= 0;
        rle_valid <= 0;
        param_request <= 0;
        processing_tag <= 0;
        current_run_active <= 0;
        current_run_length <= 0;
    end else begin
        rle_valid <= 0;
        param_request <= 0;

        case (state)
            IDLE: begin
                if (rle_start) begin
                    tag_present <= 0;
					param_cache_valid <= 0;
					rle_row_sel <= 0;
					rle_col_sel <= 0;
                    rle_done <= 0;
                    rle_busy <= 1;
					current_run_start <= 0;
					current_run_active <= 0;
					$display("\nNew Tag buffer.");
                    state <= SCAN_TILE_FOR_TAGS;
                end
            end
            
			SCAN_TILE_FOR_TAGS: begin
				// Scan entire tile to find all unique tags
				if (prim_tag != 0) begin
					tag_present[prim_tag] <= 1;
				end
				
				// Move to next pixel
				if (rle_col_sel < 31) begin
					rle_col_sel <= rle_col_sel + 1;
				end
				else begin
					rle_col_sel <= 0;
					if (rle_row_sel < 31) begin
						rle_row_sel <= rle_row_sel + 1;
					end
					else begin
						// Tile scan complete - PROPERLY transition to SELECT_TAG
						rle_row_sel <= 0;
						rle_col_sel <= 0;
						processing_tag <= find_next_tag(0);  // Start from first tag
						state <= SELECT_TAG;  // This is the critical line!
					end
				end
			end
            
			SELECT_TAG: begin
				if (processing_tag == 10'h3FF) begin
					state <= TILE_COMPLETE;
				end
				else begin
					rle_row_sel <= 0;
					rle_col_sel <= 0;
					current_run_active <= 0;
					current_run_length <= 0;
					
					if (param_cache_valid[processing_tag]) begin
						state <= SCAN_TAG_RLE;
					end
					else begin
						state <= REQUEST_PARAMS;
					end
				end
			end
            
            REQUEST_PARAMS: begin
                param_request <= 1;
                requested_tag <= processing_tag;
                // Assume params will be available next cycle
                param_cache[processing_tag] <= param_data;
                param_cache_valid[processing_tag] <= 1;
				$display("Triangle params requested.");
                rle_row_sel <= 0;
                rle_col_sel <= 0;
                current_run_active <= 0;
                state <= SCAN_TAG_RLE;
            end
            
			SCAN_TAG_RLE: begin
				// Check if current pixel belongs to the current tag
				if (prim_tag == processing_tag) begin
					if (current_run_active) begin
						// Continue current run
						current_run_length <= current_run_length + 1;
					end
					else begin
						// Start new run
						current_run_active <= 1;
						current_run_start <= {rle_row_sel, rle_col_sel};
						current_run_length <= 1;
					end
				end
				else if (current_run_active) begin
					// Tag changed - output current run
					state <= OUTPUT_RUN;
					// DON'T increment scan position - we need to process this pixel again
				end
				
				// Check if we're at the VERY LAST PIXEL (31,31)
				if (rle_row_sel == 31 && rle_col_sel == 31) begin
					if (current_run_active) begin
						state <= OUTPUT_RUN;
					end
					else begin
						state <= TAG_COMPLETE;
					end
				end
				// Advance to next pixel
				else if (rle_col_sel < 31) begin
					rle_col_sel <= rle_col_sel + 1;
				end
				else begin
					rle_col_sel <= 0;
					rle_row_sel <= rle_row_sel + 1;
					state <= ROW_CHANGE_DELAY;
				end
			end
			
			ROW_CHANGE_DELAY: begin
				state <= SCAN_TAG_RLE;
			end

			OUTPUT_RUN: begin
				// Output the RLE run
				rle_tile_x <= tile_x;
				rle_tile_y <= tile_y;
				rle_prim_type <= type_cnt - 1;
				rle_start_addr <= current_run_start;
				rle_run_length <= current_run_length;
				rle_tag <= processing_tag;
				rle_params <= param_cache[processing_tag];
				rle_valid <= 1;
				
				$display("state: %02d  tile_x: %02d  tile_y: %02d  type: %01d  addr: %04d  tag: 0x%03h  run_len: %03d" , 
						  state, tile_x, tile_y, type_cnt-1, current_run_start, processing_tag, current_run_length);
				
				// Reset run tracking
				current_run_active <= 0;
				current_run_length <= 0;
				
				// Check if we just processed the last pixel
				if (rle_row_sel == 31 && rle_col_sel == 31) begin
					state <= TAG_COMPLETE;
				end
				else begin
					// Return to scanning the same pixel that broke the run
					state <= SCAN_TAG_RLE;
				end
			end
            
            TAG_COMPLETE: begin
                // Move to next tag
                processing_tag <= find_next_tag(processing_tag);
                state <= SELECT_TAG;
            end
            
            TILE_COMPLETE: begin
                rle_done <= 1;
                rle_busy <= 0;
                if (~rle_start) begin
                    state <= IDLE;
                end
            end
        endcase
        
        // Cache parameter responses
        if (param_request) begin
            param_cache[requested_tag] <= param_data;
            param_cache_valid[requested_tag] <= 1;
        end
    end
end

endmodule
