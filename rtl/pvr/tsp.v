`timescale 1ns / 1ps
`default_nettype none

module tsp #(
	parameter [7:0] FRAC_BITS = 8'd12,			// Q format for XY coordinates (e.g., Q21.11)
	parameter [7:0] Z_FRAC_BITS = 8'd17,		// Q format for Z values (e.g., Q20.12)
	parameter [7:0] FRAC_DIFF = Z_FRAC_BITS - FRAC_BITS,
	parameter ENABLE_TEXTURE_PIPELINE = 1'b1,
	parameter ENABLE_GOURAUD_SHADE = 1'b1,
	parameter ENABLE_OFFSET_SHADE = 1'b1,
`ifdef PVR_ENABLE_TILE_ARGB_BUFFER
	parameter ENABLE_TILE_ARGB_BUFFER = 1'b1
`else
	parameter ENABLE_TILE_ARGB_BUFFER = 1'b0
`endif
) (
    input  wire clock,
    input  wire reset_n,
	input  wire pipe_flush,
	
	input [31:0] TEXT_CONTROL,
	input [31:0] PAL_RAM_CTRL,
	input [31:0] FPU_SHAD_SCALE,
	input [31:0] dbg_cycle,
	
	input [9:0] pal_addr,
	input [31:0] pal_din,
	input pal_wr,
	
	input pal_rd,
	output [31:0] pal_dout,
	
	input read_codebook,
	output wire codebook_wait,
	input wire cb_cache_clear,
	output wire cb_cache_hit,
	
	// Control Word, Vertex, and Colour Parameter inputs...
	input [31:0] isp_inst_out,
	input [31:0] tsp_inst_out,
	input [31:0] tcw_word_out,

	input signed [31:0] FDDX_BASE_A, FDDY_BASE_A, c_BASE_A,
	input signed [31:0] FDDX_BASE_R, FDDY_BASE_R, c_BASE_R,
	input signed [31:0] FDDX_BASE_G, FDDY_BASE_G, c_BASE_G,
	input signed [31:0] FDDX_BASE_B, FDDY_BASE_B, c_BASE_B,

	input signed [47:0] FDDX_U, FDDY_U, small_c_u,
	input signed [47:0] FDDX_V, FDDY_V, small_c_v,
	
	input signed [31:0] FDDX_OFFS_A, FDDY_OFFS_A, c_OFFS_A,
	input signed [31:0] FDDX_OFFS_R, FDDY_OFFS_R, c_OFFS_R,
	input signed [31:0] FDDX_OFFS_G, FDDY_OFFS_G, c_OFFS_G,
	input signed [31:0] FDDX_OFFS_B, FDDY_OFFS_B, c_OFFS_B,

	input  wire [10:0] x_ps,
	input  wire [10:0] y_ps,
	input  wire signed [47:0] z_out,
	
	input  wire [11:0] prim_tag_out,
	
	input  wire [2:0]  type_cnt,
	
	// From the ISP RLE block...
    input wire [4:0]   row_sel,
    input wire [4:0]   col_sel,
	
	input wire         transfer_z,
    input wire [11:0]  rle_tag,
    input wire [9:0]   rle_count,
    input wire [4:0]   rle_row_start,
    input wire [4:0]   rle_col_start,
    input wire         rle_valid,
    input wire         rle_busy,
	input wire         rle_param_load,
	input wire         rle_done,
	
    // Flag stuffs.
    input  wire        disable_alpha,
    input  wire        debug_ena_texel_reads,
	
	output wire [21:0] tsp_tex_word_addr,	// output [21:0]  tsp_tex_word_addr. 32-bit or 64-bit WORD address! Hard to explain. lol
	input  wire [63:0] tex_vram_din,	// input [63:0]  vram_din. Full 64-bit data for texture reads.
	input  wire        vram_wait,
	input  wire        tex_vram_valid,	
	input  wire        tex_data_ready,
	
    // Control and writeback
    input  wire        wr_pix,

    input  wire        tile_wb,
	output wire        wb_done,

    input  wire [9:0]  tilex,
    input  wire [9:0]  tiley,
	
	output wire pipeline_stall,
	output wire pipeline_busy,

	input wire tsp_pix_wr,
	//input wire [10:0] sim_ui,
	//input wire [10:0] sim_vi,
	
	output wire [31:0] texel_argb,
	
	output wire texel_valid,

	// FB writeback from new texture pipeline...
	output wire [31:0] final_argb,
	output wire [15:0] pix_565,
	output wire [9:0] x_ps_out,
	output wire [9:0] y_ps_out,
	output wire pix_valid,
	
	output wire [22:0] fb_addr,
	output wire [63:0] fb_writedata,
	output wire [7:0] fb_byteena,
	output wire [7:0] fb_burstcnt,
	output wire fb_we,
	input  wire fb_wait,
	output wire tile_wb_busy
);

// ISP/TSP Instruction Word. Bit decode, for Opaque or Translucent prims...
wire [2:0] depth_comp   = isp_inst_out[31:29];	// 0=Never, 1=Less, 2=Equal, 3=Less Or Equal, 4=Greater, 5=Not Equal, 6=Greater Or Equal, 7=Always.
wire [1:0] culling_mode = isp_inst_out[28:27];	// 0=No culling, 1=Cull if Small, 2= Cull if Neg, 3=Cull if Pos.
wire z_write_disable    = isp_inst_out[26];
wire texture            = isp_inst_out[25];
wire offset             = isp_inst_out[24];
wire gouraud            = isp_inst_out[23];
wire uv_16_bit          = isp_inst_out[22];
wire cache_bypass       = isp_inst_out[21];
wire dcalc_ctrl         = isp_inst_out[20];
// Bits [19:0] are reserved.

// ISP/TSP Instruction Word. Bit decode, for Opaque Modifier Volume or Translucent Modified Volume...
wire [2:0] volume_inst = isp_inst_out[31:29];
//wire [1:0] culling_mode = isp_inst[28:27];	// Same bit select as above.
// Bits [26:0] are reserved.

// TSP Instruction Word...
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
(*noprune*)reg [31:0] tcw_word;
wire mip_map = tcw_word_out[31];
wire vq_comp = tcw_word_out[30];
wire [2:0] pix_fmt = tcw_word_out[29:27];
wire scan_order = tcw_word_out[26];
wire stride_flag = tcw_word_out[25];
wire [20:0] tex_word_addr = tcw_word_out[20:0];		// 64-bit WORD address! (but only shift <<2 when accessing 32-bit "halves" of VRAM).

// Definitely need to use the signed version of x_ps and y_ps, to get correct colours!
wire signed [11:0] x_ps_signed = $signed({1'b0, x_ps});
wire signed [11:0] y_ps_signed = $signed({1'b0, y_ps});

wire [31:0] interp_base_col;
wire [31:0] interp_offs_col;

generate
	if (ENABLE_GOURAUD_SHADE) begin : g_gouraud_shade
		wire signed [31:0] BASE_A_INTERP = ((x_ps_signed * FDDX_BASE_A) + (y_ps_signed * FDDY_BASE_A) + c_BASE_A);
		wire signed [31:0] BASE_R_INTERP = ((x_ps_signed * FDDX_BASE_R) + (y_ps_signed * FDDY_BASE_R) + c_BASE_R);
		wire signed [31:0] BASE_G_INTERP = ((x_ps_signed * FDDX_BASE_G) + (y_ps_signed * FDDY_BASE_G) + c_BASE_G);
		wire signed [31:0] BASE_B_INTERP = ((x_ps_signed * FDDX_BASE_B) + (y_ps_signed * FDDY_BASE_B) + c_BASE_B);
		assign interp_base_col = {clamp255(BASE_A_INTERP, Z_FRAC_BITS), clamp255(BASE_R_INTERP, Z_FRAC_BITS), clamp255(BASE_G_INTERP, Z_FRAC_BITS), clamp255(BASE_B_INTERP, Z_FRAC_BITS)};
	end
	else begin : g_flat_shade
		assign interp_base_col = {clamp255(c_BASE_A, Z_FRAC_BITS), clamp255(c_BASE_R, Z_FRAC_BITS), clamp255(c_BASE_G, Z_FRAC_BITS), clamp255(c_BASE_B, Z_FRAC_BITS)};
	end

	if (ENABLE_OFFSET_SHADE) begin : g_offset_shade
		wire signed [31:0] OFFS_A_INTERP = ((x_ps_signed * FDDX_OFFS_A) + (y_ps_signed * FDDY_OFFS_A) + c_OFFS_A);
		wire signed [31:0] OFFS_R_INTERP = ((x_ps_signed * FDDX_OFFS_R) + (y_ps_signed * FDDY_OFFS_R) + c_OFFS_R);
		wire signed [31:0] OFFS_G_INTERP = ((x_ps_signed * FDDX_OFFS_G) + (y_ps_signed * FDDY_OFFS_G) + c_OFFS_G);
		wire signed [31:0] OFFS_B_INTERP = ((x_ps_signed * FDDX_OFFS_B) + (y_ps_signed * FDDY_OFFS_B) + c_OFFS_B);
		assign interp_offs_col = {clamp255(OFFS_A_INTERP, Z_FRAC_BITS), clamp255(OFFS_R_INTERP, Z_FRAC_BITS), clamp255(OFFS_G_INTERP, Z_FRAC_BITS), clamp255(OFFS_B_INTERP, Z_FRAC_BITS)};
	end
	else begin : g_no_offset_shade
		assign interp_offs_col = 32'd0;
	end
endgenerate


wire [9:0] u_flipped;
wire [9:0] v_flipped;

`ifdef VERILATOR
// Keep these names at tsp_top scope for sim_main.cpp debug/UI access.
wire [10:0] tex_u_size_full = (8 << tex_u_size);
wire [10:0] tex_v_size_full = (8 << tex_v_size);

