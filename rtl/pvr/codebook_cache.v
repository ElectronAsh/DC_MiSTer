`timescale 1ns / 1ps
`default_nettype none

module codebook_cache (
    input wire clock,
    input wire reset_n,

    input wire cache_clear,

    input wire [11:0] tag_in,			// 12-bit unique triangle identifier (debug/legacy)
    input wire [20:0] codebook_base,	// VQ codebook base word address
    input wire [7:0] read_index,		// 8-bit offset within the triangle's palette block
    input wire cache_read,				// Read request signal

    input wire tex_vram_valid,			// VRAM data valid signal
    output wire codebook_wait,			// Cache waiting signal
    output wire [7:0] ram_read_offset,	// Offset for reading VRAM
    input wire [63:0] cache_din,		// Input data to cache from VRAM
    output reg cache_hit,				// Indicates if the requested tag is in cache
    output wire [63:0] cache_dout		// 64-bit palette entry if cache hit
);

// Cache parameters
localparam CACHE_SLOTS = 8;	// Number of persistent codebooks to keep.
localparam SLOT_BITS   = 3;		// log2(CACHE_SLOTS)
localparam ENTRY_WORDS = 256;	// 256 words per VQ codebook.
localparam INDEX_BITS  = 8;
localparam BASE_WIDTH  = 21;
localparam WORD_WIDTH  = 64;	// 64-bit data width
localparam DATA_ADDR_WIDTH = SLOT_BITS + INDEX_BITS;

reg [CACHE_SLOTS-1:0] cache_valid;
reg [BASE_WIDTH-1:0]  base_tags [0:CACHE_SLOTS-1];
reg [SLOT_BITS-1:0]   replace_slot;
reg [SLOT_BITS-1:0]   fill_slot;
reg [BASE_WIDTH-1:0]  fill_base;
reg [8:0] word_index;

`ifdef VERILATOR
reg [31:0] cb_base_hit_count;
reg [31:0] cb_base_miss_count;
reg [31:0] cb_fill_count;
reg [31:0] cb_evict_count;
reg [31:0] cb_slot0_hit_count;
reg [31:0] cb_slot1_hit_count;
reg [31:0] cb_slot2_hit_count;
reg [31:0] cb_slot3_hit_count;
reg [31:0] cb_slot4_hit_count;
reg [31:0] cb_slot5_hit_count;
reg [31:0] cb_slot6_hit_count;
reg [31:0] cb_slot7_hit_count;
`endif

reg hit_now;
reg [SLOT_BITS-1:0] hit_slot;
integer hit_i;
always @(*) begin
    hit_now = 1'b0;
    hit_slot = {SLOT_BITS{1'b0}};
    for (hit_i = 0; hit_i < CACHE_SLOTS; hit_i = hit_i + 1) begin
        if (!hit_now && cache_valid[hit_i] && (base_tags[hit_i] == codebook_base)) begin
            hit_now = 1'b1;
            hit_slot = hit_i;
        end
    end
end

wire [(DATA_ADDR_WIDTH)-1:0] cache_addr = codebook_wait ? {fill_slot, word_index[7:0]} :
                                                          {hit_slot,  read_index};

`ifdef VERILATOR
single_port_ram #(
    .DATA_WIDTH(WORD_WIDTH),
    .ADDR_WIDTH(DATA_ADDR_WIDTH)
) data_cache (
    .clk(clock),
    .addr(cache_addr),
    .din(cache_din),
    .we(codebook_wait && tex_vram_valid),
    .dout(cache_dout)
);
`else
altsyncram #(
    .operation_mode("SINGLE_PORT"),
    .width_a(WORD_WIDTH),					// Data width
    .numwords_a(CACHE_SLOTS*ENTRY_WORDS),	// Number of words across all cached codebooks
    .widthad_a(DATA_ADDR_WIDTH),
    .init_file("NONE")						// No initial contents, empty at startup
) data_memory (
    .clock0(clock),
    .address_a(cache_addr),
    .data_a(cache_din),
    .wren_a(codebook_wait && tex_vram_valid),
    .q_a(cache_dout)
);
`endif

wire start_fill = cache_read && !hit_now && !codebook_wait;

// Cache update logic
integer i;
always @(posedge clock or negedge reset_n)
if (!reset_n) begin
    cache_valid <= {CACHE_SLOTS{1'b0}};
    replace_slot <= {SLOT_BITS{1'b0}};
    fill_slot <= {SLOT_BITS{1'b0}};
    fill_base <= {BASE_WIDTH{1'b0}};
    word_index <= 9'd256;
    cache_hit <= 1'b0;
`ifdef VERILATOR
    cb_base_hit_count <= 32'd0;
    cb_base_miss_count <= 32'd0;
    cb_fill_count <= 32'd0;
    cb_evict_count <= 32'd0;
    cb_slot0_hit_count <= 32'd0;
    cb_slot1_hit_count <= 32'd0;
    cb_slot2_hit_count <= 32'd0;
    cb_slot3_hit_count <= 32'd0;
    cb_slot4_hit_count <= 32'd0;
    cb_slot5_hit_count <= 32'd0;
    cb_slot6_hit_count <= 32'd0;
    cb_slot7_hit_count <= 32'd0;
`endif
    for (i = 0; i < CACHE_SLOTS; i = i + 1) begin
        base_tags[i] <= {BASE_WIDTH{1'b0}};
    end
end
else begin
    if (cache_clear) cache_valid <= {CACHE_SLOTS{1'b0}};

	cache_hit <= hit_now;

`ifdef VERILATOR
    if (cache_read && !codebook_wait) begin
        if (hit_now) begin
            cb_base_hit_count <= cb_base_hit_count + 32'd1;
            case (hit_slot)
                3'd0: cb_slot0_hit_count <= cb_slot0_hit_count + 32'd1;
                3'd1: cb_slot1_hit_count <= cb_slot1_hit_count + 32'd1;
                3'd2: cb_slot2_hit_count <= cb_slot2_hit_count + 32'd1;
                3'd3: cb_slot3_hit_count <= cb_slot3_hit_count + 32'd1;
                3'd4: cb_slot4_hit_count <= cb_slot4_hit_count + 32'd1;
                3'd5: cb_slot5_hit_count <= cb_slot5_hit_count + 32'd1;
                3'd6: cb_slot6_hit_count <= cb_slot6_hit_count + 32'd1;
                3'd7: cb_slot7_hit_count <= cb_slot7_hit_count + 32'd1;
            endcase
        end
        else begin
            cb_base_miss_count <= cb_base_miss_count + 32'd1;
        end
    end
`endif

    if (start_fill) begin
        fill_slot <= replace_slot;
        fill_base <= codebook_base;
`ifdef VERILATOR
        cb_fill_count <= cb_fill_count + 32'd1;
        if (cache_valid[replace_slot]) cb_evict_count <= cb_evict_count + 32'd1;
`endif
        cache_valid[replace_slot] <= 1'b0;
        replace_slot <= replace_slot + {{(SLOT_BITS-1){1'b0}}, 1'b1};
        word_index <= 9'd0;    // Trigger a codebook read from VRAM
    end

    // Handle VQ Code Book reading
    if (codebook_wait) begin
        if (tex_vram_valid) begin
            if (word_index == 9'd255) begin
                base_tags[fill_slot] <= fill_base;
                cache_valid[fill_slot] <= 1'b1;
            end
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
