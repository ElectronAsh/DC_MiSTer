
`timescale 1ns / 1ps
`default_nettype none

module ra_parser (
	input clock,
	input reset_n,
	
	input ra_trig,
	
	input [31:0] ISP_BACKGND_D,
	input [31:0] ISP_BACKGND_T,
	output reg render_bg,

	input [31:0] PARAM_BASE,		// 0x20.
	input [31:0] REGION_BASE,		// 0x2C.
	
	input [31:0] FPU_PARAM_CFG,	// 0x7C
	input [31:0] TA_ALLOC_CTRL,	// 0x140
	
	input vram_wait,
	input vram_valid,
	output reg ra_vram_rd,
	output reg ra_vram_wr,
	output reg [23:0] ra_vram_addr,
	input [31:0] ra_vram_din,
	
	output reg [31:0] ra_control,
	output wire ra_cont_last,
	output wire ra_cont_zclear_n,
	output wire ra_cont_flush_n,
	output wire [5:0] ra_cont_tiley,
	output wire [5:0] ra_cont_tilex,

	output reg [2:0] type_cnt,

	input isp_idle,
	
	output reg [31:0] ra_opaque,
	output reg [31:0] ra_op_mod,
	output reg [31:0] ra_trans,
	output reg [31:0] ra_tr_mod,
	output reg [31:0] ra_puncht,
	
	output reg ra_new_tile_start,
	output reg ra_entry_valid,
	
	output reg [31:0] opb_word,
	
	output reg [23:0] poly_addr,
	output reg render_poly,
	output reg render_to_tile,
	
	output reg clear_fb,
	input clear_fb_pend,
	
	input poly_drawn,
	output reg tile_prims_done,
	
	input tile_accum_done
);

wire opb_mode = TA_ALLOC_CTRL[20];
wire [1:0] pt_opb = TA_ALLOC_CTRL[17:16];
wire [1:0] tm_opb = TA_ALLOC_CTRL[13:12];
wire [1:0]  t_opb = TA_ALLOC_CTRL[9:8];
wire [1:0] om_opb = TA_ALLOC_CTRL[5:4];
wire [1:0]  o_opb = TA_ALLOC_CTRL[1:0];

// Region Array read state machine...
(*noprune*)reg [7:0] ra_state;
reg [23:0] next_region;

assign ra_cont_last     = ra_control[31];
assign ra_cont_zclear_n = ra_control[30];
assign ra_cont_flush_n  = ra_control[28];
assign ra_cont_tiley    = ra_control[13:8];
assign ra_cont_tilex    = ra_control[7:2];

// OL Word bit decodes...
wire [5:0] strip_mask = {opb_word[25], opb_word[26], opb_word[27], opb_word[28], opb_word[29], opb_word[30]};	// For Triangle Strips only.
wire [3:0] num_prims = opb_word[28:25];	// For Triangle Array or Quad Array only.
wire shadow = opb_word[24];					// For all three poly types.
wire [2:0] skip = opb_word[23:21];			// For all three poly types.
wire eol = opb_word[28];						// End Of List.

reg [7:0] ol_jump_bytes;

reg draw_last_tile;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	ra_state <= 8'd0;
	render_bg <= 1'b1;				// TESTING !!
	next_region <= 24'h00000000;
	opb_word <= 32'h00000000;
	type_cnt <= 3'd0;
	poly_addr <= 24'h000000;
	render_poly <= 1'b0;
	render_to_tile <= 1'b0;
	ra_new_tile_start <= 1'b0;
	tile_prims_done <= 1'b0;
	clear_fb <= 1'b0;