wire signed [63:0] x_ps_mult_fddx_u = (x_ps_signed * FDDX_U);
wire signed [63:0] y_ps_mult_fddy_u = (y_ps_signed * FDDY_U);
wire signed [31:0] IP_U_INTERP = x_ps_mult_fddx_u + y_ps_mult_fddy_u + small_c_u;
wire signed [31:0] IP_U_PERSP = (IP_U_INTERP <<< Z_FRAC_BITS) / z_out;
wire signed [9:0] u_div_z = IP_U_PERSP >>> Z_FRAC_BITS;

wire signed [63:0] x_ps_mult_fddx_v = (x_ps_signed * FDDX_V);
wire signed [63:0] y_ps_mult_fddy_v = (y_ps_signed * FDDY_V);
wire signed [31:0] IP_V_INTERP = x_ps_mult_fddx_v + y_ps_mult_fddy_v + small_c_v;
wire signed [31:0] IP_V_PERSP = (IP_V_INTERP <<< Z_FRAC_BITS) / z_out;
wire signed [9:0] v_div_z = IP_V_PERSP >>> Z_FRAC_BITS;

uv_clamp_flip  uv_clamp_flip_inst(
	.tex_u_size_full( tex_u_size_full ),	// input [10:0]  tex_u_size_full
	.tex_v_size_full( tex_v_size_full ),	// input [10:0]  tex_v_size_full
	.u_div_z( u_div_z ),				// input signed [9:0]  u_div_z
	.v_div_z( v_div_z ),				// input signed [9:0]  v_div_z
	.tex_u_clamp( tex_u_clamp ),		// input  tex_u_clamp
	.tex_v_clamp( tex_v_clamp ),		// input  tex_v_clamp
	.tex_u_flip( tex_u_flip ),			// input  tex_u_flip
	.tex_v_flip( tex_v_flip ),			// input  tex_v_flip
	.u_flipped( u_flipped ),			// output [9:0]  u_flipped
	.v_flipped( v_flipped )				// output [9:0]  v_flipped
);
`else
generate
	if (ENABLE_TEXTURE_PIPELINE) begin : g_uv_persp
		// Texture size scaling (8 * 2^tex_u_size)
		// Highest value is 1024 (8<<7) so we need 11 bits to store it! ElectronAsh.
		wire [10:0] tex_u_size_full = (8 << tex_u_size);
		wire [10:0] tex_v_size_full = (8 << tex_v_size);

		// Texture U/V interp and perspective divide.
		wire signed [63:0] x_ps_mult_fddx_u = (x_ps_signed * FDDX_U);
		wire signed [63:0] y_ps_mult_fddy_u = (y_ps_signed * FDDY_U);
		wire signed [31:0] IP_U_INTERP = x_ps_mult_fddx_u + y_ps_mult_fddy_u + small_c_u;
		wire signed [31:0] IP_U_PERSP = (IP_U_INTERP <<< Z_FRAC_BITS) / z_out;
		wire signed [9:0] u_div_z = IP_U_PERSP >>> Z_FRAC_BITS;

		wire signed [63:0] x_ps_mult_fddx_v = (x_ps_signed * FDDX_V);
		wire signed [63:0] y_ps_mult_fddy_v = (y_ps_signed * FDDY_V);
		wire signed [31:0] IP_V_INTERP = x_ps_mult_fddx_v + y_ps_mult_fddy_v + small_c_v;
		wire signed [31:0] IP_V_PERSP = (IP_V_INTERP <<< Z_FRAC_BITS) / z_out;
		wire signed [9:0] v_div_z = IP_V_PERSP >>> Z_FRAC_BITS;

		uv_clamp_flip  uv_clamp_flip_inst(
			.tex_u_size_full( tex_u_size_full ),	// input [10:0]  tex_u_size_full
			.tex_v_size_full( tex_v_size_full ),	// input [10:0]  tex_v_size_full
			.u_div_z( u_div_z ),				// input signed [9:0]  u_div_z
			.v_div_z( v_div_z ),				// input signed [9:0]  v_div_z
			.tex_u_clamp( tex_u_clamp ),		// input  tex_u_clamp
			.tex_v_clamp( tex_v_clamp ),		// input  tex_v_clamp
			.tex_u_flip( tex_u_flip ),			// input  tex_u_flip
			.tex_v_flip( tex_v_flip ),			// input  tex_v_flip
			.u_flipped( u_flipped ),			// output [9:0]  u_flipped
			.v_flipped( v_flipped )				// output [9:0]  v_flipped
		);
	end
	else begin : g_no_uv_persp
		assign u_flipped = 10'd0;
		assign v_flipped = 10'd0;
	end
endgenerate
`endif

