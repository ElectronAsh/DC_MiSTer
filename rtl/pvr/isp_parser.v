
`timescale 1ns / 1ps
`default_nettype none

parameter FRAC_BITS   = 8'd12;
parameter Z_FRAC_BITS = 8'd12;	// Z_FRAC_BITS needs to be >= FRAC_BITS.

parameter FRAC_DIFF = (Z_FRAC_BITS-FRAC_BITS);


module isp_parser (
	input clock,
	input reset_n,
	
	input [31:0] opb_word,
	
	input [2:0] type_cnt,
	
	input ra_cont_zclear_n,
	input [23:0] poly_addr,
	input render_poly,
	input render_to_tile,
	
	input vram_wait,
	input vram_valid,
	output reg isp_vram_rd,
	output reg isp_vram_wr,
	output reg [23:0] isp_vram_addr_out,
	input [31:0] isp_vram_din,
	output reg [31:0] isp_vram_dout,
	
	input [63:0] tex_vram_din,
	
	output reg isp_entry_valid,
	
	output reg [22:0] fb_addr,
	output reg [63:0] fb_writedata,
	output reg [7:0] fb_byteena,
	output reg fb_we,

	input ra_new_tile_start,
	input ra_entry_valid,
	input tile_prims_done,
	
	output reg poly_drawn,
	output reg tile_accum_done,

	input reg [5:0] tilex,
	input reg [5:0] tiley,
	
	input [31:0] FB_R_SOF1,
	input [31:0] FB_R_SOF2,
	
	input [31:0] TEXT_CONTROL,	// From TEXT_CONTROL reg.
	input  [1:0] PAL_RAM_CTRL,	// From PAL_RAM_CTRL reg, bits [1:0].
	
	input [9:0] pal_addr,
	input [31:0] pal_din,
	input pal_wr,
	
	input pal_rd,
	output [31:0] pal_dout,
	
	input clear_fb,
	output reg clear_fb_pend,
	
	output reg [7:0] isp_state
);

reg [23:0] isp_vram_addr;

assign isp_vram_addr_out = ((isp_state>=8'd49 && isp_state<=8'd53) || isp_state==5 || codebook_wait) ? vram_word_addr[21:0]<<2 :	// Output texture WORD address as a BYTE address.
																																		 isp_vram_addr;				// Output ISP Parser BYTE address.

// OL Word bit decodes...
wire [5:0] strip_mask = {opb_word[25], opb_word[26], opb_word[27], opb_word[28], opb_word[29], opb_word[30]};	// For Triangle Strips only.
wire [3:0] num_prims = opb_word[28:25];	// For Triangle Array or Quad Array only.
wire shadow = opb_word[24];				// For all three poly types.
wire [2:0] skip = opb_word[23:21];		// For all three poly types.
wire eol = opb_word[28];


// ISP/TSP Instruction Word. Bit decode, for Opaque or Translucent prims...
(*noprune*)reg [31:0] isp_inst;
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
(*noprune*)reg [31:0] tsp_inst;
wire tex_u_flip = tsp_inst[18];
wire tex_v_flip = tsp_inst[17];
wire tex_u_clamp = tsp_inst[16];
wire tex_v_clamp = tsp_inst[15];
wire [2:0] tex_u_size = tsp_inst[5:3];
wire [2:0] tex_v_size = tsp_inst[2:0];


// Texture Control Word...
(*noprune*)reg [31:0] tcw_word;
wire mip_map = tcw_word[31];
wire vq_comp = tcw_word[30];
wire [2:0] pix_fmt = tcw_word[29:27];
wire scan_order = tcw_word[26];
wire stride_flag = tcw_word[25];
wire [20:0] tex_word_addr = tcw_word[20:0];		// 64-bit WORD address! (but only shift <<2 when accessing 32-bit "halves" of VRAM).

reg [20:0] tex_base_word_addr_old;

reg [20:0] prev_tex_word_addr;

reg [31:0] tsp2_inst;
reg [31:0] tex2_cont;

// NOTE: Bump Map params are stored in the Offset Color regs, when Bumps are enabled.
//
// XY verts are declared as signed here, but it doesn't seem to help with rendering, when neg_xy culling is disabled.
//
(*noprune*)reg signed [31:0] vert_a_x;
(*noprune*)reg signed [31:0] vert_a_y;
(*noprune*)reg [31:0] vert_a_z;
(*noprune*)reg [31:0] vert_a_u0;
(*noprune*)reg [31:0] vert_a_v0;
(*noprune*)reg [31:0] vert_a_u1;
(*noprune*)reg [31:0] vert_a_v1;
(*noprune*)reg [31:0] vert_a_base_col_0;
(*noprune*)reg [31:0] vert_a_base_col_1;
(*noprune*)reg [31:0] vert_a_off_col;

(*noprune*)reg signed [31:0] vert_b_x;
(*noprune*)reg signed [31:0] vert_b_y;
(*noprune*)reg [31:0] vert_b_z;
(*noprune*)reg [31:0] vert_b_u0;
(*noprune*)reg [31:0] vert_b_v0;
(*noprune*)reg [31:0] vert_b_u1;
(*noprune*)reg [31:0] vert_b_v1;
(*noprune*)reg [31:0] vert_b_base_col_0;
(*noprune*)reg [31:0] vert_b_base_col_1;
(*noprune*)reg [31:0] vert_b_off_col;

(*noprune*)reg signed [31:0] vert_c_x;
(*noprune*)reg signed [31:0] vert_c_y;
(*noprune*)reg [31:0] vert_c_z;
(*noprune*)reg [31:0] vert_c_u0;
(*noprune*)reg [31:0] vert_c_v0;
(*noprune*)reg [31:0] vert_c_u1;
(*noprune*)reg [31:0] vert_c_v1;
(*noprune*)reg [31:0] vert_c_base_col_0;
(*noprune*)reg [31:0] vert_c_base_col_1;
(*noprune*)reg [31:0] vert_c_off_col;

(*noprune*)reg signed [31:0] vert_d_x;
(*noprune*)reg signed [31:0] vert_d_y;
(*noprune*)reg [31:0] vert_d_z;
(*noprune*)reg [31:0] vert_d_u0;
(*noprune*)reg [31:0] vert_d_v0;
(*noprune*)reg [31:0] vert_d_u1;
(*noprune*)reg [31:0] vert_d_v1;
(*noprune*)reg [31:0] vert_d_base_col_0;
(*noprune*)reg [31:0] vert_d_base_col_1;
(*noprune*)reg [31:0] vert_d_off_col;

wire two_volume = 1'b0;	// TODO.

(*noprune*)reg signed [31:0] vert_temp_x;
(*noprune*)reg signed [31:0] vert_temp_y;
(*noprune*)reg [31:0] vert_temp_z;
(*noprune*)reg [31:0] vert_temp_u0;
(*noprune*)reg [31:0] vert_temp_v0;
(*noprune*)reg [31:0] vert_temp_base_col_0;
(*noprune*)reg [31:0] vert_temp_base_col_1;
(*noprune*)reg [31:0] vert_temp_off_col;


// Object List read state machine...
//(*noprune*)reg [7:0] isp_state;
(*noprune*)reg [2:0] strip_cnt;
(*noprune*)reg [3:0] array_cnt;

