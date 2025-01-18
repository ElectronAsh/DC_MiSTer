`timescale 1ns / 1ps
`default_nettype none

module codebook_cache (
    input wire clock,
    input wire reset_n,
    
    input wire cache_clear,
    
    input wire [9:0] tag_in,				// 10-bit unique triangle identifier
    input wire [7:0] read_index,			// 8-bit offset within the triangle's palette block
    input wire cache_read,					// Read request signal
    
    input wire vram_valid,					// VRAM data valid signal
    output wire codebook_wait,				// Cache waiting signal
    output wire [7:0] ram_read_offset,	// Offset for reading VRAM
    input wire [63:0] cache_din,			// Input data to cache from VRAM
    output wire cache_hit,					// Indicates if the requested tag is in cache
    output wire [63:0] cache_dout		// 64-bit palette entry if cache hit
);

// Cache parameters
localparam CACHE_DEPTH = 256;	// Number of Cache entries.
localparam ADDR_WIDTH  = 8;	// Address width (log2(CACHE_DEPTH))
localparam TAG_WIDTH   = 8;	// Tag width

localparam ENTRY_SIZE  = 256;	// 256 words per triangle CB block

localparam WORD_WIDTH  = 64;	// 64-bit data width

`ifdef VERILATOR
// Block RAM for storing tags
wire [TAG_WIDTH-1:0] tag_out;
single_port_ram #(
    .DATA_WIDTH(TAG_WIDTH),		// Tag width
    .ADDR_WIDTH(ADDR_WIDTH)		// Address width for port A (10 bits for 1024 entries)
) tag_cache (
    .clk(clock),				// Connect clock to port A
    .addr(tag_in),				// Address input for port A
    .din(tag_in),				// Data input for port A (write operation)
    .we(cache_read && !cache_hit),			// Write enable for port A
    .dout(tag_out)				// Output data for port A
);

// Block RAM for storing data
single_port_ram #(
    .DATA_WIDTH(WORD_WIDTH),	// Data width
    .ADDR_WIDTH(TAG_WIDTH+ADDR_WIDTH)		// Address width for port A (10 bits for 1024 entries)
) data_cache (
    .clk(clock),				// Connect clock to port A
    .addr(cache_addr),				// Address input for port A
    .din(cache_din),			// Data input for port A (write operation)
    .we(codebook_wait && vram_valid),			// Write enable for port A
    .dout(cache_dout)			// Output data for port A
);
`else
// Block RAM for storing tags (Using altsyncram)
wire [TAG_WIDTH-1:0] tag_out;
altsyncram #(
    .operation_mode("SINGLE_PORT"),	// Two-port RAM (for read/write)
    .width_a(TAG_WIDTH),				// Tag width
    .numwords_a(CACHE_DEPTH),			// Number of entries
    .widthad_a(ADDR_WIDTH),			// Address width for port A (10 bits for 1024 entries)
    .init_file("NONE")					// No initial contents, empty at startup
) tag_memory (
    .clock0(clock),						// Connect clock to port A
    .address_a(tag_in),					// Address input for port A
    .data_a(tag_in),						// Data input for port A (write operation)
    .wren_a(cache_read && !cache_hit),				// Write enable for port A
    .q_a(tag_out)							// Output data for port A
);

// Block RAM for storing data (Using altsyncram)
altsyncram #(
    .operation_mode("SINGLE_PORT"),	// Two-port RAM (for read/write)
    .width_a(WORD_WIDTH),				// Data width
    .numwords_a(CACHE_DEPTH+ENTRY_SIZE),// Number of entries
    .widthad_a(TAG_WIDTH+ADDR_WIDTH),	// Address width for port A (10 bits for 1024 entries)
    .init_file("NONE")					// No initial contents, empty at startup
) data_memory (
    .clock0(clock),						// Connect clock to port A
    .address_a(cache_addr),					// Address input for port A
    .data_a(cache_din),					// Data input for port A (write operation)
    .wren_a(codebook_wait && vram_valid),				// Write enable for port A
    .q_a(cache_dout)						// Output data for port A
);
`endif


wire [(TAG_WIDTH+ADDR_WIDTH)-1:0] cache_addr = (codebook_wait) ? {tag_in, word_index[7:0]} : {tag_in, read_index};

// Cache valid bits
reg [CACHE_DEPTH-1:0] cache_valid;

// Cache hit detection logic
assign cache_hit = cache_valid[tag_in] && (tag_out == tag_in);

// VQ Code Book (256 64-bit Words)
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
        // Store the tag in block memory
        cache_valid[tag_in] <= 1'b1;
        word_index <= 9'd0;    // Trigger a codebook read from VRAM
    end
    
    // Handle VQ Code Book reading
    if (codebook_wait) begin
        if (vram_valid) begin
            word_index <= word_index + 9'd1; // Increment word index
        end
    end
end

// Control signals for reading from VRAM
assign codebook_wait = !word_index[8];
assign ram_read_offset = word_index[7:0];

endmodule

`ifdef VERILATOR
module single_port_ram #(
    parameter DATA_WIDTH = 8,  // Width of the data bus
    parameter ADDR_WIDTH = 8  // Width of the address bus (2^ADDR_WIDTH = memory depth)
)(
    input wire clk,            // Clock
    input wire we,             // Write enable
    input wire [ADDR_WIDTH-1:0] addr, // Address bus
    input wire [DATA_WIDTH-1:0] din,  // Data input bus
    output reg [DATA_WIDTH-1:0] dout  // Data output bus
);

    // Calculate memory depth
    localparam MEM_DEPTH = 1 << ADDR_WIDTH;

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Process for single-port RAM
    always @(posedge clk) begin
        if (we) begin
            // Write operation
            mem[addr] <= din;
        end
        // Read operation
        dout <= mem[addr];
    end

endmodule
`endif
