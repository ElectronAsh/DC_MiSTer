
`timescale 1ns / 1ps
`default_nettype none

module tile_argb_buffer (
	input clock,
	input reset_n,

	input [10:0] x_ps,	// Current screen pix coord.
	input [10:0] y_ps,	// For writing TO the tile buffer.
	input [5:0] wb_tilex,
	input [5:0] wb_tiley,

	input wr_pix,
	input [31:0] argb_in,

	output wire [31:0] argb_buf_out,

	input tile_wb,
	output reg wb_done,
	output wire wb_busy,

	output reg [19:0] wb_word_addr,		// VRAM 32-bit word address.
	output reg [63:0] fourpix_out,		// [31:0] = two 16bpp pixels; [63:32] duplicate for DDR path.
	output reg [7:0] wb_byteena,
	output wire [7:0] wb_burstcnt,

	output reg vram_wr,
	input vram_wait
);

// Two ARGB (32-bit) pixels per 64-bit word. 512 Words. 1,024 pixels. (32x32 pixel tile).

wire [8:0] pix_word_addr = {y_ps[4:0], x_ps[4:1]};
wire       pix_lane      = x_ps[0];

wire [8:0] buff_addr     = wb_active ? wb_words_issued[8:0] : pix_word_addr;
wire [1:0] buff_be       = 2'b01 << pix_lane;
wire [9:0] pix_valid_idx = {pix_word_addr, pix_lane};
wire [63:0] buff_dout;

assign argb_buf_out = pix_lane ? buff_dout[63:32] : buff_dout[31:0];

tile_argb_mem  tile_argb_mem_inst (
	.clock( clock ),

	.addr( buff_addr ),
	.din( {argb_in, argb_in} ),
	.be( buff_be ),
	.we( wr_pix && !wb_active ),

	.dout( buff_dout )
);


// wb_words_issued is 10-bit so it can reach 512 without wrapping.
reg  [9:0]  wb_words_issued;
reg  [8:0]  wb_read_addr_d;
reg         wb_read_valid;
reg         wb_active;
reg         wb_emit_valid;
reg [1023:0] lane_valid;
reg         wb_clear_invalid;
reg         wb_have_last_tile;
reg  [5:0]  wb_last_tilex;
reg  [5:0]  wb_last_tiley;

