`timescale 1ns / 1ps
`default_nettype none
module codebook_cache (
    input wire clock,
    input wire reset_n,
    
    input wire cache_clear,
    
    input wire [9:0] tag_in,			// 9-bit unique triangle identifier
    input wire [7:0] read_index,		// 8-bit offset within the triangle's palette block
    input wire cache_read,				// Read request signal
    
    input wire vram_valid,				// 
    output wire cache_wait,				// 
    output wire [7:0] ram_read_offset,	// 
    input wire [63:0] cache_din,		// 
    
    output wire cache_hit,			// Indicates if the requested tag is in cache
    output wire [63:0] cache_dout	// 64-bit palette entry if cache hit
);

// Cache parameters
//
// (32 entries seems a sweet-spot. Only drops about 1-2 FPS on average).
// 32 entries = 64KB. 64 entries = 128KB etc.
//
// I'm sure this would be even faster, if the actual Texture (codebook) base address was used as the Tag.
//
// EDIT: Using some upper bits of the texture address as the CB cache "Tag" now. Renders even faster.
// (since the CB cache is now used across multiple tiles, not just per-tile.)
//
localparam CACHE_DEPTH = 1024;	// 1024 entries to match triangle tag width.
localparam ENTRY_SIZE = 256;	// 256 words per triangle CB block
localparam TAG_WIDTH = 10;
localparam WORD_WIDTH = 64;

// Cache storage
reg [TAG_WIDTH-1:0]  cache_tags [0:CACHE_DEPTH-1];
reg [WORD_WIDTH-1:0] cache_data [0:CACHE_DEPTH-1][0:ENTRY_SIZE-1];
// Cache valid bits
reg [CACHE_DEPTH-1:0] cache_valid;

// Combinational hit detection
assign cache_hit = cache_valid[tag_in] && (cache_tags[tag_in] == tag_in);

// Combinational output assignments
assign cache_dout = /*cache_hit ?*/ cache_data[tag_in][read_index] /*: 64'hX*/;  // Don't care value for miss

// VQ Code Book. 256 64-bit Words.
reg [8:0] word_index;

// Cache update logic 
always @(posedge clock or negedge reset_n)
if (!reset_n) begin
    cache_valid <= 0;
    word_index <= 9'd256;
end
else begin
    if (cache_clear) cache_valid <= 0;
    
    if (cache_read && !cache_hit) begin
        cache_tags[tag_in]  <= tag_in;
        cache_valid[tag_in] <= 1'b1;
        word_index <= 9'd0;    // Trigger a codebook read from VRAM.
    end
    
    // Handle VQ Code Book reading.
    if (cache_wait) begin
        if (vram_valid) begin
            cache_data[tag_in][word_index[7:0]] <= cache_din;
            word_index <= word_index + 9'd1;
        end
    end
end

assign cache_wait = !word_index[8];
assign ram_read_offset = word_index[7:0];

endmodule
