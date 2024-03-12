`timescale 1ns / 1ps
`default_nettype none

parameter FRAC_BITS = 8'd13;

module isp_parser (
	input clock,
	input reset_n,
	
	input [31:0] opb_word,
	
	input [2:0] type_cnt,
	
	input [23:0] poly_addr,
	input render_poly,
	
	input vram_wait,
	input vram_valid,
	output reg isp_vram_rd,
	output reg isp_vram_wr,
	output reg [23:0] isp_vram_addr_out,
	input [63:0] isp_vram_din,
	output reg [63:0] isp_vram_dout,
	
	output reg isp_entry_valid,
	
	output reg [22:0] fb_addr,
	output reg [31:0] fb_writedata,
	output reg fb_we,

	input ra_entry_valid,
	input tile_prims_done,
	
	output reg poly_drawn,

	input reg [5:0] tilex,
	input reg [5:0] tiley,
	
	input [31:0] TEXT_CONTROL,	// From TEXT_CONTROL reg.
	input  [1:0] PAL_RAM_CTRL,	// From PAL_RAM_CTRL reg, bits [1:0].
	
	input [15:0] pal_addr,
	input [31:0] pal_din,
	input pal_rd,
	input pal_wr,
	output [31:0] pal_dout
);

reg [23:0] isp_vram_addr;
reg tex_other;
																										// Output thingy addr, when reading Texture or VQ codebook.
assign isp_vram_addr_out = ((isp_state>=8'd49 && isp_state<=8'd54) || isp_state==5 || isp_state==80) ? {tex_other, vram_word_addr[19:0]}<<2 :	
																												  isp_vram_addr;	// Output ISP Parser BYTE address.

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
(*noprune*)reg [7:0] isp_state;
(*noprune*)reg [2:0] strip_cnt;
(*noprune*)reg [3:0] array_cnt;

wire is_tri_strip  = !opb_word[31];
wire is_tri_array  = opb_word[31:29]==3'b100;
wire is_quad_array = opb_word[31:29]==3'b101;

reg quad_done;

reg [23:0] isp_vram_addr_last;

reg latch_cb;

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
	latch_cb <= 1'b0;
	prev_tex_word_addr <= 21'h1FFFFF;	// "Random" arbitrary address to start with.
end
else begin
	fb_we <= 1'b0;
	
	isp_entry_valid <= 1'b0;
	poly_drawn <= 1'b0;
	
	read_codebook <= 1'b0;
	latch_cb <= 1'b0;

	if (isp_vram_rd & !vram_wait) isp_vram_rd <= 1'b0;
	if (isp_vram_wr & !vram_wait) isp_vram_wr <= 1'b0;
	
	case (isp_state)
		0: begin
			if (render_poly) begin
				isp_vram_addr <= poly_addr;
				strip_cnt <= 3'd0;
				array_cnt <= 4'd0;
				vert_d_x <= 32'd0;
				vert_d_y <= 32'd0;
				vert_d_z <= 32'd0;
				vert_d_u0 <= 32'd0;
				vert_d_v0 <= 32'd0;
				isp_state <= isp_state + 8'd1;
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
				isp_vram_rd <= 1'b1;
				isp_state <= 8'd2;
			end
			else begin
				poly_drawn <= 1'b1;	// No idea which prim type, so skip!
				isp_state <= 8'd0;
			end
		end
		
		2: if (vram_valid) begin isp_inst <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1;  isp_state <= isp_state + 8'd1; end
		3: if (vram_valid) begin tsp_inst <= isp_vram_din; isp_vram_addr <= isp_vram_addr + 4; isp_vram_rd <= 1'b1;  isp_state <= isp_state + 8'd1; end
		4: if (vram_valid) begin
			tcw_word <= isp_vram_din;
			if (isp_vram_din[30] && prev_tex_word_addr != isp_vram_din[20:0]) begin	// Quite a big speed-up, just by checking if the texture addr has changed.
				prev_tex_word_addr <= isp_vram_din[20:0];							// No point reading the codebook again, if the texture addr is the same as the last poly.
				read_codebook <= 1'b1;	// Read VQ Code Book if TCW bit 30 is set.
				tex_other <= 1'b0;
				isp_state <= 8'd80;
			end
			else begin
				prev_tex_word_addr <= isp_vram_din[20:0];
				isp_state <= 8'd6;
			end
		end
		
		80: begin
			isp_vram_rd <= 1'b1;
			isp_state <= 8'd5;
		end
		
		5: begin
			if (!codebook_wait) isp_state <= 8'd6;
			else if (vram_valid) begin
				if (!tex_other) tex_vram_word[31:0] <= isp_vram_din[31:0];
				else begin
					tex_vram_word[63:32] <= isp_vram_din[31:0];
					latch_cb <= 1'b1;
				end
				tex_other <= ~tex_other;
				isp_state <= 8'd80;		// Jump back.
			end
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
		
		47: begin
			if (is_tri_strip && strip_cnt[0]) begin		// Swap verts A and B, for all ODD strip segments.
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
			
			// Per-tile rendering.
			// leading_zeros was often causing it to skip the first tile row, due to processing delay maybe?...
			// (leading_zeros often starting as 31, which was skipping x_ps to the end of the first tile row.
			//  this would causing horizontal lines across the whole image. ElectronAsh.)
			x_ps <= (tilex<<5) /*+ leading_zeros*/;	// Disabled for now.
			y_ps <= tiley<<5;
			
			isp_vram_addr <= isp_vram_addr + 4;	// I think this is needed, to make isp_vram_addr_last correct in isp_state 49!
			isp_state <= 8'd49;			// Draw the triangle!
		end
		
		48: begin
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
					else begin	// Triangle Array is done.
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
			isp_vram_addr_last <= isp_vram_addr;
			
			// Half-edge constants (setup).
			//int C1 = FDY12 * FX1 - FDX12 * FY1;
			mult1 <= (FDY12_FIXED*FX1_FIXED)>>FRAC_BITS;
			mult2 <= (FDX12_FIXED*FY1_FIXED)>>FRAC_BITS;

			//int C2 = FDY23 * FX2 - FDX23 * FY2;
			mult3 <= (FDY23_FIXED*FX2_FIXED)>>FRAC_BITS;
			mult4 <= (FDX23_FIXED*FY2_FIXED)>>FRAC_BITS;

			//int C3 = FDY31 * FX3 - FDX31 * FY3;
			mult5 <= (FDY31_FIXED*FX3_FIXED)>>FRAC_BITS;
			mult6 <= (FDX31_FIXED*FY3_FIXED)>>FRAC_BITS;
			
			//int C4 = FDY41 * FX4 - FDX41 * FY4;
			mult7 <= (is_quad_array) ? (FDY41_FIXED*FX4_FIXED)>>FRAC_BITS : 1<<FRAC_BITS;
			mult8 <= (is_quad_array) ? (FDX41_FIXED*FY4_FIXED)>>FRAC_BITS : 1<<FRAC_BITS;

			isp_state <= isp_state + 8'd1;
		end

		50: begin
			if (y_ps < (tiley<<5)+32) begin
				// inTri==0 check, gives us roughly 2 FPS speedup, by skipping rows with no span. ;)
				if (x_ps == (tilex<<5)+32 /*|| x_ps[4:0]==32-trailing_zeros || inTri==32'b0*/) begin
					x_ps <= (tilex<<5) /*+ leading_zeros*/;
					y_ps <= y_ps + 12'd1;
					isp_state <= 8'd51;		// Had to add an extra clock tick, to allow the VRAM address and texture stuff to update.
											// (fixed the thin vertical lines on the renders. ElectronAsh).
				end
				else begin	// Inc x_ps. Write pixel to Framebuffer if inTri bit is set.
					//if (inTri[x_ps[4:0]] /*&& allow_z_write[x_ps[4:0]]*/) fb_we <= 1'b1;
					x_ps <= x_ps + 12'd1;
					tex_other <= 1'b0;
					isp_vram_rd <= 1'b1;
					isp_state <= 8'd52;
				end
			end
			else begin	// End of tile, for this poly.
				isp_vram_addr <= isp_vram_addr_last;
				isp_state <= 8'd48;
			end
		end
		
		51: begin
			x_ps <= (tilex<<5) /*+ leading_zeros*/;
			isp_state <= 8'd50;		// Jump back,
		end			
		
		52: if (vram_valid) begin
			tex_vram_word[31:0] <= isp_vram_din[31:0];
			tex_other <= 1'b1;
			isp_vram_rd <= 1'b1;
			isp_state <= 8'd53;
		end
		
		53: if (vram_valid) begin
			tex_vram_word[63:32] <= isp_vram_din[31:0];
			tex_other <= 1'b0;
			isp_state <= 8'd54;
		end
		
		54: begin
			//if ( inTri[ x_ps[4:0] ] ) begin
			if ( inTriangle ) begin
				fb_addr <= x_ps + (y_ps * 640);	// Framebuffer write address.
				fb_writedata <= final_argb;
				fb_we <= 1'b1;							// The (current) SDRAM controller does a Write on the Rising edge of fb_we, so need to pulse it.
			end											// ie. Can't just hold it high through multiple pixels.
			isp_state <= 8'd50;
		end

		default: ;
	endcase
end

wire [7:0] vert_words = (two_volume&shadow) ? ((skip*2)+3) : (skip+3);

reg [63:0] tex_vram_word;