/*
texture_address  texture_address_inst (
	.clock( clock ),
	.reset_n( reset_n ),
	
	.isp_inst( isp_inst_out ),			// input [31:0]  isp_inst.
	.tsp_inst( tsp_inst_out ),			// input [31:0]  tsp_inst.
	.tcw_word( tcw_word_out ),			// input [31:0]  tcw_word.
	
	.TEXT_CONTROL( TEXT_CONTROL ),		// input [31:0]  TEXT_CONTROL.

	.PAL_RAM_CTRL( PAL_RAM_CTRL ),		// input from PAL_RAM_CTRL, bits [1:0].
	.pal_addr( pal_addr ),				// input [9:0]  pal_addr
	.pal_din( pal_din ),				// input [31:0]  pal_din
	.pal_wr( pal_wr ),					// input  pal_wr
	.pal_rd( pal_rd ),					// input  pal_rd
	.pal_dout( pal_dout ),				// output [31:0]  pal_dout

	//.prim_tag( prim_tag_out ),		// input [11:0]  prim_tag
	.prim_tag( tcw_word_out[13:2] ),	// input [11:0]  prim_tag
	.cb_cache_clear( cb_cache_clear ),	// input  cb_cache_clear (on new tile start).
	.cb_cache_hit( cb_cache_hit ),		// output  cb_cache_hit
	
	.read_codebook( read_codebook ),	// input  read_codebook
	.codebook_wait( codebook_wait ),	// output codebook_wait
	
	.ui( u_flipped ),
	.vi( v_flipped ),
	//.ui( sim_ui ),
	//.vi( sim_vi ),
	
	.vram_wait( vram_wait ),
	.tex_vram_valid( tex_vram_valid ),
	.vram_word_addr( tsp_tex_word_addr ),	// output [21:0]  tsp_tex_word_addr. 32-bit or 64-bit WORD address! Hard to explain. lol
	.vram_din( tex_vram_din ),			// input [63:0]  vram_din. Full 64-bit data for texture reads.
	
	// Todo: tex_fog_control. See the Sega Bible PDF, page 201.
//	.base_argb( {base_alpha, interp_base_col[23:0]} ),		// input [31:0]  base_argb.  Flat-shading colour input. (will also do Gouraud eventually).
//	.offs_argb( {offs_alpha, interp_offs_col[23:0]} ),		// input [31:0]  offs_argb.  Offset colour input.
	.base_argb( interp_base_col ),		// input [31:0]  base_argb.  Flat-shading colour input. (will also do Gouraud eventually).
	.offs_argb( interp_offs_col ),		// input [31:0]  offs_argb.  Offset colour input.
	
	.texel_argb( texel_argb ),			// output [31:0]  texel_argb. Texel ARGB 8888 output.
	.final_argb( final_argb )			// output [31:0]  final_argb. Final blended ARGB 8888 output.
);
*/


