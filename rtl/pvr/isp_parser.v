`timescale 1ns / 1ps
`default_nettype none

// Enable verbose ISP/TSP trace prints with +define+PVR_TSP_TRACE_PRINTS.
// `define PVR_TSP_TRACE_PRINTS
// Enable Tag/Z buffer row write/clear trace prints with +define+PVR_ZROW_TRACE_PRINTS.
// `define PVR_ZROW_TRACE_PRINTS

parameter FIXED_W = 48;

module isp_parser #(
	parameter [7:0] FRAC_BITS = 8'd12,
	parameter [7:0] Z_FRAC_BITS = 8'd17,
	parameter [7:0] FRAC_DIFF = Z_FRAC_BITS - FRAC_BITS,
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter ENABLE_TEXTURE_PIPELINE = 1'b1,
	parameter ENABLE_TEXTURE_PARAMS = 1'b1,
	parameter ENABLE_GOURAUD_PARAMS = 1'b1,
	parameter ENABLE_OFFSET_PARAMS = 1'b1,
	parameter ENABLE_DEPTH_COMPARE = 1'b1,
	parameter INTRI_PIXELS_PER_CYCLE = 32
) (
	input clock,
	input reset_n,
	
	input disable_alpha,
	input both_buff,
	
	input [31:0] ISP_BACKGND_D,
	input [31:0] ISP_BACKGND_T,
	input render_bg,
	
	input [31:0] dbg_cycle,
	
	input [31:0] opb_word,
	input [2:0] type_cnt,
	
	input ra_cont_zclear_n,
	input ra_cont_flush_n,
	input [23:0] poly_addr,
	input render_poly,
	input render_to_tile,
	
	input isp_vram_wait,
	input isp_vram_valid,
	input isp_vram_req_ack,
	output reg isp_vram_rd,
	output reg isp_vram_wr,
	output reg [23:0] isp_vram_addr,
	input [31:0] isp_vram_din,					// Only 32-bit, for the params.
	output reg [31:0] isp_vram_dout,			// Logic in pvr.v handles which 4MB half of VRAM gets read.
	
	input wire codebook_wait,

	input  wire        tex_cache_hit,
	output wire [21:0] tex_peek_addr,
	input  wire        tex_peek_hit,
	output wire [23:0] tex_vram_addr,
	input tex_vram_wait,
	output reg tex_vram_rd,
	input tex_vram_valid,
	input tex_vram_req_ack,

	output reg isp_entry_valid,

	input ra_new_tile_start,
	input ra_entry_valid,
	input tile_prims_done,
	
	output reg poly_drawn,
	output reg tile_accum_done,
	output wire isp_prefetch_ready,

	input reg [5:0] tilex,
	input reg [5:0] tiley,
	
	input [31:0] FB_R_SOF1,
	input [31:0] FB_R_SOF2,
	
	input [31:0] FB_W_SOF1,
	input [31:0] FB_W_SOF2,
	
	output reg [8:0] isp_state,
	
	input wire [10:0] sim_ui,
	input wire [10:0] sim_vi,
	
	input debug_ena_texel_reads,
	
	output wire tsp_busy,
	
	input [1:0] state_skip,

	output wire tsp_pipe_flush,
	output wire tsp_read_codebook,
	output wire tsp_cb_cache_clear,
	input wire tsp_cb_cache_hit,

	output wire [31:0] tsp_isp_inst_out,
	output wire [31:0] tsp_tsp_inst_out,
	output wire [31:0] tsp_tcw_word_out,

	output wire signed [31:0] tsp_FDDX_BASE_A, tsp_FDDY_BASE_A, tsp_c_BASE_A,
	output wire signed [31:0] tsp_FDDX_BASE_R, tsp_FDDY_BASE_R, tsp_c_BASE_R,
	output wire signed [31:0] tsp_FDDX_BASE_G, tsp_FDDY_BASE_G, tsp_c_BASE_G,
	output wire signed [31:0] tsp_FDDX_BASE_B, tsp_FDDY_BASE_B, tsp_c_BASE_B,

	output wire signed [47:0] tsp_FDDX_U, tsp_FDDY_U, tsp_small_c_u,
	output wire signed [47:0] tsp_FDDX_V, tsp_FDDY_V, tsp_small_c_v,

	output wire signed [31:0] tsp_FDDX_OFFS_A, tsp_FDDY_OFFS_A, tsp_c_OFFS_A,
	output wire signed [31:0] tsp_FDDX_OFFS_R, tsp_FDDY_OFFS_R, tsp_c_OFFS_R,
	output wire signed [31:0] tsp_FDDX_OFFS_G, tsp_FDDY_OFFS_G, tsp_c_OFFS_G,
	output wire signed [31:0] tsp_FDDX_OFFS_B, tsp_FDDY_OFFS_B, tsp_c_OFFS_B,

	output wire [10:0] tsp_x_ps_cmd,
	output wire [10:0] tsp_y_ps_cmd,
	output wire signed [47:0] tsp_z_out,
	output wire [2:0] tsp_type_cnt_cmd,
	output wire [5:0] tsp_tilex_cmd,
	output wire [5:0] tsp_tiley_cmd,
	output wire tsp_pix_wr_cmd,
	output wire tsp_tex_data_ready,
	output wire tsp_transfer_z,
	output wire [11:0] tsp_rle_tag,
	output wire [9:0] tsp_rle_count,
	output wire [4:0] tsp_rle_row_start,
	output wire [4:0] tsp_rle_col_start,
	output wire tsp_rle_valid,
	output wire tsp_rle_busy,
	output wire tsp_rle_param_load,
	output wire tsp_rle_done,

	input wire [21:0] tsp_tex_word_addr,
	input wire tsp_pipeline_stall,
	input wire tsp_pipeline_busy,
	input wire tsp_texel_valid,
	input wire tsp_pix_valid
);

assign tex_vram_addr = tex_vram_req_word_addr <<2;	// Output the latched texture WORD request as a BYTE address.
													// Each Texture word is actually read as 64-bit wide, but we only shift <<2.
													// It's complicated. lol
assign tex_peek_addr = tsp_tex_word_addr;			// Peek address: word address for cache pre-check.

// OL Word bit decodes...
wire [5:0] strip_mask = {	// For Triangle Strips only.
    opb_word_strip[25], opb_word_strip[26],
    opb_word_strip[27], opb_word_strip[28],
    opb_word_strip[29], opb_word_strip[30]
};
wire [3:0] num_prims = opb_word_strip[28:25];	// For Triangle Array or Quad Array only.
wire shadow          = opb_word_strip[24];		// For all three poly types.
wire [2:0] skip      = opb_word_strip[23:21];	// For all three poly types.
wire eol             = opb_word_strip[28];

wire is_tri_strip  = opb_word_strip[31]   ==1'b0;
wire is_tri_array  = opb_word_strip[31:29]==3'b100;
wire is_quad_array = opb_word_strip[31:29]==3'b101;
reg quad_second_half;

// Object List read state machine...
reg [2:0] strip_cnt;
reg [3:0] array_cnt;


// ISP/TSP Instruction Word. Bit decode, for Opaque or Translucent prims...
reg [31:0] isp_inst;
wire [2:0] depth_comp   = isp_inst[31:29];	// 0=Never, 1=Less, 2=Equal, 3=Less Or Equal, 4=Greater, 5=Not Equal, 6=Greater Or Equal, 7=Always.
wire [1:0] culling_mode = isp_inst[28:27];	// 0=No culling, 1=Cull if Small, 2= Cull if Neg, 3=Cull if Pos.
wire z_write_disable    = isp_inst[26];
wire texture            = isp_inst[25];
wire offset             = isp_inst[24];
wire gouraud            = isp_inst[23];
wire uv_16_bit          = isp_inst[22];
wire cache_bypass       = isp_inst[21];
wire dcalc_ctrl         = isp_inst[20];
// Bits [19:0] are reserved.

// ISP/TSP Instruction Word. Bit decode, for Opaque Modifier Volume or Translucent Modified Volume...
wire [2:0] volume_inst = isp_inst[31:29];
//wire [1:0] culling_mode = isp_inst[28:27];	// Same bits as above.
// Bits [26:0] are reserved.

// TSP Instruction Word...
reg [31:0] tsp_inst;
wire [2:0] tex_src_alpha = tsp_inst_out[31:29];
wire [2:0] tex_dst_alpha = tsp_inst_out[28:26];
wire tex_src_select = tsp_inst_out[25];
wire tex_dst_select = tsp_inst_out[24];
wire [1:0] tex_fog_control = tsp_inst_out[23:22];
wire tex_col_clamp = tsp_inst_out[21];
wire tex_col_use_alpha = tsp_inst_out[20];
wire tex_ignore_alpha = tsp_inst_out[19];
wire tex_u_flip = tsp_inst_out[18];
wire tex_v_flip = tsp_inst_out[17];
wire tex_u_clamp = tsp_inst_out[16];
wire tex_v_clamp = tsp_inst_out[15];
wire [1:0] tex_filter_mode = tsp_inst_out[14:13];
wire tex_super_samp = tsp_inst_out[12];
wire [3:0] tex_mipmap_d_adj = tsp_inst_out[11:8];
wire [1:0] shade_inst = tsp_inst_out[7:6];
wire [2:0] tex_u_size = tsp_inst_out[5:3];
wire [2:0] tex_v_size = tsp_inst_out[2:0];

// Texture Control Word...
reg [31:0] tcw_word;
wire mip_map = tcw_word_out[31];
wire vq_comp = tcw_word_out[30];
wire [2:0] pix_fmt = tcw_word_out[29:27];
wire scan_order = tcw_word_out[26];
wire stride_flag = tcw_word_out[25];
wire [20:0] tex_word_addr = tcw_word_out[20:0];		// 64-bit WORD address! (but only shift <<2 when accessing 32-bit "halves" of VRAM).

reg [20:0] tex_base_word_addr_old;

// NOTE: Bump Map params are stored in the Offset Color regs, when Bumps are enabled.
//
// XY verts are declared as signed here, but it doesn't seem to help with rendering, when neg_xy culling is disabled.
//
reg signed [31:0] vert_a_x;
reg signed [31:0] vert_a_y;
reg signed [31:0] vert_a_z;	// Keep as signed !!
reg [31:0] vert_a_u0;
reg [31:0] vert_a_v0;
reg [31:0] vert_a_u1;
reg [31:0] vert_a_v1;
reg [31:0] vert_a_base_col_0;
reg [31:0] vert_a_base_col_1;
reg [31:0] vert_a_off_col;

reg signed [31:0] vert_b_x;
reg signed [31:0] vert_b_y;
reg signed [31:0] vert_b_z;	// Keep as signed !!
reg [31:0] vert_b_u0;
reg [31:0] vert_b_v0;
reg [31:0] vert_b_u1;
reg [31:0] vert_b_v1;
reg [31:0] vert_b_base_col_0;
reg [31:0] vert_b_base_col_1;
reg [31:0] vert_b_off_col;

reg signed [31:0] vert_c_x;
reg signed [31:0] vert_c_y;
reg signed [31:0] vert_c_z;	// Keep as signed !!
reg [31:0] vert_c_u0;
reg [31:0] vert_c_v0;
reg [31:0] vert_c_u1;
reg [31:0] vert_c_v1;
reg [31:0] vert_c_base_col_0;
reg [31:0] vert_c_base_col_1;
reg [31:0] vert_c_off_col;

reg signed [31:0] vert_d_x;
reg signed [31:0] vert_d_y;
reg signed [31:0] vert_d_z;	// Meh
reg [31:0] vert_d_u0;
reg [31:0] vert_d_v0;
reg [31:0] vert_d_u1;
reg [31:0] vert_d_v1;
reg [31:0] vert_d_base_col_0;
reg [31:0] vert_d_base_col_1;
reg [31:0] vert_d_off_col;

wire two_volume = 1'b0;	// TODO.

`define ISSUE_RD(next) begin \
    param_issue_addr(isp_vram_addr + 24'd4, next); \
end

reg clear_z;
reg clear_z_next_bank;
reg clear_z_next_tags_only;
reg clear_z_next_seen_busy;
reg clear_z_target_bank;

reg pcache_write;
reg pcache_write_0;
reg pcache_write_1;
reg pcache_write_pending;

`ifdef VERILATOR
// Simulator-only instrumentation.
reg [31:0] isp_vram_rd_count;
reg [31:0] tex_vram_rd_count;
reg [31:0] cb_word_count;
reg [31:0] param_window_hit_count;
reg [31:0] param_window_miss_count;
reg [31:0] param_window_prefetch_count;
reg [31:0] param_window_fill_count;
reg [31:0] param_window_overlap_start_count;
reg [31:0] tag_visible_pixel_count;
reg [31:0] tag_switch_count;
reg [31:0] tag_switch_stall_count;
reg [31:0] same_tag_pixel_count;
reg [31:0] tag_run_count;
reg [31:0] tag_run_len_1_count;
reg [31:0] tag_run_len_2_3_count;
reg [31:0] tag_run_len_4_7_count;
reg [31:0] tag_run_len_8_15_count;
reg [31:0] tag_run_len_16p_count;
reg [31:0] tag_switch_textured_count;
reg [31:0] tag_switch_tex_base_change_count;
reg [31:0] tag_switch_codebook_base_change_count;
reg [31:0] tsp_tex_wait_start_count;
reg [31:0] tsp_tex_wait_cycle_count;
reg [31:0] tsp_tex_wait_next_count;
reg [31:0] tsp_tex_wait_long_count;
reg [31:0] tsp_tex_initial_skip_count;
reg [31:0] tsp_tex_addr_change_wait_count;
reg [31:0] tsp_tex_valid_addr_mismatch_count;
reg [31:0] tsp_tex_rd_codebook_mode_count;
reg [31:0] tsp_tex_cache_hit_skip_count;
reg [31:0] isp_state56_cycles;
reg [31:0] isp_state57_cycles;
reg [31:0] tile_count;
reg [8:0]  isp_state_prev;
reg tag_run_active;
reg [11:0] tag_run_tag;
reg [15:0] tag_run_len;
reg [21:0] tag_run_tcw_base;
reg tag_run_textured;
reg tag_run_vq;
reg [7:0] tsp_tex_wait_len;
reg [31:0] total_tri_count;
reg [31:0] total_vis_count;
`endif

reg [31:0] tsp_empty_tile_skip_count;
reg [31:0] tsp_empty_row_skip_count;

reg isp_vram_rd_pend;
reg tex_vram_rd_pend;

reg [11:0] prim_tag;
reg [11:0] max_tags;
reg [11:0] prim_tag_out_prev;
reg [5:0] active_tilex;
reg [5:0] active_tiley;
reg isp_z_bank;
reg tsp_z_bank;
reg tsp_ready_bank;
reg [5:0] tsp_ready_tilex;
reg [5:0] tsp_ready_tiley;
reg [2:0] tsp_ready_type_cnt;
reg tsp_ready_has_tags;
reg [8:0] tsp_state;
reg [10:0] tsp_x_ps;
reg [10:0] tsp_y_ps;
reg [5:0] tsp_tilex;
reg [5:0] tsp_tiley;
reg [2:0] tsp_type_cnt;
reg [4:0] tsp_drain_count;
reg deferred_tile_started;
assign tsp_busy = (tsp_state != 9'd0);

reg [31:0] opb_word_strip;
reg prefetched_poly_pending;
reg [31:0] prefetched_opb_word;
reg [23:0] prefetched_poly_addr;

reg tsp_pix_wr;
reg tsp_pix_adv;
reg tsp_issue_accept;
reg tsp_tex_waiting;
reg [1:0] tsp_param_wait;
reg tsp_row_settle;

wire tsp_texture_enabled        = ENABLE_TEXTURE_PIPELINE && debug_ena_texel_reads;
wire tsp_texture_needs_fetch    = isp_inst_out[25] && tsp_texture_enabled && !tsp_tex_data_ready;
wire [20:0] tsp_tcw_base_word_addr = tcw_word_out[20:0];
wire tsp_texture_needs_codebook = isp_inst_out[25] && tsp_texture_enabled &&
								  tcw_word_out[30] && (tex_base_word_addr_old != tsp_tcw_base_word_addr);
wire tsp_issue_cmd = (tsp_state == 9'd53) &&
					 (prim_tag_out != 12'd0) &&
					 (prim_tag_out == prim_tag_out_prev) &&
					 (tsp_param_wait == 2'd0) &&
					 !tsp_row_settle &&
					 !tsp_texture_needs_codebook &&
					 !tsp_texture_needs_fetch &&
					 !tsp_pipeline_stall;

reg z_params_ready;
reg z_params_hsr_ready;
reg z_params_hsr_ready_d1;

localparam signed [47:0] Z_MAX_INIT = 48'sh7fffffffffff;
localparam signed [47:0] Z_MIN_INIT = -48'sh800000000000;

`ifdef VERILATOR
localparam PARAM_WINDOW_WORDS = 56;
localparam PARAM_WINDOW_BITS = 6;
`else
localparam PARAM_WINDOW_WORDS = 1;
localparam PARAM_WINDOW_BITS = 1;
`endif
reg [31:0] param_window [0:PARAM_WINDOW_WORDS-1];
reg [PARAM_WINDOW_WORDS-1:0] param_window_valid;
reg [23:0] param_window_base;
reg param_window_active;
reg [23:0] param_ext_req_addr;
reg param_ext_req_window_hit;
reg [PARAM_WINDOW_BITS-1:0] param_ext_req_window_index;
reg [23:0] param_prefetch_addr;
reg param_prefetch_active;
reg [PARAM_WINDOW_BITS:0] param_window_fill_words;
reg param_valid;
reg [31:0] param_din;