wire is_tri_strip  = !opb_word[31];
wire is_tri_array  = opb_word[31:29]==3'b100;
wire is_quad_array = opb_word[31:29]==3'b101;

reg quad_done;

reg clear_z;

reg [23:0] isp_vram_addr_last;

reg no_tex_read;
(*noprune*)reg isp_vram_rd_pend;

reg [11:0] prim_tag;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	isp_state <= 8'd0;
	isp_vram_rd <= 1'b0;
	isp_vram_wr <= 1'b0;
	fb_we <= 1'b0;
	isp_entry_valid <= 1'b0;
	quad_done <= 1'b1;
	poly_drawn <= 1'b0;
	read_codebook <= 1'b0;
	tex_base_word_addr_old <= 21'h1FFFFF;	// Arbitrary address to start with.
	cb_cache_clear <= 1'b0;
	clear_fb_pend <= 1'b0;
	clear_z <= 1'b0;
	vram_word_addr_old <= 22'h3fffff;
	no_tex_read <= 1'b0;
	isp_vram_rd_pend <= 1'b0;
	prim_tag <= 12'd0;
	pcache_load <= 1'b0;
	tile_accum_done <= 1'b0;
end
else begin
	//fb_we <= 1'b0;
	
	cb_cache_clear <= 1'b0;
	
	isp_entry_valid <= 1'b0;
	poly_drawn <= 1'b0;
	
	clear_z <= 1'b0;
	
	read_codebook <= 1'b0;
	
	pcache_load <= 1'b0;
	tile_accum_done <= 1'b0;

	if (isp_vram_rd & !vram_wait) isp_vram_rd <= 1'b0;
	if (isp_vram_wr & !vram_wait) isp_vram_wr <= 1'b0;
	
	if (fb_we && !vram_wait) fb_we <= 1'b0;
	
	no_tex_read <= 1'b0;
	
	if (ra_new_tile_start) begin	// New tile started!
		//cb_cache_clear <= 1'b1;	// Using texture address bits [16:8] from the TCW as the "Tag" now. No need to clear before each Tile!
		clear_z <= 1'b1;
		prim_tag <= 12'd0;
	end
	
	case (isp_state)
		0: begin
			if (render_poly) begin
				strip_cnt <= 3'd0;
				array_cnt <= 4'd0;
				vert_d_x <= 32'd0;
				vert_d_y <= 32'd0;
				vert_d_z <= 32'd0;
				vert_d_u0 <= 32'd0;
				vert_d_v0 <= 32'd0;
				vram_word_addr_old <= 22'h3fffff;
				isp_vram_addr <= poly_addr;
				isp_state <= isp_state + 8'd1;
			end
			//else if (tile_prims_done) begin	// Render after ALL prims written to Tag buffer.
			else if (render_to_tile) begin		// Render after each prim TYPE is written to Tag buffer.
				tex_base_word_addr_old <= 21'h1FFFFF;	// Arbitrary address to start with.
				prim_tag_out_old <= 12'd4095;			// Set an arbitrary High value.
																// This fixes the issues from when the first (visible) prim's Tag coincided
																// with the last value left in prim_tag_out_old. Which meant it wasn't reading the codebook for that prim. ElectronAsh.
				x_ps <= tilex_start;
				y_ps <= tiley_start;
				pcache_load <= 1'b1;	// Have to pre-load this, so it renders the first pixel (Tag) correctly.
				isp_state <= 8'd51;
			end
		end
		
		1: begin
			if (is_tri_strip) begin		// TriangleStrip.
				if (strip_mask==6'b000000 || strip_cnt==3'd6) begin	// Nothing to draw for this strip.
					poly_drawn <= 1'b1;				// Tell the RA we're done.
					isp_state <= 8'd0;				// Go back to idle state.
				end
				else if (strip_cnt < 6) begin	// Check strip_mask bits 0 through 5...
					if (strip_mask[strip_cnt]) begin
						isp_vram_addr <= poly_addr;	// Always use the absolute start address of the poly. Will fetch ISP/TSP/TCW again, but then skip verts.
						isp_vram_rd <= 1'b1;
						/*if (!cache_bypass) */prim_tag <= prim_tag + 12'd1;
						isp_state <= 8'd2;				// Go to the next state if the current strip_mask bit is set.
					end
					else begin									// Current strip_mask bit was NOT set...
						strip_cnt <= strip_cnt + 3'd1;	// Increment to the next bit.
						//isp_state <= 8'd1;					// (Stay in the current state, to check the next bit.)
					end
				end
			end
			else if (is_tri_array || is_quad_array) begin	// Triangle Array or Quad Array.
				quad_done <= 1'b0;							// Ready for drawing the first half of a Quad.			
				array_cnt <= num_prims;	// Shouldn't need a +1 here, because it will render the first triangle with array_cnt==0 anyway. ElectronAsh.
				/*if (!cache_bypass) */prim_tag <= prim_tag + 12'd1;
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd2;
			end
			else begin
				poly_drawn <= 1'b1;	// No idea which prim type, so skip!
				isp_state <= 8'd0;
			end
		end
		
		2: if (vram_valid) begin isp_inst <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		3: if (vram_valid) begin tsp_inst <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		4: if (vram_valid) begin
			tcw_word <= isp_vram_din;
			if (isp_vram_din[30] && tex_base_word_addr_old != isp_vram_din[20:0]) begin	// Quite a big speed-up, just by checking if the texture BASE addr has changed.
				tex_base_word_addr_old <= isp_vram_din[20:0];										// No point reading the codebook again, if the texture BASE addr is the same as the last prim.
				read_codebook <= 1'b1;	// Read VQ Code Book if TCW bit 30 is set.
				isp_state <= 8'd80;
			end
			else begin
				isp_state <= 8'd6;
			end
		end
		
		80: begin
			isp_vram_rd <= 1'b1;		// Read the first Word.
			isp_state <= 8'd5;
		end
		
		5: begin
			if (!codebook_wait) isp_state <= 8'd81;
			else if (vram_valid) isp_state <= 8'd80;	// Jump back.
		end
		
		81: if (vram_valid) begin	// Ditch the last word.
			 isp_state <= 8'd6;
		end
		
		6: begin
			if (is_tri_strip) isp_vram_addr <= poly_addr + (3<<2) + ((vert_words*strip_cnt) << 2);	// Skip a vert, based on strip_cnt.
			else isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
			isp_state <= 8'd7;
		end
		
		// if (shadow)...
		// Probably wrong? I think the shadow bit denotes when a poly can be affected by a Modifier Volume?) ElectronAsh.
		//5:  tsp2_inst <= isp_vram_din;
		//6:  tex2_cont <= isp_vram_din;
		
		7: if (vram_valid) begin vert_a_x <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		8: if (vram_valid) begin vert_a_y <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		9: if (vram_valid) begin
			vert_a_z <= isp_vram_din;
			if (skip==0) isp_state <= 8'd17;
			else if (!texture) isp_state <= 8'd12;	// Triangle Strip (probably).
			else isp_state <= isp_state + 8'd1;		// TESTING !!
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		10: if (vram_valid) begin
			if (uv_16_bit) begin	// Read U and V from the same VRAM word.
				vert_a_u0 <= {isp_vram_din[31:16],16'h0000};
				vert_a_v0 <= {isp_vram_din[15:00],16'h0000};
				isp_state <= 8'd12;	// Skip reading v0 from VRAM.
			end
			else begin
				vert_a_u0 <= isp_vram_din;
				isp_state <= isp_state + 8'd1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		11: if (vram_valid) begin vert_a_v0 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		12: if (vram_valid) begin
			vert_a_base_col_0 <= isp_vram_din;
			if (two_volume) isp_state <= 8'd13;
			else if (offset) isp_state <= 8'd16;
			else isp_state <= 8'd17;
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		
		// if Two-volume...
		13: if (vram_valid) begin vert_a_u1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		14: if (vram_valid) begin vert_a_v1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		15: if (vram_valid) begin vert_a_base_col_1 <= isp_vram_din;
			if (!offset) isp_state <= 8'd17;
			else isp_state <= isp_state + 8'd1;
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		
		// if Offset colour.
		16: if (vram_valid) begin vert_a_off_col <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		
		17: if (vram_valid) begin vert_b_x <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		18: if (vram_valid) begin vert_b_y <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		19: if (vram_valid) begin
			vert_b_z <= isp_vram_din;
			if (skip==0) isp_state <= 8'd27;
			else if (!texture) isp_state <= 8'd22;	// Triangle Strip (probably).
			else isp_state <= isp_state + 8'd1;		// TESTING !!
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		20: if (vram_valid) begin
			if (uv_16_bit) begin	// Read U and V from the same VRAM word.
				vert_b_u0 <= {isp_vram_din[31:16],16'h0000};
				vert_b_v0 <= {isp_vram_din[15:00],16'h0000};
				isp_state <= 8'd22;	// Skip reading v0 from VRAM.
			end
			else begin
				vert_b_u0 <= isp_vram_din;
				isp_state <= isp_state + 8'd1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		21: if (vram_valid) begin vert_b_v0 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		22: if (vram_valid) begin
			vert_b_base_col_0 <= isp_vram_din;
			if (two_volume) isp_state <= 8'd23;
			else if (offset) isp_state <= 8'd26;
			else isp_state <= 8'd27;
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		
		// if Two-volume...
		23: if (vram_valid) begin vert_b_u1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		24: if (vram_valid) begin vert_b_v1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		25: if (vram_valid) begin
			vert_b_base_col_1 <= isp_vram_din;
			if (!offset) isp_state <= 8'd27;
			else isp_state <= isp_state + 8'd1;
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		
		// if Offset colour...
		26: if (vram_valid) begin vert_b_off_col <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		
		27: if (vram_valid) begin vert_c_x <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		28: if (vram_valid) begin vert_c_y <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		29: if (vram_valid) begin
			vert_c_z <= isp_vram_din;
			if (skip==0) begin
				if (is_quad_array) begin
					isp_vram_rd <= 1'b1;
					isp_state <= 8'd37;
				end
				else isp_state <= 8'd47;
			end
			else if (!texture) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd32;	// Triangle Strip (probably).
			end
			else begin
				isp_vram_rd <= 1'b1;
				isp_state <= isp_state + 8'd1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
		end
		30: if (vram_valid) begin
			if (uv_16_bit) begin	// Read U and V from the same VRAM word.
				vert_c_u0 <= {isp_vram_din[31:16],16'h0000};
				vert_c_v0 <= {isp_vram_din[15:00],16'h0000};
				isp_state <= 8'd32;	// Skip reading v0 from VRAM.
			end
			else begin
				vert_c_u0 <= isp_vram_din;
				isp_state <= isp_state + 8'd1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		31: if (vram_valid) begin vert_c_v0 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		32: if (vram_valid) begin
			vert_c_base_col_0 <= isp_vram_din;
			if (two_volume) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd33;
			end
			else if (offset) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd36;
			end
			else if (is_quad_array) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd37;	// If a Quad.
			end
			else isp_state <= 8'd47;
			isp_vram_addr <= isp_vram_addr + 4;
		end
		
		// if Two-volume...
		33: if (vram_valid) begin vert_c_u1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		34: if (vram_valid) begin vert_c_v1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		35: if (vram_valid) begin vert_c_base_col_1 <= isp_vram_din;
			if (offset) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd36;
			end
			else isp_state <= 8'd47;
			isp_vram_addr <= isp_vram_addr + 4;
		end
		
		// if Offset colour...
		36: if (vram_valid) begin
			vert_c_off_col <= isp_vram_din;	// if Offset colour.
			if (is_quad_array) begin
				isp_state <= 8'd37;		// If a Quad
				isp_vram_rd <= 1'b1;
			end
			else isp_state <= 8'd47;
			isp_vram_addr <= isp_vram_addr + 4;
		end
		
		// Quad Array stuff...
		37: if (vram_valid) begin vert_d_x <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		38: if (vram_valid) begin vert_d_y <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		39: if (vram_valid) begin
			vert_d_z <= isp_vram_din;
			if (!texture) isp_state <= 8'd42;
			else isp_state <= isp_state + 8'd1;
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		40: if (vram_valid) begin
			if (uv_16_bit) begin	// Read U and V from the same VRAM word.
				vert_d_u0 <= {isp_vram_din[31:16],16'h0000};
				vert_d_v0 <= {isp_vram_din[15:00],16'h0000};
				isp_state <= 8'd42;	// Skip reading v0 from VRAM.
			end
			else begin
				vert_d_u0 <= isp_vram_din;
				isp_state <= isp_state + 8'd1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
			isp_vram_rd <= 1'b1;
		end
		41:if (vram_valid)  begin vert_d_v0 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		42: if (vram_valid) begin
			vert_d_base_col_0 <= isp_vram_din;
			if (two_volume) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd43;
			end
			else if (offset) begin
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd46;
			end
			else isp_state <= 8'd47;
			isp_vram_addr <= isp_vram_addr + 4;
		end
		
		// if Two-volume...
		43: if (vram_valid) begin vert_d_u1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		44: if (vram_valid) begin vert_d_v1 <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1; isp_state <= isp_state + 8'd1; end
		45: if (vram_valid) begin
			vert_d_base_col_1 <= isp_vram_din;
			if (!offset) isp_state <= 8'd47;
			else begin
				isp_state <= isp_state + 8'd1;
				isp_vram_rd <= 1'b1;
			end
			isp_vram_addr <= isp_vram_addr + 4;
		end
		
		// if Offset colour...
		46: if (vram_valid) begin
			vert_d_off_col <= isp_vram_din;				// if Offset colour.
			isp_vram_addr <= isp_vram_addr + 4;
			isp_state <= isp_state + 8'd1;
		end
		
		47: if (!z_clear_busy) begin
			if (is_tri_strip && strip_cnt[0]) begin	// Swap verts A and B, for all ODD strip segments.
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
			isp_vram_addr <= isp_vram_addr + 4;	// I think this is needed, to make isp_vram_addr_last correct in isp_state 49!
			isp_state <= 8'd49;			// Draw the triangle!
		end
		
		48: if (!z_clear_busy) begin
			if (is_tri_strip) begin			// Triangle Strip.
				strip_cnt <= strip_cnt + 3'd1;	// Increment to the next strip_mask bit.
				isp_state <= 8'd1;
			end
			else if (is_tri_array || is_quad_array) begin		// Triangle Array or Quad Array.
				if (array_cnt==4'd0) begin		// If Array is done...
					if (is_quad_array) begin	// Quad Array (maybe) done.
						if (!quad_done) begin	// Second half of Quad not done yet...
							// Swap some verts and UV stuff, for the second half of a Quad. (kludge!)
							vert_b_x <= vert_d_x;
							vert_b_y <= vert_d_y;
							//vert_b_z <= vert_d_z;
							vert_b_u0 <= vert_a_u0;
							vert_b_v0 <= vert_c_v0;
							isp_state <= 8'd47;	// Draw the second half of the Quad.
														// isp_entry_valid will tell the C code to latch the
														// params again, and convert to fixed-point.
							quad_done <= 1'b1;	// <- The next time we get to this state, we know the full Quad is drawn.
						end
						else begin
							poly_drawn <= 1'b1;	// Quad is done.
							isp_state <= 8'd0;
						end
					end
					else begin	// Triangle (or part of Array) is done.
						poly_drawn <= 1'b1;
						isp_state <= 8'd0;
					end
				end
				else begin	// Triangle Array or Quad Array not done yet...
					array_cnt <= array_cnt - 3'd1;
					isp_vram_addr <= isp_vram_addr - 4;
					isp_vram_rd <= 1'b1;
					isp_state <= 8'd2;	// Jump back, to grab the next PRIM (including ISP/TSP/TCW).
				end
			end
			else begin	// Should never get to here??
				poly_drawn <= 1'b1;
				isp_state <= 8'd0;
			end
		end

		49: begin
			// Per-tile rendering.
			x_ps <= tilex_start;
			y_ps <= tiley_start;
			
			isp_vram_addr_last <= isp_vram_addr;
			isp_state <= isp_state + 8'd1;
		end

		// Write triangle spans to Z / Tag buffer, checking 32 "pixels" at once for inTri AND depth_compare.
		50: begin
			y_ps[4:0] <= y_ps[4:0] + 5'd1;
			if (y_ps[4:0]==5'd31) begin
				isp_vram_addr <= isp_vram_addr_last;
				isp_state <= 8'd48;		// Loop, to check next PRIM.
			end
			//else isp_state <= 8'd90;
		end
		
		/*
		90: begin						// Z-buff write is allowed in this state.
			isp_state <= isp_state + 8'd1;
		end
		
		91: begin
			y_ps[4:0] <= y_ps[4:0] + 5'd1;
			isp_state <= 8'd50;		// Jump back.
		end
		*/
		
		// Rendering from the Tag buffer now.
		// We jump to this state when in isp_state==0 AND "tile_prims_done" is triggered.
		//
		51: if (!z_clear_busy && !read_codebook && !codebook_wait) begin
			pcache_load <= 1'b1;
			if (prim_tag_out_old != prim_tag_out) begin			// Check to see if the Tag has changed...
				prim_tag_out_old <= prim_tag_out;					// If so, make a backup.
				if (isp_inst_out[25] && tcw_word_out[30]) begin
					read_codebook <= 1'b1;	// isp_inst[25]=texture.  tcw_word[30]=vq_comp.
					isp_state <= 8'd100;
				end
			end
			else begin
				// On the last (lower-right) pixel of the tile...
				if (y_ps[4:0]==5'd31 && x_ps[4:0]==5'd31) begin
					tile_accum_done <= 1'b1;	// Tell the RA we're done.
					isp_state <= 8'd0;			// Back to idle state.
				end
				else begin
					x_ps[4:0] <= x_ps[4:0] + 5'd1;			// Inc x_ps[4:0].
					if (x_ps[4:0]==5'd31) y_ps[4:0] <= y_ps[4:0] + 5'd1;
					//vram_word_addr_old <= vram_word_addr;
					//isp_vram_addr <= x_ps + (y_ps*640);	// Framebuffer write address.
					//isp_vram_dout <= final_argb;			// ABGR, for sim display.
					//isp_vram_wr <= 1'b1;
					isp_vram_rd <= 1'b1;	// Read texel...
					fb_addr <= (x_ps+(y_ps*640));
					isp_state <= isp_state + 8'd1;
				end
			end
		end
		
		// Next (visible) pixel...
		52: if (vram_valid) begin
			isp_state <= isp_state + 1'd1;
		end
		
		53: begin
			isp_state <= isp_state + 1'd1;
		end
		
		54: begin
			//fb_addr <= (x_ps+(y_ps*640));
			fb_writedata <= {pix_565, pix_565, pix_565, pix_565};
			fb_byteena <= (!fb_addr[0]) ? 8'b00001111 : 8'b11110000;
			fb_we <= 1'b1;
			if (!vram_wait) isp_state <= 8'd51;	// Jump back.
		end
		
		100: begin
			isp_vram_rd <= 1'b1;		// Read the first Word.
			isp_state <= 8'd101;
		end
		
		101: begin
			if (!codebook_wait) isp_state <= 8'd102;
			else if (vram_valid) isp_state <= 8'd100;	// Jump back.
		end
		
		102: if (vram_valid) begin	// Ditch the last word.
			isp_state <= 8'd103;
		end
		
		103: begin
			isp_state <= 8'd51;
		end

		default: ;
	endcase
	
	if (isp_vram_rd) isp_vram_rd_pend     <= 1'b1;
	else if (vram_valid) isp_vram_rd_pend <= 1'b0;

	/*
	// FB Clear disabled in ra_parser atm. 
	
	if (clear_fb) begin
		fb_addr <= 23'd0;
		clear_fb_pend <= 1'b1;
	end
	else if (clear_fb_pend) begin
		fb_writedata <= 64'd0;
		fb_byteena <= 8'hff;
		fb_we <= 1'b1;
		fb_addr <= fb_addr + 1;
		if (fb_addr > (640*480)) begin
			fb_we <= 1'b0;
			clear_fb_pend <= 1'b0;
		end
	end
	*/
	
	//if (pcache_load && !cache_bypass) begin
	if (pcache_load) begin
		isp_inst				<= isp_inst_out;
		tsp_inst				<= tsp_inst_out;
		tcw_word				<= tcw_word_out;
	
		vert_a_x				<= vert_a_x_out;
		vert_a_y				<= vert_a_y_out;
		vert_a_z				<= vert_a_z_out;
		vert_a_u0			<= vert_a_u0_out;
		vert_a_v0			<= vert_a_v0_out;
		vert_a_base_col_0	<= vert_a_base_col_0_out;
		vert_a_off_col		<= vert_a_off_col_out;
		
		vert_b_x				<= vert_b_x_out;
		vert_b_y				<= vert_b_y_out;
		vert_b_z				<= vert_b_z_out;
		vert_b_u0			<= vert_b_u0_out;
		vert_b_v0			<= vert_b_v0_out;
		vert_b_base_col_0	<= vert_b_base_col_0_out;
		vert_b_off_col		<= vert_b_off_col_out;
		
		vert_c_x				<= vert_c_x_out;
		vert_c_y				<= vert_c_y_out;
		vert_c_z				<= vert_c_z_out;
		vert_c_u0			<= vert_c_u0_out;
		vert_c_v0			<= vert_c_v0_out;
		vert_c_base_col_0	<= vert_c_base_col_0_out;
		vert_c_off_col		<= vert_c_off_col_out;
	end
end


wire [15:0] pix_565 = {final_argb[23:19],final_argb[15:10],final_argb[7:3]};


wire [10:0] tilex_start = {tilex, 5'b00000};
wire [10:0] tiley_start = {tiley, 5'b00000};

wire [7:0] vert_words = (two_volume&shadow) ? ((skip*2)+3) : (skip+3);


// Internal Z-buffer...
/*
wire [9:0] z_buff_addr = x_ps[4:0] + (y_ps[4:0]*32);
wire clear_done;
wire depth_allow;

z_buffer  z_buffer_inst(
	.clock( clock ),
	.reset_n( reset_n ),
	
	.clear_z( clear_z ),
	.clear_done( clear_done ),
	
	.z_buff_addr( z_buff_addr ),
	.z_in( IP_Z_INTERP ),
	.z_write_disable( z_write_disable ),
	//.z_out( old_z ),
	
	.inTriangle( inTri[x_ps[4:0]] ),
	
	.type_cnt( type_cnt ),		// From the RA. 0=Opaque, 1=Opaque Mod, 2=Trans, 3=Trans mod, 4=PunchThrough.
	.depth_comp( depth_comp ),
	.depth_allow( depth_allow )
);
*/


wire [31:0] isp_inst_out;
wire [31:0] tsp_inst_out;
wire [31:0] tcw_word_out;

wire [31:0] vert_a_x_out;
wire [31:0] vert_a_y_out;
wire [31:0] vert_a_z_out;
wire [31:0] vert_a_u0_out;
wire [31:0] vert_a_v0_out;
wire [31:0] vert_a_base_col_0_out;
wire [31:0] vert_a_off_col_out;

wire [31:0] vert_b_x_out;
wire [31:0] vert_b_y_out;
wire [31:0] vert_b_z_out;
wire [31:0] vert_b_u0_out;
wire [31:0] vert_b_v0_out;
wire [31:0] vert_b_base_col_0_out;
wire [31:0] vert_b_off_col_out;

wire [31:0] vert_c_x_out;
wire [31:0] vert_c_y_out;
wire [31:0] vert_c_z_out;
wire [31:0] vert_c_u0_out;
wire [31:0] vert_c_v0_out;
wire [31:0] vert_c_base_col_0_out;
wire [31:0] vert_c_off_col_out;


//wire pcache_write = (isp_state==8'd49 && !cache_bypass);
wire pcache_write = (isp_state==8'd49);
reg  pcache_load;

reg [9:0] prim_tag_out_old;

wire [9:0] prim_tag_mux = (isp_state>=8'd51 && isp_state<=8'd54) ? prim_tag_out : prim_tag;

param_buffer  param_buffer_inst
(
	.clock(clock) ,									// input  clock
	.reset_n(reset_n) ,								// input  reset_n
	
	.prim_tag(prim_tag_mux) ,						// input [11:0] prim_tag
	
	.pcache_write(pcache_write) ,					// input  pcache_write
	
	.isp_inst_in(isp_inst) ,						// input [31:0] isp_inst_in
	.tsp_inst_in(tsp_inst) ,						// input [31:0] tsp_inst_in
	.tcw_word_in(tcw_word) ,						// input [31:0] tcw_word_in
	
	.vert_a_x_in(         vert_a_x) ,			// input [31:0] vert_a_x_in
	.vert_a_y_in(         vert_a_y) ,			// input [31:0] vert_a_y_in
	.vert_a_z_in(         vert_a_z) ,			// input [31:0] vert_a_z_in
	.vert_a_u0_in(        vert_a_u0) ,			// input [31:0] vert_a_u0_in
	.vert_a_v0_in(        vert_a_v0) ,			// input [31:0] vert_a_v0_in
	.vert_a_base_col_0_in(vert_a_base_col_0) ,// input [31:0] vert_a_base_col_0_in
	.vert_a_off_col_in(   vert_a_off_col) ,	// input [31:0] vert_a_off_col_in
	
	.vert_b_x_in(         vert_b_x) ,			// input [31:0] vert_b_x_in
	.vert_b_y_in(         vert_b_y) ,			// input [31:0] vert_b_y_in
	.vert_b_z_in(         vert_b_z) ,			// input [31:0] vert_b_z_in
	.vert_b_u0_in(        vert_b_u0) ,			// input [31:0] vert_b_u0_in
	.vert_b_v0_in(        vert_b_v0) ,			// input [31:0] vert_b_v0_in
	.vert_b_base_col_0_in(vert_b_base_col_0) ,// input [31:0] vert_b_base_col_0_in
	.vert_b_off_col_in(   vert_b_off_col) ,	// input [31:0] vert_b_off_col_in
	
	.vert_c_x_in(         vert_c_x) ,			// input [31:0] vert_c_x_in
	.vert_c_y_in(         vert_c_y) ,			// input [31:0] vert_c_y_in
	.vert_c_z_in(         vert_c_z) ,			// input [31:0] vert_c_z_in
	.vert_c_u0_in(        vert_c_u0) ,			// input [31:0] vert_c_u0_in
	.vert_c_v0_in(        vert_c_v0) ,			// input [31:0] vert_c_v0_in
	.vert_c_base_col_0_in(vert_c_base_col_0) ,// input [31:0] vert_c_base_col_0_in
	.vert_c_off_col_in(   vert_c_off_col) ,	// input [31:0] vert_c_off_col_in
	
	.isp_inst_out(isp_inst_out) ,					// output [31:0] isp_inst_out
	.tsp_inst_out(tsp_inst_out) ,					// output [31:0] tsp_inst_out
	.tcw_word_out(tcw_word_out) ,					// output [31:0] tcw_word_out
	
	.vert_a_x_out(vert_a_x_out) ,					// output [31:0] vert_a_x_out
	.vert_a_y_out(vert_a_y_out) ,					// output [31:0] vert_a_y_out
	.vert_a_z_out(vert_a_z_out) ,					// output [31:0] vert_a_z_out
	.vert_a_u0_out(vert_a_u0_out) ,					// output [31:0] vert_a_u0_out
	.vert_a_v0_out(vert_a_v0_out) ,					// output [31:0] vert_a_v0_out
	.vert_a_base_col_0_out(vert_a_base_col_0_out) ,	// output [31:0] vert_a_base_col_0_out
	.vert_a_off_col_out(vert_a_off_col_out) ,		// output [31:0] vert_a_off_col_out
	
	.vert_b_x_out(vert_b_x_out) ,					// output [31:0] vert_b_x_out
	.vert_b_y_out(vert_b_y_out) ,					// output [31:0] vert_b_y_out
	.vert_b_z_out(vert_b_z_out) ,					// output [31:0] vert_b_z_out
	.vert_b_u0_out(vert_b_u0_out) ,					// output [31:0] vert_b_u0_out
	.vert_b_v0_out(vert_b_v0_out) ,					// output [31:0] vert_b_v0_out
	.vert_b_base_col_0_out(vert_b_base_col_0_out) ,	// output [31:0] vert_b_base_col_0_out
	.vert_b_off_col_out(vert_b_off_col_out) ,		// output [31:0] vert_b_off_col_out
	
	.vert_c_x_out(vert_c_x_out) ,					// output [31:0] vert_c_x_out
	.vert_c_y_out(vert_c_y_out) ,					// output [31:0] vert_c_y_out
	.vert_c_z_out(vert_c_z_out) ,					// output [31:0] vert_c_z_out
	.vert_c_u0_out(vert_c_u0_out) ,					// output [31:0] vert_c_u0_out
	.vert_c_v0_out(vert_c_v0_out) ,					// output [31:0] vert_c_v0_out
	.vert_c_base_col_0_out(vert_c_base_col_0_out) ,	// output [31:0] vert_c_base_col_0_out
	.vert_c_off_col_out(vert_c_off_col_out) 		// output [31:0] vert_c_off_col_out
);


// Vertex float-to-fixed conversion...
(*keep*)wire signed [47:0] FX1_FIXED;
float_to_fixed  float_x1 (
	.float_in( vert_a_x ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FX1_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FY1_FIXED;
float_to_fixed  float_y1 (
	.float_in( vert_a_y ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FY1_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FZ1_FIXED;
float_to_fixed  float_z1 (
	.float_in( vert_a_z ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FZ1_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FU1_FIXED;
float_to_fixed  float_u1 (
	.float_in( vert_a_u0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FU1_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FV1_FIXED;
float_to_fixed  float_v1 (
	.float_in( vert_a_v0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FV1_FIXED )		// output [47:0]  fixed
);

/*
wire signed [47:0] vert_b_x_in  = (is_quad_array && quad_done) ? vert_d_x : vert_b_x;
wire signed [47:0] vert_b_y_in  = (is_quad_array && quad_done) ? vert_d_y : vert_b_y;
//wire signed [47:0] vert_b_z_in  = (is_quad_array && quad_done) ? vert_d_z : vert_b_z;
wire signed [47:0] vert_b_u0_in = (is_quad_array && quad_done) ? vert_a_u0 : vert_b_u0;
wire signed [47:0] vert_b_v0_in = (is_quad_array && quad_done) ? vert_c_v0 : vert_b_v0;
*/

(*keep*)wire signed [47:0] FX2_FIXED;
float_to_fixed  float_x2 (
	//.float_in( vert_b_x_in ),	// input [31:0]  float_in
	.float_in( vert_b_x ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FX2_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FY2_FIXED;
float_to_fixed  float_y2 (
	//.float_in( vert_b_y_in ),	// input [31:0]  float_in
	.float_in( vert_b_y ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FY2_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FZ2_FIXED;
float_to_fixed  float_z2 (
	.float_in( vert_b_z ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FZ2_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FU2_FIXED;
float_to_fixed  float_u2 (
	//.float_in( vert_b_u0_in ),	// input [31:0]  float_in
	.float_in( vert_b_u0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FU2_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FV2_FIXED;
float_to_fixed  float_v2 (
	//.float_in( vert_b_v0_in ),	// input [31:0]  float_in
	.float_in( vert_b_v0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FV2_FIXED )		// output [47:0]  fixed
);

(*keep*)wire signed [47:0] FX3_FIXED;
float_to_fixed  float_x3 (
	.float_in( vert_c_x ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FX3_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FY3_FIXED;
float_to_fixed  float_y3 (
	.float_in( vert_c_y ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FY3_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FZ3_FIXED;
float_to_fixed  float_z3 (
	.float_in( vert_c_z ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FZ3_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FU3_FIXED;
float_to_fixed  float_u3 (
	.float_in( vert_c_u0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FU3_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FV3_FIXED;
float_to_fixed  float_v3 (
	.float_in( vert_c_v0 ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FV3_FIXED )		// output [47:0]  fixed
);

(*keep*)wire signed [47:0] FX4_FIXED;
float_to_fixed  float_x4 (
	.float_in( vert_d_x ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FX4_FIXED )		// output [47:0]  fixed
);
(*keep*)wire signed [47:0] FY4_FIXED;
float_to_fixed  float_y4 (
	.float_in( vert_d_y ),	// input [31:0]  float_in
	.FRAC_BITS( FRAC_BITS ),
	.fixed( FY4_FIXED )		// output [47:0]  fixed
);


reg [10:0] x_ps;
reg [10:0] y_ps;


inTri_calc  inTri_calc_inst (
	.FX1_FIXED( FX1_FIXED ),	// input signed [47:0]  FX1
	.FX2_FIXED( FX2_FIXED ),	// input signed [47:0]  FX2
	.FX3_FIXED( FX3_FIXED ),	// input signed [47:0]  FX3
	
	.FY1_FIXED( FY1_FIXED ),	// input signed [47:0]  FY1
	.FY2_FIXED( FY2_FIXED ),	// input signed [47:0]  FY2
	.FY3_FIXED( FY3_FIXED ),	// input signed [47:0]  FY3

	.x_ps( x_ps ),
	.y_ps( y_ps ),
	
	//.inTriangle( inTriangle ),	// output inTriangle
	.inTri( inTri )	// output [31:0]  inTri
);

//(*keep*)wire inTriangle;
(*keep*)wire [31:0] inTri;


// Z.Setup(x1,x2,x3, y1,y2,y3, z1,z2,z3);

interp  interp_inst_z (
	.clock( clock ),			// input  clock
	
	.FRAC_BITS( FRAC_BITS ),	// input [7:0] FRAC_BITS

	.FX1( FX1_FIXED ),		// input signed [31:0] x1
	.FX2( FX2_FIXED ),		// input signed [31:0] x2
	.FX3( FX3_FIXED ),		// input signed [31:0] x3
	
	.FY1( FY1_FIXED ),		// input signed [31:0] y1
	.FY2( FY2_FIXED ),		// input signed [31:0] y2
	.FY3( FY3_FIXED ),		// input signed [31:0] y3
	
	.FZ1( FZ1_FIXED ),		// input signed [31:0] z1
	.FZ2( FZ2_FIXED ),		// input signed [31:0] z2
	.FZ3( FZ3_FIXED ),		// input signed [31:0] z3
	
	.x_ps( x_ps ),		// input [10:0] x_ps
	.y_ps( y_ps ),		// input [10:0] y_ps
	
	//.interp( IP_Z_INTERP ),	// output signed [31:0]  interp

	.interp0(  IP_Z[0] ),  .interp1(  IP_Z[1] ),  .interp2(  IP_Z[2] ),  .interp3(  IP_Z[3] ),  .interp4(  IP_Z[4] ),  .interp5(  IP_Z[5] ),  .interp6(  IP_Z[6] ),  .interp7(  IP_Z[7] ),
	.interp8(  IP_Z[8] ),  .interp9(  IP_Z[9] ),  .interp10( IP_Z[10] ), .interp11( IP_Z[11] ), .interp12( IP_Z[12] ), .interp13( IP_Z[13] ), .interp14( IP_Z[14] ), .interp15( IP_Z[15] ),
	.interp16( IP_Z[16] ), .interp17( IP_Z[17] ), .interp18( IP_Z[18] ), .interp19( IP_Z[19] ), .interp20( IP_Z[20] ), .interp21( IP_Z[21] ), .interp22( IP_Z[22] ), .interp23( IP_Z[23] ),
	.interp24( IP_Z[24] ), .interp25( IP_Z[25] ), .interp26( IP_Z[26] ), .interp27( IP_Z[27] ), .interp28( IP_Z[28] ), .interp29( IP_Z[29] ), .interp30( IP_Z[30] ), .interp31( IP_Z[31] )
);

//wire signed [31:0] IP_Z_INTERP = FZ1_FIXED;	// Using the fixed Z value atm. Can't fit the Z interp on the DE10. ElectronAsh.
//wire signed [31:0] IP_Z_INTERP;
wire signed [31:0] IP_Z [0:31];	// [0:31] is the tile COLUMN.


// int w = tex_u_size_full;
// U.Setup(x1,x2,x3, y1,y2,y3, u1*w*z1, u2*w*z2, u3*w*z3);
//
// Don't need to shift right after, as tex_u_size_full is not fixed-point...
wire signed [63:0] u1_mult_width = FU1_FIXED * tex_u_size_full;
wire signed [63:0] u2_mult_width = FU2_FIXED * tex_u_size_full;
wire signed [63:0] u3_mult_width = FU3_FIXED * tex_u_size_full;

interp  interp_inst_u (
	.clock( clock ),			// input  clock
	
	.FRAC_BITS( FRAC_BITS ),	// input [7:0] FRAC_BITS

	.FX1( FX1_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x1
	.FX2( FX2_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x2
	.FX3( FX3_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x3
	
	.FY1( FY1_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y1
	.FY2( FY2_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y2
	.FY3( FY3_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y3
	
	.FZ1( (u1_mult_width * FZ1_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z1
	.FZ2( (u2_mult_width * FZ2_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z2
	.FZ3( (u3_mult_width * FZ3_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z3
	
	.x_ps( x_ps ),		// input [10:0] x_ps
	.y_ps( y_ps ),		// input [10:0] y_ps
	
	.interp( IP_U_INTERP )//,	// output signed [31:0]  interp

	//.interp0(  IP_U[0] ),  .interp1(  IP_U[1] ),  .interp2(  IP_U[2] ),  .interp3(  IP_U[3] ),  .interp4(  IP_U[4] ),  .interp5(  IP_U[5] ),  .interp6(  IP_U[6] ),  .interp7(  IP_U[7] ),
	//.interp8(  IP_U[8] ),  .interp9(  IP_U[9] ),  .interp10( IP_U[10] ), .interp11( IP_U[11] ), .interp12( IP_U[12] ), .interp13( IP_U[13] ), .interp14( IP_U[14] ), .interp15( IP_U[15] ),
	//.interp16( IP_U[16] ), .interp17( IP_U[17] ), .interp18( IP_U[18] ), .interp19( IP_U[19] ), .interp20( IP_U[20] ), .interp21( IP_U[21] ), .interp22( IP_U[22] ), .interp23( IP_U[23] ),
	//.interp24( IP_U[24] ), .interp25( IP_U[25] ), .interp26( IP_U[26] ), .interp27( IP_U[27] ), .interp28( IP_U[28] ), .interp29( IP_U[29] ), .interp30( IP_U[30] ), .interp31( IP_U[31] )
);

wire signed [31:0] IP_U_INTERP /*= FU2_FIXED * tex_u_size_full*/;
//wire signed [31:0] IP_U [0:31];	// [0:31] is the tile COLUMN.


// int h = tex_v_size_full;
// V.Setup(x1,x2,x3, y1,y2,y3, v1*h*z1, v2*h*z2, v3*h*z3);
//
wire signed [63:0] v1_mult_height = FV1_FIXED * tex_v_size_full;	// Don't need to shift right after, as tex_v_size_full is not fixed-point?
wire signed [63:0] v2_mult_height = FV2_FIXED * tex_v_size_full;
wire signed [63:0] v3_mult_height = FV3_FIXED * tex_v_size_full;

interp  interp_inst_v (
	.clock( clock ),			// input  clock
	
	.FRAC_BITS( FRAC_BITS ),	// input [7:0] FRAC_BITS

	.FX1( FX1_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x1
	.FX2( FX2_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x2
	.FX3( FX3_FIXED <<<FRAC_DIFF ),		// input signed [31:0] x3
	
	.FY1( FY1_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y1
	.FY2( FY2_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y2
	.FY3( FY3_FIXED <<<FRAC_DIFF ),		// input signed [31:0] y3
	
	.FZ1( (v1_mult_height * FZ1_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z1
	.FZ2( (v2_mult_height * FZ2_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z2
	.FZ3( (v3_mult_height * FZ3_FIXED) >>Z_FRAC_BITS ),	// input signed [31:0] z3
	
	.x_ps( x_ps ),		// input [10:0] x_ps
	.y_ps( y_ps ),		// input [10:0] y_ps
	
	.interp( IP_V_INTERP )//,	// output signed [31:0]  interp

	//.interp0(  IP_V[0] ),  .interp1(  IP_V[1] ),  .interp2(  IP_V[2] ),  .interp3(  IP_V[3] ),  .interp4(  IP_V[4] ),  .interp5(  IP_V[5] ),  .interp6(  IP_V[6] ),  .interp7(  IP_V[7] ),
	//.interp8(  IP_V[8] ),  .interp9(  IP_V[9] ),  .interp10( IP_V[10] ), .interp11( IP_V[11] ), .interp12( IP_V[12] ), .interp13( IP_V[13] ), .interp14( IP_V[14] ), .interp15( IP_V[15] ),
	//.interp16( IP_V[16] ), .interp17( IP_V[17] ), .interp18( IP_V[18] ), .interp19( IP_V[19] ), .interp20( IP_V[20] ), .interp21( IP_V[21] ), .interp22( IP_V[22] ), .interp23( IP_V[23] ),
	//.interp24( IP_V[24] ), .interp25( IP_V[25] ), .interp26( IP_V[26] ), .interp27( IP_V[27] ), .interp28( IP_V[28] ), .interp29( IP_V[29] ), .interp30( IP_V[30] ), .interp31( IP_V[31] )
);

wire signed [31:0] IP_V_INTERP /*= FV2_FIXED * tex_v_size_full*/;
//wire signed [31:0] IP_V [0:31];	// [0:31] is the tile COLUMN.


// Highest value is 1024 (8<<7) so we need 11 bits to store it! ElectronAsh.
wire [10:0] tex_u_size_full = (8<<tex_u_size);
wire [10:0] tex_v_size_full = (8<<tex_v_size);

//wire signed [10:0] u_div_z = (IP_U_INTERP<<<FRAC_DIFF) / IP_Z_INTERP;
//wire signed [10:0] v_div_z = (IP_V_INTERP<<<FRAC_DIFF) / IP_Z_INTERP;
wire signed [10:0] u_div_z = (IP_U_INTERP<<<FRAC_DIFF) / z_out;
wire signed [10:0] v_div_z = (IP_V_INTERP<<<FRAC_DIFF) / z_out;

wire [9:0] u_clamped = (tex_u_clamp && u_div_z>=tex_u_size_full) ? tex_u_size_full-1 :	// Clamp, if U > texture width.
							  (tex_u_clamp && u_div_z[10]) ? 10'd0 :									// Zero U coord if u_div_z is negative.
													u_div_z;														// Else, don't clamp nor zero.

wire [9:0] v_clamped = (tex_v_clamp && v_div_z>=tex_v_size_full) ? tex_v_size_full-1 :	// Clamp, if V > texture height.
							  (tex_v_clamp && v_div_z[10]) ? 10'd0 :									// Zero U coord if u_div_z is negative.
													v_div_z;														// Else, don't clamp nor zero.

wire [9:0] u_masked  = u_clamped&((tex_u_size_full<<1)-1);	// Mask with TWICE the texture width?
wire [9:0] v_masked  = v_clamped&((tex_v_size_full<<1)-1);	// Mask with TWICE the texture height?

wire [9:0] u_mask_flip = (u_masked&tex_u_size_full) ? u_div_z^((tex_u_size_full<<1)-1) : u_div_z;
wire [9:0] v_mask_flip = (v_masked&tex_v_size_full) ? v_div_z^((tex_v_size_full<<1)-1) : v_div_z;

wire [9:0] u_flipped = (tex_u_clamp) ? u_clamped : (tex_u_flip) ? u_mask_flip : u_div_z&(tex_u_size_full-1);
wire [9:0] v_flipped = (tex_v_clamp) ? v_clamped : (tex_v_flip) ? v_mask_flip : v_div_z&(tex_v_size_full-1);


texture_address  texture_address_inst (
	.clock( clock ),
	.reset_n( reset_n ),
	
	.isp_inst( isp_inst ),	// input [31:0]  isp_inst.
	.tsp_inst( tsp_inst ),	// input [31:0]  tsp_inst.
	.tcw_word( tcw_word ),	// input [31:0]  tcw_word.
	
	.TEXT_CONTROL( TEXT_CONTROL ),	// input [31:0]  TEXT_CONTROL.

	.PAL_RAM_CTRL( PAL_RAM_CTRL ),	// input from PAL_RAM_CTRL, bits [1:0].
	.pal_addr( pal_addr ),				// input [9:0]  pal_addr
	.pal_din( pal_din ),					// input [31:0]  pal_din
	.pal_wr( pal_wr ),					// input  pal_wr
	.pal_rd( pal_rd ),					// input  pal_rd
	.pal_dout( pal_dout ),				// output [31:0]  pal_dout
	
	//.prim_tag( prim_tag_out ),		// input [11:0]  prim_tag
	//.prim_tag( prim_tag ),			// input [11:0]  prim_tag

	//.cb_cache_clear( cb_cache_clear ),	// input  cb_cache_clear (on new tile start).
	//.cb_cache_hit( cb_cache_hit ),			// output  cb_cache_hit
	
	.read_codebook( read_codebook ),	// input  read_codebook
	.codebook_wait( codebook_wait ),	// output codebook_wait
	
	.ui( u_flipped ),
	.vi( v_flipped ),
	//.ui( sim_ui ),
	//.vi( sim_vi ),
	
	.vram_wait( vram_wait ),
	.vram_valid( vram_valid ),
	.vram_word_addr( vram_word_addr ),	// output [21:0]  vram_word_addr. 32-bit or 64-bit WORD address! Hard to explain. lol
	.vram_din( tex_vram_din ),				// input [63:0]  vram_din. Full 64-bit data for texture reads.
	
	.base_argb( vert_c_base_col_0 ),	// input [31:0]  base_argb.  Flat-shading colour input. (will also do Gouraud eventually).
	.offs_argb( vert_c_off_col ),		// input [31:0]  offs_argb.  Offset colour input.
	
	.texel_argb( texel_argb ),			// output [31:0]  texel_argb. Texel ARGB 8888 output.
	.final_argb( final_argb )			// output [31:0]  final_argb. Final blended ARGB 8888 output.
);

reg read_codebook;
wire codebook_wait;

reg cb_cache_clear;
wire cb_cache_hit;


//reg [9:0] sim_ui;
//reg [9:0] sim_vi;

wire [21:0] vram_word_addr;
reg [21:0] vram_word_addr_old;

wire [31:0] texel_argb;
wire [31:0] final_argb;


wire z_clear_busy;

wire signed [31:0] z_out;
wire [9:0] prim_tag_out;

wire [2:0] depth_comp_in = /*(type_cnt==4 || type_cnt==1 || type_cnt==3) ? 3'd6 : (type_cnt==2) ? 3'd3 :*/ depth_comp;

wire trig_z_row_write = isp_state==8'd50 && y_ps<=(tiley_start+31) && !z_write_disable;

z_buff  z_buff_inst(
	.clock( clock ),
	.reset_n( reset_n ),
	
	.clear_z( clear_z && !ra_cont_zclear_n ),	// clear_z && !ra_cont_zclear_n  New tile started AND ra_cont_zclear_n is asserted (Low).
	.z_clear_busy( z_clear_busy ),
	
	.col_sel( x_ps[4:0] ),			// input [4:0] col_sel  x_ps[4:0]
	.row_sel( y_ps[4:0] ),			// input [4:0] row_sel  y_ps[4:0]
	
	.z_out( z_out ),						// output signed  [31:0]  z_out
	.prim_tag_out( prim_tag_out ),	// output [11:0]  prim_tag_out
	
	.inTri( inTri ),						// input [31:0]  z_write_allow   (Bitwise AND).
	.trig_z_row_write( trig_z_row_write ),
	
	.depth_comp_in( depth_comp_in ),
	
	.prim_tag_in( prim_tag ),		// input [11:0] prim_tag_in
	
	.z_in_col_0 ( IP_Z[0] ),		// input [47:0] z_in_col_0  IP_Z[0]
	.z_in_col_1 ( IP_Z[1] ),
	.z_in_col_2 ( IP_Z[2] ),
	.z_in_col_3 ( IP_Z[3] ),
	.z_in_col_4 ( IP_Z[4] ),
	.z_in_col_5 ( IP_Z[5] ),
	.z_in_col_6 ( IP_Z[6] ),
	.z_in_col_7 ( IP_Z[7] ),
	.z_in_col_8 ( IP_Z[8] ),
	.z_in_col_9 ( IP_Z[9] ),
	.z_in_col_10( IP_Z[10] ),
	.z_in_col_11( IP_Z[11] ),
	.z_in_col_12( IP_Z[12] ),
	.z_in_col_13( IP_Z[13] ),
	.z_in_col_14( IP_Z[14] ),
	.z_in_col_15( IP_Z[15] ),
	.z_in_col_16( IP_Z[16] ),
	.z_in_col_17( IP_Z[17] ),
	.z_in_col_18( IP_Z[18] ),
	.z_in_col_19( IP_Z[19] ),
	.z_in_col_20( IP_Z[20] ),
	.z_in_col_21( IP_Z[21] ),
	.z_in_col_22( IP_Z[22] ),
	.z_in_col_23( IP_Z[23] ),
	.z_in_col_24( IP_Z[24] ),
	.z_in_col_25( IP_Z[25] ),
	.z_in_col_26( IP_Z[26] ),
	.z_in_col_27( IP_Z[27] ),
	.z_in_col_28( IP_Z[28] ),
	.z_in_col_29( IP_Z[29] ),
	.z_in_col_30( IP_Z[30] ),
	.z_in_col_31( IP_Z[31] )
);

endmodule