wire stall_tex_fetch;
wire stall_codebook;
wire fb_writeback_stall;
assign pipeline_stall = stall_tex_fetch || stall_codebook || (ENABLE_TEXTURE_PIPELINE && vram_wait) || fb_writeback_stall;

wire trace_a;
wire trace_b;
wire trace_c;

`ifdef VERILATOR
texture_pipeline  texture_address_inst (
    // Clock / reset
    .clock          ( clock          ),
    .reset_n        ( reset_n        ),
	.pipe_flush     ( pipe_flush     ),

    // Rasterizer / interpolator inputs
    .tsp_valid      ( tsp_pix_wr     ),
    .x_ps           ( x_ps           ),
    .y_ps           ( y_ps           ),
    .ui             ( u_flipped      ),
    .vi             ( v_flipped      ),

    // ISP / TSP / TCW control words
    .isp_inst       ( isp_inst_out   ),
    .tsp_inst       ( tsp_inst_out   ),
    .tcw_word       ( tcw_word_out   ),

	.TEXT_CONTROL( TEXT_CONTROL ),		// input [31:0]  TEXT_CONTROL.

	.PAL_RAM_CTRL( PAL_RAM_CTRL ),		// input from PAL_RAM_CTRL, bits [1:0].
	.pal_addr( pal_addr ),				// input [9:0]  pal_addr
	.pal_din( pal_din ),				// input [31:0]  pal_din
	.pal_wr( pal_wr ),					// input  pal_wr
	.pal_rd( pal_rd ),					// input  pal_rd
	.pal_dout( pal_dout ),				// output [31:0]  pal_dout

	.read_codebook( read_codebook ),	// input  read_codebook
	.codebook_wait( codebook_wait ),	// output codebook_wait

	//.prim_tag( prim_tag_out ),		// input [11:0]  prim_tag
	.prim_tag( tcw_word_out[13:2] ),	// input [11:0]  prim_tag
	.cb_cache_clear( cb_cache_clear ),	// input  cb_cache_clear (on new tile start).
	.cb_cache_hit( cb_cache_hit ),		// output  cb_cache_hit

	.stall_tex_fetch( stall_tex_fetch ),
	.stall_codebook( stall_codebook ),
	.pipeline_busy ( pipeline_busy ),
	.dbg_cycle     ( dbg_cycle      ),

    // VRAM interface
    // Texture read address
    .vram_word_addr ( tsp_tex_word_addr ),
    .vram_wait      ( vram_wait      ),
    .tex_vram_valid ( tex_vram_valid ),
    .tex_data_ready ( tex_data_ready ),
    .vram_din       ( tex_vram_din   ),

    // Shading inputs
    .base_argb      ( interp_base_col ),
    .offs_argb      ( interp_offs_col ),

    // Outputs to framebuffer / tile buffer
	.pix_valid      ( pix_valid      ),
	.final_argb     ( final_argb     ),
	.x_ps_out       ( x_ps_out       ),
	.y_ps_out       ( y_ps_out       ),
	.trace_a        ( trace_a        ),
	.trace_b        ( trace_b        ),
	.trace_c        ( trace_c        ),

	.texel_valid    ( texel_valid    )
);
`else
generate
	if (ENABLE_TEXTURE_PIPELINE) begin : g_texture_pipeline
