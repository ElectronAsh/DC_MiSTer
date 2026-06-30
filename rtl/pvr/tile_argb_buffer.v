
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
	input tile_final,
	output reg wb_done,
	output wire wb_busy,

	output reg [19:0] wb_word_addr,		// VRAM 32-bit word address.
	output reg [63:0] fourpix_out,		// [31:0] = two 16bpp pixels; [63:32] duplicate for DDR path.
	output reg [7:0] wb_byteena,
	output wire [7:0] wb_burstcnt,

	output wire vram_wr,
	input vram_wait
);

// Two ARGB (32-bit) pixels per 64-bit word. 512 Words. 1,024 pixels. (32x32 pixel tile).

wire [8:0] pix_word_addr = {y_ps[4:0], x_ps[4:1]};
wire       pix_lane      = x_ps[0];

wire       wb_output_ready = !wb_emit_valid || !vram_wait;
wire       wb_can_issue    = wb_active && wb_output_ready && (wb_words_issued < 10'd512);
wire [8:0] wb_buff_addr    = wb_can_issue ? wb_words_issued[8:0] : wb_read_addr_d;
wire [8:0] bank0_addr      = (wb_active && !wb_bank) ? wb_buff_addr : pix_word_addr;
wire [8:0] bank1_addr      = (wb_active &&  wb_bank) ? wb_buff_addr : pix_word_addr;
wire [1:0] buff_be       = 2'b01 << pix_lane;
wire [63:0] bank0_dout;
wire [63:0] bank1_dout;
wire [1:0] bank0_valid_dout;
wire [1:0] bank1_valid_dout;
wire [63:0] wb_buff_dout = wb_bank ? bank1_dout : bank0_dout;
wire [63:0] accum_buff_dout = accum_bank ? bank1_dout : bank0_dout;

assign argb_buf_out = pix_lane ? accum_buff_dout[63:32] : accum_buff_dout[31:0];

tile_argb_mem tile_argb_mem_bank0 (
	.clock( clock ),

	.addr( bank0_addr ),
	.din( {argb_in, argb_in} ),
	.be( buff_be ),
	.we( wr_pix && !accum_bank && (!wb_active || wb_bank) ),

	.dout( bank0_dout )
);

tile_argb_mem tile_argb_mem_bank1 (
	.clock( clock ),

	.addr( bank1_addr ),
	.din( {argb_in, argb_in} ),
	.be( buff_be ),
	.we( wr_pix && accum_bank && (!wb_active || !wb_bank) ),

	.dout( bank1_dout )
);

tile_valid_mem tile_valid_mem_bank0 (
	.clock( clock ),
	.reset_n( reset_n ),
	.wr_addr( pix_word_addr ),
	.wr_be( buff_be ),
	.wr_en( wr_pix && !accum_bank && (!wb_active || wb_bank) ),
	.clear_addr( wb_buff_addr ),
	.clear_en( wb_can_issue && !wb_bank ),
	.dout( bank0_valid_dout )
);

tile_valid_mem tile_valid_mem_bank1 (
	.clock( clock ),
	.reset_n( reset_n ),
	.wr_addr( pix_word_addr ),
	.wr_be( buff_be ),
	.wr_en( wr_pix && accum_bank && (!wb_active || !wb_bank) ),
	.clear_addr( wb_buff_addr ),
	.clear_en( wb_can_issue && wb_bank ),
	.dout( bank1_valid_dout )
);


// wb_words_issued is 10-bit so it can reach 512 without wrapping.
reg  [9:0]  wb_words_issued;
reg  [8:0]  wb_read_addr_d;
reg         wb_read_valid;
reg         wb_active;
reg         wb_emit_valid;
reg         wb_emit_last;
reg         accum_bank;
reg         wb_bank;
reg         wb_clear_invalid;
reg         wb_have_last_tile;
reg  [5:0]  wb_last_tilex;
reg  [5:0]  wb_last_tiley;
reg         wb_request_pending;
reg  [5:0]  wb_pending_tilex;
reg  [5:0]  wb_pending_tiley;
reg         wb_pending_final;
reg         wb_release_early;

// Two lane-valid bits per 64-bit RAM word (one per ARGB pixel).
wire [1:0] wb_lane_valid_now = wb_bank ? bank1_valid_dout : bank0_valid_dout;

// Kludge, for writing only the pixels in Translucent polys, if the ALPHA is above a certain threshold.
// A bit like Punch Through textures, until we can get the proper Alpha blending put back in. ElectronAsh.
parameter ALPHA_WRITE_THRESHOLD = 8'hFF;
											
wire pix0_alpha_opaque = (wb_buff_dout[31:24] >= ALPHA_WRITE_THRESHOLD);
wire pix1_alpha_opaque = (wb_buff_dout[63:56] >= ALPHA_WRITE_THRESHOLD);

wire [1:0] wb_lane_valid_alpha =
{
    wb_lane_valid_now[1] & pix1_alpha_opaque,
    wb_lane_valid_now[0] & pix0_alpha_opaque
};

assign wb_busy    = wb_active || wb_request_pending;
assign wb_burstcnt = (wb_active && wb_emit_valid && (wb_word_addr[2:0] == 3'd0)) ? 8'd8 : 8'd1;
assign vram_wr = wb_active && wb_emit_valid;

reg [5:0] tilex;
reg [5:0] tiley;

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
	wb_emit_last    <= 1'b0;
	accum_bank      <= 1'b0;
	wb_bank         <= 1'b0;
	wb_clear_invalid   <= 1'b0;
	wb_have_last_tile  <= 1'b0;
	wb_last_tilex      <= 6'd0;
	wb_last_tiley      <= 6'd0;
	wb_request_pending <= 1'b0;
	wb_pending_tilex   <= 6'd0;
	wb_pending_tiley   <= 6'd0;
	wb_pending_final   <= 1'b0;
	wb_release_early   <= 1'b0;
	wb_done         <= 1'b0;
end
else begin
	wb_done <= 1'b0;

	if (tile_wb) begin
		if (wb_active) begin
			wb_request_pending <= 1'b1;
			wb_pending_tilex <= wb_tilex;
			wb_pending_tiley <= wb_tiley;
			wb_pending_final <= tile_final;
		end
		else begin
			tilex           <= wb_tilex;
			tiley           <= wb_tiley;
			wb_bank         <= accum_bank;
			wb_release_early <= tile_final;
			if (tile_final)
				accum_bank <= ~accum_bank;
			wb_words_issued <= 10'd0;
			wb_read_addr_d  <= 9'd0;
			wb_read_valid   <= 1'b0;
			wb_active       <= 1'b1;
			wb_emit_valid   <= 1'b0;
			wb_emit_last    <= 1'b0;
			wb_clear_invalid  <= !wb_have_last_tile || (wb_tilex != wb_last_tilex) || (wb_tiley != wb_last_tiley);
			wb_have_last_tile <= 1'b1;
			wb_last_tilex     <= wb_tilex;
			wb_last_tiley     <= wb_tiley;
			wb_byteena       <= 8'd0;
			wb_done          <= tile_final;
		end
	end
	else if (wb_request_pending && !wb_active) begin
		tilex           <= wb_pending_tilex;
		tiley           <= wb_pending_tiley;
		wb_bank         <= accum_bank;
		wb_release_early <= wb_pending_final;
		if (wb_pending_final)
			accum_bank <= ~accum_bank;
		wb_words_issued <= 10'd0;
		wb_read_addr_d  <= 9'd0;
		wb_read_valid   <= 1'b0;
		wb_active       <= 1'b1;
		wb_emit_valid   <= 1'b0;
		wb_emit_last    <= 1'b0;
		wb_clear_invalid  <= !wb_have_last_tile ||
		                     (wb_pending_tilex != wb_last_tilex) ||
		                     (wb_pending_tiley != wb_last_tiley);
		wb_have_last_tile <= 1'b1;
		wb_last_tilex     <= wb_pending_tilex;
		wb_last_tiley     <= wb_pending_tiley;
		wb_request_pending <= 1'b0;
		wb_byteena       <= 8'd0;
		wb_done          <= wb_pending_final;
	end

	// Writeback: one RAM read (64-bit = 2 ARGB pixels) → one DDR write (32-bit = 2x 16bpp).
	// No half-word ping-pong needed — each word address maps 1:1 to a DDR write.
	if (wb_active) begin
		if (wb_emit_valid && !vram_wait) begin
			if (wb_emit_last) begin
				wb_active <= 1'b0;
				if (!wb_release_early)
					wb_done <= 1'b1;
			end
		end

		if (wb_output_ready) begin
			if (wb_read_valid) begin
				//fourpix_out <= {two_pix_to_565_masked(buff_dout, wb_lane_valid_now, wb_clear_invalid),
				//                two_pix_to_565_masked(buff_dout, wb_lane_valid_now, wb_clear_invalid)};
				fourpix_out <= {two_pix_to_565_masked(wb_buff_dout, wb_lane_valid_alpha, wb_clear_invalid),
									 two_pix_to_565_masked(wb_buff_dout, wb_lane_valid_alpha, wb_clear_invalid)};

				wb_byteena <= wb_clear_invalid ? 8'h0f : lane_byteena(wb_lane_valid_now);
				wb_word_addr <= ({tiley, wb_read_addr_d[8:4]} * 320) +
				                {tilex, wb_read_addr_d[3:0]};
				wb_emit_valid <= 1'b1;
				wb_emit_last  <= (wb_read_addr_d == 9'd511);
			end
			else begin
				wb_emit_valid <= 1'b0;
				wb_emit_last  <= 1'b0;
			end

			if (wb_words_issued < 10'd512) begin
				wb_read_addr_d  <= wb_words_issued[8:0];
				wb_words_issued <= wb_words_issued + 10'd1;
				wb_read_valid   <= 1'b1;
			end
			else begin
				wb_read_valid <= 1'b0;
			end
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


module tile_valid_mem (
	input clock,
	input reset_n,

	input [8:0] wr_addr,
	input [1:0] wr_be,
	input       wr_en,

	input [8:0] clear_addr,
	input       clear_en,

	output wire [1:0] dout
);

`ifdef VERILATOR

reg [1:0] valid_mem [0:511];
reg [1:0] dout_r;
reg       clear_pending;
reg [8:0] clear_addr_d;
integer valid_i;

assign dout = dout_r;

initial begin
	for (valid_i = 0; valid_i < 512; valid_i = valid_i + 1)
		valid_mem[valid_i] = 2'b00;
end

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		clear_pending <= 1'b0;
		clear_addr_d <= 9'd0;
		dout_r <= 2'b00;
	end
	else begin
		if (clear_pending)
			valid_mem[clear_addr_d] <= 2'b00;
		else if (wr_en) begin
			if (wr_be[0]) valid_mem[wr_addr][0] <= 1'b1;
			if (wr_be[1]) valid_mem[wr_addr][1] <= 1'b1;
		end
		dout_r <= valid_mem[clear_addr];
		clear_pending <= clear_en;
		clear_addr_d <= clear_addr;
	end
end

`else

wire [9:0] valid_q;
reg        clear_pending;
reg  [8:0] clear_addr_d;
wire       port_a_clear = clear_pending;
wire [8:0] port_a_addr = port_a_clear ? clear_addr_d : wr_addr;
wire [9:0] port_a_data = port_a_clear ? 10'd0 : 10'h3ff;
wire [1:0] port_a_be = port_a_clear ? 2'b11 : wr_be;
wire       port_a_we = port_a_clear || wr_en;

assign dout = {valid_q[5], valid_q[0]};

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		clear_pending <= 1'b0;
		clear_addr_d <= 9'd0;
	end
	else begin
		clear_pending <= clear_en;
		clear_addr_d <= clear_addr;
	end
end

altsyncram #(
	.operation_mode("DUAL_PORT"),
	.width_a(10),
	.numwords_a(512),
	.widthad_a(9),
	.width_b(10),
	.numwords_b(512),
	.widthad_b(9),
	.width_byteena_a(2),
	.byte_size(5),
	.init_file("NONE")
) tile_valid_mem_altsyncram (
	.clock0( clock ),
	.clock1( clock ),
	.address_a( port_a_addr ),
	.data_a( port_a_data ),
	.wren_a( port_a_we ),
	.byteena_a( port_a_be ),
	.address_b( clear_addr ),
	.q_b( valid_q )
);

`endif

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