(*keep*)wire signed [63:0] f_area = ((FX1_FIXED-FX3_FIXED) * (FY2_FIXED-FY3_FIXED)) - ((FY1_FIXED-FY3_FIXED) * (FX2_FIXED-FX3_FIXED));
(*keep*)wire sgn = f_area[63];

// Vertex deltas...
(*keep*)wire signed [47:0] FDX12_FIXED = (sgn) ? (FX1_FIXED - FX2_FIXED) : (FX2_FIXED - FX1_FIXED);
(*keep*)wire signed [47:0] FDX23_FIXED = (sgn) ? (FX2_FIXED - FX3_FIXED) : (FX3_FIXED - FX2_FIXED);
(*keep*)wire signed [47:0] FDX31_FIXED = (is_quad_array) ? sgn ? (FX3_FIXED - FX4_FIXED) : (FX4_FIXED - FX3_FIXED) : sgn ? (FX3_FIXED - FX1_FIXED) : (FX1_FIXED - FX3_FIXED);
(*keep*)wire signed [47:0] FDX41_FIXED = (is_quad_array) ? sgn ? (FX4_FIXED - FX1_FIXED) : (FX1_FIXED - FX4_FIXED) : 0;

(*keep*)wire signed [47:0] FDY12_FIXED = sgn ? (FY1_FIXED - FY2_FIXED) : (FY2_FIXED - FY1_FIXED);
(*keep*)wire signed [47:0] FDY23_FIXED = sgn ? (FY2_FIXED - FY3_FIXED) : (FY3_FIXED - FY2_FIXED);
(*keep*)wire signed [47:0] FDY31_FIXED = (is_quad_array) ? sgn ? (FY3_FIXED - FY4_FIXED) : (FY4_FIXED - FY3_FIXED) : sgn ? (FY3_FIXED - FY1_FIXED) : (FY1_FIXED - FY3_FIXED);
(*keep*)wire signed [47:0] FDY41_FIXED = (is_quad_array) ? sgn ? (FY4_FIXED - FY1_FIXED) : (FY1_FIXED - FY4_FIXED) : 0;