texture_pipeline  texture_address_inst (
    // Clock / reset
    .clock          ( clock          ),
    .reset_n        ( reset_n        ),
	.pipe_flush     ( pipe_flush     ),

    // Rasterizer / interpolator inputs
    .tsp_valid      ( tsp_pix_wr     ),
    .x_ps           ( x_ps           ),
    .y_ps           ( y_ps           ),
    .ui             ( u_flipped      ),
    .vi             ( v_flipped      ),

    // ISP / TSP / TCW control words
    .isp_inst       ( isp_inst_out   ),
    .tsp_inst       ( tsp_inst_out   ),
    .tcw_word       ( tcw_word_out   ),
	
	.TEXT_CONTROL( TEXT_CONTROL ),		// input [31:0]  TEXT_CONTROL.

	.PAL_RAM_CTRL( PAL_RAM_CTRL ),		// input from PAL_RAM_CTRL, bits [1:0].
	.pal_addr( pal_addr ),				// input [9:0]  pal_addr
	.pal_din( pal_din ),				// input [31:0]  pal_din
	.pal_wr( pal_wr ),					// input  pal_wr
	.pal_rd( pal_rd ),					// input  pal_rd
	.pal_dout( pal_dout ),				// output [31:0]  pal_dout
	
	.read_codebook( read_codebook ),	// input  read_codebook
	.codebook_wait( codebook_wait ),	// output codebook_wait
	
	//.prim_tag( prim_tag_out ),		// input [11:0]  prim_tag
	.prim_tag( tcw_word_out[13:2] ),	// input [11:0]  prim_tag
	.cb_cache_clear( cb_cache_clear ),	// input  cb_cache_clear (on new tile start).
	.cb_cache_hit( cb_cache_hit ),		// output  cb_cache_hit
	
	.stall_tex_fetch( stall_tex_fetch ),
	.stall_codebook( stall_codebook ),
	.pipeline_busy ( pipeline_busy ),
	.dbg_cycle     ( dbg_cycle      ),

    // VRAM interface
    // Texture read address
    .vram_word_addr ( tsp_tex_word_addr ),
    .vram_wait      ( vram_wait      ),
    .tex_vram_valid ( tex_vram_valid ),
    .tex_data_ready ( tex_data_ready ),
    .vram_din       ( tex_vram_din   ),

    // Shading inputs
    .base_argb      ( interp_base_col ),
    .offs_argb      ( interp_offs_col ),

    // Outputs to framebuffer / tile buffer
	.pix_valid      ( pix_valid      ),
	.final_argb     ( final_argb     ),
	.x_ps_out       ( x_ps_out       ),
	.y_ps_out       ( y_ps_out       ),
	.trace_a        ( trace_a        ),
	.trace_b        ( trace_b        ),
	.trace_c        ( trace_c        ),

	.texel_valid    ( texel_valid    )
);
	end
	else begin : g_no_texture_pipeline
		assign stall_tex_fetch = 1'b0;
		assign stall_codebook = 1'b0;
		assign pipeline_busy = 1'b0;
		assign tsp_tex_word_addr = 22'd0;
		assign codebook_wait = 1'b0;
		assign cb_cache_hit = 1'b0;
		assign pal_dout = 32'd0;
		assign texel_argb = 32'd0;
		assign texel_valid = 1'b0;
		assign final_argb = interp_base_col;
		assign pix_valid = tsp_pix_wr;
		assign x_ps_out = x_ps[9:0];
		assign y_ps_out = y_ps[9:0];
		assign trace_a = 1'b0;
		assign trace_b = 1'b0;
		assign trace_c = 1'b0;
	end
