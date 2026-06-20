`timescale 1ns / 1ps
`default_nettype none

module texture_address (
	input clock,
	input reset_n,
	
	input [31:0] isp_inst,
	input [31:0] tsp_inst,
	input [31:0] tcw_word,
	
	input [1:0] PAL_RAM_CTRL,	// From PAL_RAM_CTRL[1:0].
	input [31:0] TEXT_CONTROL,	// From TEXT_CONTROL reg.
	
	input [15:0] pal_addr,
	input [31:0] pal_din,
	input pal_rd,
	input pal_wr,
	output [31:0] pal_dout,
	
	input cb_cache_clear,
	input [11:0] prim_tag,
	output cb_cache_hit,
	
	input read_codebook,
	output reg codebook_wait,
		
	input wire [9:0] ui,				// From rasterizer/interp...
	input wire [9:0] vi,
		
	input vram_wait,
	input tex_vram_valid,
	output reg [20:0] vram_word_addr,	// 64-bit WORD address!
	input [63:0] vram_din,				// Full 64-bit data for texture reads.
	
	input [31:0] base_argb,				// Flat-shading (or Gouraud) colour input.
	input [31:0] offs_argb,				// Offset colour input.
	
	output reg [31:0] texel_argb,		// Texel ARGB 8888 output.
	output wire [31:0] final_argb		// Final blended ARGB 8888 output.
);

// ISP Instruction Word.
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
// (those prim types use the same culling_mode bits as above.)
wire [2:0] volume_inst = isp_inst[31:29];


// TSP Instruction Word...
wire [2:0] tex_src_alpha = tsp_inst[31:29];
wire [2:0] tex_dst_alpha = tsp_inst[28:26];
wire tex_src_select = tsp_inst[25];
wire tex_dst_select = tsp_inst[24];
wire [1:0] tex_fog_control = tsp_inst[23:22];
wire tex_col_clamp = tsp_inst[21];
wire tex_col_use_alpha = tsp_inst[20];
wire tex_ignore_alpha = tsp_inst[19];
wire tex_u_flip = tsp_inst[18];
wire tex_v_flip = tsp_inst[17];
wire tex_u_clamp = tsp_inst[16];
wire tex_v_clamp = tsp_inst[15];
wire [1:0] tex_filter_mode = tsp_inst[14:13];
wire tex_super_samp = tsp_inst[12];
wire [3:0] tex_mipmap_d_adj = tsp_inst[11:8];
wire [1:0] shade_inst = tsp_inst[7:6];
wire [2:0] tex_u_size = tsp_inst[5:3];
wire [2:0] tex_v_size = tsp_inst[2:0];


// Texture Control Word...
wire mip_map = tcw_word[31];
wire vq_comp = tcw_word[30];
wire [2:0] pix_fmt = tcw_word[29:27];
wire scan_order = tcw_word[26];
wire stride_flag = tcw_word[25];
wire [5:0] pal_selector = tcw_word[26:21];		// Used for 4BPP or 8BPP palette textures.
wire [20:0] tex_word_addr = tcw_word[20:0];		// 64-bit WORD address! (but only shift <<2 when accessing 32-bit "halves" of VRAM).


// TEXT_CONTROL PVR reg. (not to be confused with TCW above!).
wire code_book_endian = TEXT_CONTROL[17];
wire index_endian     = TEXT_CONTROL[16];
wire [5:0] bank_bit   = TEXT_CONTROL[12:8];
wire [4:0] stride     = TEXT_CONTROL[4:0];

reg [9:0] size_mask_u;
always @(*) begin
  case (tex_u_size)
    0: size_mask_u = 10'h007;
    1: size_mask_u = 10'h00F;
    2: size_mask_u = 10'h01F;
    3: size_mask_u = 10'h03F;
    4: size_mask_u = 10'h07F;
    5: size_mask_u = 10'h0FF;
    6: size_mask_u = 10'h1FF;
    7: size_mask_u = 10'h3FF;
  endcase
end

reg [9:0] size_mask_v;
always @(*) begin
  case (tex_v_size)
    0: size_mask_v = 10'h007;
    1: size_mask_v = 10'h00F;
    2: size_mask_v = 10'h01F;
    3: size_mask_v = 10'h03F;
    4: size_mask_v = 10'h07F;
    5: size_mask_v = 10'h0FF;
    6: size_mask_v = 10'h1FF;
    7: size_mask_v = 10'h3FF;
  endcase
end

