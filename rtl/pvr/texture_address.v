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
	
	input read_codebook,
	output codebook_wait,
		
	input wire [9:0] ui,				// From rasterizer/interp...
	input wire [9:0] vi,
		
	input vram_wait,
	input vram_valid,
	output reg [21:0] vram_word_addr,	// 32-bit (params) or 64-bit (textures) WORD address!
	input [63:0] vram_din,				// Full 64-bit data for texture reads.
	
	input [31:0] base_argb,				// Flat-shading colour input. (will also do Gouraud eventually).
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
wire tex_u_flip = tsp_inst[18];
wire tex_v_flip = tsp_inst[17];
wire tex_u_clamp = tsp_inst[16];
wire tex_v_clamp = tsp_inst[15];
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
wire [9:0] ui_masked = ui & ((8<<tex_u_size)-1);
wire [9:0] vi_masked = vi & ((8<<tex_v_size)-1);

wire [19:0] twop_full = {ui[9],vi[9],ui[8],vi[8],ui[7],vi[7],ui[6],vi[6],ui[5],vi[5],ui[4],vi[4],ui[3],vi[3],ui[2],vi[2],ui[1],vi[1],ui[0],vi[0]};
reg [19:0] twop;

wire [19:0] non_twid_addr = (ui_masked + (vi_masked * (8<<tex_u_size)));

reg [3:0] pal4_nib;
/* verilator lint_off UNOPTFLAT */
reg [7:0] pal8_byte;
/* verilator lint_on UNOPTFLAT */
reg [7:0] vq_index;
reg [15:0] pix16;