// Two lane-valid bits per 64-bit RAM word (one per ARGB pixel).
wire [1:0] wb_lane_valid_now = {lane_valid[{wb_read_addr_d, 1'b1}],
                                 lane_valid[{wb_read_addr_d, 1'b0}]};
assign wb_busy    = wb_active;
assign wb_burstcnt = (wb_active && wb_emit_valid && (wb_word_addr[2:0] == 3'd0)) ? 8'd8 : 8'd1;

reg [5:0] tilex;
reg [5:0] tiley;

(* keep *) reg [31:0] dbg_wr_pix_count;
(* keep *) reg [31:0] dbg_tile_wb_count;
(* keep *) reg [31:0] dbg_vram_wr_count;
(* keep *) reg [19:0] dbg_last_wb_word_addr;
(* keep *) reg [63:0] dbg_last_fourpix_out;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	wb_word_addr    <= 20'd0;
	fourpix_out     <= 64'd0;
	wb_byteena      <= 8'd0;
	wb_words_issued <= 10'd0;
	wb_read_addr_d  <= 9'd0;
	wb_read_valid   <= 1'b0;
	wb_active       <= 1'b0;
	wb_emit_valid   <= 1'b0;
	lane_valid      <= 1024'd0;
	wb_clear_invalid   <= 1'b0;
	wb_have_last_tile  <= 1'b0;
	wb_last_tilex      <= 6'd0;
	wb_last_tiley      <= 6'd0;
	vram_wr         <= 1'b0;
	wb_done         <= 1'b0;
	dbg_wr_pix_count   <= 32'd0;
	dbg_tile_wb_count  <= 32'd0;
	dbg_vram_wr_count  <= 32'd0;
	dbg_last_wb_word_addr <= 20'd0;
	dbg_last_fourpix_out  <= 64'd0;
end
else begin
	vram_wr <= 1'b0;
	wb_done <= 1'b0;

	if (wr_pix && !wb_active) begin
		dbg_wr_pix_count <= dbg_wr_pix_count + 32'd1;
		lane_valid[pix_valid_idx] <= 1'b1;
	end

	if (tile_wb) begin
		tilex           <= wb_tilex;
		tiley           <= wb_tiley;
		wb_words_issued <= 10'd0;
		wb_read_addr_d  <= 9'd0;
		wb_read_valid   <= 1'b0;
		wb_active       <= 1'b1;
		wb_emit_valid   <= 1'b0;
		wb_clear_invalid  <= !wb_have_last_tile || (wb_tilex != wb_last_tilex) || (wb_tiley != wb_last_tiley);
		wb_have_last_tile <= 1'b1;
		wb_last_tilex     <= wb_tilex;
		wb_last_tiley     <= wb_tiley;
		wb_byteena      	<= 8'd0;
		dbg_tile_wb_count <= dbg_tile_wb_count + 32'd1;
	end

	// Writeback: one RAM read (64-bit = 2 ARGB pixels) → one DDR write (32-bit = 2x 16bpp).
	// No half-word ping-pong needed — each word address maps 1:1 to a DDR write.
	if (wb_active) begin
		if (wb_emit_valid) begin
			vram_wr <= 1'b1;
			dbg_last_wb_word_addr <= wb_word_addr;
			dbg_last_fourpix_out  <= fourpix_out;
			if (!vram_wait) begin
				dbg_vram_wr_count <= dbg_vram_wr_count + 32'd1;
				wb_emit_valid <= 1'b0;
				if (wb_read_addr_d == 9'd511) begin
					wb_active     <= 1'b0;
					wb_read_valid <= 1'b0;
					wb_done       <= 1'b1;
				end
			end
		end
		else if (wb_read_valid) begin
			// Convert the two ARGB pixels in buff_dout to 16bpp and prepare the DDR word.
			lane_valid[{wb_read_addr_d, 1'b0}] <= 1'b0;
			lane_valid[{wb_read_addr_d, 1'b1}] <= 1'b0;
			fourpix_out <= {two_pix_to_565_masked(buff_dout, wb_lane_valid_now, wb_clear_invalid),
			                two_pix_to_565_masked(buff_dout, wb_lane_valid_now, wb_clear_invalid)};
			wb_byteena  <= wb_clear_invalid ? 8'hF : lane_byteena(wb_lane_valid_now);
			// wb_read_addr_d[8:4] = row within tile, wb_read_addr_d[3:0] = pixel-pair column within tile.
			wb_word_addr <= ({tiley, wb_read_addr_d[8:4]} * 320) + {tilex, wb_read_addr_d[3:0]};
			wb_read_valid <= 1'b0;
			wb_emit_valid <= 1'b1;
		end
		else if (wb_words_issued < 10'd512) begin
			wb_read_addr_d  <= wb_words_issued[8:0];
			wb_words_issued <= wb_words_issued + 10'd1;
			wb_read_valid   <= 1'b1;
		end
	end

end

// lane_byteena: 2 byteena bits per 16bpp pixel (one per byte).
function automatic [3:0] lane_byteena;
	input [1:0] lane_valid_in;
begin
	lane_byteena = {{2{lane_valid_in[1]}}, {2{lane_valid_in[0]}}};
end
endfunction

// Convert two ARGB32 pixels (packed in a 64-bit word) to two RGB565 pixels.
// Returns {pix1_565, pix0_565} in [31:0].
function automatic [31:0] two_pix_to_565_masked;
	input [63:0] argb_pair;
	input [1:0]  lane_valid_in;
	input        clear_invalid;
	reg [15:0] pix0;
	reg [15:0] pix1;
begin
	pix0 = (lane_valid_in[0] || !clear_invalid) ? {argb_pair[23:19], argb_pair[15:10], argb_pair[07:03]} : 16'h0000;
	pix1 = (lane_valid_in[1] || !clear_invalid) ? {argb_pair[55:51], argb_pair[47:42], argb_pair[39:35]} : 16'h0000;
	two_pix_to_565_masked = {pix1, pix0};
end
endfunction
endmodule


module tile_argb_mem (
	input clock,

	input  [8:0]  addr,
	input  [63:0] din,
	input  [1:0]  be,
	input         we,

	output reg [63:0] dout
);


`ifdef VERILATOR

reg [63:0] buff [0:511];
always @(posedge clock) begin
	if (we) begin
		if (be[0]) buff[ addr ][31:00] <= din[31:00];
		if (be[1]) buff[ addr ][63:32] <= din[63:32];
	end
	dout <= buff[ addr ];
end

`else

altsyncram #(
	.operation_mode("SINGLE_PORT"),
	.lpm_hint("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=TILE"),
	.width_a(64),
	.numwords_a(512),
	.widthad_a(9),
	.width_byteena_a(8),
	.byte_size(8),
	.init_file("NONE")
) tile_argb_mem_altsyncram (
	.clock0( clock ),
	.address_a( addr ),
	.data_a( din ),
	.wren_a( we ),
	.byteena_a( {be[1],be[1],be[1],be[1], be[0],be[0],be[0],be[0]} ),
	.q_a( dout )
);


`endif

endmodule