// Vertex float-to-fixed conversion...
(*keep*)wire signed [47:0] FX1_FIXED;
float_to_fixed  float_x1 (
	.float_in( vert_a_x ),	// input [31:0]  float_in
	.fixed( FX1_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FY1_FIXED;
float_to_fixed  float_y1 (
	.float_in( vert_a_y ),	// input [31:0]  float_in
	.fixed( FY1_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FZ1_FIXED;
float_to_fixed  float_z1 (
	.float_in( vert_a_z ),	// input [31:0]  float_in
	.fixed( FZ1_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FU1_FIXED;
float_to_fixed  float_u1 (
	.float_in( vert_a_u0 ),	// input [31:0]  float_in
	.fixed( FU1_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FV1_FIXED;
float_to_fixed  float_v1 (
	.float_in( vert_a_v0 ),	// input [31:0]  float_in
	.fixed( FV1_FIXED )		// output [31:0]  fixed
);

(*keep*)wire signed [47:0] FX2_FIXED;
float_to_fixed  float_x2 (
	.float_in( vert_b_x ),	// input [31:0]  float_in
	.fixed( FX2_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FY2_FIXED;
float_to_fixed  float_y2 (
	.float_in( vert_b_y ),	// input [31:0]  float_in
	.fixed( FY2_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FZ2_FIXED;
float_to_fixed  float_z2 (
	.float_in( vert_b_z ),	// input [31:0]  float_in
	.fixed( FZ2_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FU2_FIXED;
float_to_fixed  float_u2 (
	.float_in( vert_b_u0 ),	// input [31:0]  float_in
	.fixed( FU2_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FV2_FIXED;
float_to_fixed  float_v2 (
	.float_in( vert_b_v0 ),	// input [31:0]  float_in
	.fixed( FV2_FIXED )		// output [31:0]  fixed
);

(*keep*)wire signed [47:0] FX3_FIXED;
float_to_fixed  float_x3 (
	.float_in( vert_c_x ),	// input [31:0]  float_in
	.fixed( FX3_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FY3_FIXED;
float_to_fixed  float_y3 (
	.float_in( vert_c_y ),	// input [31:0]  float_in
	.fixed( FY3_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FZ3_FIXED;
float_to_fixed  float_z3 (
	.float_in( vert_c_z ),	// input [31:0]  float_in
	.fixed( FZ3_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FU3_FIXED;
float_to_fixed  float_u3 (
	.float_in( vert_c_u0 ),	// input [31:0]  float_in
	.fixed( FU3_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FV3_FIXED;
float_to_fixed  float_v3 (
	.float_in( vert_c_v0 ),	// input [31:0]  float_in
	.fixed( FV3_FIXED )		// output [31:0]  fixed
);

(*keep*)wire signed [47:0] FX4_FIXED;
float_to_fixed  float_x4 (
	.float_in( vert_d_x ),	// input [31:0]  float_in
	.fixed( FX4_FIXED )		// output [31:0]  fixed
);
(*keep*)wire signed [47:0] FY4_FIXED;
float_to_fixed  float_y4 (
	.float_in( vert_d_y ),	// input [31:0]  float_in
	.fixed( FY4_FIXED )		// output [31:0]  fixed
);


reg [10:0] x_ps;
reg [10:0] y_ps;

// Half-edge constants
// Setup phase...
//int C1 = FDY12 * FX1 - FDX12 * FY1;
reg signed [63:0] mult1;
reg signed [63:0] mult2;
wire signed [63:0] C1 = (mult1 - mult2);

//int C2 = FDY23 * FX2 - FDX23 * FY2;
reg signed [63:0] mult3;
reg signed [63:0] mult4;
wire signed [63:0] C2 = (mult3 - mult4);

//int C3 = FDY31 * FX3 - FDX31 * FY3;
reg signed [63:0] mult5;
reg signed [63:0] mult6;
wire signed [63:0] C3 = (mult5 - mult6);

//int C4 = FDY41 * FX4 - FDX41 * FY4;
reg signed [63:0] mult7;
reg signed [63:0] mult8;
wire signed [63:0] C4 = (is_quad_array) ? (mult7 - mult8) : 1;	// 1? C4 is fixed-point, no? todo: FIX! ElectronAsh.

//int Xhs12 = C1 + MUL_PREC(FDX12, y_ps<<FRAC_BITS, FRAC_BITS) - MUL_PREC(FDY12, x_ps<<FRAC_BITS, FRAC_BITS);
//int Xhs23 = C2 + MUL_PREC(FDX23, y_ps<<FRAC_BITS, FRAC_BITS) - MUL_PREC(FDY23, x_ps<<FRAC_BITS, FRAC_BITS);
//int Xhs31 = C3 + MUL_PREC(FDX31, y_ps<<FRAC_BITS, FRAC_BITS) - MUL_PREC(FDY31, x_ps<<FRAC_BITS, FRAC_BITS);

// "Realtime" calcs, based on x_ps and y_ps...
//
inTri_calc  inTri_calc_inst (
	.C1( C1 ),	// input signed [63:0]  C1
	.C2( C2 ),	// input signed [63:0]  C2
	.C3( C3 ),	// input signed [63:0]  C3
	.C4( C4 ),	// input signed [63:0]  C4
	
	.FDX12( FDX12_FIXED ),	// input signed [47:0]  FDX12
	.FDX23( FDX23_FIXED ),	// input signed [47:0]  FDX23
	.FDX31( FDX31_FIXED ),	// input signed [47:0]  FDX31
	.FDX41( FDX41_FIXED ),	// input signed [47:0]  FDX41
	
	.FDY12( FDY12_FIXED ),	// input signed [47:0]  FDX12
	.FDY23( FDY23_FIXED ),	// input signed [47:0]  FDY23
	.FDY31( FDY31_FIXED ),	// input signed [47:0]  FDY31
	.FDY41( FDY41_FIXED ),	// input signed [47:0]  FDY41

	.x_ps( {1'b0, x_ps[9:0]} ),
	.y_ps( {1'b0, y_ps[9:0]} ),
	
	.inTriangle( inTriangle ),	// output inTriangle
	
	.inTri( inTri ),	// output [31:0]  inTri
	
	.leading_zeros( leading_zeros ),	// output [4:0]  leading_zeros
	.trailing_zeros( trailing_zeros )	// output [4:0]  trailing_zeros
);

(*keep*)wire inTriangle;
(*keep*)wire [31:0] inTri;

wire [4:0] leading_zeros;
wire [4:0] trailing_zeros;


// Z.Setup(x1,x2,x3, y1,y2,y3, z1,z2,z3);
/*
interp  interp_inst_z (
	.clock( clock ),			// input  clock
	.setup( isp_entry_valid ),	// input  setup
	
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
	
	.x_ps( {1'b0, x_ps[9:0]} ),		// input signed [10:0] x_ps
	.y_ps( {1'b0, y_ps[9:0]} ),		// input signed [10:0] y_ps
	
	.interp( IP_Z_INTERP ),	// output signed [31:0]  interp

	.interp0(  IP_Z[0] ),  .interp1(  IP_Z[1] ),  .interp2(  IP_Z[2] ),  .interp3(  IP_Z[3] ),  .interp4(  IP_Z[4] ),  .interp5(  IP_Z[5] ),  .interp6(  IP_Z[6] ),  .interp7(  IP_Z[7] ),
	.interp8(  IP_Z[8] ),  .interp9(  IP_Z[9] ),  .interp10( IP_Z[10] ), .interp11( IP_Z[11] ), .interp12( IP_Z[12] ), .interp13( IP_Z[13] ), .interp14( IP_Z[14] ), .interp15( IP_Z[15] ),
	.interp16( IP_Z[16] ), .interp17( IP_Z[17] ), .interp18( IP_Z[18] ), .interp19( IP_Z[19] ), .interp20( IP_Z[20] ), .interp21( IP_Z[21] ), .interp22( IP_Z[22] ), .interp23( IP_Z[23] ),
	.interp24( IP_Z[24] ), .interp25( IP_Z[25] ), .interp26( IP_Z[26] ), .interp27( IP_Z[27] ), .interp28( IP_Z[28] ), .interp29( IP_Z[29] ), .interp30( IP_Z[30] ), .interp31( IP_Z[31] )
);
*/
wire signed [31:0] IP_Z_INTERP = FZ2_FIXED;
wire signed [31:0] IP_Z [0:31];	// [0:31] is the tile COLUMN.


// int w = tex_u_size_full;
// U.Setup(x1,x2,x3, y1,y2,y3, u1*w*z1, u2*w*z2, u3*w*z3);
//
wire signed [63:0] u1_mult_width = FU1_FIXED * tex_u_size_full;	// Don't need to shift right after, as tex_u_size_full is not fixed-point?
wire signed [63:0] u2_mult_width = FU2_FIXED * tex_u_size_full;
wire signed [63:0] u3_mult_width = FU3_FIXED * tex_u_size_full;

interp  interp_inst_u (
	.clock( clock ),			// input  clock
	.setup( isp_entry_valid ),	// input  setup
	
	.FRAC_BITS( FRAC_BITS ),	// input [7:0] FRAC_BITS

	.FX1( FX1_FIXED ),		// input signed [31:0] x1
	.FX2( FX2_FIXED ),		// input signed [31:0] x2
	.FX3( FX3_FIXED ),		// input signed [31:0] x3
	
	.FY1( FY1_FIXED ),		// input signed [31:0] y1
	.FY2( FY2_FIXED ),		// input signed [31:0] y2
	.FY3( FY3_FIXED ),		// input signed [31:0] y3
	
	.FZ1( (u1_mult_width * FZ1_FIXED) >>FRAC_BITS ),	// input signed [31:0] z1
	.FZ2( (u2_mult_width * FZ2_FIXED) >>FRAC_BITS ),	// input signed [31:0] z2
	.FZ3( (u3_mult_width * FZ3_FIXED) >>FRAC_BITS ),	// input signed [31:0] z3
	
	.x_ps( {1'b0, x_ps[9:0]} ),		// input signed [11:0] x_ps
	.y_ps( {1'b0, y_ps[9:0]} ),		// input signed [11:0] y_ps
	
	.interp( IP_U_INTERP ),	// output signed [31:0]  interp

	.interp0(  IP_U[0] ),  .interp1(  IP_U[1] ),  .interp2(  IP_U[2] ),  .interp3(  IP_U[3] ),  .interp4(  IP_U[4] ),  .interp5(  IP_U[5] ),  .interp6(  IP_U[6] ),  .interp7(  IP_U[7] ),
	.interp8(  IP_U[8] ),  .interp9(  IP_U[9] ),  .interp10( IP_U[10] ), .interp11( IP_U[11] ), .interp12( IP_U[12] ), .interp13( IP_U[13] ), .interp14( IP_U[14] ), .interp15( IP_U[15] ),
	.interp16( IP_U[16] ), .interp17( IP_U[17] ), .interp18( IP_U[18] ), .interp19( IP_U[19] ), .interp20( IP_U[20] ), .interp21( IP_U[21] ), .interp22( IP_U[22] ), .interp23( IP_U[23] ),
	.interp24( IP_U[24] ), .interp25( IP_U[25] ), .interp26( IP_U[26] ), .interp27( IP_U[27] ), .interp28( IP_U[28] ), .interp29( IP_U[29] ), .interp30( IP_U[30] ), .interp31( IP_U[31] )
);

wire signed [31:0] IP_U_INTERP /*= FU2_FIXED * tex_u_size_full*/;
wire signed [31:0] IP_U [0:31];	// [0:31] is the tile COLUMN.


// int h = tex_v_size_full;
// V.Setup(x1,x2,x3, y1,y2,y3, v1*h*z1, v2*h*z2, v3*h*z3);
//
wire signed [63:0] v1_mult_height = FV1_FIXED * tex_v_size_full;	// Don't need to shift right after, as tex_v_size_full is not fixed-point?
wire signed [63:0] v2_mult_height = FV2_FIXED * tex_v_size_full;
wire signed [63:0] v3_mult_height = FV3_FIXED * tex_v_size_full;

interp  interp_inst_v (
	.clock( clock ),			// input  clock
	.setup( isp_entry_valid ),	// input  setup
	
	.FRAC_BITS( FRAC_BITS ),	// input [7:0] FRAC_BITS

	.FX1( FX1_FIXED ),		// input signed [31:0] x1
	.FX2( FX2_FIXED ),		// input signed [31:0] x2
	.FX3( FX3_FIXED ),		// input signed [31:0] x3
	
	.FY1( FY1_FIXED ),		// input signed [31:0] y1
	.FY2( FY2_FIXED ),		// input signed [31:0] y2
	.FY3( FY3_FIXED ),		// input signed [31:0] y3
	
	.FZ1( (v1_mult_height * FZ1_FIXED) >>FRAC_BITS ),	// input signed [31:0] z1
	.FZ2( (v2_mult_height * FZ2_FIXED) >>FRAC_BITS ),	// input signed [31:0] z2
	.FZ3( (v3_mult_height * FZ3_FIXED) >>FRAC_BITS ),	// input signed [31:0] z3
	
	.x_ps( {1'b0, x_ps[9:0]} ),		// input signed [11:0] x_ps
	.y_ps( {1'b0, y_ps[9:0]} ),		// input signed [11:0] y_ps
	
	.interp( IP_V_INTERP ),	// output signed [31:0]  interp

	.interp0(  IP_V[0] ),  .interp1(  IP_V[1] ),  .interp2(  IP_V[2] ),  .interp3(  IP_V[3] ),  .interp4(  IP_V[4] ),  .interp5(  IP_V[5] ),  .interp6(  IP_V[6] ),  .interp7(  IP_V[7] ),
	.interp8(  IP_V[8] ),  .interp9(  IP_V[9] ),  .interp10( IP_V[10] ), .interp11( IP_V[11] ), .interp12( IP_V[12] ), .interp13( IP_V[13] ), .interp14( IP_V[14] ), .interp15( IP_V[15] ),
	.interp16( IP_V[16] ), .interp17( IP_V[17] ), .interp18( IP_V[18] ), .interp19( IP_V[19] ), .interp20( IP_V[20] ), .interp21( IP_V[21] ), .interp22( IP_V[22] ), .interp23( IP_V[23] ),
	.interp24( IP_V[24] ), .interp25( IP_V[25] ), .interp26( IP_V[26] ), .interp27( IP_V[27] ), .interp28( IP_V[28] ), .interp29( IP_V[29] ), .interp30( IP_V[30] ), .interp31( IP_V[31] )
);

wire signed [31:0] IP_V_INTERP /*= FV2_FIXED * tex_v_size_full*/;
wire signed [31:0] IP_V [0:31];	// [0:31] is the tile COLUMN.

/*
always @(*) begin
	case (x_ps[4:0])
		 0:	u_div_z_fixed = (IP_U[0] <<FRAC_BITS) / IP_Z[0];
		 1:	u_div_z_fixed = (IP_U[1] <<FRAC_BITS) / IP_Z[1];
		 2:	u_div_z_fixed = (IP_U[2] <<FRAC_BITS) / IP_Z[2];
		 3:	u_div_z_fixed = (IP_U[3] <<FRAC_BITS) / IP_Z[3];
		 4:	u_div_z_fixed = (IP_U[4] <<FRAC_BITS) / IP_Z[4];
		 5:	u_div_z_fixed = (IP_U[5] <<FRAC_BITS) / IP_Z[5];
		 6:	u_div_z_fixed = (IP_U[6] <<FRAC_BITS) / IP_Z[6];
		 7:	u_div_z_fixed = (IP_U[7] <<FRAC_BITS) / IP_Z[7];
		 8:	u_div_z_fixed = (IP_U[8] <<FRAC_BITS) / IP_Z[8];
		 9:	u_div_z_fixed = (IP_U[9] <<FRAC_BITS) / IP_Z[9];
		10:	u_div_z_fixed = (IP_U[10]<<FRAC_BITS) / IP_Z[10];
		11:	u_div_z_fixed = (IP_U[11]<<FRAC_BITS) / IP_Z[11];
		12:	u_div_z_fixed = (IP_U[12]<<FRAC_BITS) / IP_Z[12];
		13:	u_div_z_fixed = (IP_U[13]<<FRAC_BITS) / IP_Z[13];
		14:	u_div_z_fixed = (IP_U[14]<<FRAC_BITS) / IP_Z[14];
		15:	u_div_z_fixed = (IP_U[15]<<FRAC_BITS) / IP_Z[15];
		16:	u_div_z_fixed = (IP_U[16]<<FRAC_BITS) / IP_Z[16];
		17:	u_div_z_fixed = (IP_U[17]<<FRAC_BITS) / IP_Z[17];
		18:	u_div_z_fixed = (IP_U[18]<<FRAC_BITS) / IP_Z[18];
		19:	u_div_z_fixed = (IP_U[19]<<FRAC_BITS) / IP_Z[19];
		20:	u_div_z_fixed = (IP_U[20]<<FRAC_BITS) / IP_Z[20];
		21:	u_div_z_fixed = (IP_U[21]<<FRAC_BITS) / IP_Z[21];
		22:	u_div_z_fixed = (IP_U[22]<<FRAC_BITS) / IP_Z[22];
		23:	u_div_z_fixed = (IP_U[23]<<FRAC_BITS) / IP_Z[23];
		24:	u_div_z_fixed = (IP_U[24]<<FRAC_BITS) / IP_Z[24];
		25:	u_div_z_fixed = (IP_U[25]<<FRAC_BITS) / IP_Z[25];
		26:	u_div_z_fixed = (IP_U[26]<<FRAC_BITS) / IP_Z[26];
		27:	u_div_z_fixed = (IP_U[27]<<FRAC_BITS) / IP_Z[27];
		28:	u_div_z_fixed = (IP_U[28]<<FRAC_BITS) / IP_Z[28];
		29:	u_div_z_fixed = (IP_U[29]<<FRAC_BITS) / IP_Z[29];
		30:	u_div_z_fixed = (IP_U[30]<<FRAC_BITS) / IP_Z[30];
		31:	u_div_z_fixed = (IP_U[31]<<FRAC_BITS) / IP_Z[31];
	endcase

	case (x_ps[4:0])
		 0:	v_div_z_fixed = (IP_V[0] <<FRAC_BITS) / IP_Z[0];
		 1:	v_div_z_fixed = (IP_V[1] <<FRAC_BITS) / IP_Z[1];
		 2:	v_div_z_fixed = (IP_V[2] <<FRAC_BITS) / IP_Z[2];
		 3:	v_div_z_fixed = (IP_V[3] <<FRAC_BITS) / IP_Z[3];
		 4:	v_div_z_fixed = (IP_V[4] <<FRAC_BITS) / IP_Z[4];
		 5:	v_div_z_fixed = (IP_V[5] <<FRAC_BITS) / IP_Z[5];
		 6:	v_div_z_fixed = (IP_V[6] <<FRAC_BITS) / IP_Z[6];
		 7:	v_div_z_fixed = (IP_V[7] <<FRAC_BITS) / IP_Z[7];
		 8:	v_div_z_fixed = (IP_V[8] <<FRAC_BITS) / IP_Z[8];
		 9:	v_div_z_fixed = (IP_V[9] <<FRAC_BITS) / IP_Z[9];
		10:	v_div_z_fixed = (IP_V[10]<<FRAC_BITS) / IP_Z[10];
		11:	v_div_z_fixed = (IP_V[11]<<FRAC_BITS) / IP_Z[11];
		12:	v_div_z_fixed = (IP_V[12]<<FRAC_BITS) / IP_Z[12];
		13:	v_div_z_fixed = (IP_V[13]<<FRAC_BITS) / IP_Z[13];
		14:	v_div_z_fixed = (IP_V[14]<<FRAC_BITS) / IP_Z[14];
		15:	v_div_z_fixed = (IP_V[15]<<FRAC_BITS) / IP_Z[15];
		16:	v_div_z_fixed = (IP_V[16]<<FRAC_BITS) / IP_Z[16];
		17:	v_div_z_fixed = (IP_V[17]<<FRAC_BITS) / IP_Z[17];
		18:	v_div_z_fixed = (IP_V[18]<<FRAC_BITS) / IP_Z[18];
		19:	v_div_z_fixed = (IP_V[19]<<FRAC_BITS) / IP_Z[19];
		20:	v_div_z_fixed = (IP_V[20]<<FRAC_BITS) / IP_Z[20];
		21:	v_div_z_fixed = (IP_V[21]<<FRAC_BITS) / IP_Z[21];
		22:	v_div_z_fixed = (IP_V[22]<<FRAC_BITS) / IP_Z[22];
		23:	v_div_z_fixed = (IP_V[23]<<FRAC_BITS) / IP_Z[23];
		24:	v_div_z_fixed = (IP_V[24]<<FRAC_BITS) / IP_Z[24];
		25:	v_div_z_fixed = (IP_V[25]<<FRAC_BITS) / IP_Z[25];
		26:	v_div_z_fixed = (IP_V[26]<<FRAC_BITS) / IP_Z[26];
		27:	v_div_z_fixed = (IP_V[27]<<FRAC_BITS) / IP_Z[27];
		28:	v_div_z_fixed = (IP_V[28]<<FRAC_BITS) / IP_Z[28];
		29:	v_div_z_fixed = (IP_V[29]<<FRAC_BITS) / IP_Z[29];
		30:	v_div_z_fixed = (IP_V[30]<<FRAC_BITS) / IP_Z[30];
		31:	v_div_z_fixed = (IP_V[31]<<FRAC_BITS) / IP_Z[31];
	endcase
end
*/

wire signed [63:0] u_div_z_fixed = (IP_U_INTERP<<FRAC_BITS) / IP_Z_INTERP;
//reg signed [31:0] u_div_z_fixed;

wire signed [63:0] v_div_z_fixed = (IP_V_INTERP<<FRAC_BITS) / IP_Z_INTERP;
//reg signed [31:0] v_div_z_fixed;

wire signed [31:0] u_div_z = u_div_z_fixed >>FRAC_BITS;
wire signed [31:0] v_div_z = v_div_z_fixed >>FRAC_BITS;

// Highest value is 1024 (8<<7) so we need 11 bits to store it! ElectronAsh.
wire [10:0] tex_u_size_full = (8<<tex_u_size);
wire [10:0] tex_v_size_full = (8<<tex_v_size);

/*
	if (pp_Clamp) {			// clamp
		if (coord < 0) coord = 0;
		else if (coord >= size) coord = size-1;
	}
	else if (pp_Flip) {		// flip
		coord &= size*2-1;
		if (coord & size) coord ^= size*2-1;
	}
	else coord &= size-1;
*/

/* verilator lint_off LATCH */
/*
always @* begin
	if (tex_u_clamp) begin			// clamp
		if (u_div_z < 0) u_flipped = 0;
		else if (u_div_z >= tex_u_size_full) u_flipped = tex_u_size_full-1;
	end
	else if (tex_u_flip) begin		// flip
		u_flipped = u_div_z & ((tex_u_size_full*2)-1);
		if (u_div_z & tex_u_size_full) u_flipped ^= ((tex_u_size_full*2)-1);
	end
	else u_flipped = u_div_z & (tex_u_size_full-1);
	
	if (tex_v_clamp) begin			// clamp
		if (v_div_z < 0) v_flipped = 0;
		else if (v_div_z >= tex_v_size_full) v_flipped = tex_v_size_full-1;
	end
	else if (tex_v_flip) begin		// flip
		v_flipped = v_div_z & ((tex_v_size_full*2)-1);
		if (v_div_z & tex_v_size_full) v_flipped ^= ((tex_v_size_full*2)-1);
	end
	else v_flipped = v_div_z & (tex_v_size_full-1);
end
reg [9:0] u_flipped;
reg [9:0] v_flipped;
*/
/* verilator lint_on LATCH */

wire [9:0] u_clamp = (u_div_z<0) ? 10'd0 : 
		(u_div_z>=tex_u_size_full) ? tex_u_size_full-1 :
											  u_div_z;

wire [9:0] v_clamp = (v_div_z<0) ? 10'd0 :
		(v_div_z>=tex_v_size_full) ? tex_v_size_full-1 :
											  v_div_z;

wire [9:0] u_masked  = u_div_z&((tex_u_size_full*2)-1);
wire [9:0] v_masked  = v_div_z&((tex_v_size_full*2)-1);

wire [9:0] u_mask_flip = (u_masked&tex_u_size_full) ? u_masked^((tex_u_size_full*2)-1) : u_masked;
wire [9:0] v_mask_flip = (v_masked&tex_v_size_full) ? v_masked^((tex_u_size_full*2)-1) : v_masked;

wire [9:0] u_flipped = (tex_u_clamp) ? u_clamp :
							  (tex_u_flip)  ? u_mask_flip : u_div_z&(tex_u_size_full-1);

wire [9:0] v_flipped = (tex_v_clamp) ? v_clamp :
								(tex_v_flip) ? v_mask_flip : v_div_z&(tex_v_size_full-1);


texture_address  texture_address_inst (
	.clock( clock ),
	.reset_n( reset_n ),
	
	.isp_inst( isp_inst ),	// input [31:0]  isp_inst.
	.tsp_inst( tsp_inst ),	// input [31:0]  tsp_inst.
	.tcw_word( tcw_word ),	// input [31:0]  tcw_word.
	
	.TEXT_CONTROL( TEXT_CONTROL ),	// input [31:0]  TEXT_CONTROL.

	.PAL_RAM_CTRL( PAL_RAM_CTRL ),	// input from PAL_RAM_CTRL, bits [1:0].		
	.pal_addr( pal_addr ),				// input [15:0]  pal_addr
	.pal_din( pal_din ),					// input [31:0]  pal_din
	.pal_rd( pal_rd ),					// input  pal_rd
	.pal_wr( pal_wr ),					// input  pal_wr
	.pal_dout( pal_dout ),				// output [31:0]  pal_dout
	
	.read_codebook( read_codebook ),	// input  read_codebook
	.codebook_wait( codebook_wait ),	// output  codebook_wait
	.latch_cb( latch_cb ),				// input  latch_cb
	
	.ui( u_flipped ),
	.vi( v_flipped ),
	//.ui( sim_ui ),
	//.vi( sim_vi ),
	
	.vram_wait( vram_wait ),
	.vram_valid( vram_valid ),
	.vram_word_addr( vram_word_addr ),	// output [20:0]  vram_word_addr. 64-bit WORD address!
	.vram_din( tex_vram_word ),			// input [63:0]  vram_din. Full 64-bit data for texture reads.
	
	.base_argb( vert_c_base_col_0 ),	// input [31:0]  base_argb.  Flat-shading colour input. (will also do Gouraud eventually).
	.offs_argb( vert_c_off_col ),		// input [31:0]  offs_argb.  Offset colour input.
	
	.texel_argb( texel_argb ),			// output [31:0]  texel_argb. Texel ARGB 8888 output.
	.final_argb( final_argb )			// output [31:0]  final_argb. Final blended ARGB 8888 output.
);

reg read_codebook;
wire codebook_wait;

reg [9:0] sim_ui;
reg [9:0] sim_vi;

wire [20:0] vram_word_addr;

wire [31:0] texel_argb;
wire [31:0] final_argb;
//wire [31:0] final_argb = {8'hff, vert_b_base_col_0[23:0]};


// The registers below make up our 32x32 internal Z buffer.
//
// It's a bit hard to describe how the regs below relate to the mapping of the tile pixels, but here goes...
// 
// z_col_0[0] is the Z value for the top-left tile pixel.
// z_col_0[1] is the Z value for the tile pixel just below the top-left pixel, and so-on.
//
// z_col_1[0] is the top pixel for the next COLUMN along the tile.
//
// The [0:31] number basically selects the tile ROW.
//
/*
reg signed [31:0] z_col_0  [0:31];
reg signed [31:0] z_col_1  [0:31];
reg signed [31:0] z_col_2  [0:31];
reg signed [31:0] z_col_3  [0:31];
reg signed [31:0] z_col_4  [0:31];
reg signed [31:0] z_col_5  [0:31];
reg signed [31:0] z_col_6  [0:31];
reg signed [31:0] z_col_7  [0:31];

reg signed [31:0] z_col_8  [0:31];
reg signed [31:0] z_col_9  [0:31];
reg signed [31:0] z_col_10 [0:31];
reg signed [31:0] z_col_11 [0:31];
reg signed [31:0] z_col_12 [0:31];
reg signed [31:0] z_col_13 [0:31];
reg signed [31:0] z_col_14 [0:31];
reg signed [31:0] z_col_15 [0:31];

reg signed [31:0] z_col_16 [0:31];
reg signed [31:0] z_col_17 [0:31];
reg signed [31:0] z_col_18 [0:31];
reg signed [31:0] z_col_19 [0:31];
reg signed [31:0] z_col_20 [0:31];
reg signed [31:0] z_col_21 [0:31];
reg signed [31:0] z_col_22 [0:31];
reg signed [31:0] z_col_23 [0:31];

reg signed [31:0] z_col_24 [0:31];
reg signed [31:0] z_col_25 [0:31];
reg signed [31:0] z_col_26 [0:31];
reg signed [31:0] z_col_27 [0:31];
reg signed [31:0] z_col_28 [0:31];
reg signed [31:0] z_col_29 [0:31];
reg signed [31:0] z_col_30 [0:31];
reg signed [31:0] z_col_31 [0:31];


wire [31:0] allow_z_write;

reg z_clear_ena;
reg [5:0] z_clear_row;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	z_clear_ena <= 1'b0;
	z_clear_row <= 6'd0;
end
else begin
	if (ra_entry_valid) begin	// New tile started!...
		z_clear_row <= 6'd0;
		z_clear_ena <= 1'b1;
	end

	if (z_clear_ena) begin
		if (z_clear_row==6'd32) begin
			z_clear_ena <= 1'b0;
		end
		else begin
			z_col_0[  z_clear_row ] <= 32'd0;
			z_col_1[  z_clear_row ] <= 32'd0;
			z_col_2[  z_clear_row ] <= 32'd0;
			z_col_3[  z_clear_row ] <= 32'd0;
			z_col_4[  z_clear_row ] <= 32'd0;
			z_col_5[  z_clear_row ] <= 32'd0;
			z_col_6[  z_clear_row ] <= 32'd0;
			z_col_7[  z_clear_row ] <= 32'd0;
			z_col_8[  z_clear_row ] <= 32'd0;
			z_col_9[  z_clear_row ] <= 32'd0;
			z_col_10[ z_clear_row ] <= 32'd0;
			z_col_11[ z_clear_row ] <= 32'd0;
			z_col_12[ z_clear_row ] <= 32'd0;
			z_col_13[ z_clear_row ] <= 32'd0;
			z_col_14[ z_clear_row ] <= 32'd0;
			z_col_15[ z_clear_row ] <= 32'd0;
			z_col_16[ z_clear_row ] <= 32'd0;
			z_col_17[ z_clear_row ] <= 32'd0;
			z_col_18[ z_clear_row ] <= 32'd0;
			z_col_19[ z_clear_row ] <= 32'd0;
			z_col_20[ z_clear_row ] <= 32'd0;
			z_col_21[ z_clear_row ] <= 32'd0;
			z_col_22[ z_clear_row ] <= 32'd0;
			z_col_23[ z_clear_row ] <= 32'd0;
			z_col_24[ z_clear_row ] <= 32'd0;
			z_col_25[ z_clear_row ] <= 32'd0;
			z_col_26[ z_clear_row ] <= 32'd0;
			z_col_27[ z_clear_row ] <= 32'd0;
			z_col_28[ z_clear_row ] <= 32'd0;
			z_col_29[ z_clear_row ] <= 32'd0;
			z_col_30[ z_clear_row ] <= 32'd0;
			z_col_31[ z_clear_row ] <= 32'd0;
			z_clear_row <= z_clear_row + 5'd1;
		end
	end

	//if (isp_state==49 || isp_state==51)
	begin	// At the start of rendering each tile ROW...
		// Check the allow_z_write bits, to see if we should write the Z value from the new polygon into the Z buffer.
		// (for the whole tile ROW).
		if (allow_z_write[0])  z_col_0 [ y_ps[4:0] ] <= IP_Z[0];
		if (allow_z_write[1])  z_col_1 [ y_ps[4:0] ] <= IP_Z[1];
		if (allow_z_write[2])  z_col_2 [ y_ps[4:0] ] <= IP_Z[2];
		if (allow_z_write[3])  z_col_3 [ y_ps[4:0] ] <= IP_Z[3];
		if (allow_z_write[4])  z_col_4 [ y_ps[4:0] ] <= IP_Z[4];
		if (allow_z_write[5])  z_col_5 [ y_ps[4:0] ] <= IP_Z[5];
		if (allow_z_write[6])  z_col_6 [ y_ps[4:0] ] <= IP_Z[6];
		if (allow_z_write[7])  z_col_7 [ y_ps[4:0] ] <= IP_Z[7];
		if (allow_z_write[8])  z_col_8 [ y_ps[4:0] ] <= IP_Z[8];
		if (allow_z_write[9])  z_col_9 [ y_ps[4:0] ] <= IP_Z[9];
		if (allow_z_write[10]) z_col_10[ y_ps[4:0] ] <= IP_Z[10];
		if (allow_z_write[11]) z_col_11[ y_ps[4:0] ] <= IP_Z[11];
		if (allow_z_write[12]) z_col_12[ y_ps[4:0] ] <= IP_Z[12];
		if (allow_z_write[13]) z_col_13[ y_ps[4:0] ] <= IP_Z[13];
		if (allow_z_write[14]) z_col_14[ y_ps[4:0] ] <= IP_Z[14];
		if (allow_z_write[15]) z_col_15[ y_ps[4:0] ] <= IP_Z[15];
		if (allow_z_write[16]) z_col_16[ y_ps[4:0] ] <= IP_Z[16];
		if (allow_z_write[17]) z_col_17[ y_ps[4:0] ] <= IP_Z[17];
		if (allow_z_write[18]) z_col_18[ y_ps[4:0] ] <= IP_Z[18];
		if (allow_z_write[19]) z_col_19[ y_ps[4:0] ] <= IP_Z[19];
		if (allow_z_write[20]) z_col_20[ y_ps[4:0] ] <= IP_Z[20];
		if (allow_z_write[21]) z_col_21[ y_ps[4:0] ] <= IP_Z[21];
		if (allow_z_write[22]) z_col_22[ y_ps[4:0] ] <= IP_Z[22];
		if (allow_z_write[23]) z_col_23[ y_ps[4:0] ] <= IP_Z[23];
		if (allow_z_write[24]) z_col_24[ y_ps[4:0] ] <= IP_Z[24];
		if (allow_z_write[25]) z_col_25[ y_ps[4:0] ] <= IP_Z[25];
		if (allow_z_write[26]) z_col_26[ y_ps[4:0] ] <= IP_Z[26];
		if (allow_z_write[27]) z_col_27[ y_ps[4:0] ] <= IP_Z[27];
		if (allow_z_write[28]) z_col_28[ y_ps[4:0] ] <= IP_Z[28];
		if (allow_z_write[29]) z_col_29[ y_ps[4:0] ] <= IP_Z[29];
		if (allow_z_write[30]) z_col_30[ y_ps[4:0] ] <= IP_Z[30];
		if (allow_z_write[31]) z_col_31[ y_ps[4:0] ] <= IP_Z[31];
	end
end
*/

/*
depth_compare depth_compare_inst0 (
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( Z from buffer ),				// input [22:0]  old_z
	.invW( IP_Z_INTERP ),					// input [22:0]  invW
	.depth_allow( allow_z_write[0] )		// output depth_allow
);	
*/


/*
depth_compare depth_compare_inst0 (
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_0[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[0] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[0] )		// output depth_allow
);	
depth_compare depth_compare_inst1 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_1[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[1] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[1] )		// output depth_allow
);	
depth_compare depth_compare_inst2 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_2[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[2] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[2] )		// output depth_allow
);	
depth_compare depth_compare_inst3 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_3[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[3] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[3] )		// output depth_allow
);	
depth_compare depth_compare_inst4 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_4[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[4] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[4] )		// output depth_allow
);	
depth_compare depth_compare_inst5 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_5[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[5] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[5] )		// output depth_allow
);	
depth_compare depth_compare_inst6 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_6[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[6] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[6] )		// output depth_allow
);	
depth_compare depth_compare_inst7 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_7[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[7] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[7] )		// output depth_allow
);	
depth_compare depth_compare_inst8 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_8[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[8] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[8] )		// output depth_allow
);	
depth_compare depth_compare_inst9 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_9[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[9] ),							// input [22:0]  invW
	.depth_allow( allow_z_write[9] )		// output depth_allow
);	
depth_compare depth_compare_inst10 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_10[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[10] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[10] )	// output depth_allow
);	
depth_compare depth_compare_inst11 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_11[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[11] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[11] )	// output depth_allow
);	
depth_compare depth_compare_inst12 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_12[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[12] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[12] )	// output depth_allow
);	
depth_compare depth_compare_inst13 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_13[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[13] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[13] )	// output depth_allow
);	
depth_compare depth_compare_inst14 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_14[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[14] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[14] )	// output depth_allow
);	
depth_compare depth_compare_inst15 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_15[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[15] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[15] )	// output depth_allow
);	
depth_compare depth_compare_inst16 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_16[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[16] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[16] )	// output depth_allow
);	
depth_compare depth_compare_inst17 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_17[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[17] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[17] )	// output depth_allow
);	
depth_compare depth_compare_inst18 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_18[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[18] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[18] )	// output depth_allow
);	
depth_compare depth_compare_inst19 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_19[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[19] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[19] )	// output depth_allow
);	
depth_compare depth_compare_inst20 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_20[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[20] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[20] )	// output depth_allow
);	
depth_compare depth_compare_inst21 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_21[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[21] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[21] )	// output depth_allow
);	
depth_compare depth_compare_inst22 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_22[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[22] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[22] )	// output depth_allow
);	
depth_compare depth_compare_inst23 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_23[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[23] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[23] )	// output depth_allow
);	
depth_compare depth_compare_inst24 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_24[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[24] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[24] )	// output depth_allow
);	
depth_compare depth_compare_inst25 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_25[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[25] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[25] )	// output depth_allow
);	
depth_compare depth_compare_inst26 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_26[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[26] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[26] )	// output depth_allow
);	
depth_compare depth_compare_inst27 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_27[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[27] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[27] )	// output depth_allow
);	
depth_compare depth_compare_inst28 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_28[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[28] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[28] )	// output depth_allow
);	
depth_compare depth_compare_inst29 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_29[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[29] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[29] )	// output depth_allow
);	
depth_compare depth_compare_inst30 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_30[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[30] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[30] )	// output depth_allow
);	
depth_compare depth_compare_inst31 (	
	.depth_comp( depth_comp ),				// input [2:0]  depth_comp
	.old_z( z_col_31[ y_ps[4:0] ] ),		// input [22:0]  old_z
	.invW( IP_Z[31] ),						// input [22:0]  invW
	.depth_allow( allow_z_write[31] )	// output depth_allow
);
*/
endmodule


module inTri_calc (
	input signed [63:0] C1, C2, C3, C4,

	input signed [47:0] FDX12, FDY12,
	input signed [47:0] FDX23, FDY23,
	input signed [47:0] FDX31, FDY31,
	input signed [47:0] FDX41, FDY41,

	input signed [9:0] x_ps, y_ps,
	
	output reg inTriangle,
	
	output reg [31:0] inTri,
	
    output reg [4:0] leading_zeros,
    output reg [4:0] trailing_zeros
);

// No need to shift right after, since y_ps etc. are not fixed-point?
wire signed [63:0] mult9  = FDX12 * {1'b0, y_ps};
wire signed [63:0] mult11 = FDX23 * {1'b0, y_ps};
wire signed [63:0] mult13 = FDX31 * {1'b0, y_ps};
wire signed [63:0] mult15 = FDX41 * {1'b0, y_ps};

//wire signed [63:0] mult10 = FDY12 * {1'b0, x_ps};
//wire signed [63:0] mult12 = FDY23 * {1'b0, x_ps};
//wire signed [63:0] mult14 = FDY31 * {1'b0, x_ps};
//wire signed [63:0] mult16 = FDY41 * {1'b0, x_ps};

wire signed [47:0] Xhs12 = C1 + (mult9  - (FDY12 * {1'b0, x_ps}) );
wire signed [47:0] Xhs23 = C2 + (mult11 - (FDY23 * {1'b0, x_ps}) );
wire signed [47:0] Xhs31 = C3 + (mult13 - (FDY31 * {1'b0, x_ps}) );
wire signed [47:0] Xhs41 = C4 + (mult15 - (FDY41 * {1'b0, x_ps}) );

/*
wire signed [47:0] Xhs12_0 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd0}) );
wire signed [47:0] Xhs23_0 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd0}) );
wire signed [47:0] Xhs31_0 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd0}) );
wire signed [47:0] Xhs41_0 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd0}) );

wire signed [47:0] Xhs12_1 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd1}) );
wire signed [47:0] Xhs23_1 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd1}) );
wire signed [47:0] Xhs31_1 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd1}) );
wire signed [47:0] Xhs41_1 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd1}) );

wire signed [47:0] Xhs12_2 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd2}) );
wire signed [47:0] Xhs23_2 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd2}) );
wire signed [47:0] Xhs31_2 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd2}) );
wire signed [47:0] Xhs41_2 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd2}) );

wire signed [47:0] Xhs12_3 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd3}) );
wire signed [47:0] Xhs23_3 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd3}) );
wire signed [47:0] Xhs31_3 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd3}) );
wire signed [47:0] Xhs41_3 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd3}) );

wire signed [47:0] Xhs12_4 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd4}) );
wire signed [47:0] Xhs23_4 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd4}) );
wire signed [47:0] Xhs31_4 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd4}) );
wire signed [47:0] Xhs41_4 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd4}) );

wire signed [47:0] Xhs12_5 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd5}) );
wire signed [47:0] Xhs23_5 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd5}) );
wire signed [47:0] Xhs31_5 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd5}) );
wire signed [47:0] Xhs41_5 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd5}) );

wire signed [47:0] Xhs12_6 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd6}) );
wire signed [47:0] Xhs23_6 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd6}) );
wire signed [47:0] Xhs31_6 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd6}) );
wire signed [47:0] Xhs41_6 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd6}) );

wire signed [47:0] Xhs12_7 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd7}) );
wire signed [47:0] Xhs23_7 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd7}) );
wire signed [47:0] Xhs31_7 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd7}) );
wire signed [47:0] Xhs41_7 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd7}) );

wire signed [47:0] Xhs12_8 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd8}) );
wire signed [47:0] Xhs23_8 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd8}) );
wire signed [47:0] Xhs31_8 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd8}) );
wire signed [47:0] Xhs41_8 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd8}) );

wire signed [47:0] Xhs12_9 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd9}) );
wire signed [47:0] Xhs23_9 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd9}) );
wire signed [47:0] Xhs31_9 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd9}) );
wire signed [47:0] Xhs41_9 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd9}) );

wire signed [47:0] Xhs12_10 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd10}) );
wire signed [47:0] Xhs23_10 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd10}) );
wire signed [47:0] Xhs31_10 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd10}) );
wire signed [47:0] Xhs41_10 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd10}) );

wire signed [47:0] Xhs12_11 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd11}) );
wire signed [47:0] Xhs23_11 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd11}) );
wire signed [47:0] Xhs31_11 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd11}) );
wire signed [47:0] Xhs41_11 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd11}) );

wire signed [47:0] Xhs12_12 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd12}) );
wire signed [47:0] Xhs23_12 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd12}) );
wire signed [47:0] Xhs31_12 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd12}) );
wire signed [47:0] Xhs41_12 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd12}) );

wire signed [47:0] Xhs12_13 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd13}) );
wire signed [47:0] Xhs23_13 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd13}) );
wire signed [47:0] Xhs31_13 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd13}) );
wire signed [47:0] Xhs41_13 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd13}) );

wire signed [47:0] Xhs12_14 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd14}) );
wire signed [47:0] Xhs23_14 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd14}) );
wire signed [47:0] Xhs31_14 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd14}) );
wire signed [47:0] Xhs41_14 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd14}) );

wire signed [47:0] Xhs12_15 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd15}) );
wire signed [47:0] Xhs23_15 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd15}) );
wire signed [47:0] Xhs31_15 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd15}) );
wire signed [47:0] Xhs41_15 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd15}) );

wire signed [47:0] Xhs12_16 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd16}) );
wire signed [47:0] Xhs23_16 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd16}) );
wire signed [47:0] Xhs31_16 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd16}) );
wire signed [47:0] Xhs41_16 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd16}) );

wire signed [47:0] Xhs12_17 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd17}) );
wire signed [47:0] Xhs23_17 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd17}) );
wire signed [47:0] Xhs31_17 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd17}) );
wire signed [47:0] Xhs41_17 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd17}) );

wire signed [47:0] Xhs12_18 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd18}) );
wire signed [47:0] Xhs23_18 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd18}) );
wire signed [47:0] Xhs31_18 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd18}) );
wire signed [47:0] Xhs41_18 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd18}) );

wire signed [47:0] Xhs12_19 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd19}) );
wire signed [47:0] Xhs23_19 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd19}) );
wire signed [47:0] Xhs31_19 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd19}) );
wire signed [47:0] Xhs41_19 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd19}) );

wire signed [47:0] Xhs12_20 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd20}) );
wire signed [47:0] Xhs23_20 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd20}) );
wire signed [47:0] Xhs31_20 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd20}) );
wire signed [47:0] Xhs41_20 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd20}) );

wire signed [47:0] Xhs12_21 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd21}) );
wire signed [47:0] Xhs23_21 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd21}) );
wire signed [47:0] Xhs31_21 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd21}) );
wire signed [47:0] Xhs41_21 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd21}) );

wire signed [47:0] Xhs12_22 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd22}) );
wire signed [47:0] Xhs23_22 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd22}) );
wire signed [47:0] Xhs31_22 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd22}) );
wire signed [47:0] Xhs41_22 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd22}) );

wire signed [47:0] Xhs12_23 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd23}) );
wire signed [47:0] Xhs23_23 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd23}) );
wire signed [47:0] Xhs31_23 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd23}) );
wire signed [47:0] Xhs41_23 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd23}) );

wire signed [47:0] Xhs12_24 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd24}) );
wire signed [47:0] Xhs23_24 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd24}) );
wire signed [47:0] Xhs31_24 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd24}) );
wire signed [47:0] Xhs41_24 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd24}) );

wire signed [47:0] Xhs12_25 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd25}) );
wire signed [47:0] Xhs23_25 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd25}) );
wire signed [47:0] Xhs31_25 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd25}) );
wire signed [47:0] Xhs41_25 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd25}) );

wire signed [47:0] Xhs12_26 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd26}) );
wire signed [47:0] Xhs23_26 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd26}) );
wire signed [47:0] Xhs31_26 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd26}) );
wire signed [47:0] Xhs41_26 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd26}) );

wire signed [47:0] Xhs12_27 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd27}) );
wire signed [47:0] Xhs23_27 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd27}) );
wire signed [47:0] Xhs31_27 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd27}) );
wire signed [47:0] Xhs41_27 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd27}) );

wire signed [47:0] Xhs12_28 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd28}) );
wire signed [47:0] Xhs23_28 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd28}) );
wire signed [47:0] Xhs31_28 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd28}) );
wire signed [47:0] Xhs41_28 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd28}) );

wire signed [47:0] Xhs12_29 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd29}) );
wire signed [47:0] Xhs23_29 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd29}) );
wire signed [47:0] Xhs31_29 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd29}) );
wire signed [47:0] Xhs41_29 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd29}) );

wire signed [47:0] Xhs12_30 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd30}) );
wire signed [47:0] Xhs23_30 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd30}) );
wire signed [47:0] Xhs31_30 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd30}) );
wire signed [47:0] Xhs41_30 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd30}) );

wire signed [47:0] Xhs12_31 = C1 + (mult9  - (FDY12 * {1'b0, x_ps[9:5], 5'd31}) );
wire signed [47:0] Xhs23_31 = C2 + (mult11 - (FDY23 * {1'b0, x_ps[9:5], 5'd31}) );
wire signed [47:0] Xhs31_31 = C3 + (mult13 - (FDY31 * {1'b0, x_ps[9:5], 5'd31}) );
wire signed [47:0] Xhs41_31 = C4 + (mult15 - (FDY41 * {1'b0, x_ps[9:5], 5'd31}) );
*/
always @* begin
	inTriangle = !Xhs12[47]  && !Xhs23[47]  && !Xhs31[47]  && !Xhs41[47];
	/*
	inTri[0]  = !Xhs12_0[47]  && !Xhs23_0[47]  && !Xhs31_0[47]  && !Xhs41_0[47];
	inTri[1]  = !Xhs12_1[47]  && !Xhs23_1[47]  && !Xhs31_1[47]  && !Xhs41_1[47];
	inTri[2]  = !Xhs12_2[47]  && !Xhs23_2[47]  && !Xhs31_2[47]  && !Xhs41_2[47];
	inTri[3]  = !Xhs12_3[47]  && !Xhs23_3[47]  && !Xhs31_3[47]  && !Xhs41_3[47];
	inTri[4]  = !Xhs12_4[47]  && !Xhs23_4[47]  && !Xhs31_4[47]  && !Xhs41_4[47];
	inTri[5]  = !Xhs12_5[47]  && !Xhs23_5[47]  && !Xhs31_5[47]  && !Xhs41_5[47];
	inTri[6]  = !Xhs12_6[47]  && !Xhs23_6[47]  && !Xhs31_6[47]  && !Xhs41_6[47];
	inTri[7]  = !Xhs12_7[47]  && !Xhs23_7[47]  && !Xhs31_7[47]  && !Xhs41_7[47];
	inTri[8]  = !Xhs12_8[47]  && !Xhs23_8[47]  && !Xhs31_8[47]  && !Xhs41_8[47];
	inTri[9]  = !Xhs12_9[47]  && !Xhs23_9[47]  && !Xhs31_9[47]  && !Xhs41_9[47];
	inTri[10] = !Xhs12_1[47]  && !Xhs23_1[47]  && !Xhs31_1[47]  && !Xhs41_1[47];
	inTri[11] = !Xhs12_11[47] && !Xhs23_11[47] && !Xhs31_11[47] && !Xhs41_11[47];
	inTri[12] = !Xhs12_12[47] && !Xhs23_12[47] && !Xhs31_12[47] && !Xhs41_12[47];
	inTri[13] = !Xhs12_13[47] && !Xhs23_13[47] && !Xhs31_13[47] && !Xhs41_13[47];
	inTri[14] = !Xhs12_14[47] && !Xhs23_14[47] && !Xhs31_14[47] && !Xhs41_14[47];
	inTri[15] = !Xhs12_15[47] && !Xhs23_15[47] && !Xhs31_15[47] && !Xhs41_15[47];
	inTri[16] = !Xhs12_16[47] && !Xhs23_16[47] && !Xhs31_16[47] && !Xhs41_16[47];
	inTri[17] = !Xhs12_17[47] && !Xhs23_17[47] && !Xhs31_17[47] && !Xhs41_17[47];
	inTri[18] = !Xhs12_18[47] && !Xhs23_18[47] && !Xhs31_18[47] && !Xhs41_18[47];
	inTri[19] = !Xhs12_19[47] && !Xhs23_19[47] && !Xhs31_19[47] && !Xhs41_19[47];
	inTri[20] = !Xhs12_20[47] && !Xhs23_20[47] && !Xhs31_20[47] && !Xhs41_20[47];
	inTri[21] = !Xhs12_21[47] && !Xhs23_21[47] && !Xhs31_21[47] && !Xhs41_21[47];
	inTri[22] = !Xhs12_22[47] && !Xhs23_22[47] && !Xhs31_22[47] && !Xhs41_22[47];
	inTri[23] = !Xhs12_23[47] && !Xhs23_23[47] && !Xhs31_23[47] && !Xhs41_23[47];
	inTri[24] = !Xhs12_24[47] && !Xhs23_24[47] && !Xhs31_24[47] && !Xhs41_24[47];
	inTri[25] = !Xhs12_25[47] && !Xhs23_25[47] && !Xhs31_25[47] && !Xhs41_25[47];
	inTri[26] = !Xhs12_26[47] && !Xhs23_26[47] && !Xhs31_26[47] && !Xhs41_26[47];
	inTri[27] = !Xhs12_27[47] && !Xhs23_27[47] && !Xhs31_27[47] && !Xhs41_27[47];
	inTri[28] = !Xhs12_28[47] && !Xhs23_28[47] && !Xhs31_28[47] && !Xhs41_28[47];
	inTri[29] = !Xhs12_29[47] && !Xhs23_29[47] && !Xhs31_29[47] && !Xhs41_29[47];
	inTri[30] = !Xhs12_30[47] && !Xhs23_30[47] && !Xhs31_30[47] && !Xhs41_30[47];
	inTri[31] = !Xhs12_31[47] && !Xhs23_31[47] && !Xhs31_31[47] && !Xhs41_31[47];
	
		 if (inTri[30:00]==0) leading_zeros = 31;
	else if (inTri[29:00]==0) leading_zeros = 30;
	else if (inTri[28:00]==0) leading_zeros = 29;
	else if (inTri[27:00]==0) leading_zeros = 28;
	else if (inTri[26:00]==0) leading_zeros = 27;
	else if (inTri[25:00]==0) leading_zeros = 26;
	else if (inTri[24:00]==0) leading_zeros = 25;
	else if (inTri[23:00]==0) leading_zeros = 24;
	else if (inTri[22:00]==0) leading_zeros = 23;
	else if (inTri[21:00]==0) leading_zeros = 22;
	else if (inTri[20:00]==0) leading_zeros = 21;
	else if (inTri[19:00]==0) leading_zeros = 20;
	else if (inTri[18:00]==0) leading_zeros = 19;
	else if (inTri[17:00]==0) leading_zeros = 18;
	else if (inTri[16:00]==0) leading_zeros = 17;
	else if (inTri[15:00]==0) leading_zeros = 16;
	else if (inTri[14:00]==0) leading_zeros = 15;
	else if (inTri[13:00]==0) leading_zeros = 14;
	else if (inTri[12:00]==0) leading_zeros = 13;
	else if (inTri[11:00]==0) leading_zeros = 12;
	else if (inTri[10:00]==0) leading_zeros = 11;
	else if (inTri[09:00]==0) leading_zeros = 10;
	else if (inTri[08:00]==0) leading_zeros = 9;
	else if (inTri[07:00]==0) leading_zeros = 8;
	else if (inTri[06:00]==0) leading_zeros = 7;
	else if (inTri[05:00]==0) leading_zeros = 6;
	else if (inTri[04:00]==0) leading_zeros = 5;
	else if (inTri[03:00]==0) leading_zeros = 4;
	else if (inTri[02:00]==0) leading_zeros = 3;
	else if (inTri[01:00]==0) leading_zeros = 2;
	else if (inTri[00:00]==0) leading_zeros = 1;
	else leading_zeros = 0;
	
		 if (inTri[31:01]==0) trailing_zeros = 31;
	else if (inTri[31:02]==0) trailing_zeros = 30;
	else if (inTri[31:03]==0) trailing_zeros = 29;
	else if (inTri[31:04]==0) trailing_zeros = 28;
	else if (inTri[31:05]==0) trailing_zeros = 27;
	else if (inTri[31:06]==0) trailing_zeros = 26;
	else if (inTri[31:07]==0) trailing_zeros = 25;
	else if (inTri[31:08]==0) trailing_zeros = 24;
	else if (inTri[31:09]==0) trailing_zeros = 23;
	else if (inTri[31:10]==0) trailing_zeros = 22;
	else if (inTri[31:11]==0) trailing_zeros = 21;
	else if (inTri[31:12]==0) trailing_zeros = 20;
	else if (inTri[31:13]==0) trailing_zeros = 19;
	else if (inTri[31:14]==0) trailing_zeros = 18;
	else if (inTri[31:15]==0) trailing_zeros = 17;
	else if (inTri[31:16]==0) trailing_zeros = 16;
	else if (inTri[31:17]==0) trailing_zeros = 15;
	else if (inTri[31:18]==0) trailing_zeros = 14;
	else if (inTri[31:19]==0) trailing_zeros = 13;
	else if (inTri[31:20]==0) trailing_zeros = 12;
	else if (inTri[31:21]==0) trailing_zeros = 11;
	else if (inTri[31:22]==0) trailing_zeros = 10;
	else if (inTri[31:23]==0) trailing_zeros = 9;
	else if (inTri[31:24]==0) trailing_zeros = 8;
	else if (inTri[31:25]==0) trailing_zeros = 7;
	else if (inTri[31:26]==0) trailing_zeros = 6;
	else if (inTri[31:27]==0) trailing_zeros = 5;
	else if (inTri[31:28]==0) trailing_zeros = 4;
	else if (inTri[31:29]==0) trailing_zeros = 3;
	else if (inTri[31:30]==0) trailing_zeros = 2;
	else if (inTri[31:31]==0) trailing_zeros = 1;
	else trailing_zeros = 0;
	*/
end

endmodule


module float_to_fixed (
	input signed [31:0] float_in,
	output wire signed [31:0] fixed
);

wire float_sign = float_in[31];
wire [7:0]  exp = float_in[30:23];	// Sign bit not included here.
wire [23:0] man = {1'b1, float_in[22:00]};	// Prepend the implied 1.

wire [47:0] float_shifted = (exp>127) ? man<<(exp-127) :	// Exponent is positive.
													 man>>(127-exp);	// Exponent is negative.
										 
wire [30:0] new_fixed = float_shifted>>((23-FRAC_BITS));	// Sign bit not included here.

assign fixed = float_sign ? {1'b1,-new_fixed[30:0]} : {1'b0,new_fixed[30:0]};	// Invert the lower bits when the Sign bit is set.
																										// (tip from SKMP, because float values are essentially sign-magnitude.)
endmodule


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
	output reg codebook_wait,
	input latch_cb,
		
	input wire [9:0] ui,				// From rasterizer/interp...
	input wire [9:0] vi,
		
	input vram_wait,
	input vram_valid,
	output reg [20:0] vram_word_addr,	// 64-bit WORD address!
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
reg [19:0] texel_word_offs;

/* verilator lint_off UNOPTFLAT */
wire [2:0] pal8_sel = (is_pal4) ? twop_or_not[3:1] :	// PAL4. Drop the LSB bit, which is then used to select a the nibble from the pal8 mux result.
					  (vq_comp) ? twop_or_not[4:2] :	// VQ. Drop two lower bits.
								  twop_or_not[2:0];		// PAL8. Don't drop any bits. Directly select the byte from vram_din.
/* verilator lint_on UNOPTFLAT */

always @(*) begin
	if ((tex_u_size==tex_v_size) || (is_twid && mip_map) ) begin	// Square texture. (VQ textures are always square, then tex_v_size is ignored).
		case (tex_u_size)	// Using tex_u_size here. Doesn't really matter which one we use?
			0: twop = {14'b0, twop_full[5:0]};	// 8x8
			1: twop = {12'b0, twop_full[7:0]};	// 16x16
			2: twop = {10'b0, twop_full[9:0]};	// 32x32
			3: twop = {8'b0, twop_full[11:0]};	// 64x64
			4: twop = {6'b0, twop_full[13:0]};	// 128x128
			5: twop = {4'b0, twop_full[15:0]};	// 256x256
			6: twop = {2'b0, twop_full[17:0]};	// 512x512
			7: twop = twop_full[19:0];				// 1024x1024
		endcase
	end
	else if (tex_u_size > tex_v_size) begin		// Rectangular texture. U size greater than V size.
		case (tex_v_size)
			0: twop = {7'b0, ui_masked[9:3] ,twop_full[5:0]};	// V size 8 
			1: twop = {6'b0, ui_masked[9:4] ,twop_full[7:0]};	// V size 16
			2: twop = {5'b0, ui_masked[9:5] ,twop_full[9:0]};	// V size 32
			3: twop = {4'b0, ui_masked[9:6] ,twop_full[11:0]};	// V size 64
			4: twop = {3'b0, ui_masked[9:7] ,twop_full[13:0]};	// V size 128
			5: twop = {2'b0, ui_masked[9:8] ,twop_full[15:0]};	// V size 256
			6: twop = {1'b0, ui_masked[9]   ,twop_full[17:0]};	// V size 512
			7: twop = twop_full[19:0];							// V size 1024
		endcase
	end
	else if (tex_v_size > tex_u_size) begin // Rectangular. V size greater than U size.
		case (tex_u_size)
			0: twop = {7'b0, vi_masked[9:3] ,twop_full[5:0]};	// U size 8
			1: twop = {6'b0, vi_masked[9:4] ,twop_full[7:0]};	// U size 16
			2: twop = {5'b0, vi_masked[9:5] ,twop_full[9:0]};	// U size 32
			3: twop = {4'b0, vi_masked[9:6] ,twop_full[11:0]};	// U size 64
			4: twop = {3'b0, vi_masked[9:7] ,twop_full[13:0]};	// U size 128
			5: twop = {2'b0, vi_masked[9:8] ,twop_full[15:0]};	// U size 256
			6: twop = {1'b0, vi_masked[9]   ,twop_full[17:0]};	// U size 512
			7: twop = twop_full[19:0];							// U size 1024
		endcase
	end
	//else twop = twop_full;	// Default case, to prevent Latch warnings.
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

wire [63:0] cb_dout = code_book[pal8_byte];

wire [63:0] codebook_mux = (vq_comp) ? cb_dout : vram_din;


reg [31:0] pal_raw;
reg [31:0] pal_final;

// Palette RAM. 1024 32-bit Words.
// PVR Addr 0x1000-0x1FFC.
//reg [31:0] pal_ram [0:1023];


// VQ Code Book. 256 64-bit Words.
reg [63:0] code_book [0:256];
reg [8:0] cb_word_index;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	codebook_wait <= 1'b0;
end
else begin
	// Handle Palette RAM writes.
	//if (pal_addr[15:12]==4'b0001 && pal_wr) pal_ram[ pal_addr[11:2] ] <= pal_din;

	// Handle VQ Code Book reading.
	if (read_codebook) begin
		cb_word_index <= 9'd0;
		codebook_wait <= 1'b1;
	end
	else if (codebook_wait) begin
		if (cb_word_index==9'd256) codebook_wait <= 1'b0;
		else if (latch_cb) begin
			code_book[ cb_word_index ] <= vram_din;
			cb_word_index <= cb_word_index + 8'd1;
		end
	end
end

//assign pal_dout = pal_ram[ pal_addr[11:2] ];

endmodule


module depth_compare (
	input [2:0] depth_comp,
	
	input signed [31:0] old_z,
	input signed [31:0] invW,
	
	output reg depth_allow
);

always @* begin
	case (depth_comp)
		0: depth_allow = 0;						// Never.
		1: depth_allow = (invW <  old_z);	// Less.
		2: depth_allow = (invW == old_z);	// Equal.
		3: depth_allow = (invW <= old_z);	// Less or Equal
		4: depth_allow = (invW >  old_z);	// Greater.
		5: depth_allow = (invW != old_z);	// Not Equal.
		6: depth_allow = (invW >= old_z);	// Greater or Equal.
		7: depth_allow = 1;						// Always
	endcase
end

endmodule