wire param_word_valid = param_valid || isp_vram_valid;
wire [31:0] param_word_din = param_valid ? param_din : isp_vram_din;
reg interp_params_ready;
wire can_overlap_param_prefetch = ((isp_state == 9'd56) || (isp_state == 9'd57)) &&
								  !prefetched_poly_pending && !param_prefetch_active &&
								  !render_bg;
assign isp_prefetch_ready = can_overlap_param_prefetch;

`ifdef VERILATOR
function param_window_contains;
	input [23:0] addr;
	begin
		param_window_contains = param_window_active &&
			(addr >= param_window_base) &&
			(addr < (param_window_base + (PARAM_WINDOW_WORDS << 2)));
	end
endfunction

function [PARAM_WINDOW_BITS-1:0] param_window_index;
	input [23:0] addr;
	begin
		param_window_index = (addr - param_window_base) >> 2;
	end
endfunction
`else
function param_window_contains;
	input [23:0] addr;
	begin
		param_window_contains = param_window_active && (addr[23:2] == param_window_base[23:2]);
	end
endfunction

function [PARAM_WINDOW_BITS-1:0] param_window_index;
	input [23:0] addr;
	begin
		param_window_index = {PARAM_WINDOW_BITS{1'b0}};
	end
endfunction
`endif

task param_issue_addr;
	input [23:0] addr;
	input [8:0] next_state;
	reg [PARAM_WINDOW_BITS-1:0] idx;
	reg hit;
	begin
		idx = param_window_index(addr);
		hit = param_window_contains(addr);
		isp_vram_addr <= addr;
		if (hit && param_window_valid[idx]) begin
			param_din <= param_window[idx];
			param_valid <= 1'b1;
`ifdef VERILATOR
			param_window_hit_count <= param_window_hit_count + 1'b1;
`endif
			isp_state <= next_state;
		end
		else begin
			isp_vram_rd <= 1'b1;
			param_ext_req_addr <= addr;
			param_ext_req_window_hit <= hit;
			param_ext_req_window_index <= idx;
`ifdef VERILATOR
			param_window_miss_count <= param_window_miss_count + 1'b1;
`endif
			isp_state <= next_state;
		end
	end
endtask

`ifdef VERILATOR
task tag_run_finish;
	input [15:0] len;
	begin
		tag_run_count <= tag_run_count + 1'b1;
		if (len == 16'd1) tag_run_len_1_count <= tag_run_len_1_count + 1'b1;
		else if (len <= 16'd3) tag_run_len_2_3_count <= tag_run_len_2_3_count + 1'b1;
		else if (len <= 16'd7) tag_run_len_4_7_count <= tag_run_len_4_7_count + 1'b1;
		else if (len <= 16'd15) tag_run_len_8_15_count <= tag_run_len_8_15_count + 1'b1;
		else tag_run_len_16p_count <= tag_run_len_16p_count + 1'b1;
	end
endtask
`endif

reg [5:0] param_id_in;
reg [5:0] param_id_last;
reg start_interp;

wire [5:0] param_id_out;
wire interp_valid;
wire z_param_result_valid = interp_valid && (param_id_out == 6'd0);
wire interp_param_result_valid = interp_valid &&
	((!isp_inst[24] && (param_id_out == 6'd6)) ||
	 ( isp_inst[24] && (param_id_out == 6'd10)));

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	isp_state <= 9'd0;
	isp_vram_rd <= 1'b0;
	isp_vram_wr <= 1'b0;
	isp_entry_valid <= 1'b0;
	tex_vram_rd <= 1'b0;
	isp_vram_rd_pend <= 1'b0;
	tex_vram_rd_pend <= 1'b0;
`ifdef VERILATOR
	isp_vram_rd_count <= 32'd0;
	tex_vram_rd_count <= 32'd0;
	cb_word_count <= 32'd0;
	param_window_hit_count <= 32'd0;
	param_window_miss_count <= 32'd0;
	param_window_prefetch_count <= 32'd0;
	param_window_fill_count <= 32'd0;
	param_window_overlap_start_count <= 32'd0;
	isp_state56_cycles <= 32'd0;
	isp_state57_cycles <= 32'd0;
	tile_count <= 32'd0;
	isp_state_prev <= 9'd0;
`endif
	param_window_valid <= {PARAM_WINDOW_WORDS{1'b0}};
	param_window_base <= 24'd0;
	param_window_active <= 1'b0;
	param_ext_req_addr <= 24'd0;
	param_ext_req_window_hit <= 1'b0;
	param_ext_req_window_index <= {PARAM_WINDOW_BITS{1'b0}};
	param_prefetch_addr <= 24'd0;
	param_prefetch_active <= 1'b0;
	param_window_fill_words <= 7'd0;
	param_valid <= 1'b0;
	param_din <= 32'd0;
`ifdef VERILATOR
	tag_visible_pixel_count <= 32'd0;
	tag_switch_count <= 32'd0;
	tag_switch_stall_count <= 32'd0;
	same_tag_pixel_count <= 32'd0;
	tag_run_count <= 32'd0;
	tag_run_len_1_count <= 32'd0;
	tag_run_len_2_3_count <= 32'd0;
	tag_run_len_4_7_count <= 32'd0;
	tag_run_len_8_15_count <= 32'd0;
	tag_run_len_16p_count <= 32'd0;
	tag_switch_textured_count <= 32'd0;
	tag_switch_tex_base_change_count <= 32'd0;
	tag_switch_codebook_base_change_count <= 32'd0;
	tsp_tex_wait_start_count <= 32'd0;
	tsp_tex_wait_cycle_count <= 32'd0;
	tsp_tex_wait_next_count <= 32'd0;
	tsp_tex_wait_long_count <= 32'd0;
	tsp_tex_initial_skip_count <= 32'd0;
	tsp_tex_addr_change_wait_count <= 32'd0;
	tsp_tex_valid_addr_mismatch_count <= 32'd0;
	tsp_tex_rd_codebook_mode_count <= 32'd0;
	tsp_tex_cache_hit_skip_count <= 32'd0;
	tsp_empty_tile_skip_count <= 32'd0;
	tsp_empty_row_skip_count <= 32'd0;
	tag_run_active <= 1'b0;
	tag_run_tag <= 12'd0;
	tag_run_len <= 16'd0;
	tag_run_tcw_base <= 22'd0;
	tag_run_textured <= 1'b0;
	tag_run_vq <= 1'b0;
`endif
	prefetched_poly_pending <= 1'b0;
	prefetched_opb_word <= 32'd0;
	prefetched_poly_addr <= 24'd0;
	quad_second_half <= 1'b0;
	poly_drawn <= 1'b0;
	read_codebook <= 1'b0;
	tex_base_word_addr_old <= 21'h1FFFFF;	// Arbitrary address to start with.
	tsp_tex_word_addr_old <= 22'h3fffff;
`ifdef VERILATOR
	tsp_tex_req_addr <= 22'd0;
	tsp_tex_wait_addr_prev <= 22'd0;
`endif
	tex_vram_req_word_addr <= 22'd0;
	cb_cache_clear <= 1'b0;
	clear_z <= 1'b0;
	clear_z_next_bank <= 1'b0;
	clear_z_next_tags_only <= 1'b0;
	clear_z_next_seen_busy <= 1'b0;
	clear_z_target_bank <= 1'b0;
	prim_tag <= 12'd1;
	max_tags <= 12'd0;
	active_tilex <= 6'd0;
	active_tiley <= 6'd0;
	isp_z_bank <= 1'b0;
	tsp_z_bank <= 1'b0;
	tsp_ready_bank <= 1'b0;
	tsp_ready_tilex <= 6'd0;
	tsp_ready_tiley <= 6'd0;
	tsp_ready_type_cnt <= 3'd0;
	tsp_ready_has_tags <= 1'b0;
	tsp_state <= 9'd0;
	tsp_x_ps <= 11'd0;
	tsp_y_ps <= 11'd0;
	tsp_tilex <= 6'd0;
	tsp_tiley <= 6'd0;
	tsp_type_cnt <= 3'd0;
	tsp_drain_count <= 5'd0;
	deferred_tile_started <= 1'b0;
	pcache_write <= 1'b0;
	pcache_write_0 <= 1'b0;
	pcache_write_1 <= 1'b0;
	pcache_write_pending <= 1'b0;
	//trig_z_row_write <= 1'b0;
	tile_accum_done <= 1'b0;
	param_id_in <= 6'd11;
	param_id_last <= 6'd10;
	start_interp <= 1'b0;
	interp_params_ready <= 1'b0;
	tsp_pix_wr <= 1'b0;
	tsp_pix_adv <= 1'b0;
	tsp_issue_accept = 1'b0;
	tsp_tex_waiting <= 1'b0;
	tsp_param_wait <= 2'd0;
	tsp_row_settle <= 1'b0;
`ifdef VERILATOR
	tsp_tex_wait_len <= 8'd0;
`endif
`ifdef VERILATOR
	total_tri_count <= 32'd0;
	total_vis_count <= 32'd0;
`endif
	z_params_valid <= 1'b0;
	z_params_ready <= 1'b0;
	z_params_hsr_ready <= 1'b0;
	z_params_hsr_ready_d1 <= 1'b0;
end
else begin
	cb_cache_clear <= 1'b0;

	z_params_hsr_ready_d1 <= z_param_result_valid;
	if (z_params_hsr_ready_d1) z_params_hsr_ready <= 1'b1;

	start_interp <= 1'b0;
	
	z_params_valid <= 1'b0;

	isp_entry_valid <= 1'b0;
	poly_drawn <= 1'b0;
	
	clear_z <= 1'b0;
	clear_z_next_bank <= 1'b0;
	clear_z_next_tags_only <= 1'b0;

	read_codebook <= 1'b0;
	
	//trig_z_row_write <= 1'b0;
	tile_accum_done <= 1'b0;

	/*if (isp_vram_rd & !isp_vram_wait)*/ isp_vram_rd <= 1'b0;
	if (isp_vram_wr & !isp_vram_wait) isp_vram_wr <= 1'b0;

	// Default to a one-cycle strobe; state logic asserts when ready.
	tex_vram_rd <= 1'b0;
	param_valid <= 1'b0;

`ifdef VERILATOR
	if (isp_vram_rd) isp_vram_rd_count <= isp_vram_rd_count + 1'd1;
	if (tex_vram_rd) tex_vram_rd_count <= tex_vram_rd_count + 1'd1;
	if (isp_state == 9'd56) isp_state56_cycles <= isp_state56_cycles + 1'd1;
	if (isp_state == 9'd57) isp_state57_cycles <= isp_state57_cycles + 1'd1;
	if (isp_state == 9'd57 && isp_state_prev != 9'd57) tile_count <= tile_count + 1'd1;
	isp_state_prev <= isp_state;
`endif

	pcache_write <= 1'b0;
	pcache_write_0 <= 1'b0;
	pcache_write_1 <= 1'b0;
	rle_start <= 1'b0;
	tsp_pix_wr <= 1'b0;
	tsp_pix_adv <= 1'b0;
	tsp_issue_accept = 1'b0;

	if (param_id_in <= param_id_last) begin
		start_interp <= (param_id_in < param_id_last);
		param_id_in <= param_id_in + 1;
		/*
		if (start_interp) begin
			$display("param_id_in: %d", param_id_in);
			$display("FDDX_BASE_R: %08X  FDDY_BASE_R: %08X", FDDX_BASE_R, FDDY_BASE_R);
			$display("FDDX_U: %012X  FDDY_U: %012X", FDDX_U, FDDY_U);
			$display("FDDX_V: %012X  FDDY_V: %012X", FDDX_V, FDDY_V);
		end
		*/
	end

	if (interp_param_result_valid) begin
		interp_params_ready <= 1'b1;
	end

	z_params_valid <= z_param_result_valid;
	if (z_param_result_valid) z_params_ready <= 1'b1;

	if (ra_new_tile_start) begin	// New tile started!
		active_tilex <= tilex;
		active_tiley <= tiley;
		//cb_cache_clear <= 1'b1;	// Using some lower bits of the texture address bits from the TCW as the "Tag" now. No need to clear before each Tile.
		clear_z <= !ra_cont_zclear_n;
		prim_tag <= 12'd1;
	end

	if (isp_vram_valid && param_ext_req_window_hit) begin
		param_window[param_ext_req_window_index] <= isp_vram_din;
		param_window_valid[param_ext_req_window_index] <= 1'b1;
`ifdef VERILATOR
		param_window_fill_count <= param_window_fill_count + 1'b1;
`endif
		if (param_prefetch_active) param_window_fill_words <= param_window_fill_words + 1'b1;
	end

	if (can_overlap_param_prefetch && render_poly) begin
		prefetched_poly_pending <= 1'b1;
		prefetched_opb_word <= opb_word;
		prefetched_poly_addr <= poly_addr;
		param_window_base <= poly_addr;
		param_window_valid <= {PARAM_WINDOW_WORDS{1'b0}};
		param_window_active <= 1'b1;
		param_prefetch_addr <= poly_addr;
		param_window_fill_words <= 7'd0;
		param_prefetch_active <= 1'b1;
`ifdef VERILATOR
		param_window_overlap_start_count <= param_window_overlap_start_count + 1'b1;
`endif
	end

	if (param_prefetch_active &&
		((isp_state == 9'd56) || (isp_state == 9'd57)) &&
		(param_window_fill_words >= PARAM_WINDOW_WORDS)) begin
		param_prefetch_active <= 1'b0;
	end
	else if (param_prefetch_active &&
			 ((isp_state == 9'd56) || (isp_state == 9'd57)) &&
			 !isp_vram_rd_pend && !isp_vram_rd &&
			 (param_window_fill_words < PARAM_WINDOW_WORDS)) begin
		isp_vram_addr <= param_prefetch_addr;
		isp_vram_rd <= 1'b1;
		param_ext_req_addr <= param_prefetch_addr;
		param_ext_req_window_hit <= param_window_contains(param_prefetch_addr);
		param_ext_req_window_index <= param_window_index(param_prefetch_addr);
		param_prefetch_addr <= param_prefetch_addr + 24'd4;
`ifdef VERILATOR
		param_window_prefetch_count <= param_window_prefetch_count + 1'b1;
`endif
	end

	case (isp_state)
		0: begin
			if (render_poly) begin
				strip_cnt <= 3'd0;
				array_cnt <= 4'd0;
				quad_second_half <= 1'b0;
				vert_d_x <= 32'd0;
				vert_d_y <= 32'd0;
				vert_d_z <= 32'd0;
				vert_d_u0 <= 32'd0;
				vert_d_v0 <= 32'd0;
				opb_word_strip <= opb_word;
				isp_vram_addr <= poly_addr;
				param_window_base <= poly_addr;
				param_window_valid <= {PARAM_WINDOW_WORDS{1'b0}};
				param_window_active <= 1'b1;
				param_prefetch_addr <= poly_addr;
				param_prefetch_active <= 1'b0;
				param_window_fill_words <= 7'd0;
				isp_state <= 9'd1;
			end
			else if (render_to_tile) begin				// Render after each prim TYPE is written to Tag buffer.
				max_tags <= prim_tag;
				rle_tilex <= active_tilex;
				rle_tiley <= active_tiley;
				tsp_ready_bank <= isp_z_bank;
				tsp_ready_tilex <= active_tilex;
				tsp_ready_tiley <= active_tiley;
				tsp_ready_type_cnt <= type_cnt;
				tsp_ready_has_tags <= (prim_tag != 12'd1);
				//rle_start <= 1'b1;	// rle_by_tag reduces the "Daytona Behind" (theoretical) frame rate from around 32 to 26 FPS. tsp_tag_sorter is FAR slower (like 12 FPS!).
				//param_id_in <= 6'd0;
				if (!tsp_busy) begin
					tsp_z_bank <= isp_z_bank;
					tsp_x_ps <= {active_tilex, 5'd0};
					tsp_y_ps <= {active_tiley, 5'd0};
					tsp_tilex <= active_tilex;
					tsp_tiley <= active_tiley;
					tsp_type_cnt <= type_cnt;
					tex_base_word_addr_old <= 21'h1FFFFF;	// Arbitrary address to start with.
					tsp_tex_word_addr_old <= 22'h3fffff;
					tsp_tex_waiting <= 1'b0;
					tsp_param_wait <= 2'd2;
					tsp_row_settle <= 1'b1;
					tsp_state <= 9'd51;
					prim_tag_out_prev <= 12'd4095;		// Force the first TSP tag to fetch its params.
					if (prim_tag == 12'd1)
						tsp_empty_tile_skip_count <= tsp_empty_tile_skip_count + 1'b1;
					tsp_ready_bank <= isp_z_bank;
					deferred_tile_started <= 1'b1;
					isp_state <= 9'd57;
				end
				else begin
					deferred_tile_started <= 1'b0;
					isp_state <= 9'd57;
				end
			end
		end

		400: begin
			if (param_window_fill_words >= PARAM_WINDOW_WORDS) begin
				param_prefetch_active <= 1'b0;
				isp_state <= 9'd1;
			end
			else if (!isp_vram_rd_pend && !isp_vram_rd) begin
				isp_vram_addr <= param_prefetch_addr;
				isp_vram_rd <= 1'b1;
				param_ext_req_addr <= param_prefetch_addr;
				param_ext_req_window_hit <= param_window_contains(param_prefetch_addr);
				param_ext_req_window_index <= param_window_index(param_prefetch_addr);
				param_prefetch_addr <= param_prefetch_addr + 24'd4;
`ifdef VERILATOR
				param_window_prefetch_count <= param_window_prefetch_count + 1'b1;
`endif
			end
		end
		
		1: begin
			if (render_bg) begin
				// Using poly_addr from the RA now (isp_vram_addr set in isp_state 0), as it includes the PARAM_BASE offset.
				//isp_vram_addr <= {ISP_BACKGND_T[23:3],2'b00};
				param_issue_addr(isp_vram_addr, 9'd2);
			end
			else begin
				if (is_tri_strip) begin		// TriangleStrip. (ra_parser now skips render_poly, if all strip_mask bits are 0. Tiny speed boost).
					if (strip_cnt < 3'd6) begin	// Check strip_mask bits 0 through 5...
						if (strip_mask[strip_cnt]) begin
							param_issue_addr(poly_addr, 9'd2);	// Go to the next state if the current strip_mask bit is set.
						end
						else begin							// Current strip_mask bit was NOT set...
							strip_cnt <= strip_cnt + 3'd1;	// Increment to the next bit. (Stay in the current state, to check the next bit.)
						end
					end
					else begin	// strip_cnt == 6.
						poly_drawn <= 1'b1;				// Tell the RA we're done.
						isp_state <= 9'd0;				// Go back to idle state.
					end
				end
				else if (is_tri_array || is_quad_array) begin	// Triangle Array or Quad Array.
					quad_second_half <= 1'b0;					// Ready for drawing the first half of a Quad.			
					array_cnt <= num_prims;	// Shouldn't need the +1 here, because it will render the first triangle with array_cnt==0 anyway. ElectronAsh.
					param_issue_addr(isp_vram_addr, 9'd2);
				end
				else begin
					poly_drawn <= 1'b1;	// No idea which prim type, so skip!
					isp_state <= 9'd0;
				end
			end
		end

		2: if (param_word_valid) begin isp_inst <= param_word_din; `ISSUE_RD(9'd3) end
		
		3: if (param_word_valid) begin tsp_inst <= param_word_din; `ISSUE_RD(9'd4) end

		4: if (param_word_valid) begin
			tcw_word <= param_word_din;
			if (is_tri_strip) param_issue_addr(poly_addr + (3<<2) + ((vert_words*strip_cnt) << 2), 9'd7);	// Skip a vert, based on strip_cnt.
			else param_issue_addr(isp_vram_addr + 24'd4, 9'd7);
		end
		
		/*
		5: begin
			// Spare state. Used to be for Codebook reading, but we're using the Tag buffer now.
		end
		*/
		
		6: begin
			if (is_tri_strip) param_issue_addr(poly_addr + (3<<2) + ((vert_words*strip_cnt) << 2), 9'd7);	// Skip a vert, based on strip_cnt.
			else param_issue_addr(isp_vram_addr + 24'd4, 9'd7);
		end
		
		7: if (param_word_valid) begin vert_a_x <= param_word_din; `ISSUE_RD(9'd8) end

		8: if (param_word_valid) begin vert_a_y <= param_word_din; `ISSUE_RD(9'd9) end
		
		9: if (param_word_valid) begin
			vert_a_z <= param_word_din;
			if (skip==3'd0) param_issue_addr(isp_vram_addr + 24'd4, 9'd17);
			else if (!texture) param_issue_addr(isp_vram_addr + 24'd4, 9'd12);
			else param_issue_addr(isp_vram_addr + 24'd4, 9'd10);
		end
		
		// vert_a UV.
		10: if (param_word_valid) begin
			if (uv_16_bit) begin
				vert_a_u0 <= {param_word_din[31:16],16'h0000};	// vert_a 16-bit UV.
				vert_a_v0 <= {param_word_din[15:0],16'h0000};
				`ISSUE_RD(9'd12)
			end
			else begin
				vert_a_u0 <= param_word_din;	// vert_a 32-bit U.
				`ISSUE_RD(9'd11)		// Grab 32-bit V...
			end
		end
		
		// vert_a 32-bit V.
		11: if (param_word_valid) begin vert_a_v0 <= param_word_din; `ISSUE_RD(9'd12) end

		// vert_a_base_col_0.
		12: if (param_word_valid) begin
			vert_a_base_col_0 <= param_word_din;
			if (two_volume) `ISSUE_RD(9'd13)
			else if (offset) `ISSUE_RD(9'd16)
			else `ISSUE_RD(9'd17)
		end
		
		// if Two-volume...
		13: if (param_word_valid) begin vert_a_u1         <= param_word_din; `ISSUE_RD(9'd14) end
		
		14: if (param_word_valid) begin vert_a_v1         <= param_word_din; `ISSUE_RD(9'd15) end

		15: if (param_word_valid) begin vert_a_base_col_1 <= param_word_din; `ISSUE_RD(offset ? 9'd16 : 9'd17) end
		
		// if Offset colour.
		16: if (param_word_valid) begin vert_a_off_col    <= param_word_din; `ISSUE_RD(9'd17) end
		
		// vert_b_x.
		17: if (param_word_valid) begin vert_b_x          <= param_word_din; `ISSUE_RD(9'd18) end
		
		// vert_b_y.
		18: if (param_word_valid) begin vert_b_y          <= param_word_din; `ISSUE_RD(9'd19) end
		
		// vert_b_z.
		19: if (param_word_valid) begin
			vert_b_z <= param_word_din;
			if (skip==0) param_issue_addr(isp_vram_addr + 24'd4, 9'd27);
			else if (!texture) param_issue_addr(isp_vram_addr + 24'd4, 9'd22);
			else param_issue_addr(isp_vram_addr + 24'd4, 9'd20);
		end
		
		// vert_b UV.
		20: if (param_word_valid) begin
			if (uv_16_bit) begin
				vert_b_u0 <= {param_word_din[31:16],16'h0000};	// vert_a 16-bit UV.
				vert_b_v0 <= {param_word_din[15:0],16'h0000};
				`ISSUE_RD(9'd22)
			end
			else begin
				vert_b_u0 <= param_word_din;	// vert_a 32-bit U.
				`ISSUE_RD(9'd21)		// Grab vert_a 32-bit V.
			end
		end

		// vert_b_v0 (32-bit V).
		21: if (param_word_valid) begin vert_b_v0 <= param_word_din; `ISSUE_RD(9'd22) end

		// vert_b_base_col_0.
		22: if (param_word_valid) begin
			vert_b_base_col_0 <= param_word_din;
			if (two_volume) `ISSUE_RD(9'd23)
			else if (offset) `ISSUE_RD(9'd26)
			else `ISSUE_RD(9'd27)
		end
		
		// if Two-volume...
		// vert_b_u1.
		23: if (param_word_valid) begin vert_b_u1 <= param_word_din; `ISSUE_RD(9'd24) end

		// vert_b_v1.
		24: if (param_word_valid) begin vert_b_v1 <= param_word_din; `ISSUE_RD(9'd25) end

		// vert_b_base_col_1.
		25: if (param_word_valid) begin
			vert_b_base_col_1 <= param_word_din;
			if (offset) `ISSUE_RD(9'd26)
			else `ISSUE_RD(9'd27)
		end
		
		// if Offset colour...
		26: if (param_word_valid) begin vert_b_off_col <= param_word_din; `ISSUE_RD(9'd27) end
		
		// vert_c_x.
		27: if (param_word_valid) begin vert_c_x <= param_word_din; `ISSUE_RD(9'd28) end

		// vert_c_y.
		28: if (param_word_valid) begin vert_c_y <= param_word_din; `ISSUE_RD(9'd29) end

		// vert_c_z.
		29: if (param_word_valid) begin
			vert_c_z <= param_word_din;
			if (skip==0) begin
				if (is_quad_array) `ISSUE_RD(9'd37)
				else begin
					isp_vram_addr <= isp_vram_addr + 8;
					isp_state <= 9'd47;
				end
			end
			else if (!texture) `ISSUE_RD(9'd32)
			else `ISSUE_RD(9'd30)
		end
		
		// vert_c 16-bit UV.
		30: if (param_word_valid) begin
			if (uv_16_bit) begin
				vert_c_u0 <= {param_word_din[31:16],16'h0000};
				vert_c_v0 <= {param_word_din[15:0],16'h0000};
				`ISSUE_RD(9'd32)
			end
			else begin
				vert_c_u0 <= param_word_din;
				`ISSUE_RD(9'd31)
			end
		end

		31: if (param_word_valid) begin vert_c_v0 <= param_word_din; `ISSUE_RD(9'd32) end
		
		// Vert C Base Colour.
		32: if (param_word_valid) begin
			vert_c_base_col_0 <= param_word_din;
			if (two_volume) `ISSUE_RD(9'd33)
			else if (offset) `ISSUE_RD(9'd36)
			else if (is_quad_array) `ISSUE_RD(9'd37)
			else begin
				isp_vram_addr <= isp_vram_addr + 4;
				isp_state <= 9'd47;
			end
		end
		
		// if Two-volume...
		33: if (param_word_valid) begin
			vert_c_u1 <= param_word_din;
			if (offset) `ISSUE_RD(9'd36)
			else if (is_quad_array) `ISSUE_RD(9'd37)
			else begin
				isp_vram_addr <= isp_vram_addr + 8;
				isp_state <= 9'd47;
			end
		end

		34: if (param_word_valid) begin vert_c_v1 <= param_word_din; `ISSUE_RD(9'd35) end

		35: if (param_word_valid) begin
			vert_c_base_col_1 <= param_word_din;
			if (offset) `ISSUE_RD(9'd36)
			else begin
				isp_vram_addr <= isp_vram_addr + 8;
				isp_state <= 9'd47;
			end
		end
		
		36: if (param_word_valid) begin
			vert_c_off_col <= param_word_din;
			if (is_quad_array) `ISSUE_RD(9'd37)
			else begin
				isp_vram_addr <= isp_vram_addr + 8;
				isp_state <= 9'd47;
			end
		end
		
		// Quad Array stuff...
		37:  if (param_word_valid) begin vert_d_x <= param_word_din; `ISSUE_RD(9'd38) end

		38:  if (param_word_valid) begin vert_d_y <= param_word_din; `ISSUE_RD(9'd39) end

		39: if (param_word_valid) begin
			vert_d_z <= param_word_din;
			if (texture) `ISSUE_RD(9'd40)
			else `ISSUE_RD(9'd42)
		end

		40: if (param_word_valid) begin
			if (uv_16_bit) begin
				vert_d_u0 <= {param_word_din[31:16],16'h0000};
				vert_d_v0 <= {param_word_din[15:0],16'h0000};
				`ISSUE_RD(9'd42)
			end
			else begin
				vert_d_u0 <= param_word_din;
				`ISSUE_RD(9'd41)
			end
		end

		41: if (param_word_valid) begin vert_d_v0 <= param_word_din; `ISSUE_RD(9'd42) end

		42: if (param_word_valid) begin
			vert_d_base_col_0 <= param_word_din;
			if (two_volume) `ISSUE_RD(9'd43)
			else if (offset) `ISSUE_RD(9'd46)
			else begin
				isp_vram_addr <= isp_vram_addr + 4;
				isp_state <= 9'd47;
			end
		end
		
		// if Two-volume...
		43:  if (param_word_valid) begin vert_d_u1 <= param_word_din; `ISSUE_RD(9'd44) end

		44:  if (param_word_valid) begin vert_d_v1 <= param_word_din; `ISSUE_RD(9'd45) end

		45:  if (param_word_valid) begin
			vert_d_base_col_1 <= param_word_din;
			if (offset) `ISSUE_RD(9'd46)
			else begin
				isp_vram_addr <= isp_vram_addr + 4;
				isp_state <= 9'd47;
			end
		end
		
		// if Offset colour...
		46:  if (param_word_valid) begin vert_d_off_col <= param_word_din; `ISSUE_RD(9'd47) end
		
		47: if (!z_clear_busy) begin
			if (render_bg) begin
				//vert_a_x <= vert_b_x;
				//vert_a_y <= vert_c_y;
				//vert_b_x <= vert_c_x;
				//vert_b_y <= vert_c_y;
				//vert_c_x <= vert_b_x;
				//vert_c_y <= vert_b_y;
				vert_d_x <= vert_b_x;
				vert_d_y <= vert_c_y;
				vert_d_u0 <= vert_b_u0;
				vert_d_v0 <= vert_c_v0;
			end
			else if (is_tri_strip && strip_cnt[0]) begin	// Swap verts A and B, for all ODD strip segments.
				vert_a_x  <= vert_b_x;
				vert_a_y  <= vert_b_y;
				vert_a_z  <= vert_b_z;
				vert_a_u0 <= vert_b_u0;
				vert_a_v0 <= vert_b_v0;
				vert_a_base_col_0 <= vert_b_base_col_0;
				vert_a_off_col <= vert_b_off_col;

				vert_b_x  <= vert_a_x;
				vert_b_y  <= vert_a_y;
				vert_b_z  <= vert_a_z;
				vert_b_u0 <= vert_a_u0;
				vert_b_v0 <= vert_a_v0;
				vert_b_base_col_0 <= vert_a_base_col_0;
				vert_b_off_col <= vert_a_off_col;
			end

			isp_entry_valid <= 1'b1;

			if (!(is_quad_array && quad_second_half)) begin
				isp_vram_addr <= isp_vram_addr + 4;
				interp_params_ready <= 1'b0;
			end

			param_id_in <= 6'd11;

			pcache_write_pending <= 1'b0;
			// State 49 starts the interp sequence after the fixed-point
			// vertex registers have captured the current primitive.
			if (render_bg) begin
				vert_a_z <= (ISP_BACKGND_D & 32'hFFFFFFF0);	// ISP_BACKGND_D has only 28 bits.
				vert_b_z <= (ISP_BACKGND_D & 32'hFFFFFFF0);
				vert_c_z <= (ISP_BACKGND_D & 32'hFFFFFFF0);
				vert_d_z <= (ISP_BACKGND_D & 32'hFFFFFFF0);
			end
			if (!(is_quad_array && quad_second_half)) begin
				z_params_ready <= 1'b0;
				z_params_hsr_ready <= 1'b0;
				z_params_hsr_ready_d1 <= 1'b0;
						end
			isp_state <= 9'd49;			// "Draw" the triangle! (register spans to the TAG buffer).
		end
		
		48: if (!z_clear_busy) begin
			if (is_tri_strip) begin				// Triangle Strip.
				if (strip_cnt==3'd6) begin		// Last segment just drawn.
					poly_drawn <= 1'b1;			// Done.
					isp_state <= 9'd0;			// Back to Idle.
				end
				else begin
					strip_cnt <= strip_cnt + 3'd1;	// Increment to the next strip_mask bit.
					isp_state <= 9'd1;
				end
			end
			else if (is_tri_array || is_quad_array) begin	// Triangle Array or Quad Array.
				if ((array_cnt==4'd0) || (is_quad_array && !quad_second_half)) begin
					if (is_quad_array) begin		// Quad Array (maybe) done.
						if (!quad_second_half) begin		// Second half of Quad not done yet...
							// Vertex D carries only X/Y. Rasterize A-D-C while
							// retaining the projective planes from A/B/C.
							vert_b_x          <= vert_d_x;
							vert_b_y          <= vert_d_y;

							if (render_bg) begin
								//vert_a_x <= vert_b_x;
								//vert_a_y <= vert_c_y;
								//vert_b_x <= vert_c_x;
								//vert_b_y <= vert_c_y;
								//vert_c_x <= vert_b_x;
								//vert_c_y <= vert_b_y;
								vert_d_x <= vert_b_x;
								vert_d_y <= vert_c_y;
								vert_d_u0 <= vert_b_u0;
								vert_d_v0 <= vert_c_v0;
							end
							
							//vert_b_u0 <= vert_a_u0;
							//vert_b_v0 <= vert_c_v0;
							
							// B ← C (full vertex copy)
							// Note: This breaks Quad textures far worse than the code above.
							/*
							vert_b_x  <= vert_c_x;
							vert_b_y  <= vert_c_y;
							vert_b_z  <= vert_c_z;
							vert_b_u0 <= vert_c_u0;
							vert_b_v0 <= vert_c_v0;
							vert_b_base_col_0 <= vert_c_base_col_0;
							vert_b_off_col    <= vert_c_off_col;

							// C ← D (POSITION ONLY)
							vert_c_x  <= vert_d_x;
							vert_c_y  <= vert_d_y;
							*/
							isp_state <= 9'd47;		// Draw the second half of the Quad.
													// isp_entry_valid will tell the C code to latch the
													// params again, and convert to fixed-point.
							quad_second_half <= 1'b1;	// <- The next time we get to this state, we know the full Quad is drawn.
						end
						else begin
							poly_drawn <= 1'b1;	// Quad is done.
							isp_state <= 9'd0;
						end
					end
					else begin	// Triangle (or part of Array) is done.
						poly_drawn <= 1'b1;
						isp_state <= 9'd0;
					end
				end
				else begin	// Triangle Array or Quad Array not done yet...
					array_cnt <= array_cnt - 3'd1;
					quad_second_half <= 1'b0;
					param_issue_addr(isp_vram_addr - 24'd4, 9'd2);	// Jump back, to grab the next PRIM (including ISP/TSP/TCW).
				end
			end
			else begin	// Should never get to here??
				poly_drawn <= 1'b1;
				isp_state <= 9'd0;
			end
		end

		49: begin
			// First setup cycle: capture the registered float-to-fixed values.
			param_id_in <= 6'd11;
			//interp_params_ready <= 1'b0;
			pcache_write_pending <= 1'b0;
			if (is_quad_array && quad_second_half) begin
				// The second half reuses the first half's planes. Defer the
				// cache write until this triangle is known to be visible.
				isp_state <= 9'd50;
			end
			else begin
				z_params_ready <= 1'b0;
				z_params_hsr_ready <= 1'b0;
				z_params_hsr_ready_d1 <= 1'b0;
							isp_state <= 9'd200;
			end
		end

		200: begin
			// BIG_C is a registered pipeline behind the live vertex inputs.
			// Allow swaps performed in state 47 to propagate before launching
			// any parameter from this primitive.
			isp_state <= 9'd201;
		end

		201: begin
			isp_state <= 9'd202;
		end

		202: begin
			// ISP setup only needs the Z plane. UV and colour planes are
			// launched after HSR confirms that this triangle wrote tags.
			param_id_in <= 6'd0;
			param_id_last <= 6'd0;
			start_interp <= 1'b1;
			pcache_write_pending <= 1'b0;
			isp_state <= 9'd50;
		end
		// HSR row scan — delegated to hsr_core; wait here for hsr_done.
		50: if (hsr_done) begin
`ifdef VERILATOR
			total_tri_count <= total_tri_count + 1;	// Total *processed* (incoming) Triangles.
`endif
			// Latch which bank holds the completed tile before the ISP
			// flips back to the opposite write/clear bank.
			tsp_ready_bank <= isp_z_bank;
			tsp_ready_tilex <= active_tilex;
			tsp_ready_tiley <= active_tiley;
			tsp_ready_type_cnt <= type_cnt;
			tsp_ready_has_tags <= (prim_tag != 12'd1);

			if (render_bg || any_tags_written) begin
				if (is_quad_array && quad_second_half) begin
					// The first half already produced the projective planes.
					// Write them under this half's tag only when it is visible.
					pcache_write <= 1'b1;
					pcache_write_0 <= !isp_z_bank;
					pcache_write_1 <=  isp_z_bank;
					isp_state <= 9'd204;
				end
				else begin
					// TSP phase: UV, base colour, and optional offset colour.
					param_id_in <= 6'd1;
					param_id_last <= isp_inst[24] ? 6'd10 : 6'd6;
					start_interp <= 1'b1;
					interp_params_ready <= 1'b0;
					pcache_write_pending <= 1'b1;
					isp_state <= 9'd203;
				end
			end
			else begin
				isp_state <= 9'd48;	// Whole PRIM written to Z/Tag buffer! (if any pixels are visible in Tile) - Load the next PRIM.
			end
		end

		203: begin
			// Wait for the final TSP coefficient before committing this tag's
			// parameter-cache entry.
			if (pcache_write_pending && interp_param_result_valid) begin
				pcache_write <= 1'b1;
				pcache_write_0 <= !isp_z_bank;
				pcache_write_1 <=  isp_z_bank;
				interp_params_ready <= 1'b0;
				pcache_write_pending <= 1'b0;
				isp_state <= 9'd204;
			end
		end

		204: begin
			// pcache_write is sampled by param_buffer on this edge, before the
			// tag advances.
			prim_tag <= prim_tag + 1'b1;
			if (render_bg) begin
				poly_drawn <= 1'b1;
				isp_state <= 9'd0;
			end
			else begin
`ifdef VERILATOR
				total_vis_count <= total_vis_count + 1'b1;
`endif
				isp_state <= 9'd48;
			end
		end
		
		// Rendering from the Tag buffer now.
		// We jump to this state when in isp_state==0 AND "render_to_tile" is triggered.
		51: if (!z_clear_busy && !rle_busy) begin	// // isp_inst_out[24] = Current Triangle / pixel uses Offset colour.
			if (!tsp_texture_enabled) begin
				isp_state <= 9'd53;
			end
			else begin
				tex_vram_req_word_addr <= tsp_tex_word_addr;
				tex_vram_rd <= 1'b1;			// Read the first Texel?
				isp_state <= isp_state + 9'd1;	// Wait for tex_vram_valid.	
			end
		end

		// Wait for Texture WORD...
		52: begin
			if (!tsp_texture_enabled) begin
				isp_state <= 9'd53;
			end
			else if (tex_vram_valid) begin
				tsp_pix_wr <= 1'b1;
				isp_state <= isp_state + 9'd1;
			end
		end

		// Write pixel to Tile ARGB buffer.
		53: begin
			if (!tsp_pipeline_stall) begin
				tsp_pix_wr <= 1'b1;
				tsp_pix_adv <= tsp_pix_valid;
			end

			if (isp_inst_out[25] && tsp_texture_enabled) begin	// If Textured...
				if (tcw_word_out[30] && (tex_base_word_addr_old != tsp_tcw_base_word_addr)) begin	// Is VQ - has the texture BASE address has changed?...
					tex_base_word_addr_old <= tsp_tcw_base_word_addr;
					read_codebook <= 1'b1;							// If so, read the new Codebook.
					isp_state <= 9'd100;
				end
				else begin					// Else - Textured (non-VQ, or VQ). BASE addr has not changed...
					if (tsp_tex_word_addr_old != tsp_tex_word_addr) begin	// Has texel OFFSET addr changed?...
						tsp_tex_word_addr_old <= tsp_tex_word_addr;
						//if (!tex_vram_wait) begin		// <- This was causing corrupted tiles, because we only check this ONCE, when the Texture offset changes.
							if (!tex_cache_hit) begin	// tex_cache_hit: only skip if old addr still matches cache
								tex_vram_req_word_addr <= tsp_tex_word_addr;
								tex_vram_rd <= 1'b1;	// Read a Texel WORD...
								isp_state <= 9'd52;		// Wait for tex_vram_valid
							end
`ifdef VERILATOR
							else if (tex_peek_hit) tsp_tex_cache_hit_skip_count <= tsp_tex_cache_hit_skip_count + 1'b1;
`endif
						//end
					end
					//else isp_state <= 9'd53;	// Textured (non-VQ), but the TEXEL addr hasn't changed, write the pixel anyway.
				end
			end
			//else isp_state <= 9'd53;	// Flat-shaded or Gouraud pixel, no need to do a Texel fetch.

			if (tsp_pix_adv) begin
				if (x_ps >= {active_tilex, 5'd31}) begin
					if (y_ps >= {active_tiley, 5'd31}) begin	// We've reached the last (lower-right) pixel of the Tile...
						// Move the ISP to the opposite bank from the bank it just
						// finished. Do not derive this from tsp_z_bank; that may be
						// stale if the TSP FSM is idle or has already completed.
						isp_z_bank <= ~isp_z_bank;
						clear_z_target_bank <= ~isp_z_bank;
						clear_z_next_bank <= 1'b1;
						prim_tag <= 12'd1;
						clear_z_next_bank <= 1'b1;
						clear_z_next_seen_busy <= 1'b0;
						//tsp_pix_wr  <= 1'b0;
						tsp_pix_adv <= 1'b0;
						isp_state <= 9'd56;
					end
					else begin						// Not on the last row yet...
						x_ps <= tilex_start;
						y_ps <= y_ps + 5'd1;
					end
				end
				else begin
					x_ps <= x_ps + 5'd1;
				end
			end
		end
		/*
		54: begin
		end
		*/
		/*
		55: begin
		end
		*/
		56: begin
			if (clear_z_target_busy) begin
				clear_z_next_seen_busy <= 1'b1;
			end
			else if (clear_z_next_seen_busy) begin
				if (prefetched_poly_pending) begin
					if (!isp_vram_rd_pend && !isp_vram_rd) begin
						tile_accum_done <= 1'b1;
						strip_cnt <= 3'd0;
						array_cnt <= 4'd0;
						vert_d_x <= 32'd0;
						vert_d_y <= 32'd0;
						vert_d_z <= 32'd0;
						vert_d_u0 <= 32'd0;
						vert_d_v0 <= 32'd0;
						opb_word_strip <= prefetched_opb_word;
						isp_vram_addr <= prefetched_poly_addr;
						param_window_base <= prefetched_poly_addr;
						param_window_valid <= {PARAM_WINDOW_WORDS{1'b0}};
						param_window_active <= 1'b1;
						param_prefetch_active <= 1'b0;
						param_window_fill_words <= 7'd0;
						prefetched_poly_pending <= 1'b0;
						isp_state <= 9'd1;
					end
				end
				else begin
					tile_accum_done <= 1'b1;
					isp_state <= 9'd0;
				end
			end
		end

		57: begin
			if (!deferred_tile_started) begin
				if (!tsp_busy) begin
					tsp_z_bank <= tsp_ready_bank;
					tsp_x_ps <= {tsp_ready_tilex, 5'd0};
					tsp_y_ps <= {tsp_ready_tiley, 5'd0};
					tsp_tilex <= tsp_ready_tilex;
					tsp_tiley <= tsp_ready_tiley;
					tsp_type_cnt <= tsp_ready_type_cnt;
					tex_base_word_addr_old <= 21'h1FFFFF;
					tsp_tex_word_addr_old <= 22'h3fffff;
					tsp_tex_waiting <= 1'b0;
					tsp_param_wait <= 2'd2;
					tsp_row_settle <= 1'b1;
					tsp_state <= 9'd51;
					prim_tag_out_prev <= 12'd4095;
`ifdef VERILATOR
					if (!tsp_ready_has_tags) tsp_empty_tile_skip_count <= tsp_empty_tile_skip_count + 1'b1;
`endif
					deferred_tile_started <= 1'b1;
				end
			end
			else if (!tsp_busy) begin
				clear_z_target_bank <= tsp_ready_bank;
				clear_z_next_bank <= 1'b1;
				clear_z_next_tags_only <= 1'b1;
				clear_z_next_seen_busy <= 1'b0;
				prim_tag <= 12'd1;
				deferred_tile_started <= 1'b0;
				isp_state <= 9'd56;
			end
		end

		100: begin
			// Codebook fetch entry
			if (!tsp_texture_enabled) begin
				isp_state <= 9'd53;
			end
			else if (tsp_cb_cache_hit) begin
				isp_state  <= 9'd53; // No need to do a new Codebook fetch.
			end
			else /*if (!tex_vram_wait)*/ begin
				tex_vram_req_word_addr <= tsp_tex_word_addr;
				tex_vram_rd <= 1'b1; // Start codebook fetch
`ifdef VERILATOR
				cb_word_count <= cb_word_count + 1'd1;
`endif
				isp_state   <= 9'd101;
			end
		end

		101: begin
			if (!tsp_texture_enabled) begin
				isp_state <= 9'd53;
			end
			else if (codebook_wait) begin // Still loading -> request next word
				if (!tex_vram_valid) begin
					tex_vram_req_word_addr <= tsp_tex_word_addr;
					tex_vram_rd <= 1'b1;
				end
`ifdef VERILATOR
				if (tex_vram_req_ack || tex_vram_valid) cb_word_count <= cb_word_count + 1'd1;
`endif
			end
			else begin // Codebook fully loaded
				tex_vram_req_word_addr <= tsp_tex_word_addr;
				tex_vram_rd <= 1'b1; // Read first texel word after codebook.
				isp_state  <= 9'd52;
			end
		end
		default: ;
	endcase

	case (tsp_state)
		9'd0: begin
			// Idle; ISP starts this FSM when a completed tag/param bank is handed to the TSP.
		end

		9'd51: if (!z_clear_busy && !rle_busy) begin
`ifdef VERILATOR
			tsp_tex_initial_skip_count <= tsp_tex_initial_skip_count + 1'b1;
`endif
			tsp_state <= 9'd53;
		end

		9'd52: begin
			if (!tsp_texture_enabled) begin
				tsp_tex_waiting <= 1'b0;
				tsp_state <= 9'd53;
			end
			else if (tex_vram_valid) begin
				tsp_tex_waiting <= 1'b0;
				tsp_state <= 9'd53;
			end
		end

		9'd53: begin
			if (!tsp_texture_enabled && tsp_tex_waiting) begin
				tsp_tex_waiting <= 1'b0;
			end
			else if (tsp_tex_waiting) begin
`ifdef VERILATOR
				if (tsp_tex_word_addr != tsp_tex_wait_addr_prev) begin
					tsp_tex_addr_change_wait_count <= tsp_tex_addr_change_wait_count + 1'b1;
					tsp_tex_wait_addr_prev <= tsp_tex_word_addr;
				end
`endif
				// Consume the texture response as a bubble. Issuing a pixel in the
				// same cycle as tex_vram_valid can misalign texel data vs x/y.
				if (tex_vram_valid) begin
					tsp_tex_waiting <= 1'b0;
`ifdef VERILATOR
					if (tsp_tex_word_addr != tsp_tex_req_addr)
						tsp_tex_valid_addr_mismatch_count <= tsp_tex_valid_addr_mismatch_count + 1'b1;
					if (tsp_tex_wait_len <= 8'd1)
						tsp_tex_wait_next_count <= tsp_tex_wait_next_count + 1'b1;
					else
						tsp_tex_wait_long_count <= tsp_tex_wait_long_count + 1'b1;
`endif
				end
				else begin
					// Hold in this state until the requested texture word arrives.
`ifdef VERILATOR
					tsp_tex_wait_cycle_count <= tsp_tex_wait_cycle_count + 1'b1;
					if (tsp_tex_wait_len != 8'hff) tsp_tex_wait_len <= tsp_tex_wait_len + 1'b1;
`endif
				end
			end
			else if (tsp_row_settle) begin
				// z_buff row reads are synchronous. After wrapping x back to the
				// start of a tile row, wait one cycle before consuming the new
				// row's prim_tag_out/params.
				tsp_row_settle <= 1'b0;
			end
			else if (1'b0 && !tsp_tag_row_occupied_w[tsp_y_ps[4:0]]) begin
`ifdef VERILATOR
				tsp_empty_row_skip_count <= tsp_empty_row_skip_count + 1'b1;
`endif
				if (tsp_y_ps >= {tsp_tiley, 5'd31}) begin
					tsp_drain_count <= 5'd16;
					tsp_state <= 9'd54;
				end
				else begin
					tsp_x_ps <= {tsp_tilex, 5'd0};
					tsp_y_ps <= tsp_y_ps + 11'd1;
					tsp_row_settle <= 1'b1;
				end
			end
			else if (prim_tag_out == 12'd0) begin
				// Tag 0 is the cleared/no-primitive value from the Z/tag RAM.
				// Skip it without reading parameter slot 0 or feeding the TSP.
				tsp_issue_accept = 1'b1;

				if (tsp_issue_accept) begin
					if (tsp_x_ps >= {tsp_tilex, 5'd31}) begin
						if (tsp_y_ps >= {tsp_tiley, 5'd31}) begin
							tsp_drain_count <= 5'd16;
							tsp_state <= 9'd54;
						end
						else begin
							tsp_x_ps <= {tsp_tilex, 5'd0};
							tsp_y_ps <= tsp_y_ps + 11'd1;
							tsp_row_settle <= 1'b1;
						end
					end
					else begin
						tsp_x_ps <= tsp_x_ps + 11'd1;
					end
				end
			end
			else if (prim_tag_out != prim_tag_out_prev) begin
				prim_tag_out_prev <= prim_tag_out;
				tsp_param_wait <= 2'd1;
`ifdef VERILATOR
				tag_switch_stall_count <= tag_switch_stall_count + 1'b1;
`endif
			end
			else if (tsp_param_wait != 2'd0) begin
				// prim_tag_out (combinatorial from z_buff col mux) addresses the
				// synchronous param RAM; only 1 cycle is needed before params are valid.
				tsp_param_wait <= tsp_param_wait - 2'd1;
			end
			else begin
				if (tsp_texture_needs_codebook) begin
					tex_base_word_addr_old <= tsp_tcw_base_word_addr;
					tsp_state <= 9'd100;
				end
				else if (tsp_texture_needs_fetch) begin
					if (!tsp_tex_waiting) begin
						tsp_tex_word_addr_old <= tsp_tex_word_addr;
`ifdef VERILATOR
						tsp_tex_req_addr <= tsp_tex_word_addr;
						tsp_tex_wait_addr_prev <= tsp_tex_word_addr;
`endif
						tex_vram_req_word_addr <= tsp_tex_word_addr;
						tex_vram_rd <= 1'b1;
						tsp_tex_waiting <= 1'b1;
`ifdef VERILATOR
						tsp_tex_wait_len <= 8'd0;
						tsp_tex_wait_start_count <= tsp_tex_wait_start_count + 1'b1;
`endif
					end
				end
				else if (tsp_issue_cmd) begin
					tsp_pix_wr <= 1'b1;
					tsp_pix_adv <= 1'b1;
					tsp_issue_accept = 1'b1;
`ifdef VERILATOR
					if (tsp_pix_valid) begin
						tag_visible_pixel_count <= tag_visible_pixel_count + 1'b1;
						if (!tag_run_active) begin
							tag_run_active <= 1'b1;
							tag_run_tag <= prim_tag_out;
							tag_run_len <= 16'd1;
							tag_run_tcw_base <= tcw_word_out[21:0];
							tag_run_textured <= isp_inst_out[25];
							tag_run_vq <= tcw_word_out[30];
						end
						else if (prim_tag_out == tag_run_tag) begin
							same_tag_pixel_count <= same_tag_pixel_count + 1'b1;
							if (tag_run_len != 16'hffff) tag_run_len <= tag_run_len + 1'b1;
						end
						else begin
							tag_run_finish(tag_run_len);
							tag_switch_count <= tag_switch_count + 1'b1;
							if (isp_inst_out[25]) tag_switch_textured_count <= tag_switch_textured_count + 1'b1;
							if (tag_run_textured && isp_inst_out[25] && (tag_run_tcw_base != tcw_word_out[21:0]))
								tag_switch_tex_base_change_count <= tag_switch_tex_base_change_count + 1'b1;
							if (tag_run_textured && isp_inst_out[25] && tag_run_vq && tcw_word_out[30] && (tag_run_tcw_base != tcw_word_out[21:0]))
								tag_switch_codebook_base_change_count <= tag_switch_codebook_base_change_count + 1'b1;
							tag_run_tag <= prim_tag_out;
							tag_run_len <= 16'd1;
							tag_run_tcw_base <= tcw_word_out[21:0];
							tag_run_textured <= isp_inst_out[25];
							tag_run_vq <= tcw_word_out[30];
						end
					end
`endif
				end

				if (tsp_issue_accept) begin
					if (tsp_x_ps >= {tsp_tilex, 5'd31}) begin
						if (tsp_y_ps >= {tsp_tiley, 5'd31}) begin
							tsp_drain_count <= 5'd16;
							tsp_state <= 9'd54;
						end
						else begin
							tsp_x_ps <= {tsp_tilex, 5'd0};
							tsp_y_ps <= tsp_y_ps + 11'd1;
							tsp_row_settle <= 1'b1;
						end
					end
					else begin
						tsp_x_ps <= tsp_x_ps + 11'd1;
					end
				end
			end
		end

		9'd54: begin
			// Keep the completed bank selected while delayed texture/shade outputs drain.
			if (tsp_pipeline_busy || tsp_pix_valid || tsp_texel_valid) begin
				tsp_drain_count <= 5'd8;
			end
			else if (tsp_drain_count != 5'd0) begin
				tsp_drain_count <= tsp_drain_count - 5'd1;
			end
			else begin
`ifdef VERILATOR
				if (tag_run_active) begin
					tag_run_finish(tag_run_len);
					tag_run_active <= 1'b0;
					tag_run_len <= 16'd0;
				end
`endif
				tsp_state <= 9'd0;
			end
		end

		9'd100: begin
			// Pulse the cache lookup, then wait one cycle before sampling the
			// registered hit/wait outputs from codebook_cache.
			if (!tsp_texture_enabled) begin
				tsp_tex_waiting <= 1'b0;
				tsp_state <= 9'd53;
			end
			else begin
				read_codebook <= 1'b1;
				tsp_state <= 9'd102;
			end
		end

		9'd101: begin
			if (!tsp_texture_enabled) begin
				tsp_tex_waiting <= 1'b0;
				tsp_state <= 9'd53;
			end
			else if (tsp_cb_cache_hit) begin
				tex_base_word_addr_old <= tsp_tcw_base_word_addr;
				tex_vram_req_word_addr <= tsp_tex_word_addr;
				tex_vram_rd <= 1'b1;
				tsp_tex_word_addr_old <= tsp_tex_word_addr;
`ifdef VERILATOR
				tsp_tex_req_addr <= tsp_tex_word_addr;
				tsp_tex_wait_addr_prev <= tsp_tex_word_addr;
`endif
				tsp_tex_waiting <= 1'b1;
`ifdef VERILATOR
				tsp_tex_wait_len <= 8'd0;
				tsp_tex_wait_start_count <= tsp_tex_wait_start_count + 1'b1;
`endif
				tsp_state <= 9'd53;
			end
			else if (codebook_wait) begin
				if (!tex_vram_valid) begin
`ifdef VERILATOR
					tsp_tex_rd_codebook_mode_count <= tsp_tex_rd_codebook_mode_count + 1'b1;
`endif
					tex_vram_req_word_addr <= tsp_tex_word_addr;
					tex_vram_rd <= 1'b1;
				end
`ifdef VERILATOR
				if (tex_vram_req_ack || tex_vram_valid) cb_word_count <= cb_word_count + 1'd1;
`endif
			end
			else begin
				tex_base_word_addr_old <= tsp_tcw_base_word_addr;
				tex_vram_req_word_addr <= tsp_tex_word_addr;
				tex_vram_rd <= 1'b1;
				tsp_tex_word_addr_old <= tsp_tex_word_addr;
`ifdef VERILATOR
				tsp_tex_req_addr <= tsp_tex_word_addr;
				tsp_tex_wait_addr_prev <= tsp_tex_word_addr;
`endif
				tsp_tex_waiting <= 1'b1;
`ifdef VERILATOR
				tsp_tex_wait_len <= 8'd0;
				tsp_tex_wait_start_count <= tsp_tex_wait_start_count + 1'b1;
`endif
				tsp_state <= 9'd53;
			end
		end

		9'd102: begin
			tsp_state <= 9'd101;
		end

	default: tsp_state <= 9'd0;
	endcase

	// Only for Debug atm...
	if (isp_vram_rd) isp_vram_rd_pend     <= 1'b1;
	else if (/*isp_vram_req_ack ||*/ isp_vram_valid) isp_vram_rd_pend <= 1'b0;
	
	if (tex_vram_rd) tex_vram_rd_pend     <= 1'b1;
	else if (/*tex_vram_req_ack ||*/ tex_vram_valid) tex_vram_rd_pend <= 1'b0;

`ifdef VERILATOR
`ifdef PVR_TSP_TRACE_PRINTS
	if (debug_ena_texel_reads &&
		(tsp_issue_cmd || tsp_issue_accept || tsp_pix_valid || tsp_texel_valid ||
		 tex_vram_rd || tsp_tex_waiting || (tsp_state != 9'd0))) begin
		$strobe("[ISP/TSP] cyc=%0d isp_state=%0d tsp_state=%0d isp_xy=%0d,%0d tsp_cmd_xy=%0d,%0d tile=%0d,%0d type=%0d tag=%0d prev_tag=%0d wr=%0b adv=%0b accept=%0b pix_valid=%0b texel_valid=%0b stall=%0b tex_rd=%0b tex_ready=%0b tex_wait=%0b tex_word=%06x tex_req=%06x cb_wait=%0b codebook_rd=%0b",
			dbg_cycle, isp_state, tsp_state,
			x_ps, y_ps, tsp_x_ps, tsp_y_ps, tsp_tilex, tsp_tiley, tsp_type_cnt,
			prim_tag_out, prim_tag_out_prev, tsp_issue_cmd, tsp_pix_adv, tsp_issue_accept,
			tsp_pix_valid, tsp_texel_valid, tsp_pipeline_stall, tex_vram_rd, tsp_tex_data_ready, tsp_tex_waiting,
			tsp_tex_word_addr, tex_vram_req_word_addr, codebook_wait, read_codebook);
	end
`endif
`endif
end

wire [10:0] tilex_start = {active_tilex, 5'b00000};
wire [10:0] tiley_start = {active_tiley, 5'b00000};

wire [7:0] vert_words = (two_volume&shadow) ? ((skip*2)+3) : (skip+3);

/*
wire tri_vis;
//wire signed [47:0] FX1_CLIPPED;
//wire signed [47:0] FY1_CLIPPED;
//wire signed [47:0] FX2_CLIPPED;
//wire signed [47:0] FY2_CLIPPED;
//wire signed [47:0] FX3_CLIPPED;
//wire signed [47:0] FY3_CLIPPED;

vertex_clipper  vertex_clipper_inst (
	.FRAC_BITS( FRAC_BITS ),	// input [7:0]  FRAC_BITS
	.FX1( FX1_FIXED_R ),
	.FY1( FY1_FIXED_R ),
	.FX2( FX2_FIXED ),
	.FY2( FY2_FIXED ),
	.FX3( FX3_FIXED ),
	.FY3( FY3_FIXED ),
	.max_width(  32'd1200000 ),	// input [31:0]
	.max_height( 32'd1200000 ),	// input [31:0]
	
	//.FX1_clipped( FX1_CLIPPED ),			// output signed [47:0]
	//.FY1_clipped( FY1_CLIPPED ),
	//.FX2_clipped( FX2_CLIPPED ),
	//.FY2_clipped( FY2_CLIPPED ),
	//.FX3_clipped( FX3_CLIPPED ),
	//.FY3_clipped( FY3_CLIPPED ),

	.triangle_visible( tri_vis )
);
*/

wire signed [47:0] z_min = min3(FZ1_FIXED, FZ2_FIXED, FZ3_FIXED);

wire signed [47:0] z_max = max3(FZ1_FIXED, FZ2_FIXED, FZ3_FIXED);


wire signed [47:0] y1_int = FY1_FIXED >>>FRAC_BITS;
wire signed [47:0] y2_int = FY2_FIXED >>>FRAC_BITS;
wire signed [47:0] y3_int = FY3_FIXED >>>FRAC_BITS;
wire signed [47:0] y4_int = FY4_FIXED >>>FRAC_BITS;

wire signed [47:0] y_min_int = is_quad_array ?
        min4(y1_int, y2_int, y3_int, y4_int) :
        min3(y1_int, y2_int, y3_int);

wire signed [47:0] y_max_int = is_quad_array ?
        max4(y1_int, y2_int, y3_int, y4_int) :
        max3(y1_int, y2_int, y3_int);

wire signed [47:0] tile_y_base = $signed({37'd0, tiley_start});
wire signed [47:0] tile_y_end  = tile_y_base + 48'sd31;

wire signed [47:0] tri_min_row_offs = y_min_int - tile_y_base;
wire signed [47:0] tri_max_row_offs = y_max_int - tile_y_base;

wire [4:0] tri_min_row =
	(y_min_int <= tile_y_base) ? 5'd0 :
	(y_min_int >= tile_y_end)  ? 5'd31 :
	tri_min_row_offs[4:0];

wire [4:0] tri_max_row =
	(y_max_int <= tile_y_base) ? 5'd0 :
	(y_max_int >= tile_y_end)  ? 5'd31 :
	tri_max_row_offs[4:0];

wire [4:0] hsr_start_row = render_bg ? 5'd0 : tri_min_row;
wire [4:0] hsr_end_row = render_bg ? 5'd31 : tri_max_row;


// Vertex float-to-fixed conversion...
wire signed [47:0] FX1_FIXED;
wire signed [47:0] FY1_FIXED;
wire signed [47:0] FZ1_FIXED;
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_x1 (.float_in( vert_a_x ),  .fixed( FX1_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_y1 (.float_in( vert_a_y ),  .fixed( FY1_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_z1 (.float_in( vert_a_z ),  .fixed( FZ1_FIXED ));

wire signed [47:0] FX2_FIXED;
wire signed [47:0] FY2_FIXED;
wire signed [47:0] FZ2_FIXED;
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_x2 (.float_in( vert_b_x ),  .fixed( FX2_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_y2 (.float_in( vert_b_y ),  .fixed( FY2_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_z2 (.float_in( vert_b_z ),  .fixed( FZ2_FIXED ));

wire signed [47:0] FX3_FIXED;
wire signed [47:0] FY3_FIXED;
wire signed [47:0] FZ3_FIXED;
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_x3 (.float_in( vert_c_x ),  .fixed( FX3_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_y3 (.float_in( vert_c_y ),  .fixed( FY3_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_z3 (.float_in( vert_c_z ),  .fixed( FZ3_FIXED ));

wire signed [47:0] FX4_FIXED;
wire signed [47:0] FY4_FIXED;
float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_x4 (.float_in( vert_d_x ), .fixed( FX4_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_y4 (.float_in( vert_d_y ), .fixed( FY4_FIXED ));
reg signed [47:0] FX1_FIXED_R, FY1_FIXED_R, FZ1_FIXED_R;
reg signed [47:0] FX2_FIXED_R, FY2_FIXED_R, FZ2_FIXED_R;
reg signed [47:0] FX3_FIXED_R, FY3_FIXED_R, FZ3_FIXED_R;
reg signed [47:0] FX4_FIXED_R, FY4_FIXED_R;

reg signed [47:0] FY2_sub_FY1;
reg signed [47:0] FY3_sub_FY1;
reg signed [47:0] FX2_sub_FX1;
reg signed [47:0] FX3_sub_FX1;

reg signed [55:0] C_mult_1;
reg signed [55:0] C_mult_2;
reg signed [43:0] BIG_C;

always @(posedge clock) begin
	FX1_FIXED_R <= FX1_FIXED; FY1_FIXED_R <= FY1_FIXED; FZ1_FIXED_R <= FZ1_FIXED;
	FX2_FIXED_R <= FX2_FIXED; FY2_FIXED_R <= FY2_FIXED; FZ2_FIXED_R <= FZ2_FIXED;
	FX3_FIXED_R <= FX3_FIXED; FY3_FIXED_R <= FY3_FIXED; FZ3_FIXED_R <= FZ3_FIXED;
	FX4_FIXED_R <= FX4_FIXED; FY4_FIXED_R <= FY4_FIXED;
end

always @(posedge clock) begin
	FY2_sub_FY1 <= (FY2_FIXED - FY1_FIXED);
	FY3_sub_FY1 <= (FY3_FIXED - FY1_FIXED);
	FX2_sub_FX1 <= (FX2_FIXED - FX1_FIXED);
	FX3_sub_FX1 <= (FX3_FIXED - FX1_FIXED);
end

always @(posedge clock) begin
	C_mult_1    <= (FX2_sub_FX1 * FY3_sub_FY1);
	C_mult_2    <= (FX3_sub_FX1 * FY2_sub_FY1);
end

reg signed [63:0] BIG_C_raw;
always @(posedge clock) begin
    BIG_C_raw <= C_mult_2 - C_mult_1;
end

/*
always @(posedge clock) begin
	//BIG_C       <= ((FX3_sub_FX1 * FY2_sub_FY1) - (FX2_sub_FX1 * FY3_sub_FY1)) >>>(FRAC_BITS-FRAC_DIFF);
	//BIG_C <= (C_mult_2 - C_mult_1) >>> (FRAC_BITS-FRAC_DIFF);
	BIG_C <= BIG_C_raw >>> (FRAC_BITS-FRAC_DIFF);
end
*/
wire signed [43:0] BIG_C_shifted = BIG_C_raw >>> (FRAC_BITS-FRAC_DIFF);
always @(posedge clock) BIG_C <= BIG_C_shifted;

// From the Sega Bible PDF, page 204..
//
// "Gouraud shading (ISP/TSP Instruction Word, bit 23).
//
// This specifies the type of shading. If this bit is set to "1," Gouraud shading is used, in which
// each of the vertex colors is interpolated according to the perspective. If this bit is set to "0," Flat
// Shading is used with the color from the third vertex.""
//
wire [31:0] interp_fz1_base_argb = (gouraud) ? vert_a_base_col_0 : vert_c_base_col_0;
wire [31:0] interp_fz2_base_argb = (gouraud) ? vert_b_base_col_0 : vert_c_base_col_0;
wire [31:0] interp_fz3_base_argb = (gouraud) ? vert_c_base_col_0 : vert_c_base_col_0;

// Offset colour...
wire [31:0] interp_fz1_offs_argb = (gouraud) ? vert_a_off_col : vert_c_off_col;
wire [31:0] interp_fz2_offs_argb = (gouraud) ? vert_b_off_col : vert_c_off_col;
wire [31:0] interp_fz3_offs_argb = (gouraud) ? vert_c_off_col : vert_c_off_col;

wire [10:0] tex_u_size_full = (8 << tsp_inst[5:3]);
wire [10:0] tex_v_size_full = (8 << tsp_inst[2:0]);

wire signed [31:0] FDDX_COL;
wire signed [31:0] FDDY_COL;
wire signed [31:0] small_c_COL;

generate
if (ENABLE_TEXTURE_PARAMS || ENABLE_GOURAUD_PARAMS || ENABLE_OFFSET_PARAMS) begin : g_param_interp
interp_params #(
    .FRAC_BITS( FRAC_BITS ),
    .Z_FRAC_BITS( Z_FRAC_BITS ),
    .FRAC_DIFF( FRAC_DIFF )
)
interp_params_inst (
	.clock( clock ),
	.reset_n( reset_n ),
	
    .param_id_in( param_id_in ),	// input [5:0]  param_id_in
    .start_interp( start_interp ),	// input  start_interp

	// FRAC_BITS Format...
	// All of these, including BIG_C are pre-calculated, per-triangle.
	.FY2_sub_FY1( FY2_sub_FY1 ),	// input signed [47:0] FY2_sub_FY1
	.FY3_sub_FY1( FY3_sub_FY1 ),	// input signed [47:0] FY3_sub_FY1
	.FX2_sub_FX1( FX2_sub_FX1 ),	// input signed [47:0] FX2_sub_FX1
	.FX3_sub_FX1( FX3_sub_FX1 ),	// input signed [47:0] FX3_sub_FX1
	.FX1( FX1_FIXED ),				// input signed [47:0] FX1. Fixed-point X coord for Vertex A.
	.FY1( FY1_FIXED ),				// input signed [47:0] FY1. Fixed-point Y coord for Vertex A.
	
	// Now in Z_FRAC_BITS format...
	.BIG_C( BIG_C ),				// input signed [63:0] BIG_C

	.param_a_z( vert_a_z ),
	.param_b_z( vert_b_z ),
	.param_c_z( vert_c_z ),

	.param_a_u( vert_a_u0 ),
	.param_b_u( vert_b_u0 ),
	.param_c_u( vert_c_u0 ),

	.param_a_v( vert_a_v0 ),
	.param_b_v( vert_b_v0 ),
	.param_c_v( vert_c_v0 ),

	.param_a_base_argb( interp_fz1_base_argb ),
	.param_b_base_argb( interp_fz2_base_argb ),
	.param_c_base_argb( interp_fz3_base_argb ),

	.param_a_offs_argb( interp_fz1_offs_argb ),
	.param_b_offs_argb( interp_fz2_offs_argb ),
	.param_c_offs_argb( interp_fz3_offs_argb ),

	.tex_u_size( tex_u_size_full ),
	.tex_v_size( tex_v_size_full ),

    .FDDX( FDDX_COL ),					// output [31:0]  FDDX.
    .FDDY( FDDY_COL ),					// output [31:0]  FDDY.
    .small_c( small_c_COL ),			// output [31:0]  small_c.
	
    .param_id_out( param_id_out ),	// output [5:0]  param_id_out.
    .interp_valid( interp_valid )		// output  interp_valid.
);
end
else begin : g_no_param_interp
	assign FDDX_COL = 32'd0;
	assign FDDY_COL = 32'd0;
	assign small_c_COL = 32'd0;
end
endgenerate


reg signed [31:0] FDDX_BASE_A;
reg signed [31:0] FDDX_BASE_R;
reg signed [31:0] FDDX_BASE_G;
reg signed [31:0] FDDX_BASE_B;

reg signed [31:0] FDDY_BASE_A;
reg signed [31:0] FDDY_BASE_R;
reg signed [31:0] FDDY_BASE_G;
reg signed [31:0] FDDY_BASE_B;

reg signed [31:0] c_BASE_A;
reg signed [31:0] c_BASE_R;
reg signed [31:0] c_BASE_G;
reg signed [31:0] c_BASE_B;

reg signed [47:0] FDDX_U, FDDY_U, small_c_u;
reg signed [47:0] FDDX_V, FDDY_V, small_c_v;

reg signed [31:0] FDDX_OFFS_A;
reg signed [31:0] FDDX_OFFS_R;
reg signed [31:0] FDDX_OFFS_G;
reg signed [31:0] FDDX_OFFS_B;

reg signed [31:0] FDDY_OFFS_A;
reg signed [31:0] FDDY_OFFS_R;
reg signed [31:0] FDDY_OFFS_G;
reg signed [31:0] FDDY_OFFS_B;

reg signed [31:0] c_OFFS_A;
reg signed [31:0] c_OFFS_R;
reg signed [31:0] c_OFFS_G;
reg signed [31:0] c_OFFS_B;

always @(posedge clock)
if (interp_valid) begin
	case (param_id_out)
		0:  begin FDDX_Z <= FDDX_COL; FDDY_Z <= FDDY_COL; small_c_z <= small_c_COL; end

		// Texture UV...
		1:  begin FDDX_U <= FDDX_COL; FDDY_U <= FDDY_COL; small_c_u <= small_c_COL; end
		2:  begin FDDX_V <= FDDX_COL; FDDY_V <= FDDY_COL; small_c_v <= small_c_COL; end

		// Base colour ARGB...
		3:  begin FDDX_BASE_A <= FDDX_COL; FDDY_BASE_A <= FDDY_COL; c_BASE_A <= small_c_COL; end
		4:  begin FDDX_BASE_R <= FDDX_COL; FDDY_BASE_R <= FDDY_COL; c_BASE_R <= small_c_COL; end
		5:  begin FDDX_BASE_G <= FDDX_COL; FDDY_BASE_G <= FDDY_COL; c_BASE_G <= small_c_COL; end
		6:  begin FDDX_BASE_B <= FDDX_COL; FDDY_BASE_B <= FDDY_COL; c_BASE_B <= small_c_COL; end
		
		// Offset colour ARGB...
		7:  begin FDDX_OFFS_A <= FDDX_COL; FDDY_OFFS_A <= FDDY_COL; c_OFFS_A <= small_c_COL; end
		8:  begin FDDX_OFFS_R <= FDDX_COL; FDDY_OFFS_R <= FDDY_COL; c_OFFS_R <= small_c_COL; end
		9:  begin FDDX_OFFS_G <= FDDX_COL; FDDY_OFFS_G <= FDDY_COL; c_OFFS_G <= small_c_COL; end
		10: begin FDDX_OFFS_B <= FDDX_COL; FDDY_OFFS_B <= FDDY_COL; c_OFFS_B <= small_c_COL; end
		default:;
	endcase
end


reg [10:0] x_ps;
reg [10:0] y_ps;

wire [31:0] isp_inst_out;
wire [31:0] isp_inst_out_0;
wire [31:0] isp_inst_out_1;
assign isp_inst_out = tsp_z_bank ? isp_inst_out_1 : isp_inst_out_0;

wire [31:0] tsp_inst_out;
wire [31:0] tsp_inst_out_0;
wire [31:0] tsp_inst_out_1;
assign tsp_inst_out = tsp_z_bank ? tsp_inst_out_1 : tsp_inst_out_0;

wire [31:0] tcw_word_out;
wire [31:0] tcw_word_out_0;
wire [31:0] tcw_word_out_1;
assign tcw_word_out = tsp_z_bank ? tcw_word_out_1 : tcw_word_out_0;

wire signed [31:0] FDDX_BASE_A_out;
wire signed [31:0] FDDX_BASE_A_out_0;
wire signed [31:0] FDDX_BASE_A_out_1;
assign FDDX_BASE_A_out = tsp_z_bank ? FDDX_BASE_A_out_1 : FDDX_BASE_A_out_0;

wire signed [31:0] FDDX_BASE_R_out;
wire signed [31:0] FDDX_BASE_R_out_0;
wire signed [31:0] FDDX_BASE_R_out_1;
assign FDDX_BASE_R_out = tsp_z_bank ? FDDX_BASE_R_out_1 : FDDX_BASE_R_out_0;

wire signed [31:0] FDDX_BASE_G_out;
wire signed [31:0] FDDX_BASE_G_out_0;
wire signed [31:0] FDDX_BASE_G_out_1;
assign FDDX_BASE_G_out = tsp_z_bank ? FDDX_BASE_G_out_1 : FDDX_BASE_G_out_0;

wire signed [31:0] FDDX_BASE_B_out;
wire signed [31:0] FDDX_BASE_B_out_0;
wire signed [31:0] FDDX_BASE_B_out_1;
assign FDDX_BASE_B_out = tsp_z_bank ? FDDX_BASE_B_out_1 : FDDX_BASE_B_out_0;

wire signed [31:0] FDDY_BASE_A_out;
wire signed [31:0] FDDY_BASE_A_out_0;
wire signed [31:0] FDDY_BASE_A_out_1;
assign FDDY_BASE_A_out = tsp_z_bank ? FDDY_BASE_A_out_1 : FDDY_BASE_A_out_0;

wire signed [31:0] FDDY_BASE_R_out;
wire signed [31:0] FDDY_BASE_R_out_0;
wire signed [31:0] FDDY_BASE_R_out_1;
assign FDDY_BASE_R_out = tsp_z_bank ? FDDY_BASE_R_out_1 : FDDY_BASE_R_out_0;

wire signed [31:0] FDDY_BASE_G_out;
wire signed [31:0] FDDY_BASE_G_out_0;
wire signed [31:0] FDDY_BASE_G_out_1;
assign FDDY_BASE_G_out = tsp_z_bank ? FDDY_BASE_G_out_1 : FDDY_BASE_G_out_0;

wire signed [31:0] FDDY_BASE_B_out;
wire signed [31:0] FDDY_BASE_B_out_0;
wire signed [31:0] FDDY_BASE_B_out_1;
assign FDDY_BASE_B_out = tsp_z_bank ? FDDY_BASE_B_out_1 : FDDY_BASE_B_out_0;

wire signed [31:0] c_BASE_A_out;
wire signed [31:0] c_BASE_A_out_0;
wire signed [31:0] c_BASE_A_out_1;
assign c_BASE_A_out = tsp_z_bank ? c_BASE_A_out_1 : c_BASE_A_out_0;

wire signed [31:0] c_BASE_R_out;
wire signed [31:0] c_BASE_R_out_0;
wire signed [31:0] c_BASE_R_out_1;
assign c_BASE_R_out = tsp_z_bank ? c_BASE_R_out_1 : c_BASE_R_out_0;

wire signed [31:0] c_BASE_G_out;
wire signed [31:0] c_BASE_G_out_0;
wire signed [31:0] c_BASE_G_out_1;
assign c_BASE_G_out = tsp_z_bank ? c_BASE_G_out_1 : c_BASE_G_out_0;

wire signed [31:0] c_BASE_B_out;
wire signed [31:0] c_BASE_B_out_0;
wire signed [31:0] c_BASE_B_out_1;
assign c_BASE_B_out = tsp_z_bank ? c_BASE_B_out_1 : c_BASE_B_out_0;

wire signed [31:0] FDDX_OFFS_A_out;
wire signed [31:0] FDDX_OFFS_A_out_0;
wire signed [31:0] FDDX_OFFS_A_out_1;
assign FDDX_OFFS_A_out = tsp_z_bank ? FDDX_OFFS_A_out_1 : FDDX_OFFS_A_out_0;

wire signed [31:0] FDDX_OFFS_R_out;
wire signed [31:0] FDDX_OFFS_R_out_0;
wire signed [31:0] FDDX_OFFS_R_out_1;
assign FDDX_OFFS_R_out = tsp_z_bank ? FDDX_OFFS_R_out_1 : FDDX_OFFS_R_out_0;

wire signed [31:0] FDDX_OFFS_G_out;
wire signed [31:0] FDDX_OFFS_G_out_0;
wire signed [31:0] FDDX_OFFS_G_out_1;
assign FDDX_OFFS_G_out = tsp_z_bank ? FDDX_OFFS_G_out_1 : FDDX_OFFS_G_out_0;

wire signed [31:0] FDDX_OFFS_B_out;
wire signed [31:0] FDDX_OFFS_B_out_0;
wire signed [31:0] FDDX_OFFS_B_out_1;
assign FDDX_OFFS_B_out = tsp_z_bank ? FDDX_OFFS_B_out_1 : FDDX_OFFS_B_out_0;

wire signed [31:0] FDDY_OFFS_A_out;
wire signed [31:0] FDDY_OFFS_A_out_0;
wire signed [31:0] FDDY_OFFS_A_out_1;
assign FDDY_OFFS_A_out = tsp_z_bank ? FDDY_OFFS_A_out_1 : FDDY_OFFS_A_out_0;

wire signed [31:0] FDDY_OFFS_R_out;
wire signed [31:0] FDDY_OFFS_R_out_0;
wire signed [31:0] FDDY_OFFS_R_out_1;
assign FDDY_OFFS_R_out = tsp_z_bank ? FDDY_OFFS_R_out_1 : FDDY_OFFS_R_out_0;

wire signed [31:0] FDDY_OFFS_G_out;
wire signed [31:0] FDDY_OFFS_G_out_0;
wire signed [31:0] FDDY_OFFS_G_out_1;
assign FDDY_OFFS_G_out = tsp_z_bank ? FDDY_OFFS_G_out_1 : FDDY_OFFS_G_out_0;

wire signed [31:0] FDDY_OFFS_B_out;
wire signed [31:0] FDDY_OFFS_B_out_0;
wire signed [31:0] FDDY_OFFS_B_out_1;
assign FDDY_OFFS_B_out = tsp_z_bank ? FDDY_OFFS_B_out_1 : FDDY_OFFS_B_out_0;

wire signed [31:0] c_OFFS_A_out;
wire signed [31:0] c_OFFS_A_out_0;
wire signed [31:0] c_OFFS_A_out_1;
assign c_OFFS_A_out = tsp_z_bank ? c_OFFS_A_out_1 : c_OFFS_A_out_0;

wire signed [31:0] c_OFFS_R_out;
wire signed [31:0] c_OFFS_R_out_0;
wire signed [31:0] c_OFFS_R_out_1;
assign c_OFFS_R_out = tsp_z_bank ? c_OFFS_R_out_1 : c_OFFS_R_out_0;

wire signed [31:0] c_OFFS_G_out;
wire signed [31:0] c_OFFS_G_out_0;
wire signed [31:0] c_OFFS_G_out_1;
assign c_OFFS_G_out = tsp_z_bank ? c_OFFS_G_out_1 : c_OFFS_G_out_0;

wire signed [31:0] c_OFFS_B_out;
wire signed [31:0] c_OFFS_B_out_0;
wire signed [31:0] c_OFFS_B_out_1;
assign c_OFFS_B_out = tsp_z_bank ? c_OFFS_B_out_1 : c_OFFS_B_out_0;

wire signed [47:0] FDDX_U_out;
wire signed [47:0] FDDX_U_out_0;
wire signed [47:0] FDDX_U_out_1;
assign FDDX_U_out = tsp_z_bank ? FDDX_U_out_1 : FDDX_U_out_0;

wire signed [47:0] FDDY_U_out;
wire signed [47:0] FDDY_U_out_0;
wire signed [47:0] FDDY_U_out_1;
assign FDDY_U_out = tsp_z_bank ? FDDY_U_out_1 : FDDY_U_out_0;

wire signed [47:0] small_c_u_out;
wire signed [47:0] small_c_u_out_0;
wire signed [47:0] small_c_u_out_1;
assign small_c_u_out = tsp_z_bank ? small_c_u_out_1 : small_c_u_out_0;

wire signed [47:0] FDDX_V_out;
wire signed [47:0] FDDX_V_out_0;
wire signed [47:0] FDDX_V_out_1;
assign FDDX_V_out = tsp_z_bank ? FDDX_V_out_1 : FDDX_V_out_0;

wire signed [47:0] FDDY_V_out;
wire signed [47:0] FDDY_V_out_0;
wire signed [47:0] FDDY_V_out_1;
assign FDDY_V_out = tsp_z_bank ? FDDY_V_out_1 : FDDY_V_out_0;

wire signed [47:0] small_c_v_out;
wire signed [47:0] small_c_v_out_0;
wire signed [47:0] small_c_v_out_1;
assign small_c_v_out = tsp_z_bank ? small_c_v_out_1 : small_c_v_out_0;

wire [11:0] prim_tag_mux_0 = (tsp_busy && !tsp_z_bank) ? prim_tag_out : prim_tag;
wire [11:0] prim_tag_mux_1 = (tsp_busy &&  tsp_z_bank) ? prim_tag_out : prim_tag;

param_buffer #(
	.ENABLE_TEXTURE_PARAMS(ENABLE_TEXTURE_PARAMS),
	.ENABLE_GOURAUD_PARAMS(ENABLE_GOURAUD_PARAMS),
	.ENABLE_OFFSET_PARAMS(ENABLE_OFFSET_PARAMS)
) param_buffer_inst_0
(
	.clock(clock) ,					// input  clock
	.reset_n(reset_n) ,				// input  reset_n
	
	.prim_tag(prim_tag_mux_0) ,		// input [11:0] prim_tag
	.pcache_write(pcache_write_0) ,	// input  pcache_write
	
	// input [31:0]
	.isp_inst_in(isp_inst), .tsp_inst_in(tsp_inst), .tcw_word_in(tcw_word),
	
	.FDDX_BASE_A(FDDX_BASE_A), .FDDY_BASE_A(FDDY_BASE_A), .c_BASE_A(c_BASE_A),	// input signed [31:0]
	.FDDX_BASE_R(FDDX_BASE_R), .FDDY_BASE_R(FDDY_BASE_R), .c_BASE_R(c_BASE_R),	// input signed [31:0]
	.FDDX_BASE_G(FDDX_BASE_G), .FDDY_BASE_G(FDDY_BASE_G), .c_BASE_G(c_BASE_G),	// input signed [31:0]
	.FDDX_BASE_B(FDDX_BASE_B), .FDDY_BASE_B(FDDY_BASE_B), .c_BASE_B(c_BASE_B),	// input signed [31:0]

	.FDDX_U(FDDX_U), .FDDY_U(FDDY_U), .small_c_u(small_c_u),	// input signed [47:0]
	.FDDX_V(FDDX_V), .FDDY_V(FDDY_V), .small_c_v(small_c_v),	// input signed [47:0]
	
	.FDDX_OFFS_A(FDDX_OFFS_A), .FDDY_OFFS_A(FDDY_OFFS_A), .c_OFFS_A(c_OFFS_A),	// input signed [31:0]
	.FDDX_OFFS_R(FDDX_OFFS_R), .FDDY_OFFS_R(FDDY_OFFS_R), .c_OFFS_R(c_OFFS_R),	// input signed [31:0]
	.FDDX_OFFS_G(FDDX_OFFS_G), .FDDY_OFFS_G(FDDY_OFFS_G), .c_OFFS_G(c_OFFS_G),	// input signed [31:0]
	.FDDX_OFFS_B(FDDX_OFFS_B), .FDDY_OFFS_B(FDDY_OFFS_B), .c_OFFS_B(c_OFFS_B),	// input signed [31:0]

	// output [31:0]
	.isp_inst_out(isp_inst_out_0), .tsp_inst_out(tsp_inst_out_0), .tcw_word_out(tcw_word_out_0),

	.FDDX_BASE_A_out(FDDX_BASE_A_out_0), .FDDY_BASE_A_out(FDDY_BASE_A_out_0), .c_BASE_A_out(c_BASE_A_out_0),	// output signed [31:0]
	.FDDX_BASE_R_out(FDDX_BASE_R_out_0), .FDDY_BASE_R_out(FDDY_BASE_R_out_0), .c_BASE_R_out(c_BASE_R_out_0),	// output signed [31:0]
	.FDDX_BASE_G_out(FDDX_BASE_G_out_0), .FDDY_BASE_G_out(FDDY_BASE_G_out_0), .c_BASE_G_out(c_BASE_G_out_0),	// output signed [31:0]
	.FDDX_BASE_B_out(FDDX_BASE_B_out_0), .FDDY_BASE_B_out(FDDY_BASE_B_out_0), .c_BASE_B_out(c_BASE_B_out_0),	// output signed [31:0]

	.FDDX_U_out(FDDX_U_out_0), .FDDY_U_out(FDDY_U_out_0), .small_c_u_out(small_c_u_out_0),	// output signed [47:0]
	.FDDX_V_out(FDDX_V_out_0), .FDDY_V_out(FDDY_V_out_0), .small_c_v_out(small_c_v_out_0),	// output signed [47:0]
	
	.FDDX_OFFS_A_out(FDDX_OFFS_A_out_0), .FDDY_OFFS_A_out(FDDY_OFFS_A_out_0), .c_OFFS_A_out(c_OFFS_A_out_0),	// output signed [31:0]
	.FDDX_OFFS_R_out(FDDX_OFFS_R_out_0), .FDDY_OFFS_R_out(FDDY_OFFS_R_out_0), .c_OFFS_R_out(c_OFFS_R_out_0),	// output signed [31:0]
	.FDDX_OFFS_G_out(FDDX_OFFS_G_out_0), .FDDY_OFFS_G_out(FDDY_OFFS_G_out_0), .c_OFFS_G_out(c_OFFS_G_out_0),	// output signed [31:0]
	.FDDX_OFFS_B_out(FDDX_OFFS_B_out_0), .FDDY_OFFS_B_out(FDDY_OFFS_B_out_0), .c_OFFS_B_out(c_OFFS_B_out_0)	// output signed [31:0]
);

param_buffer #(
	.ENABLE_TEXTURE_PARAMS(ENABLE_TEXTURE_PARAMS),
	.ENABLE_GOURAUD_PARAMS(ENABLE_GOURAUD_PARAMS),
	.ENABLE_OFFSET_PARAMS(ENABLE_OFFSET_PARAMS)
) param_buffer_inst_1
(
	.clock(clock) ,					// input  clock
	.reset_n(reset_n) ,				// input  reset_n
	
	.prim_tag(prim_tag_mux_1) ,		// input [11:0] prim_tag
	.pcache_write(pcache_write_1) ,	// input  pcache_write
	
	// input [31:0]
	.isp_inst_in(isp_inst), .tsp_inst_in(tsp_inst), .tcw_word_in(tcw_word),
	
	.FDDX_BASE_A(FDDX_BASE_A), .FDDY_BASE_A(FDDY_BASE_A), .c_BASE_A(c_BASE_A),	// input signed [31:0]
	.FDDX_BASE_R(FDDX_BASE_R), .FDDY_BASE_R(FDDY_BASE_R), .c_BASE_R(c_BASE_R),	// input signed [31:0]
	.FDDX_BASE_G(FDDX_BASE_G), .FDDY_BASE_G(FDDY_BASE_G), .c_BASE_G(c_BASE_G),	// input signed [31:0]
	.FDDX_BASE_B(FDDX_BASE_B), .FDDY_BASE_B(FDDY_BASE_B), .c_BASE_B(c_BASE_B),	// input signed [31:0]

	.FDDX_U(FDDX_U), .FDDY_U(FDDY_U), .small_c_u(small_c_u),	// input signed [47:0]
	.FDDX_V(FDDX_V), .FDDY_V(FDDY_V), .small_c_v(small_c_v),	// input signed [47:0]
	
	.FDDX_OFFS_A(FDDX_OFFS_A), .FDDY_OFFS_A(FDDY_OFFS_A), .c_OFFS_A(c_OFFS_A),	// input signed [31:0]
	.FDDX_OFFS_R(FDDX_OFFS_R), .FDDY_OFFS_R(FDDY_OFFS_R), .c_OFFS_R(c_OFFS_R),	// input signed [31:0]
	.FDDX_OFFS_G(FDDX_OFFS_G), .FDDY_OFFS_G(FDDY_OFFS_G), .c_OFFS_G(c_OFFS_G),	// input signed [31:0]
	.FDDX_OFFS_B(FDDX_OFFS_B), .FDDY_OFFS_B(FDDY_OFFS_B), .c_OFFS_B(c_OFFS_B),	// input signed [31:0]

	// output [31:0]
	.isp_inst_out(isp_inst_out_1), .tsp_inst_out(tsp_inst_out_1), .tcw_word_out(tcw_word_out_1),

	.FDDX_BASE_A_out(FDDX_BASE_A_out_1), .FDDY_BASE_A_out(FDDY_BASE_A_out_1), .c_BASE_A_out(c_BASE_A_out_1),	// output signed [31:0]
	.FDDX_BASE_R_out(FDDX_BASE_R_out_1), .FDDY_BASE_R_out(FDDY_BASE_R_out_1), .c_BASE_R_out(c_BASE_R_out_1),	// output signed [31:0]
	.FDDX_BASE_G_out(FDDX_BASE_G_out_1), .FDDY_BASE_G_out(FDDY_BASE_G_out_1), .c_BASE_G_out(c_BASE_G_out_1),	// output signed [31:0]
	.FDDX_BASE_B_out(FDDX_BASE_B_out_1), .FDDY_BASE_B_out(FDDY_BASE_B_out_1), .c_BASE_B_out(c_BASE_B_out_1),	// output signed [31:0]

	.FDDX_U_out(FDDX_U_out_1), .FDDY_U_out(FDDY_U_out_1), .small_c_u_out(small_c_u_out_1),	// output signed [47:0]
	.FDDX_V_out(FDDX_V_out_1), .FDDY_V_out(FDDY_V_out_1), .small_c_v_out(small_c_v_out_1),	// output signed [47:0]
	
	.FDDX_OFFS_A_out(FDDX_OFFS_A_out_1), .FDDY_OFFS_A_out(FDDY_OFFS_A_out_1), .c_OFFS_A_out(c_OFFS_A_out_1),	// output signed [31:0]
	.FDDX_OFFS_R_out(FDDX_OFFS_R_out_1), .FDDY_OFFS_R_out(FDDY_OFFS_R_out_1), .c_OFFS_R_out(c_OFFS_R_out_1),	// output signed [31:0]
	.FDDX_OFFS_G_out(FDDX_OFFS_G_out_1), .FDDY_OFFS_G_out(FDDY_OFFS_G_out_1), .c_OFFS_G_out(c_OFFS_G_out_1),	// output signed [31:0]
	.FDDX_OFFS_B_out(FDDX_OFFS_B_out_1), .FDDY_OFFS_B_out(FDDY_OFFS_B_out_1), .c_OFFS_B_out(c_OFFS_B_out_1)	// output signed [31:0]
);

/*
wire signed [63:0] f_area = ((FX1_FIXED-FX3_FIXED) * (FY2_FIXED-FY3_FIXED) - 
							 (FY1_FIXED-FY3_FIXED) * (FX2_FIXED-FX3_FIXED)) >>> FRAC_BITS;

wire sgn = f_area[63];
*/

// Z.Setup(x1,x2,x3, y1,y2,y3, z1,z2,z3);
reg signed [47:0] FDDX_Z;
reg signed [47:0] FDDY_Z;
reg signed [47:0] small_c_z;
reg  z_params_valid;

wire z_clear_busy;
wire z_clear_busy_0;
wire z_clear_busy_1;
wire isp_z_clear_busy = isp_z_bank ? z_clear_busy_1 : z_clear_busy_0;
wire clear_z_target_busy = clear_z_target_bank ? z_clear_busy_1 : z_clear_busy_0;

wire [47:0] z_out_0;
wire [47:0] z_out_1;
wire [47:0] z_out = tsp_z_bank ? z_out_1 : z_out_0;
wire [11:0] prim_tag_out_0;
wire [11:0] prim_tag_out_1;
wire [11:0] prim_tag_out = tsp_z_bank ? prim_tag_out_1 : prim_tag_out_0;

wire        any_tags_written;
wire [31:0] tag_row_occupied_0;
wire [31:0] tag_row_occupied_1;
wire [31:0] tsp_tag_row_occupied_w = tsp_z_bank ? tag_row_occupied_1 : tag_row_occupied_0;
wire signed [47:0] tile_z_min;
wire signed [47:0] tile_z_max;

wire clear_z_bank_0 = (clear_z & !isp_z_bank) | (clear_z_next_bank & !clear_z_target_bank);
wire clear_z_bank_1 = (clear_z &  isp_z_bank) | (clear_z_next_bank &  clear_z_target_bank);
wire clear_tags_only_bank_0 = clear_z_next_bank & clear_z_next_tags_only & !clear_z_target_bank & !clear_z;
wire clear_tags_only_bank_1 = clear_z_next_bank & clear_z_next_tags_only &  clear_z_target_bank & !clear_z;

// clear_tag_row_occ_*: replicate the two places isp_parser previously zeroed
// tag_row_occupied directly.
// Condition 1: ra_new_tile_start path (clear_z fires, !clear_tags_only).
// Condition 2: state-57 deferred-tile path, when TSP frees up and we
//              move back to state 56 to wait for z_clear.
wire tsp_deferred_tile_done = (isp_state == 9'd57) && deferred_tile_started && !tsp_busy;
wire clear_tag_row_occ_0 = (!isp_z_bank && clear_z_bank_0 && !clear_tags_only_bank_0) ||
                            (!tsp_ready_bank && tsp_deferred_tile_done);
wire clear_tag_row_occ_1 = ( isp_z_bank && clear_z_bank_1 && !clear_tags_only_bank_1) ||
                            ( tsp_ready_bank && tsp_deferred_tile_done);

// hsr_start: pulse one cycle before entering state 50, so hsr_core
// initialises its scan on the first clock of state 50.
wire hsr_start = ((isp_state == 9'd49) && (is_quad_array && quad_second_half)) ||
                 (isp_state == 9'd202);
wire hsr_done;

hsr_core #(
	.FRAC_BITS            (FRAC_BITS),
	.Z_FRAC_BITS          (Z_FRAC_BITS),
	.FRAC_DIFF            (FRAC_DIFF),
	.PIXEL_CENTER_SAMPLE  (PIXEL_CENTER_SAMPLE),
	.ENABLE_DEPTH_COMPARE (ENABLE_DEPTH_COMPARE),
	.INTRI_PIXELS_PER_CYCLE(INTRI_PIXELS_PER_CYCLE)
) hsr_core_inst (
	.clock       ( clock ),
	.reset_n     ( reset_n ),

	.hsr_start   ( hsr_start ),
	.hsr_done    ( hsr_done ),

	.FX1_FIXED_R ( FX1_FIXED_R ), .FX2_FIXED_R ( FX2_FIXED_R ),
	.FX3_FIXED_R ( FX3_FIXED_R ), .FX4_FIXED_R ( FX4_FIXED_R ),
	.FY1_FIXED_R ( FY1_FIXED_R ), .FY2_FIXED_R ( FY2_FIXED_R ),
	.FY3_FIXED_R ( FY3_FIXED_R ), .FY4_FIXED_R ( FY4_FIXED_R ),
	.is_quad     ( is_quad_array ),

	.tilex_start     ( tilex_start ),
	.tiley_start     ( tiley_start ),
	.hsr_start_row   ( hsr_start_row ),
	.hsr_end_row     ( hsr_end_row ),

	.z_params_hsr_ready ( z_params_hsr_ready ),
	.FDDX_Z  ( FDDX_Z ),
	.FDDY_Z  ( FDDY_Z ),
	.small_c_z ( small_c_z ),

	.depth_comp      ( depth_comp ),
	.z_write_disable ( z_write_disable ),
	.render_bg       ( render_bg ),

	.isp_z_bank ( isp_z_bank ),
	.prim_tag   ( prim_tag ),

	.clear_z_bank_0        ( clear_z_bank_0 ),
	.clear_z_bank_1        ( clear_z_bank_1 ),
	.clear_tags_only_bank_0( clear_tags_only_bank_0 ),
	.clear_tags_only_bank_1( clear_tags_only_bank_1 ),
	.clear_tag_row_occ_0   ( clear_tag_row_occ_0 ),
	.clear_tag_row_occ_1   ( clear_tag_row_occ_1 ),

	.tsp_busy    ( tsp_busy ),
	.tsp_z_bank  ( tsp_z_bank ),
	.tsp_x_ps    ( tsp_x_ps[4:0] ),
	.tsp_y_ps    ( tsp_y_ps[4:0] ),
	.rle_busy    ( rle_busy ),
	.rle_col_sel ( rle_col_sel ),
	.rle_row_sel ( rle_row_sel ),

	.any_tags_written   ( any_tags_written ),
	.tag_row_occupied_0 ( tag_row_occupied_0 ),
	.tag_row_occupied_1 ( tag_row_occupied_1 ),
	.tile_z_min         ( tile_z_min ),
	.tile_z_max         ( tile_z_max ),

	.z_clear_busy   ( z_clear_busy ),
	.z_clear_busy_0 ( z_clear_busy_0 ),
	.z_clear_busy_1 ( z_clear_busy_1 ),

	.z_out_0       ( z_out_0 ),
	.z_out_1       ( z_out_1 ),
	.prim_tag_out_0( prim_tag_out_0 ),
	.prim_tag_out_1( prim_tag_out_1 )
);

/*
// Row input
wire                span_row_valid;
wire                span_busy;
wire [4:0]          span_row_y;

wire [11:0]         tag_row [0:31];
wire signed [47:0]  z_row   [0:31];

// Span output
wire                span_valid;
wire                span_accept;

wire [11:0]         span_tag;
wire [4:0]          span_x;
wire [4:0]          span_y;
wire [5:0]          span_width;

wire signed [47:0]  span_z_start;
wire signed [47:0]  span_dzdx;

span_sorter_row #(
    .TAG_W (12),
    .Z_W   (48)
) span_sorter_inst (
    .clk        ( clock ),
    .rst        ( !reset_n ),

    // Row input
	.span_busy  ( span_busy ),		// output
    .row_valid  ( span_row_valid ),	// input
    .row_y      ( span_row_y ),		// input [4:0]
    .tag_row    ( tag_row ),		// input [TAG_W-1:0]    tag_row [0:31]
    .z_row      ( z_row ),			// input signed [Z_W-1:0] z_row [0:31]

    // Span output
    .span_valid   ( span_valid ),	// output to TSP.
    .span_accept  ( span_accept ),	// input from TSP.

    .span_tag     ( span_tag ),		// output [TAG_W-1:0]
    .span_x       ( span_x ),		// output [4:0]
    .span_y       ( span_y ),		// output [4:0]
    .span_width   ( span_width ),	// output [5:0]

    .span_z_start ( span_z_start ),	// output signed [Z_W-1:0]
    .span_dzdx    ( span_dzdx )		// output signed [Z_W-1:0]
);
*/

reg rle_start;
wire [4:0] rle_row_sel;
wire [4:0] rle_col_sel;

reg [4:0] rle_tilex;
reg [4:0] rle_tiley;

wire [11:0] rle_tag;
wire [9:0] rle_count;
wire [4:0] rle_row_start;
wire [4:0] rle_col_start;
wire transfer_z;
wire rle_valid;


wire rle_busy = 1'b0;
wire rle_param_load = 1'b0;	// Not needed atm. Params get read during RLE / Z-buffer / prim_tag_out anyway.

wire rle_done = 1'b1;
/*
rle_by_tag  rle_by_tag_inst (
    .clk( clock ),					// input  clock
    .rst( !reset_n ),				// input  rst
    
	.rle_start( rle_start ),		// input  rle_start
    
    .rle_row_sel( rle_row_sel ),	// output [4:0] rle_row_sel
	.rle_col_sel( rle_col_sel ),	// output [4:0] rle_col_sel
	
	.tag_in( prim_tag_out ),		// input  [11:0] tag_in
	
	.transfer_z( transfer_z ),		    // output  transfer_z
	.rle_tag( rle_tag ),				// output [11:0]  rle_tag
	.rle_count( rle_count ),			// output [9:0]  rle_count
    .rle_row_start( rle_row_start ),	// output reg  [4:0]  rle_row_start
    .rle_col_start( rle_col_start ),	// output reg  [4:0]  rle_col_start
    .rle_valid( rle_valid ),			// output  rle_valid
	.rle_busy( rle_busy ),				// output  rle_busy
	.rle_param_load( rle_param_load ),	// output  rle_param_load
	
    .rle_done( rle_done )				// output  rle_done
);
*/

/*
reg rle_start;
wire rle_busy;
wire rle_done;

wire [4:0] rle_row_sel;
wire [4:0] rle_col_sel;

reg [4:0] rle_tilex;
reg [4:0] rle_tiley;

wire  [4:0] sorter_row_index;
wire  sorter_row_valid;
wire  [127:0] sorter_param_data;
wire  sorter_param_valid;
 
wire [4:0] rle_tile_x;
wire [4:0] rle_tile_y;
wire [2:0] rle_prim_type;
wire [9:0] rle_start_addr; //  y*32 + x
wire [10:0] rle_run_length;
wire [9:0] rle_tag;
wire [127:0] rle_params;
wire rle_valid;
wire param_request;
wire [5:0] requested_tag;

tsp_tag_sorter  tag_sorter_inst (
    .clk( clock ),						// input wire 
    .reset( !reset_n ),					// input wire 
	
    .rle_start( rle_start ),			// input wire 
    .rle_busy( rle_busy ),				// output wire 
	
    .rle_row_sel( rle_row_sel ),		// output  [4:0] rle_row_sel
    .rle_col_sel( rle_col_sel ),		// output  [4:0] rle_col_sel
	
	.prim_tag( prim_tag_out ),			// input [11:0] prim_tag
	
	.param_data( sorter_param_data ),	// input [127:0] param_data
	.tile_x( active_tilex ),			// input [4:0] tile_x
	.tile_y( active_tiley ),			// input [4:0] tile_y
	.type_cnt( type_cnt ),				// input [2:0] type_cnt
	
	.rle_tile_x( rle_tile_x ),			// output [4:0] rle_tile_x
	.rle_tile_y( rle_tile_y ),			// output [4:0] rle_tile_y
	.rle_prim_type( rle_prim_type ),	// output [2:0] rle_prim_type
    .rle_start_addr( rle_start_addr ),	// output [9:0] rle_start_addr.  y*32 + x
    .rle_run_length( rle_run_length ),	// output [10:0] rle_run_length. (starts from 1, so needs to be 11-bits, for max value of 1,024).
    .rle_tag( rle_tag ),           		// output [9:0] rle_tag.
    .rle_params( rle_params ),      	// output [127:0] rle_params.
    .rle_valid( rle_valid ),			// output rle_valid.
    .param_request( param_request ),	// output param_request
    .requested_tag( requested_tag ),	// output [5:0] requested_tag
	
    .rle_done( rle_done )				// output  processing_complete
);
*/

//wire codebook_wait;
reg read_codebook;
reg cb_cache_clear;

reg [21:0] tsp_tex_word_addr_old;
`ifdef VERILATOR
reg [21:0] tsp_tex_req_addr;
reg [21:0] tsp_tex_wait_addr_prev;
`endif
reg [21:0] tex_vram_req_word_addr;

wire pipe_flush = (tsp_state == 9'd51);

assign tsp_pipe_flush = pipe_flush;
assign tsp_read_codebook = read_codebook;
assign tsp_cb_cache_clear = cb_cache_clear;

assign tsp_isp_inst_out = isp_inst_out;
assign tsp_tsp_inst_out = tsp_inst_out;
assign tsp_tcw_word_out = tcw_word_out;

assign tsp_FDDX_BASE_A = FDDX_BASE_A_out; assign tsp_FDDY_BASE_A = FDDY_BASE_A_out; assign tsp_c_BASE_A = c_BASE_A_out;
assign tsp_FDDX_BASE_R = FDDX_BASE_R_out; assign tsp_FDDY_BASE_R = FDDY_BASE_R_out; assign tsp_c_BASE_R = c_BASE_R_out;
assign tsp_FDDX_BASE_G = FDDX_BASE_G_out; assign tsp_FDDY_BASE_G = FDDY_BASE_G_out; assign tsp_c_BASE_G = c_BASE_G_out;
assign tsp_FDDX_BASE_B = FDDX_BASE_B_out; assign tsp_FDDY_BASE_B = FDDY_BASE_B_out; assign tsp_c_BASE_B = c_BASE_B_out;

assign tsp_FDDX_U = FDDX_U_out; assign tsp_FDDY_U = FDDY_U_out; assign tsp_small_c_u = small_c_u_out;
assign tsp_FDDX_V = FDDX_V_out; assign tsp_FDDY_V = FDDY_V_out; assign tsp_small_c_v = small_c_v_out;

assign tsp_FDDX_OFFS_A = FDDX_OFFS_A_out; assign tsp_FDDY_OFFS_A = FDDY_OFFS_A_out; assign tsp_c_OFFS_A = c_OFFS_A_out;
assign tsp_FDDX_OFFS_R = FDDX_OFFS_R_out; assign tsp_FDDY_OFFS_R = FDDY_OFFS_R_out; assign tsp_c_OFFS_R = c_OFFS_R_out;
assign tsp_FDDX_OFFS_G = FDDX_OFFS_G_out; assign tsp_FDDY_OFFS_G = FDDY_OFFS_G_out; assign tsp_c_OFFS_G = c_OFFS_G_out;
assign tsp_FDDX_OFFS_B = FDDX_OFFS_B_out; assign tsp_FDDY_OFFS_B = FDDY_OFFS_B_out; assign tsp_c_OFFS_B = c_OFFS_B_out;

assign tsp_x_ps_cmd = tsp_x_ps;
assign tsp_y_ps_cmd = tsp_y_ps;
assign tsp_z_out = z_out;
assign tsp_type_cnt_cmd = tsp_type_cnt;
assign tsp_tilex_cmd = tsp_tilex;
assign tsp_tiley_cmd = tsp_tiley;
assign tsp_pix_wr_cmd = tsp_issue_cmd;
assign tsp_tex_data_ready = !tsp_texture_enabled || !isp_inst_out[25] ||
							(!tsp_tex_waiting && (tsp_tex_word_addr_old == tsp_tex_word_addr));
assign tsp_transfer_z = transfer_z;
assign tsp_rle_tag = rle_tag;
assign tsp_rle_count = rle_count;
assign tsp_rle_row_start = rle_row_start;
assign tsp_rle_col_start = rle_col_start;
assign tsp_rle_valid = rle_valid;
assign tsp_rle_busy = rle_busy;
assign tsp_rle_param_load = rle_param_load;
assign tsp_rle_done = rle_done;


endmodule

function automatic signed [FIXED_W-1:0] min3;
    input signed [FIXED_W-1:0] a;
    input signed [FIXED_W-1:0] b;
    input signed [FIXED_W-1:0] c;
    begin
        min3 = (a < b) ? ((a < c) ? a : c)
                       : ((b < c) ? b : c);
    end
endfunction

function automatic signed [FIXED_W-1:0] max3;
    input signed [FIXED_W-1:0] a;
    input signed [FIXED_W-1:0] b;
    input signed [FIXED_W-1:0] c;
    begin
        max3 = (a > b) ? ((a > c) ? a : c)
                       : ((b > c) ? b : c);
    end
endfunction

function automatic signed [FIXED_W-1:0] min4;
    input signed [FIXED_W-1:0] a;
    input signed [FIXED_W-1:0] b;
    input signed [FIXED_W-1:0] c;
    input signed [FIXED_W-1:0] d;
    reg signed [FIXED_W-1:0] m1, m2;
    begin
        m1 = (a < b) ? a : b;
        m2 = (c < d) ? c : d;
        min4 = (m1 < m2) ? m1 : m2;
    end
endfunction

function automatic signed [FIXED_W-1:0] max4;
    input signed [FIXED_W-1:0] a;
    input signed [FIXED_W-1:0] b;
    input signed [FIXED_W-1:0] c;
    input signed [FIXED_W-1:0] d;
    reg signed [FIXED_W-1:0] m1, m2;
    begin
        m1 = (a > b) ? a : b;
        m2 = (c > d) ? c : d;
        max4 = (m1 > m2) ? m1 : m2;
    end
endfunction