end
else begin
	ra_new_tile_start <= 1'b0;

	clear_fb <= 1'b0;

	ra_entry_valid <= 1'b0;
	render_poly <= 1'b0;

	render_to_tile <= 1'b0;
	tile_prims_done <= 1'b0;
	
	if (ra_vram_rd && !vram_wait) ra_vram_rd <= 1'b0;
	if (ra_vram_wr && !vram_wait) ra_vram_wr <= 1'b0;

	case (ra_state)
		0: begin
			draw_last_tile <= 1'b0;
			if (ra_trig) begin
				//clear_fb <= 1'b1;
				ra_state <= ra_state + 8'd1;
			end
		end
		
		1: if (!clear_fb && !clear_fb_pend) begin
			ra_vram_addr <= REGION_BASE[23:0];	// Allowing the full 16MB VRAM address here.
			ra_vram_rd <= 1'b1;
			ra_state <= ra_state + 1;
		end
		
		2: if (vram_valid) begin
			ra_control <= ra_vram_din;
			ra_vram_addr <= ra_vram_addr + 4;
			ra_vram_rd <= 1'b1;
			ra_state <= ra_state + 8'd1;
		end

		3: if (vram_valid) begin
			ra_opaque <= ra_vram_din;
			ra_vram_addr <= ra_vram_addr + 4;
			ra_vram_rd <= 1'b1;
			ra_state <= ra_state + 8'd1;
		end
		
		4: if (vram_valid) begin
			ra_op_mod <= ra_vram_din;
			ra_vram_addr <= ra_vram_addr + 4;
			ra_vram_rd <= 1'b1;
			ra_state <= ra_state + 8'd1;
		end
		
		5: if (vram_valid) begin
			ra_trans <= ra_vram_din;
			ra_vram_addr <= ra_vram_addr + 4;
			ra_vram_rd <= 1'b1;
			ra_state <= ra_state + 8'd1;
		end
		
		6: if (vram_valid) begin
			ra_tr_mod <= ra_vram_din;
			if (FPU_PARAM_CFG[21]) begin	// fmt v2 (grab puncht value in next ra_state).
				ra_vram_rd <= 1'b1;
				ra_vram_addr <= ra_vram_addr + 4;
				ra_state <= 8'd7;
			end
			else begin						// fmt v1.
				ra_puncht <= 32'h80000000;	// (mark ra_puncht as Unused).
				ra_state <= 8'd8;			// Done!
			end
		end
		
		7: if (vram_valid) begin
			ra_puncht <= ra_vram_din;	// fmt v2 (grab puncht).
			ra_vram_addr <= ra_vram_addr + 4;
			ra_state <= ra_state + 8'd1;
		end
		
		8: begin
			next_region <= ra_vram_addr;	// Save address of next RA entry.
			ra_entry_valid <= 1'b1;
			type_cnt <= 3'd0;
			ra_new_tile_start <= 1'b1;
			ra_state <= ra_state + 8'd1;
		end
		
		9: begin
			// The Background poly has no OPB word.
			// Copy some flags from the ISP_BACKGND_T reg...
			if (render_bg) begin
				opb_word[31:29] <= 3'b101;						// Single Quad. (or Quad Array).
				opb_word[24]    <= ISP_BACKGND_T[27];		// Shadow.
				opb_word[23:21] <= ISP_BACKGND_T[26:24];	// Skip.
				opb_word[28:25] <= 4'd1;						// num_prims ?
				poly_addr       <= (PARAM_BASE&24'hf00000)+{ISP_BACKGND_T[23:3],2'b00};
				render_poly     <= 1'b1;
				ra_state        <= 8'd100;		// Wait for BG Poly to be drawn.
			end
			else begin
				type_cnt <= type_cnt + 1;	// Check through each Type.
				case (type_cnt)
				// Point ra_vram_addr to an OBJECT address...
				// If the MSB bit is CLEARED, it means the type/entry is in use, otherwise we skip to the next type.
				//
				// o_opb, pt_opb, om_opb, t_opb, tm_opb, gives the OPB size for each prim type...
				// 0=No List, 1=8 Words, 2=16 Words, 3=32 Words.
				// TODO: Shift won't work for o_opb==0 etc. (we now check for o_opb>0 etc.)
				//
				// Note: No need to add PARAM_BASE to ra_opaque[23:0] etc. ra_opaque is already the Absolute VRAM address! ElectronAsh.
				//
				0: if (!ra_opaque[31] &&  o_opb>0) begin ra_vram_addr <= ra_opaque[23:0]; ra_vram_rd <= 1'b1; ol_jump_bytes <= (4<<o_opb )*4; ra_state <= 8'd10; end // Alpha = 1.0 only.
				1: if (!ra_puncht[31] && pt_opb>0) begin ra_vram_addr <= ra_puncht[23:0]; ra_vram_rd <= 1'b1; ol_jump_bytes <= (4<<pt_opb)*4; ra_state <= 8'd10; end // Alpha 0.0 or 1.0 only.
				//2: if (!ra_op_mod[31] && om_opb>0) begin ra_vram_addr <= ra_op_mod[23:0]; ra_vram_rd <= 1'b1; ol_jump_bytes <= (4<<om_opb)*4; ra_state <= 8'd10; end // Modifier Vol, for Opaque/Punch-through
				3: if (!ra_trans[31]  &&  t_opb>0) begin ra_vram_addr <= ra_trans[23:0];  ra_vram_rd <= 1'b1; ol_jump_bytes <= (4<<t_opb )*4; ra_state <= 8'd10; end // Alpha between 0.0 and 1.0.
				//4: if (!ra_tr_mod[31] && tm_opb>0) begin ra_vram_addr <= ra_tr_mod[23:0]; ra_vram_rd <= 1'b1; ol_jump_bytes <= (4<<tm_opb)*4; ra_state <= 8'd10; end // Modifier Vol, for Transparent.
				5: ra_state <= 8'd14;	// All prim TYPES in this Object are done!
				default: ;
				endcase
			end
		end
		
		100: if (poly_drawn) begin
			render_bg <= 1'b0;
			ra_state <= 8'd9;
		end
		
		10: if (vram_valid) begin
			opb_word <= ra_vram_din;
			ra_state <= ra_state + 8'd1;
		end
		
		// Check for Object Pointer Block Link, or Primitive Type...
		11: begin
			if (!opb_word[31]) begin					// Triangle Strip.
				poly_addr <= (PARAM_BASE&24'hf00000)+{opb_word[20:0], 2'b00};
				if (isp_idle) begin
					render_poly <= 1'b1;
					ra_state <= ra_state + 8'd1;
				end
			end
			else if (opb_word[31:29]==3'b100) begin		// Triangle Array.
				poly_addr <= (PARAM_BASE&24'hf00000)+{opb_word[20:0], 2'b00};
				if (isp_idle) begin
					render_poly <= 1'b1;
					ra_state <= ra_state + 8'd1;
				end
			end
			else if (opb_word[31:29]==3'b101) begin		// Single Quad, or Quad Array.
				poly_addr <= (PARAM_BASE&24'hf00000)+{opb_word[20:0], 2'b00};
				if (isp_idle) begin
					render_poly <= 1'b1;
					ra_state <= ra_state + 8'd1;
				end
			end
			else if (opb_word[31:29]==3'b111) begin		// Pointer Block Link.
				if (eol) begin							// Is it the End of this OBJECT List? opb_word[28].[31:28]==F.
					render_to_tile <= 1'b1;
					ra_state <= 8'd13;					// If so, check the next primitive TYPE in the current Region Array block.
				end
				else begin
					ra_vram_addr <= {opb_word[23:2], 2'b00};	// Take the Link address jump. [31:28]==E.
					ra_vram_rd <= 1'b1;
					ra_state <= 8'd10;							// Jump back to previous state, to grab the next OL entry word.
				end
			end
			else begin
				$display("Undefined Object prim type! (OL overrun?)\n");
				ra_state <= 8'd0;
			end
		end
		
		12: begin
			if (poly_drawn) begin
				if (ra_cont_last) draw_last_tile <= 1'b1;
				ra_vram_addr <= ra_vram_addr + 4;	// Go to next WORD in OL.
				ra_vram_rd <= 1'b1;
				ra_state <= 10;
			end
		end
		
		13: if (tile_accum_done) begin
			if (opb_word[31:29]==3'b111 || poly_drawn) begin
				ra_state <= 8'd9;	// Read the next Prim TYPE entry.
			end
		end
		
		14: if (isp_idle) begin	// All primitive TYPES within this Tile have been processed!
			tile_prims_done <= 1'b1;

			if (ra_cont_last) ra_state <= 8'd15;	// TESTING. Don't repeat rendering the same frame, just stop.
			else begin
				ra_vram_addr <= next_region;	// Check the next Region Array entry.
				render_bg <= 1'b1;
				ra_vram_rd <= 1'b1;
				ra_state <= 8'd2;
			end	
		end
		
		15: ;	// All tiles Done! (this ra_state is used to pause the sim after all Tiles have been rendered.)
		
		default: ;
	
	endcase
end

endmodule
