`timescale 1ns / 1ps
`default_nettype none

module tile_tag_rle_top #(
    parameter TAG_WIDTH = 12,
    parameter NUM_ROWS  = 32,
    parameter MAX_RLE   = 1024,
    parameter MAX_TAGS  = 128
)(
    input  logic                     clk,
    input  logic                     rst,

    // Per-row primitive write
    input  logic [4:0]               write_row,
    input  logic                     write_enable,
    input  logic [TAG_WIDTH-1:0]     prim_tag,
    input  logic [31:0]              inTri,

    // Global flush signal
    input  logic                     flush_all,
	
	output logic                     flushing,

    // Output RLE
    output logic                     rle_valid,
    output logic [TAG_WIDTH-1:0]     rle_tag,
    output logic [4:0]               rle_row,
    output logic [4:0]               rle_start_x,
    output logic [4:0]               rle_length
);

    // Internal signals
    logic [NUM_ROWS-1:0]         row_flush;
    logic [NUM_ROWS-1:0]         row_valid_out;
    logic [TAG_WIDTH-1:0]        row_rle_tag   [NUM_ROWS-1:0];
    logic [4:0]                  row_rle_start [NUM_ROWS-1:0];
    logic [4:0]                  row_rle_len   [NUM_ROWS-1:0];
    logic [4:0]                  row_rle_row   [NUM_ROWS-1:0];

    // Output FIFO for grouping
    typedef struct packed {
        logic [TAG_WIDTH-1:0] tag;
        logic [4:0]           row;
        logic [4:0]           start_x;
        logic [4:0]           length;
    } rle_t;

    // Bucketed RLEs by tag
    rle_t tag_buckets [0:MAX_TAGS-1][0:MAX_RLE-1];
    logic [$clog2(MAX_RLE)-1:0] bucket_ptr [0:MAX_TAGS-1];
    logic [TAG_WIDTH-1:0]       tag_list   [0:MAX_TAGS-1];
    logic [6:0]                 num_tags;

    // Flush state
    logic [5:0] flush_row_idx;

    // Tag index lookup
    function automatic int find_tag_index(input logic [TAG_WIDTH-1:0] tag);
        int idx;
        begin
            find_tag_index = -1;
            for (idx = 0; idx < num_tags; idx++) begin
                if (tag_list[idx] == tag) begin
                    find_tag_index = idx;
                end
            end
        end
    endfunction

    // Generate row modules
    genvar i;
    generate
        for (i = 0; i < NUM_ROWS; i++) begin : row_gen
            tag_row_rle row_inst (
                .clk(clk),
                .rst(rst),
                .write_enable(write_enable && write_row == i),
                .prim_tag(prim_tag),
                .inTri(inTri),
                .flush(row_flush[i]),
                .row_index(i[4:0]),
                .valid_out(row_valid_out[i]),
                .rle_tag(row_rle_tag[i]),
                .rle_row(row_rle_row[i]),
                .rle_start_x(row_rle_start[i]),
                .rle_length(row_rle_len[i])
            );
        end
    endgenerate

    // Flush controller
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            flush_row_idx <= 0;
            flushing      <= 0;
            row_flush     <= 0;
            num_tags      <= 0;
            for (int t = 0; t < MAX_TAGS; t++) begin
                bucket_ptr[t] <= 0;
                tag_list[t]   <= 0;
            end
        end else begin
            if (flush_all) begin
                flush_row_idx <= 0;
                flushing      <= 1;
                num_tags      <= 0;
            end else if (flushing) begin
                if (flush_row_idx < NUM_ROWS) begin
                    row_flush <= (1 << flush_row_idx);
                    flush_row_idx <= flush_row_idx + 1;
                end else begin
                    row_flush <= 0;
                    flushing <= 0;
                end
            end else begin
                row_flush <= 0;
            end

            // Capture valid outputs into buckets
            for (int j = 0; j < NUM_ROWS; j++) begin
                if (row_valid_out[j]) begin
                    int tag_idx = -1;
                    // Find tag index
                    for (int k = 0; k < num_tags; k++) begin
                        if (tag_list[k] == row_rle_tag[j]) begin
                            tag_idx = k;
                        end
                    end

                    // If new tag, add it to the list
                    if (tag_idx == -1 && num_tags < MAX_TAGS) begin
                        tag_idx = num_tags;
                        tag_list[num_tags] <= row_rle_tag[j];
                        num_tags <= num_tags + 1;
                    end
                    
                    // Capture RLE for the tag in bucket
                    if (tag_idx >= 0) begin
                        tag_buckets[tag_idx][bucket_ptr[tag_idx]].tag     <= row_rle_tag[j];
                        tag_buckets[tag_idx][bucket_ptr[tag_idx]].row     <= row_rle_row[j];
                        tag_buckets[tag_idx][bucket_ptr[tag_idx]].start_x <= row_rle_start[j];
                        tag_buckets[tag_idx][bucket_ptr[tag_idx]].length  <= row_rle_len[j];
                        bucket_ptr[tag_idx] <= bucket_ptr[tag_idx] + 1;
                    end
                end
            end
        end
    end

    // Output sequencer
    logic [6:0] output_tag_idx;
    logic [$clog2(MAX_RLE)-1:0] output_bucket_idx;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            output_tag_idx    <= 0;
            output_bucket_idx <= 0;
            rle_valid         <= 0;
        end else begin
            if (output_tag_idx < num_tags) begin
                if (output_bucket_idx < bucket_ptr[output_tag_idx]) begin
                    rle_valid    <= 1;
                    rle_tag      <= tag_buckets[output_tag_idx][output_bucket_idx].tag;
                    rle_row      <= tag_buckets[output_tag_idx][output_bucket_idx].row;
                    rle_start_x  <= tag_buckets[output_tag_idx][output_bucket_idx].start_x;
                    rle_length   <= tag_buckets[output_tag_idx][output_bucket_idx].length;
                    output_bucket_idx <= output_bucket_idx + 1;
                end else begin
                    output_bucket_idx <= 0;
                    output_tag_idx <= output_tag_idx + 1;
                    rle_valid <= 0;
                end
            end else begin
                rle_valid <= 0;
            end
        end
    end

endmodule