endgenerate
`endif


// This is probably wrong. It doesn't look right, around the stained-glass windows in DOA2, etc.
//wire [7:0] base_alpha = tex_col_use_alpha ? interp_base_col[31:24] : 8'hff;
//wire [7:0] offs_alpha = tex_col_use_alpha ? interp_offs_col[31:24] : 8'hff;

assign pix_565 = /*(!debug_ena_texel_reads) ? {debug_red[7:3],debug_grn[7:2],debug_blu[7:3]} :*/
											{final_argb[23:19],final_argb[15:10],final_argb[7:3]};


generate
if (ENABLE_TILE_ARGB_BUFFER) begin : g_tile_argb_writeback
	wire tile_wb_we;
	wire [19:0] wb_word_addr;
	 wire [63:0] fourpix_out;
	 wire [3:0] wb_byteena;
	wire [7:0] wb_burstcnt;
	wire [31:0] tile_buf_argb_in = final_argb;
	wire [31:0] argb_buf_out;

	assign fb_we = tile_wb_we;
	assign fb_addr = {3'd0, wb_word_addr};
	assign fb_writedata = fourpix_out;
	assign fb_byteena = {4'd0, wb_byteena};
	assign fb_burstcnt = wb_burstcnt;
	assign fb_writeback_stall = tile_wb_busy;

	tile_argb_buffer tile_argb_buffer_inst (
		.clock( clock ),
		.reset_n( reset_n ),

		.x_ps( {1'b0, x_ps_out} ),
		.y_ps( {1'b0, y_ps_out} ),
		.wb_tilex( tilex[5:0] ),
		.wb_tiley( tiley[5:0] ),

		.wr_pix( pix_valid ),
		.argb_in( tile_buf_argb_in ),

		.argb_buf_out( argb_buf_out ),

		.tile_wb( tile_wb ),
		.wb_done( wb_done ),
		.wb_busy( tile_wb_busy ),

		.wb_word_addr( wb_word_addr ),
		.fourpix_out( fourpix_out ),
		.wb_byteena( wb_byteena ),

		.wb_burstcnt( wb_burstcnt ),

		.vram_wr( tile_wb_we ),
		.vram_wait( fb_wait )
	);
end
else begin : g_direct_fb_writeback
reg direct_fb_pending;
reg [22:0] direct_fb_addr;
reg [63:0] direct_fb_writedata;
reg [7:0] direct_fb_byteena;

wire [19:0] direct_pix_word_addr = ({10'd0, y_ps_out} * 20'd320) + {11'd0, x_ps_out[9:1]};
wire [31:0] direct_pix_pair = {pix_565, pix_565};
wire [63:0] direct_pix_write = {direct_pix_pair, direct_pix_pair};
wire [7:0] direct_pix_be = x_ps_out[0] ? 8'h0c : 8'h03;
wire direct_fb_can_load = !direct_fb_pending || !fb_wait;

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		direct_fb_pending <= 1'b0;
		direct_fb_addr <= 23'd0;
		direct_fb_writedata <= 64'd0;
		direct_fb_byteena <= 8'd0;
	end
	else begin
		if (direct_fb_pending && !fb_wait) begin
			direct_fb_pending <= 1'b0;
		end

		if (pix_valid && direct_fb_can_load) begin
			direct_fb_pending <= 1'b1;
			direct_fb_addr <= {3'd0, direct_pix_word_addr};
			direct_fb_writedata <= direct_pix_write;
			direct_fb_byteena <= direct_pix_be;
		end
	end
end

assign fb_we = direct_fb_pending;
assign fb_addr = direct_fb_addr;
assign fb_writedata = direct_fb_writedata;
assign fb_byteena = direct_fb_byteena;
assign fb_burstcnt = 8'd1;
assign fb_writeback_stall = direct_fb_pending && fb_wait;

// tile_argb_buffer is bypassed for FPGA bring-up. Direct pixel writes above
// drive the fb_* interface, and tile_wb just releases the RA tile handshake.
assign wb_done = tile_wb;
assign tile_wb_busy = direct_fb_pending;
end
endgenerate

endmodule

function automatic [7:0] clamp255;
    input signed [47:0] value;   // signed fixed-point input
    input integer       SHIFT;   // number of fractional bits to drop
    reg   signed [31:0] shifted;
begin
    shifted = value >>>SHIFT;

    if (shifted < 0) clamp255 = 8'd0;
    else if (shifted > 255) clamp255 = 8'd255;
    else clamp255 = shifted[7:0];
end
endfunction

function automatic [7:0] clamp255_pre;
    input signed [15:0] v; // already shifted
begin
    if (v < 0)
        clamp255_pre = 8'd0;
    else if (v > 255)
        clamp255_pre = 8'd255;
    else
        clamp255_pre = v[7:0];
end
endfunction