// tex_u_size and tex_v_size (raw value vs actual)...
// 0 = 8
// 1 = 16
// 2 = 32
// 3 = 64
// 4 = 128
// 5 = 256
// 6 = 512
// 7 = 1024
// Highest (masked) value is 1023?
//wire [9:0] ui_masked = ui & ((8<<tex_u_size)-1);
//wire [9:0] vi_masked = vi & ((8<<tex_v_size)-1);
wire [9:0] ui_masked = ui & size_mask_u;	// LUTs are likely better for timing than Barrel Shifter. ElectronAsh.
wire [9:0] vi_masked = vi & size_mask_v;

wire [19:0] twop_full = {ui[9],vi[9],ui[8],vi[8],ui[7],vi[7],ui[6],vi[6],ui[5],vi[5],ui[4],vi[4],ui[3],vi[3],ui[2],vi[2],ui[1],vi[1],ui[0],vi[0]};
reg [19:0] twop;

// Really wide wire here, but the max stride_full value is 34,359,738,368. lol
// I'm sure the real PVR doesn't pre-calc stride-full this way, but just uses the "stride" value directly. ElectronAsh.
//
//wire [35:0] stride_full = 16<<stride;	// stride 0==invalid (default?). stride 1=32. stride 2=64. stride 3=96. stride 4=128, and so-on.

wire [19:0] non_twid_addr = (ui_masked + (vi_masked * (8<<tex_u_size)));
//wire [19:0] non_twid_addr = (ui_masked + (vi_masked * (stride_flag ? stride_full : (8<<tex_u_size)) ));

reg [3:0] pal4_nib;
/* verilator lint_off UNOPTFLAT */
reg [7:0] pal8_byte;
reg [15:0] pix16;
/* verilator lint_on UNOPTFLAT */
reg [7:0] vq_index;

