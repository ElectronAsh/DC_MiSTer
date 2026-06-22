
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
	
	output reg [19:0] wb_word_addr,		// VRAM 32-bit word address, even-aligned for 64-bit four-pixel writes.
	output reg [63:0] fourpix_out,
	output reg [3:0] wb_byteena,
	output wire [7:0] wb_burstcnt,
	
	//output reg [7:0] wb_burst_cnt,
	//output reg burst_begin,
	output reg vram_wr,
	input vram_wait
);


// Four ARGB (32-bit) pixels per 128-bit word. 256 Words. 1,024 pixels. (32x32 pixel tile).

wire [7:0] pix_word_addr = {y_ps[4:0], x_ps[4:2]};
wire [1:0] pix_lane = x_ps[1:0];

wire [7:0] buff_addr = wb_active ? wb_words_issued[7:0] : pix_word_addr;
wire [3:0] buff_be = 4'b0001 << pix_lane;
wire [9:0] pix_valid_idx = {pix_word_addr, pix_lane};
wire [127:0] buff_dout;

assign argb_buf_out = (pix_lane==2'd0) ? buff_dout[31:00] :
                      (pix_lane==2'd1) ? buff_dout[63:32] :
                      (pix_lane==2'd2) ? buff_dout[95:64] :
                                         buff_dout[127:96];

tile_argb_mem  tile_argb_mem_inst (
	.clock( clock ),					// input  clock
	
	.addr( buff_addr ),				// input [7:0]  addr
	.din( {argb_in, argb_in, argb_in, argb_in} ),	// input [127:0]  din
	.be( buff_be ),					// input [3:0]  be
	.we( wr_pix && !wb_active ),	// input  we
	
	.dout( buff_dout )				// output [127:0]  dout
);


reg [8:0] wb_words_issued;
reg [7:0] wb_read_addr_d;
reg wb_read_valid;
reg wb_active;
reg wb_half_sel;
reg wb_emit_valid;
reg wb_advance_after_write;
reg [127:0] wb_quad_hold;
reg [1023:0] lane_valid;
reg [3:0] wb_lane_valid_hold;
reg wb_clear_invalid;
reg wb_have_last_tile;
reg [5:0] wb_last_tilex;
reg [5:0] wb_last_tiley;
wire [3:0] wb_lane_valid_now = {lane_valid[{wb_read_addr_d, 2'd3}],
                                  lane_valid[{wb_read_addr_d, 2'd2}],
                                  lane_valid[{wb_read_addr_d, 2'd1}],
                                  lane_valid[{wb_read_addr_d, 2'd0}]};
assign wb_busy = wb_active;
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
	wb_word_addr <= 20'd0;
	fourpix_out <= 64'd0;
	 wb_byteena <= 4'd0;
	 wb_words_issued <= 9'd0;
	wb_read_addr_d <= 8'd0;
	wb_read_valid <= 1'b0;
	wb_active <= 1'b0;
	wb_half_sel <= 1'b0;
	wb_emit_valid <= 1'b0;
	wb_advance_after_write <= 1'b0;
	wb_quad_hold <= 128'd0;
	 lane_valid <= 1024'd0;
	 wb_lane_valid_hold <= 4'd0;
	 wb_clear_invalid <= 1'b0;
	 wb_have_last_tile <= 1'b0;
	 wb_last_tilex <= 6'd0;
	 wb_last_tiley <= 6'd0;
	 //wb_burst_cnt <= 8'd16;
	//burst_begin <= 1'b0;
	vram_wr <= 1'b0;
	wb_done <= 1'b0;
	dbg_wr_pix_count <= 32'd0;
	dbg_tile_wb_count <= 32'd0;
	dbg_vram_wr_count <= 32'd0;
	dbg_last_wb_word_addr <= 20'd0;
	dbg_last_fourpix_out <= 64'd0;
end
else begin
	//burst_begin <= 1'b0;
	vram_wr <= 1'b0;
	wb_done <= 1'b0;

	if (wr_pix && !wb_active) begin
		 dbg_wr_pix_count <= dbg_wr_pix_count + 32'd1;
		 lane_valid[pix_valid_idx] <= 1'b1;
	 end

	if (tile_wb) begin
		tilex <= wb_tilex;
		tiley <= wb_tiley;
		wb_words_issued <= 9'd0;
		wb_read_addr_d <= 8'd0;
		wb_read_valid <= 1'b0;
		wb_active <= 1'b1;
		wb_half_sel <= 1'b0;
		wb_emit_valid <= 1'b0;
		wb_advance_after_write <= 1'b0;
		wb_quad_hold <= 128'd0;
		 wb_lane_valid_hold <= 4'd0;
		 wb_clear_invalid <= !wb_have_last_tile || (wb_tilex != wb_last_tilex) || (wb_tiley != wb_last_tiley);
		 wb_have_last_tile <= 1'b1;
		 wb_last_tilex <= wb_tilex;
		 wb_last_tiley <= wb_tiley;
		 wb_byteena <= 4'd0;
		 dbg_tile_wb_count <= dbg_tile_wb_count + 32'd1;
		//burst_begin <= 1'b1;
	end

	// Handle Tile writeback...
	if (wb_active) begin
		if (wb_emit_valid) begin
			 vram_wr <= 1'b1;
			 dbg_last_wb_word_addr <= wb_word_addr;
			 dbg_last_fourpix_out <= fourpix_out;
			 if (!vram_wait) begin
				 dbg_vram_wr_count <= dbg_vram_wr_count + 32'd1;
			 end
			 if (!vram_wait) begin
				wb_emit_valid <= 1'b0;
				if (wb_half_sel && wb_read_addr_d==8'd255) begin
					wb_active <= 1'b0;
					wb_read_valid <= 1'b0;
					wb_done <= 1'b1;
				end
				else begin
					wb_read_valid <= 1'b0;
					wb_advance_after_write <= 1'b1;
				end
			end
		end
		else if (wb_advance_after_write) begin
			wb_advance_after_write <= 1'b0;
			if (!wb_half_sel) begin
				fourpix_out <= {two_pix_to_565_masked(wb_quad_hold, 1'b1, wb_lane_valid_hold, wb_clear_invalid), two_pix_to_565_masked(wb_quad_hold, 1'b1, wb_lane_valid_hold, wb_clear_invalid)};
				 wb_byteena <= wb_clear_invalid ? 4'hF : lane_byteena(wb_lane_valid_hold, 1'b1);
				 wb_word_addr <= wb_word_addr + 20'd1;
				wb_half_sel <= 1'b1;
				wb_emit_valid <= 1'b1;
			end
			else begin
				wb_half_sel <= 1'b0;
			end
		end
		else if (wb_read_valid) begin
			 wb_quad_hold <= buff_dout;
			 wb_lane_valid_hold <= wb_lane_valid_now;
			 lane_valid[{wb_read_addr_d, 2'd0}] <= 1'b0;
			 lane_valid[{wb_read_addr_d, 2'd1}] <= 1'b0;
			 lane_valid[{wb_read_addr_d, 2'd2}] <= 1'b0;
			 lane_valid[{wb_read_addr_d, 2'd3}] <= 1'b0;
			 fourpix_out <= {two_pix_to_565_masked(buff_dout, 1'b0, wb_lane_valid_now, wb_clear_invalid), two_pix_to_565_masked(buff_dout, 1'b0, wb_lane_valid_now, wb_clear_invalid)};
			 wb_byteena <= wb_clear_invalid ? 4'hF : lane_byteena(wb_lane_valid_now, 1'b0);
			 wb_word_addr <= ({tiley, wb_read_addr_d[7:3]} * 320) + {tilex, wb_read_addr_d[2:0], 1'b0};
			wb_half_sel <= 1'b0;
			wb_emit_valid <= 1'b1;
		end
		else if (wb_words_issued < 9'd256) begin
			wb_read_addr_d <= wb_words_issued[7:0];
			wb_words_issued <= wb_words_issued + 9'd1;
			wb_read_valid <= 1'b1;
		end
	end

end

function automatic [3:0] lane_byteena;
	input [3:0] lane_valid_in;
	input half_sel;
begin
	lane_byteena = half_sel ? {{2{lane_valid_in[3]}}, {2{lane_valid_in[2]}}}
	                         : {{2{lane_valid_in[1]}}, {2{lane_valid_in[0]}}};
end
endfunction

function automatic [31:0] two_pix_to_565_masked;
	input [127:0] argb_quad;
	input half_sel;
	input [3:0] lane_valid_in;
	input clear_invalid;
	reg [15:0] pix0;
	reg [15:0] pix1;
	reg [15:0] pix2;
	reg [15:0] pix3;
begin
	pix0 = (lane_valid_in[0] || !clear_invalid) ? {argb_quad[23:19],   argb_quad[15:10],   argb_quad[07:03]}  : 16'h0000;
	pix1 = (lane_valid_in[1] || !clear_invalid) ? {argb_quad[55:51],   argb_quad[47:42],   argb_quad[39:35]}  : 16'h0000;
	pix2 = (lane_valid_in[2] || !clear_invalid) ? {argb_quad[87:83],   argb_quad[79:74],   argb_quad[71:67]}  : 16'h0000;
	pix3 = (lane_valid_in[3] || !clear_invalid) ? {argb_quad[119:115], argb_quad[111:106], argb_quad[103:99]} : 16'h0000;
	two_pix_to_565_masked = half_sel ? {pix3, pix2} : {pix1, pix0};
end
endfunction
endmodule


module tile_argb_mem (
	input clock,
	
	input [7:0] addr,
	input [127:0] din,
	input [3:0] be,
	input we,

	output reg [127:0] dout
);


`ifdef VERILATOR

reg [127:0] buff [0:255];
always @(posedge clock) begin
	if (we) begin
		if (be[0]) buff[ addr ][31:00]  <= din[31:00];
		if (be[1]) buff[ addr ][63:32]  <= din[63:32];
		if (be[2]) buff[ addr ][95:64]  <= din[95:64];
		if (be[3]) buff[ addr ][127:96] <= din[127:96];
	end
	dout <= buff[ addr ];
end

`else

altsyncram #(
	.operation_mode("SINGLE_PORT"),
	.lpm_hint("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=TILE"),
	.width_a(128),
	.numwords_a(256),
	.widthad_a(8),
	.width_byteena_a(16),
	.byte_size(8),
	.init_file("NONE")
) tile_argb_mem_altsyncram (
	.clock0( clock ),
	.address_a( addr ),
	.data_a( din ),
	.wren_a( we ),
	.byteena_a( {be[3],be[3],be[3],be[3], be[2],be[2],be[2],be[2], be[1],be[1],be[1],be[1], be[0],be[0],be[0],be[0]} ),
	.q_a( dout )
);


`endif


endmodule