wire is_pal4 = (pix_fmt==3'd5);
wire is_pal8 = (pix_fmt==3'd6);
wire is_twid = (scan_order==1'b0);
wire is_mipmap = mip_map && scan_order==0;

reg [19:0] twop_or_not;
reg [21:0] texel_word_offs;

/* verilator lint_off UNOPTFLAT */
wire [2:0] pal8_sel = (is_pal4) ? twop_or_not[3:1] :	// PAL4. Drop the LSB bit, which is then used to select a the nibble from the pal8 mux result.
							 (vq_comp) ? twop_or_not[4:2] :	// VQ. Drop two lower bits.
											 twop_or_not[2:0];	// PAL8. Don't drop any bits. Directly select the byte from vram_din.
/* verilator lint_on UNOPTFLAT */

reg [6:0] twop_upper_bits;

always @(*) begin
	twop_upper_bits = (tex_u_size==tex_v_size) || (is_twid && mip_map) ? 7'b0 :	// Square texture. (VQ textures are always square, then tex_v_size is ignored).
											 (tex_u_size > tex_v_size) ? ui_masked[9:3] :	// U is larger than V.
																				  vi_masked[9:3];		// V is larger than U.
	
	case ((tex_u_size > tex_v_size) ? tex_v_size : tex_u_size)
		0: twop = twop_upper_bits[6:0] | twop_full[5:0];	// U or V size 8 
		1: twop = twop_upper_bits[6:1] | twop_full[7:0];	// U or V size 16
		2: twop = twop_upper_bits[6:2] | twop_full[9:0];	// U or V size 32
		3: twop = twop_upper_bits[6:3] | twop_full[11:0];	// U or V size 64
		4: twop = twop_upper_bits[6:4] | twop_full[13:0];	// U or V size 128
		5: twop = twop_upper_bits[6:5] | twop_full[15:0];	// U or V size 256
		6: twop = twop_upper_bits[6]   | twop_full[17:0];	// U or V size 512
		7: twop = twop_full[19:0];									// U or V size 1024
	endcase
	
	//$display("ui: %d  vi: %d  tex_u_size (raw): %d  tex_v_size (raw): %d  twop 0x%08X  twop_full: 0x%08X", ui, vi, tex_u_size, tex_v_size, twop, twop_full);
end


reg [19:0] mipmap_byte_offs_vq;
reg [19:0] mipmap_byte_offs_norm;
//reg [19:0] mipmap_byte_offs_pal;	// The palette mipmap offset table is just mipmap_byte_offs_norm[]>>1, so I ditched the table.

reg [19:0] mipmap_byte_offs;

// Really wide wire here, but the max stride_full value is 34,359,738,368. lol
//
// I'm sure the real PVR doesn't pre-calc stride-full this way, but just uses the "stride" value directly. ElectronAsh.
//
//wire [35:0] stride_full = 16<<stride;	// stride 0==invalid (default?). stride 1=32. stride 2=64. stride 3=96. stride 4=128, and so-on.

always @(*) begin
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

	case (tex_u_size+3)
		0:  mipmap_byte_offs_vq <= 20'h0; 		// 1 texel
		1:  mipmap_byte_offs_vq <= 20'h1; 		// 2 texels
		2:  mipmap_byte_offs_vq <= 20'h2; 		// 4 texels
		3:  mipmap_byte_offs_vq <= 20'h6; 		// 8 texels
		4:  mipmap_byte_offs_vq <= 20'h16; 		// 16 texels
		5:  mipmap_byte_offs_vq <= 20'h56; 		// 32 texels
		6:  mipmap_byte_offs_vq <= 20'h156; 	// 64 texels
		7:  mipmap_byte_offs_vq <= 20'h556; 	// 128 texels
		8:  mipmap_byte_offs_vq <= 20'h1556; 	// 256 texels
		9:  mipmap_byte_offs_vq <= 20'h5556; 	// 512 texels
		10: mipmap_byte_offs_vq <= 20'h15556; 	// 1024 texels
		default: mipmap_byte_offs_vq <= 20'h15556;
	endcase
end

always @(*) begin
	// mipmap table mux (or zero offset, for non-mipmap)...
	mipmap_byte_offs = (!is_mipmap) ? 0 :
						  (vq_comp) ? mipmap_byte_offs_vq :
			 (is_pal4 | is_pal8) ? (mipmap_byte_offs_norm>>1) : // Note: The mipmap byte offset table for Palettes is just mipmap_byte_offs_norm[]>>1.
										  mipmap_byte_offs_norm;
	
	// Twiddled or Non-Twiddled).
	twop_or_not = (vq_comp) ? ((12'd2048 + mipmap_byte_offs)<<2) + twop :
		  (is_pal4 || is_pal8 || is_twid) ? (mipmap_byte_offs>>1) + twop :		// I haven't figured out why this needs the >>1 yet. Oh well.
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
	case (twop_or_not[1:0])
		0: pix16 = codebook_mux[15:00];
		1: pix16 = codebook_mux[31:16];
		2: pix16 = codebook_mux[47:32];
		3: pix16 = codebook_mux[63:48];
	endcase
	
	/*
	pal4_nib = !twop_or_not[0] ? pal8_byte[03:00] : pal8_byte[07:04];
	if (is_pal4) pal_raw = pal_ram[ {pal_selector[5:0], pal4_nib}  ];
	if (is_pal8) pal_raw = pal_ram[ {pal_selector[5:4], pal8_byte} ];
	case (PAL_RAM_CTRL)
		0: pal_final = { {8{pal_raw[15]}},    pal_raw[14:10],pal_raw[14:12], pal_raw[09:05],pal_raw[09:07], pal_raw[04:00],pal_raw[04:02] };	// ARGB 1555
		1: pal_final = {            8'hff,    pal_raw[15:11],pal_raw[15:13], pal_raw[10:05],pal_raw[10:09], pal_raw[04:00],pal_raw[04:02] };	//  RGB 565
		2: pal_final = { {2{pal_raw[15:12]}}, {2{pal_raw[11:08]}},           {2{pal_raw[07:04]}},           {2{pal_raw[03:00]}} };					// ARGB 4444
		3: pal_final = pal_raw;		// ARGB 8888. (the full 32-bit wide Palette entry is used directly).
	endcase
	*/
	
	// Convert all texture pixel formats to ARGB8888.
	// (fill missing lower colour bits using some of the upper colour bits.)
	case (pix_fmt)
		0: texel_argb = { {8{pix16[15]}},    pix16[14:10],pix16[14:12], pix16[09:05],pix16[09:07], pix16[04:00],pix16[04:02] };	// ARGB 1555
		1: texel_argb = {          8'hff,    pix16[15:11],pix16[15:13], pix16[10:05],pix16[10:09], pix16[04:00],pix16[04:02] };	//  RGB 565
		2: texel_argb = { {2{pix16[15:12]}}, {2{pix16[11:08]}},         {2{pix16[07:04]}},         {2{pix16[03:00]}} };			// ARGB 4444
		3: texel_argb = pix16;		// TODO. YUV422 (32-bit Y8 U8 Y8 V8).
		4: texel_argb = pix16;		// TODO. Bump Map (16-bit S8 R8).
		//5: texel_argb = pal_final;	// PAL4 or PAL8 can be ARGB1555, RGB565, ARGB4444, or even ARGB8888.
		//6: texel_argb = pal_final;	// Palette format read from PAL_RAM_CTRL[1:0].
		7: texel_argb = { {8{pix16[15]}},    pix16[14:10],pix16[14:12], pix16[09:05],pix16[09:07], pix16[04:00],pix16[04:02] };	// Reserved (considered ARGB 1555).
		default: texel_argb = 32'hff0000aa;
	endcase

	// Colour Blender...
	case (shade_inst)
		0: begin				// Decal.
			blend_argb[31:24] = texel_argb[31:24];	// Blend Alpha <- Texel Alpha.  Texel_RGB + Offset_RGB.
			blend_argb[23:16] = texel_argb[23:16];	// Red.
			blend_argb[15:08] = texel_argb[15:08];	// Green.
			blend_argb[07:00] = texel_argb[07:00];	// Blue.
		end
		
		1: begin				// Modulate.
			blend_argb[31:24] = texel_argb[31:24];	// Blend Alpha <- Texel Alpha.  (Texel_RGB * Base_RGB) + Offset_RGB.
			blend_argb[23:16] = (texel_argb[23:16] * base_argb[23:16]) /256;	// Red.
			blend_argb[15:08] = (texel_argb[15:08] * base_argb[15:08]) /256;	// Green.
			blend_argb[07:00] = (texel_argb[07:00] * base_argb[07:00]) /256;	// Blue.
		end
		
		2: begin				// Decal Alpha.
			blend_argb[31:24] = base_argb[31:24];	// Blend Alpha <- Base Alpha.  (Texel_RGB * Texel_Alpha) + (Base_RGB * (255-Texel_Alpha)) + Offset_RGB.
			blend_argb[23:16] = ((texel_argb[23:16] * texel_argb[31:24]) /256) + ((base_argb[23:16] * (255-texel_argb[31:24])) /256);	// Red.
			blend_argb[15:08] = ((texel_argb[15:08] * texel_argb[31:24]) /256) + ((base_argb[15:08] * (255-texel_argb[31:24])) /256);	// Green.
			blend_argb[07:00] = ((texel_argb[07:00] * texel_argb[31:24]) /256) + ((base_argb[07:00] * (255-texel_argb[31:24])) /256);	// Blue.
		end
		
		3: begin				// Modulate Alpha.
			blend_argb[31:24] = (texel_argb[31:24] * base_argb[31:24]) /256;	// (Texel_ARGB * Base_ARGB) + Offset_RGB.
			blend_argb[23:16] = (texel_argb[23:16] * base_argb[23:16]) /256;	// Red.
			blend_argb[15:08] = (texel_argb[15:08] * base_argb[15:08]) /256;	// Green.
			blend_argb[07:00] = (texel_argb[07:00] * base_argb[07:00]) /256;	// Blue.
		end
	endcase
end


reg [31:0] blend_argb;

wire [9:0] blend_plus_offs_r = blend_argb[23:16] + offs_argb[23:16];
wire [9:0] blend_plus_offs_g = blend_argb[15:08] + offs_argb[15:08];
wire [9:0] blend_plus_offs_b = blend_argb[07:00] + offs_argb[07:00];

wire [7:0] offs_r_clamped = (blend_plus_offs_r>255) ? 8'd255 : blend_plus_offs_r;
wire [7:0] offs_g_clamped = (blend_plus_offs_g>255) ? 8'd255 : blend_plus_offs_g;
wire [7:0] offs_b_clamped = (blend_plus_offs_b>255) ? 8'd255 : blend_plus_offs_b;

wire [31:0] blend_offs_argb = {blend_argb[31:24], offs_r_clamped, offs_g_clamped, offs_b_clamped};


assign final_argb = (texture) ? blend_offs_argb : base_argb;
//assign final_argb = (texture) ? texel_argb : base_argb;	// TESTING. Bypass Blender for now.


wire [63:0] codebook_mux = (vq_comp) ? code_book[pal8_byte] : vram_din;


reg [31:0] pal_raw;
reg [31:0] pal_final;

// Palette RAM. 1024 32-bit Words.
// PVR Addr 0x1000-0x1FFC.
reg [31:0] pal_ram [0:1023];

//assign pal_dout = pal_ram[ pal_addr[11:2] ];

// VQ Code Book. 256 64-bit Words.
reg [63:0] code_book [0:255];
reg [8:0] cb_word_index;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	cb_word_index <= 9'd256;
end
else begin
	// Handle Palette RAM writes.
	if (pal_addr[15:12]==4'b0001 && pal_wr) pal_ram[ pal_addr[11:2] ] <= pal_din;

	// Handle VQ Code Book reading.
	if (read_codebook) begin
		cb_word_index <= 9'd0;
	end
	else if (codebook_wait) begin
		if (vram_valid) begin
			code_book[ cb_word_index ] <= vram_din;
			cb_word_index <= cb_word_index + 9'd1;
		end
	end
end

assign codebook_wait = !cb_word_index[8];



endmodule