wire is_pal4 = (pix_fmt==3'd5);
wire is_pal8 = (pix_fmt==3'd6);
wire is_twid = (scan_order==1'b0);
wire is_mipmap = mip_map && scan_order==0;

reg [19:0] twop_or_not;
reg [19:0] texel_word_offs;

wire [2:0] pal8_sel = (is_pal4) ? twop_or_not[3:1] :	// PAL4. Drop the LSB bit, which is then used to select a the nibble from the pal8 mux result.
					  (vq_comp) ? twop_or_not[4:2] :	// VQ. Drop two lower bits.
								  twop_or_not[2:0];		// PAL8. Don't drop any bits. Directly select the byte from vram_din.

// which_uv selects the smaller dimension to use for the case statement.
// The smaller dimension selects how many (interleaved) bits of twop to use.
wire [9:0] which_uv = (tex_u_size > tex_v_size) ? tex_v_size : tex_u_size;

// upper_bits provides the linear UI or VI addressing for the excess bits (larger texture dimension).
// (Or, upper_bits is zeroed, for square textures).
wire [9:0] upper_bits = (tex_u_size == tex_v_size || (is_twid && mip_map)) ? 10'd0 :	// Square texture. (VQ is always Square).
                        (tex_u_size > tex_v_size) ? ui_masked :							// U size is greater than V, use UI.
													vi_masked;							// Else, V size must be greater than U, use VI.

always @(*) begin
	case (which_uv)
		0: twop = {7'b0, upper_bits[9:3] ,twop_full[5:0]};	// Smaller dimension = 8
		1: twop = {6'b0, upper_bits[9:4] ,twop_full[7:0]};	// Smaller dimension = 16
		2: twop = {5'b0, upper_bits[9:5] ,twop_full[9:0]};	// Smaller dimension = 32
		3: twop = {4'b0, upper_bits[9:6] ,twop_full[11:0]};	// Smaller dimension = 64
		4: twop = {3'b0, upper_bits[9:7] ,twop_full[13:0]};	// Smaller dimension = 128
		5: twop = {2'b0, upper_bits[9:8] ,twop_full[15:0]};	// Smaller dimension = 256
		6: twop = {1'b0, upper_bits[9]   ,twop_full[17:0]};	// Smaller dimension = 512
		7: twop = twop_full[19:0];							// 1024
		default: twop = twop_full[19:0];					// Default = Use twop_full?
	endcase
end

reg [19:0] mipmap_byte_offs_norm;
//reg [19:0] mipmap_byte_offs_vq;	// The VQ mipmap offset table is just mipmap_byte_offs_norm[]>>3, so I ditched the VQ table.
//reg [19:0] mipmap_byte_offs_pal;	// The palette mipmap offset table is just mipmap_byte_offs_norm[]>>1, so I ditched the PALette table.

reg [19:0] mipmap_byte_offs;

always @(posedge clock) begin
	// NOTE: Need to add 3 to tex_u_size in all of these LUTs, because the mipmap table starts at a 1x1 texture size, but tex_u_size==0 is the 8x8 texture size.
	case (tex_u_size+3)
		0:  mipmap_byte_offs_norm <= 20'h6; 	// 1 texel
		1:  mipmap_byte_offs_norm <= 20'h8; 	// 2 texels
		2:  mipmap_byte_offs_norm <= 20'h10; 	// 4 texels
		3:  mipmap_byte_offs_norm <= 20'h30; 	// 8 texels
		4:  mipmap_byte_offs_norm <= 20'hb0; 	// 16 texels
		5:  mipmap_byte_offs_norm <= 20'h2b0; 	// 32 texels
		6:  mipmap_byte_offs_norm <= 20'hab0; 	// 64 texels
		7:  mipmap_byte_offs_norm <= 20'h2ab0; // 128 texels
		8:  mipmap_byte_offs_norm <= 20'haab0; // 256 texels
		9:  mipmap_byte_offs_norm <= 20'h2aab0;// 512 texels
		10: mipmap_byte_offs_norm <= 20'haaab0;// 1024 texels
		default: mipmap_byte_offs_norm <= 20'haaab0;
	endcase
	
	//vram_word_addr <= tex_word_addr + ((read_codebook || codebook_wait) ? cb_word_index : texel_word_offs);
end

always @(*) begin
	// mipmap table mux (or zero offset, for non-mipmap)...
	mipmap_byte_offs = (!is_mipmap) ? 0 :
						  (vq_comp) ? mipmap_byte_offs_norm>>3 :	// Note: The mipmap byte offset table for VQ is just mipmap_byte_offs_norm[]>>3.
				(is_pal4 | is_pal8) ? (mipmap_byte_offs_norm>>1) :	// Note: The mipmap byte offset table for Palettes is just mipmap_byte_offs_norm[]>>1.
									  mipmap_byte_offs_norm;
	
	// Twiddled or Non-Twiddled).
	twop_or_not = (vq_comp) ? ((12'd2048 + mipmap_byte_offs)<<2) + twop :
		 (is_pal4 || is_pal8 || is_twid) ? (mipmap_byte_offs>>1) + twop :
										mipmap_byte_offs + non_twid_addr;
													 
	// Shift twop_or_not, based on the number of nibbles, bytes, or words to read from each 64-bit vram_din word.
	texel_word_offs = (vq_comp) ? (twop_or_not>>5) : // VQ = 32 TEXELS per 64-bit VRAM word. (1 BYTE per FOUR Texels).
					  (is_pal4) ? (twop_or_not>>4) : // PAL4   = 16 TEXELS per 64-bit word. (4BPP).
					  (is_pal8) ? (twop_or_not>>3) : // PAL8   = 8  TEXELS per 64-bit word. (8BPP).
								  (twop_or_not>>2);	 // Uncomp = 4  TEXELS per 64-bit word (16BPP).
	
	// Generate the 64-bit VRAM WORD address using either the Code Book READ index, or texel_word_offs;
	vram_word_addr = tex_word_addr + ((read_codebook || codebook_wait) ? cb_word_index : texel_word_offs);
	
	// VQ has FOUR TEXELS per Index Byte.
	// 32 TEXELS per 64-bit VRAM word.
	case (pal8_sel)							// pal8_sel is a shift of twop_or_not, depending on whether PAL4 or vq_comp are set.
		0:  pal8_byte = vram_din[07:00];	// PAL4 will drop the LSB bit of twop_or_not, then twop_or_not[0] is used to select the nibble from the pal8_byte result.
		1:  pal8_byte = vram_din[15:08];	// When PAL4 and vq_comp are both low, that would be a normal PAL8 vram_din byte select.
		2:  pal8_byte = vram_din[23:16];
		3:  pal8_byte = vram_din[31:24];
		4:  pal8_byte = vram_din[39:32];
		5:  pal8_byte = vram_din[47:40];
		6:  pal8_byte = vram_din[55:48];
		7:  pal8_byte = vram_din[63:56];
	endcase
	
	// Read 16BPP from either the Code Book (for VQ), or direct from VRAM.
	case (is_twid ? twop[1:0] : non_twid_addr[1:0])
		0: pix16 = cb_or_direct[15:00];
		1: pix16 = cb_or_direct[31:16];
		2: pix16 = cb_or_direct[47:32];
		3: pix16 = cb_or_direct[63:48];
	endcase
	
	// For non-palette textures, pix_fmt (tcw_word[29:27]) determines the colour format.
	// For PAL4 or PAL8 textures, the PAL_RAM_CTRL[1:0] value determines the colour format.
	// (pix16_mux selects between pal_raw and pix16). Shouldn't need case 5 nor case 6 here!
	case ( (pix_fmt==4 || pix_fmt==5) ? PAL_RAM_CTRL[1:0] : pix_fmt)
		0: texel_argb = { {8{pix16_mux[15]}},    pix16_mux[14:10],pix16_mux[14:12], pix16_mux[09:05],pix16_mux[09:07], pix16_mux[04:00],pix16_mux[04:02] };	// ARGB 1555
		1: texel_argb = {              8'hff,    pix16_mux[15:11],pix16_mux[15:13], pix16_mux[10:05],pix16_mux[10:09], pix16_mux[04:00],pix16_mux[04:02] };	//  RGB 565
		2: texel_argb = { {2{pix16_mux[15:12]}}, {2{pix16_mux[11:08]}},             {2{pix16_mux[07:04]}},             {2{pix16_mux[03:00]}} };				// ARGB 4444
		3: texel_argb = pix16_mux;			// TODO. YUV422 (32-bit Y8 U8 Y8 V8).
		4: texel_argb = pix16_mux;			// TODO. Bump Map (16-bit S8 R8).
		//5: texel_argb = pal_final;		// PAL4 or PAL8 can be ARGB1555, RGB565, ARGB4444, or even ARGB8888.
		//6: texel_argb = pal_final;		// Palette format read from PAL_RAM_CTRL[1:0].
		7: texel_argb = { {8{pix16[15]}},    pix16[14:10],pix16[14:12], pix16[09:05],pix16[09:07], pix16[04:00],pix16[04:02] };	// Reserved (considered ARGB 1555).
		default: texel_argb = pix16_mux;	// Just to show anything at all, if some of the above cases are disabled. ElectronAsh.
	endcase
	
	case (shade_inst)
		0: begin				// Decal.
			blend_a = texel_a;	// Blend Alpha <- Texel Alpha.  Texel_RGB + Offset_RGB.
			blend_r = texel_r;	// Red.
			blend_g = texel_g;	// Green.
			blend_b = texel_b;	// Blue.
		end
		
		1: begin								// Modulate.
			blend_a = texel_a;					// Blend Alpha <- Texel Alpha.  (Base_RGB * Texel_RGB) + Offset_RGB.
			blend_r = r_tex_mult_base_div_256;	// Red.
			blend_g = g_tex_mult_base_div_256;	// Green.
			blend_b = b_tex_mult_base_div_256;	// Blue.
		end
		
		2: begin 				// Decal Alpha
			blend_a = base_a;	// Blend Alpha <- Base Alpha.  (Texel_RGB * Texel_Alpha) + (Base_RGB * (255-Texel_Alpha)) + Offset_RGB.
			blend_r = ((texel_r * texel_a) /256) + ((base_r * inv_alpha) /256);
			blend_g = ((texel_g * texel_a) /256) + ((base_g * inv_alpha) /256);
			blend_b = ((texel_b * texel_a) /256) + ((base_b * inv_alpha) /256);
		end
		
		3: begin								// Modulate Alpha.
			blend_a = a_tex_mult_base_div_256;	// (Base_ARGB * Texel_ARGB) + Offset_RGB.
			blend_r = r_tex_mult_base_div_256;	// Red.
			blend_g = g_tex_mult_base_div_256;	// Green.
			blend_b = b_tex_mult_base_div_256;	// Blue.
		end
	endcase
end

wire [7:0] base_a = base_argb[31:24];
wire [7:0] base_r = base_argb[23:16];
wire [7:0] base_g = base_argb[15:08];
wire [7:0] base_b = base_argb[07:00];

wire [7:0] offs_a = offs_argb[31:24];
wire [7:0] offs_r = offs_argb[23:16];
wire [7:0] offs_g = offs_argb[15:08];
wire [7:0] offs_b = offs_argb[07:00];

wire [7:0] texel_a = texel_argb[31:24];
wire [7:0] texel_r = texel_argb[23:16];
wire [7:0] texel_g = texel_argb[15:08];
wire [7:0] texel_b = texel_argb[07:00];

wire [15:0] a_tex_mult_base_div_256 = (base_a * texel_a) /256;
wire [15:0] r_tex_mult_base_div_256 = (base_r * texel_r) /256;
wire [15:0] g_tex_mult_base_div_256 = (base_g * texel_g) /256;
wire [15:0] b_tex_mult_base_div_256 = (base_b * texel_b) /256;

wire [7:0] inv_alpha = 255 - texel_a;  // (255 - alpha)


reg [7:0] blend_a;
reg [7:0] blend_r;
reg [7:0] blend_g;
reg [7:0] blend_b;

// Add Offset Colour, then Clamp.
wire [8:0] blend_plus_offs_a = blend_a + offs_a;
wire [8:0] blend_plus_offs_r = blend_r + offs_r;
wire [8:0] blend_plus_offs_g = blend_g + offs_g;
wire [8:0] blend_plus_offs_b = blend_b + offs_b;

wire [7:0] offs_a_clamp = (blend_plus_offs_a[8]) ? 8'd255 : blend_plus_offs_a[7:0];
wire [7:0] offs_r_clamp = (blend_plus_offs_r[8]) ? 8'd255 : blend_plus_offs_r[7:0];
wire [7:0] offs_g_clamp = (blend_plus_offs_g[8]) ? 8'd255 : blend_plus_offs_g[7:0];
wire [7:0] offs_b_clamp = (blend_plus_offs_b[8]) ? 8'd255 : blend_plus_offs_b[7:0];

wire [31:0] blend_offs_argb = (offset) ? {offs_a_clamp, offs_r_clamp, offs_g_clamp, offs_b_clamp} : {blend_a, blend_r, blend_g, blend_b};

assign final_argb = (texture) ? blend_offs_argb : base_argb;


// Read 16BPP from either the Code Book for VQ, or direct from VRAM.
wire [63:0] cb_or_direct = (vq_comp) ? cb_cache_dout : vram_din;

wire [9:0] my_pal_addr = (pal_wr) ? pal_addr :																// Writes, from SH4/sim.
						(is_pal4) ? {pal_selector[5:0], (!twop[0] ? pal8_byte[3:0] : pal8_byte[7:4]) } :	// PAL4
									{pal_selector[5:4], pal8_byte};											// PAL8


// Palette RAM. 1024 32-bit Words.
// PVR Addr 0x1000-0x1FFC.
reg [31:0] pal_ram [0:1023];
always @(posedge clock) begin
	if (pal_wr) pal_ram[ my_pal_addr ] <= pal_din;
end

wire [31:0] pal_raw = pal_ram[ my_pal_addr ];

// Select from Palette (PAL4 or PAL8), or the raw 16BPP pixel.
wire [15:0] pix16_mux = (pix_fmt==4 || pix_fmt==5) ? pal_raw : pix16;

/*
// VQ Code Book. 256 64-bit Words.
reg [63:0] code_book [0:255];
reg [8:0] cb_word_index;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	cb_word_index <= 9'd256;
end
else begin
	// Handle VQ Code Book reading.
	if (read_codebook) begin
		cb_word_index <= 9'd0;
	end
	else if (codebook_wait) begin
		if (tex_vram_valid) begin
			code_book[ cb_word_index ] <= vram_din;
			cb_word_index <= cb_word_index + 9'd1;
		end
	end
end

assign codebook_wait = !cb_word_index[8];

wire [63:0] cb_cache_dout = code_book[ pal8_byte ];
*/

wire [7:0] cb_word_index;
wire [63:0] cb_cache_dout;

codebook_cache  codebook_cache_inst (
    .clock( clock ),
    .reset_n( reset_n ),
	
	.cache_clear( cb_cache_clear ),		// input  cb_cache_clear
	
    .tag_in( prim_tag ),				// input [11:0]  12-bit unique triangle Tag.
										// (Actually a PRIMITIVE tag. Often a collection of triangles, which share the same TCW/Codebook).
	.codebook_base( tex_word_addr ),
										
    .read_index( pal8_byte ),			// input [7:0]  8-bit offset address to read from the CB
	
    .cache_read( read_codebook ),		// Read request signal
	.codebook_wait( codebook_wait ),	// output  codebook_wait / cache_wait
	
	.ram_read_offset( cb_word_index ),	// output [7:0]  ram_read_offset (to read from VRAM).
	.tex_vram_valid( tex_vram_valid ),	// input  tex_vram_valid
	.cache_din( vram_din ),				// input [63:0]  cache_din
	
	.cache_hit( cb_cache_hit ),			// Indicates if the requested tag is in cache
    .cache_dout( cb_cache_dout ) 		// output [63:0]  cache_dout.  64-bit palette entry data if cache hit
);


endmodule
