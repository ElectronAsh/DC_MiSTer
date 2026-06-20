`timescale 1ns / 1ps
`default_nettype none

module tile_accelerator (
	input reset_n,
	input clock,
	
	input [15:0] ta_reg_addr,
	input [31:0] ta_reg_wrdata,
	input ta_reg_wr,
	output [31:0] ta_reg_rddata,
	
	input [31:0] ta_fifo_din,
	input ta_fifo_wr,
	output [31:0] ta_fifo_dout,
	output ta_fifo_empty,
	output ta_fifo_full,
	output [8:0] ta_fifo_used,
	
	input ta_vram_wait,
	output [23:0] ta_vram_addr,
	output [31:0] ta_vram_wrdata,
	output ta_vram_wr
);

// TA REGS
/*
parameter TA_OL_BASE_addr         = 16'h0124; // RW  Object list write start address
parameter TA_ISP_BASE_addr        = 16'h0128; // RW  ISP/TSP Parameter write start address
parameter TA_OL_LIMIT_addr        = 16'h012C; // RW  Object list addr limit
parameter TA_ISP_LIMIT_addr       = 16'h0130; // RW  ISP/TSP Parameter addr limit
parameter TA_NEXT_OPB_addr        = 16'h0134; // R   Start address of next Object Pointer Block
parameter TA_ISP_CURRENT_addr     = 16'h0138; // R   Current ISP/TSP Parameter write address
parameter TA_GLOB_TILE_CLIP_addr  = 16'h013C; // RW  Global Tile clip control
parameter TA_ALLOC_CTRL_addr      = 16'h0140; // RW  Object list control
parameter TA_LIST_INIT_addr       = 16'h0144; // RW  TA initialization
parameter TA_YUV_TEX_BASE_addr    = 16'h0148; // RW  YUV422 texture write start address
parameter TA_YUV_TEX_CTRL_addr    = 16'h014C; // RW  YUV converter control
parameter TA_YUV_TEX_CNT_addr     = 16'h0150; // R   YUV converter macro block counter value

parameter TA_LIST_CONT_addr       = 16'h0160; // RW  TA continuation processing
parameter TA_NEXT_OPB_INIT_addr   = 16'h0164; // RW  Additional OPB starting address

parameter FOG_TABLE_START_addr        = 16'h0200; // RW  Look-up table Fog data
parameter FOG_TABLE_END_addr          = 16'h03FC;

parameter TA_OL_POINTERS_START_addr   = 16'h0600; // R   TA object List Pointer data
parameter TA_OL_POINTERS_END_addr     = 16'h0F5C;
*/
reg [31:0] TA_OL_BASE;
reg [31:0] TA_ISP_BASE;
reg [31:0] TA_OL_LIMIT;
reg [31:0] TA_ISP_LIMIT;
reg [31:0] TA_NEXT_OPB;
reg [31:0] TA_ISP_CURRENT;
reg [31:0] TA_GLOB_TILE_CLIP;
reg [31:0] TA_ALLOC_CTRL;
reg [31:0] TA_LIST_INIT;
reg [31:0] TA_YUV_TEX_BASE;
reg [31:0] TA_YUV_TEX_CTRL;
reg [31:0] TA_YUV_TEX_CNT;

reg [31:0] TA_LIST_CONT;
reg [31:0] TA_NEXT_OPB_INIT;

//reg [31:0] FOG_TABLE_START;
//reg [31:0] FOG_TABLE_END;

//reg [31:0] TA_OL_POINTERS_START;
//reg [31:0] TA_OL_POINTERS_END;

// Pointer RAM.
//
// (600 "tile" buffer of pointers to OPB lists. Each OPB list contains the polys that relate to each tile).
//
// Make each pointer a 24-bit BYTE address for now, so it can access the full (NAOMI) 16MB VRAM.
// Later, this will be reduced to a word address, and then probably to 21-bit WORD address, plus PARAM_BASE.
//
// PRAM[0] relates to the top-left tile.
// PRAM[39] relates to the top-right tile.
// PRAM[40] relates to the left-hand tile on the second row, and so-on.
//
reg [23:0] pram [0:599];

/*
wire [31:0] FX1_TILE = FX1_INT[31:5];
wire [31:0] FY1_TILE = FY1_INT[31:5];
wire [31:0] FZ1_TILE = FZ1_INT[31:5];
wire [31:0] FU1_TILE = FU1_INT[31:5];
wire [31:0] FV1_TILE = FV1_INT[31:5];

wire [31:0] FX2_TILE = FX2_INT[31:5];
wire [31:0] FY2_TILE = FY2_INT[31:5];
wire [31:0] FZ2_TILE = FZ2_INT[31:5];
wire [31:0] FU2_TILE = FU2_INT[31:5];
wire [31:0] FV2_TILE = FV2_INT[31:5];

wire [31:0] FX3_TILE = FX3_INT[31:5];
wire [31:0] FY3_TILE = FY3_INT[31:5];
wire [31:0] FZ3_TILE = FZ3_INT[31:5];
wire [31:0] FU3_TILE = FU3_INT[31:5];
wire [31:0] FV3_TILE = FV3_INT[31:5];

wire [31:0] tile_x_min = (FX1_TILE < FX2_TILE) ? 
                        ((FX1_TILE < FX3_TILE) ? FX1_TILE : FX3_TILE) : 
                        ((FX2_TILE < FX3_TILE) ? FX2_TILE : FX3_TILE);

wire [31:0] tile_x_max = (FX1_TILE > FX2_TILE) ? 
                        ((FX1_TILE > FX3_TILE) ? FX1_TILE : FX3_TILE) : 
                        ((FX2_TILE > FX3_TILE) ? FX2_TILE : FX3_TILE);

wire [31:0] tile_y_min = (FY1_TILE < FY2_TILE) ? 
                        ((FY1_TILE < FY3_TILE) ? FY1_TILE : FY3_TILE) : 
                        ((FY2_TILE < FY3_TILE) ? FY2_TILE : FY3_TILE);

wire [31:0] tile_y_max = (FY1_TILE > FY2_TILE) ? 
                        ((FY1_TILE > FY3_TILE) ? FY1_TILE : FY3_TILE) : 
                        ((FY2_TILE > FY3_TILE) ? FY2_TILE : FY3_TILE);

						 
reg [5:0] curr_tile_x;
reg [3:0] curr_tile_y;
wire [9:0] pram_addr = curr_tile_x + (curr_tile_y*40);
*/

reg [31:0] pcw;	// Parameter Control Word.
//
// [31:24]=Para Control. [23:16]=Group Control. [15:0]=Object Control.
//
// Group Control.
// This is the control data for an object group. This is valid only in Global Parameters.
// [23]=Group_En. [22:20]=Reserved. [19:18]=Strip_Len. [17:16]=User_Clip.
//
// Group_En...
// If "1", update the Strip_Len and User_Clip settings.
// If "0", the existing settings are used.
//
// Strip_Len...
// code 0: 1 strip.
// code 1: 2 strips.
// code 2: 4 strips.
// code 3: 6 strips.
//
// User_Clip...
// code 0: Disable.
// code 1: Reserved.
// code 2: Inside enable.
// code 3: Outside enable.
//
wire group_en = pcw[23];
// These two regs will get updated in the TA state machine.
// (since they are only updated if the group_en bit is set, after reading in a new pcw.)
reg [1:0] strip_len;
reg [1:0] user_clip;


// Object Control.
// This data sets an object. This is valid only in Global Parameters.
// [15:8]=Reserved. [7]=Shadow. [6]=Volume [5:4]=Col_Type. [3]=Texture. [2]=Offset. [1]=Gouraud [0]=16bit_UV.
//
// Shadow: The value of this bit is used in "Shadow bit (bit 24)" of the Object List.
// This bit must be set to "1" for parameters in with "Two Volumes" format.
// In Intensity Volume Mode, set this bit to "1" in order to perform shadow processing on a polygon.
//
// Volume: This specifies whether the parameters are in "with Two Volumes" format, or whether or not
// the polygon is the last Triangle polygon in the volume. In the case of the Modifier Volume
// type, the Volume Instruction (bits 31 to 29) in the ISP/TSP Instruction Word must be set
// correctly, along with this bit. In the case of the Sprite type, set this bit to "0."
// 
// Col_Type...
// code 0: Packed Color.     8-bit values for each A,R,G,B.
// code 1: Floating Color.   32-bit floating-point values for each A,R,G,B.
// code 2: Intensity Mode 1. The Face Color is specified by the immediately preceding Global Parameters.
// code 3: Intensity Mode 2. The previous Face Color value that was specified by Global Parameters in Intensity
//
// Mode 1 is used for the Face Color.
// Note that a polygon for which this mode is used must only be input after a Mode 1 polygon has been input at least once.
// It is not necessary for the Mode 1 polygon to have immediately preceded this polygon.
//
wire shadow   = pcw[7];
wire volume   = pcw[6];
wire [1:0] col_type = pcw[5:4];
wire texture  = pcw[3];
wire offset   = pcw[2];
wire gouraud  = pcw[1];
wire uv_16bit = pcw[0];

// Four bits in the ISP/TSP Instruction Word are overwritten with the corresponding bit values from the Parameter Control Word.
//
// Parameter Control Word      ISP/TSP Instruction Word
//
// Bit 3 Texture           ->  Bit 25 Texture
// Bit 2 Offset            ->  Bit 24 Offset
// Bit 1 Gouraud           ->  Bit 23 Gouraud shading
// Bit 0 16bit_UV          ->  Bit 22 16 Bit UV
//


// Figure out the "Poly" (packet) Type, and the packet length.
// (for Global Parameter and Vertex Parameter packet types).
//
reg [2:0] glob_param_type;
reg [3:0] vert_param_type;
wire sprite_type = texture;

// 0=8 WORDS. 1=16 WORDS...
reg glob_pkt_big;
reg vert_pkt_big;

// From the "Parameter Combinations" table in the Sega Dev Kit System PDF, page 191.
//
always @(*) begin
	casez ( {volume, col_type, texture, offset, gouraud, uv_16bit} )
		7'b0_00_0???: begin glob_param_type = 3'd0; vert_param_type = 4'd00; end
		7'b0_01_0???: begin glob_param_type = 3'd0; vert_param_type = 4'd01; end
		7'b0_10_0???: begin glob_param_type = 3'd1; vert_param_type = 4'd02; end
		7'b0_11_0???: begin glob_param_type = 3'd0; vert_param_type = 4'd02; end
		7'b1_00_0???: begin glob_param_type = 3'd3; vert_param_type = 4'd09; end
		7'b1_10_0???: begin glob_param_type = 3'd4; vert_param_type = 4'd10; end
		7'b1_11_0???: begin glob_param_type = 3'd3; vert_param_type = 4'd10; end
		//
		7'b0_00_1??0: begin glob_param_type = 3'd0; vert_param_type = 4'd03; end
		7'b0_00_1??1: begin glob_param_type = 3'd0; vert_param_type = 4'd04; end
		7'b0_01_1??0: begin glob_param_type = 3'd0; vert_param_type = 4'd05; end
		7'b0_01_1??1: begin glob_param_type = 3'd0; vert_param_type = 4'd06; end
		7'b0_10_10?0: begin glob_param_type = 3'd1; vert_param_type = 4'd07; end
		7'b0_10_11?0: begin glob_param_type = 3'd2; vert_param_type = 4'd07; end
		7'b0_10_10?1: begin glob_param_type = 3'd1; vert_param_type = 4'd08; end
		7'b0_10_11?1: begin glob_param_type = 3'd2; vert_param_type = 4'd08; end
		7'b0_11_1??0: begin glob_param_type = 3'd0; vert_param_type = 4'd07; end
		7'b0_11_1??1: begin glob_param_type = 3'd0; vert_param_type = 4'd08; end
		7'b1_00_1??0: begin glob_param_type = 3'd3; vert_param_type = 4'd11; end
		7'b1_00_1??1: begin glob_param_type = 3'd3; vert_param_type = 4'd12; end
		7'b1_10_1??0: begin glob_param_type = 3'd4; vert_param_type = 4'd13; end
		7'b1_10_1??1: begin glob_param_type = 3'd4; vert_param_type = 4'd14; end
		7'b1_11_1??0: begin glob_param_type = 3'd3; vert_param_type = 4'd13; end
		7'b1_11_1??1: begin glob_param_type = 3'd3; vert_param_type = 4'd14; end
		     default: begin glob_param_type = 3'd0; vert_param_type = 4'd00; end
	endcase
	
	case (glob_param_type)
		0: glob_pkt_big = 1'b0;
		1: glob_pkt_big = 1'b0;
		2: glob_pkt_big = 1'b1;
		3: glob_pkt_big = 1'b0;
		4: glob_pkt_big = 1'b1;
		default: glob_pkt_big = 1'b0;
	endcase
	
	case (vert_param_type)
		0:  vert_pkt_big = 1'b0;
		1:  vert_pkt_big = 1'b0;
		2:  vert_pkt_big = 1'b0;
		3:  vert_pkt_big = 1'b0;
		4:  vert_pkt_big = 1'b0;
		5:  vert_pkt_big = 1'b1;
		6:  vert_pkt_big = 1'b1;
		7:  vert_pkt_big = 1'b0;
		8:  vert_pkt_big = 1'b0;
		9:  vert_pkt_big = 1'b0;
		10: vert_pkt_big = 1'b0;
		11: vert_pkt_big = 1'b1;
		12: vert_pkt_big = 1'b1;
		13: vert_pkt_big = 1'b1;
		14: vert_pkt_big = 1'b1;
		default: vert_pkt_big = 1'b0;
	endcase
end

wire [2:0] para_type = pcw[31:29];
// para_type...
//
// [CONTROL]
// 0 end of list
// 1 user tile clip
// 2 object list set
//
// [GLOBAL]
// 3 reserved
// 4 polygon/modifier volume
// 5 sprite
// 6 reserved
//
// [VERTEX]
// 7 vertex
//

wire end_of_strip = pcw[28];	
// end_of_strip...
// Valid only in the Vertex Parameters. A parameter in which this bit is "1" ends a strip.
// The Sprite and Modifier Volume Vertex Parameter must be set to "1".

// pcw[27] = reserved?

wire [2:0] list_type = pcw[26:24];
// list_type...
//
// 0   Opaque                       (Polygon or Sprite)
// 1   Opaque Modifier Volume       (Modifier Volume)
// 2   Translucent                  (Polygon or Sprite)
// 3   Translucent Modifier Volume  (Modifier Volume)
// 4   Punch Through                (Polygon or Sprite)
// 5~7 Reserved                     (Prohibited)
//


// [CONTROL] User Tile Clip regs...
reg [5:0] user_clip_x_min;
reg [3:0] user_clip_y_min;
reg [5:0] user_clip_x_max;
reg [3:0] user_clip_y_max;


// [CONTROL] Object List set regs...
reg [31:0] object_pointer;
reg [5:0] bounding_box_x_min;
reg [3:0] bounding_box_y_min;
reg [5:0] bounding_box_x_max;
reg [3:0] bounding_box_y_max;


// Internal reg stuff for Global params...
reg [31:0] isp_tsp_inst;
reg [31:0] tsp_inst_0;
reg [31:0] tsp_inst_1;
reg [31:0] tcw_0;
reg [31:0] tcw_1;

// GLOBAL params...
reg [31:0] sort_dma_size;
reg [31:0] sort_dma_next;
reg [31:0] face_col_a_0;
reg [31:0] face_col_r_0;
reg [31:0] face_col_g_0;
reg [31:0] face_col_b_0;
reg [31:0] face_col_a_1;
reg [31:0] face_col_r_1;
reg [31:0] face_col_g_1;
reg [31:0] face_col_b_1;
reg [31:0] face_offs_col_a;
reg [31:0] face_offs_col_r;
reg [31:0] face_offs_col_g;
reg [31:0] face_offs_col_b;

// VERTEX params...
reg [31:0] vert_a_x;
reg [31:0] vert_a_y;
reg [31:0] vert_a_z;
// Values below are only used for Sprites/Lines...
reg [31:0] vert_b_x;
reg [31:0] vert_b_y;
reg [31:0] vert_b_z;
reg [31:0] vert_c_x;
reg [31:0] vert_c_y;
reg [31:0] vert_c_z;
reg [31:0] vert_d_x;
reg [31:0] vert_d_y;
reg [31:0] vert_d_z;
reg [31:0] vert_u_0;
reg [31:0] vert_v_0;
reg [31:0] vert_u_1;
reg [31:0] vert_v_1;
reg [31:0] sprite_au_av;
reg [31:0] sprite_bu_bv;
reg [31:0] sprite_cu_cv;
//
reg [31:0] base_col_0;
reg [31:0] offs_col_0;
reg [31:0] base_col_1;
reg [31:0] offs_col_1;
reg [31:0] base_int_0;
reg [31:0] offs_int_0;
reg [31:0] base_int_1;
reg [31:0] offs_int_1;
reg [31:0] base_col_a_0;
reg [31:0] base_col_r_0;
reg [31:0] base_col_g_0;
reg [31:0] base_col_b_0;
reg [31:0] base_col_a_1;
reg [31:0] base_col_r_1;
reg [31:0] base_col_g_1;
reg [31:0] base_col_b_1;
reg [31:0] offs_col_a_0;
reg [31:0] offs_col_r_0;
reg [31:0] offs_col_g_0;
reg [31:0] offs_col_b_0;
reg [31:0] offs_col_a_1;
reg [31:0] offs_col_r_1;
reg [31:0] offs_col_g_1;
reg [31:0] offs_col_b_1;


reg [7:0] ta_state;
reg ta_fifo_rd;
reg [3:0] total_fifo_count;

reg [4:0] curr_word;
reg [4:0] word_max;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	ta_state <= 8'd0;
	ta_fifo_rd <= 1'b0;
	total_fifo_count <= 4'd0;
	curr_word <= 4'd0;
	word_max <= 4'd7;
end
else begin
	ta_fifo_rd <= 1'b0;	// Default.
	if (ta_fifo_rd) total_fifo_count <= total_fifo_count + 9'd1;

	case (ta_state)
		0: begin
			curr_word <= 3'd0;
			if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				ta_state <= ta_state + 8'd1;
			end
		end
		
		1: begin
			// First WORD in the buffer is the Parameter Control Word.
			//	 pppp pppp gggg gggg oooo oooo oooo oooo
			//
			//	 p = para control
			//	 g = group control
			//	 o = object control
			pcw <= ta_fifo_dout;
			ta_state <= ta_state + 8'd1;
		end

		// Parse PCW para_type...
		2: begin
			case (para_type)
				// [CONTROL].
				0: begin word_max <= 4'd7; ta_state <= 8'd3; end	// End Of List.
				1: begin word_max <= 4'd7; ta_state <= 8'd4; end	// User Tile Clip.
				2: begin word_max <= 4'd7; ta_state <= 8'd5; end	// Object List set.
				3: begin word_max <= 4'd7; ta_state <= 8'd3; end	// Reserved.
				
				// [GLOBAL] Parameter.
				4: begin word_max <= (glob_pkt_big)? 4'd15 : 4'd7; ta_state <= 8'd6; end	// Polygon / Modifier volume *header*.
				5: begin word_max <= 4'd7;						   ta_state <= 8'd7; end	// Sprite (quad?) *header*.
				6: begin word_max <= 4'd7;                         ta_state <= 8'd3; end	// Reserved (ditch other FIFO Words).
				
				// [VERTEX] Parameter.
				7: begin word_max <= (vert_pkt_big) ? 4'd15 : 4'd7; ta_state <= 8'd13; end	// Vertex parameter.
				default: ;
			endcase
		end

		// [CONTROL] End Of List / or Reserved...
		// (ditch/ignore the next 7 or 15 FIFO words).
		3: begin
			if (curr_word==word_max) begin
				if (para_type==3 || para_type==6) ta_state <= 8'd0;	// Reserved. (ditch/ignore FIFO words only).
				else begin	// para_type==0. EOL.
					// TODO: End of List stuff.
					ta_state <= 8'd0;
				end
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
		end

		// [CONTROL] User Tile Clip...
		4: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0=pcw
				4: user_clip_x_min <= ta_fifo_dout[5:0];
				5: user_clip_y_min <= ta_fifo_dout[3:0];
				6: user_clip_x_max <= ta_fifo_dout[5:0];
				7: user_clip_y_max <= ta_fifo_dout[3:0];
				default: ;
			endcase
		end

		// [CONTROL] Object List Set...
		5: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: object_pointer     <= ta_fifo_dout;
				4: bounding_box_x_min <= ta_fifo_dout[5:0];
				5: bounding_box_y_min <= ta_fifo_dout[3:0];
				6: bounding_box_x_max <= ta_fifo_dout[5:0];
				7: bounding_box_y_max <= ta_fifo_dout[3:0];
				default: ;
			endcase
		end

		// [GLOBAL] Polygon / Modifier Volume *header* type...
		6: begin
			// 0   Opaque                       (Polygon or Sprite)
			// 1   Opaque Modifier Volume       (Modifier Volume)
			// 2   Translucent                  (Polygon or Sprite)
			// 3   Translucent Modifier Volume  (Modifier Volume)
			// 4   Punch Through                (Polygon or Sprite)
			// 5~7 Reserved                     (Prohibited)
			if (!list_type[0]) begin	// Polygon...
				case (glob_param_type)
					0: begin ta_state <= 8'd8;  end	// Packed/Floating Color.
					1: begin ta_state <= 8'd9;	end	// Intensity, no Offset Color.
					2: begin ta_state <= 8'd10; end	// Intensity, use Offset Color.
					3: begin ta_state <= 8'd11; end	// Packed Color, with Two Volumes.
					4: begin ta_state <= 8'd12; end	// Intensity, with Two Volumes.
					default: ta_state <= 8'd3;	// Invalid Global Parameter type! (ditch the last FIFO Words).
				endcase
			end
			else begin	// Modifier Volume...
				if (curr_word==4'd7) begin	// Implicitly set to 8 Words (0~7).
					ta_state <= 8'd0;
				end
				else if (!ta_fifo_empty) begin
					ta_fifo_rd <= 1'b1;
					curr_word <= curr_word + 4'd1;
				end
				case (curr_word)
					// 0: PCW.
					1: isp_tsp_inst	 <= ta_fifo_dout;
					2: tsp_inst_0	 <= ta_fifo_dout;
					// 3: ignored.
					// 4: ignored.
					// 5: ignored.
					// 6: ignored.
					// 7: ignored.
					default: ;
				endcase
			end
		end

		// [GLOBAL] Sprite (Packed color). *header*...
		7: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 <= ta_fifo_dout;
				2: tsp_inst_0	 <= ta_fifo_dout;
				3: tcw_0		 <= ta_fifo_dout;
				4: base_col_0	 <= ta_fifo_dout;
				5: offs_col_0	 <= ta_fifo_dout;
				6: sort_dma_size <= ta_fifo_dout;
				7: sort_dma_next <= ta_fifo_dout;
				default: ;
			endcase
		end
		
		// (GLOBAL Polygon Type 0). Packed/Floating Color. *header*...
		8: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 <= ta_fifo_dout;
				2: tsp_inst_0	 <= ta_fifo_dout;
				3: tcw_0		 <= ta_fifo_dout;
				// 4: ignored.
				// 5: ignored.
				6: sort_dma_size <= ta_fifo_dout;
				7: sort_dma_next <= ta_fifo_dout;
				default: ;
			endcase
		end

		// (GLOBAL Polygon Type 1). Intensity, no Offset Color. *header*...
		9: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 <= ta_fifo_dout;
				2: tsp_inst_0	 <= ta_fifo_dout;
				3: tcw_0		 <= ta_fifo_dout;
				4: face_col_a_0	 <= ta_fifo_dout;
				5: face_col_r_0	 <= ta_fifo_dout;
				6: face_col_g_0	 <= ta_fifo_dout;
				7: face_col_b_0	 <= ta_fifo_dout;
				default: ;
			endcase
		end

		// (GLOBAL Polygon Type 2). Intensity, use Offset Color. *header*...
		10: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 	<= ta_fifo_dout;
				2: tsp_inst_0	 	<= ta_fifo_dout;
				3: tcw_0		 	<= ta_fifo_dout;
				// 4: ignored.
				// 5: ignored.
				6: sort_dma_size	<= ta_fifo_dout;
				7: sort_dma_next	<= ta_fifo_dout;
				8: face_col_a_0		<= ta_fifo_dout;
				9: face_col_r_0		<= ta_fifo_dout;
				10: face_col_g_0	<= ta_fifo_dout;
				11: face_col_b_0	<= ta_fifo_dout;
				12: face_offs_col_a <= ta_fifo_dout;
				13: face_offs_col_r <= ta_fifo_dout;
				14: face_offs_col_g <= ta_fifo_dout;
				15: face_offs_col_b <= ta_fifo_dout;
				default: ;
			endcase
		end

		// (GLOBAL Polygon Type 3). Packed Color, with Two Volumes. *header*...
		11: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 <= ta_fifo_dout;
				2: tsp_inst_0	 <= ta_fifo_dout;
				3: tcw_0		 <= ta_fifo_dout;
				4: tsp_inst_1	 <= ta_fifo_dout;
				5: tcw_1		 <= ta_fifo_dout;
				6: sort_dma_size <= ta_fifo_dout;
				7: sort_dma_next <= ta_fifo_dout;
				default: ;
			endcase
		end

		// (GLOBAL Polygon Type 4). Intensity, with Two Volumes. *header*...
		12: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: isp_tsp_inst	 	<= ta_fifo_dout;
				2: tsp_inst_0	 	<= ta_fifo_dout;
				3: tcw_0		 	<= ta_fifo_dout;
				4: tsp_inst_1	 	<= ta_fifo_dout;
				5: tcw_1		 	<= ta_fifo_dout;
				6: sort_dma_size	<= ta_fifo_dout;
				7: sort_dma_next	<= ta_fifo_dout;
				8: face_col_a_0		<= ta_fifo_dout;
				9: face_col_r_0		<= ta_fifo_dout;
				10: face_col_g_0	<= ta_fifo_dout;
				11: face_col_b_0	<= ta_fifo_dout;
				12: face_col_a_1	<= ta_fifo_dout;
				13: face_col_r_1	<= ta_fifo_dout;
				14: face_col_g_1	<= ta_fifo_dout;
				15: face_col_b_1	<= ta_fifo_dout;
				default: ;
			endcase
		end

		// [VERTEX] Vertex parameter types...
		13: begin
			case (vert_param_type)
				0:  ta_state <= 8'd14;		// (8 Words).  Non-Textured, Packed Color.
				1:  ta_state <= 8'd15;		// (8 Words).  Non-Textured, Floating Color.
				2:  ta_state <= 8'd16;		// (8 Words).  Non-Textured, Intensity.
				//
				3:  ta_state <= 8'd17;		// (8 Words).  Packed Color.
				4:  ta_state <= 8'd17;		// (8 Words).  Packed Color, 16-bit UV.
				//
				5:  ta_state <= 8'd19;		// (16 Words). Floating Color.
				6:  ta_state <= 8'd19;		// (16 Words). Floating Color, 16-bit UV.
				//
				7:  ta_state <= 8'd21;		// (8 Words).  Intensity.
				8:  ta_state <= 8'd21;		// (8 Words).  Intensity, 16-bit UV.
				//
				9:  ta_state <= 8'd23;		// (8 Words).  Non-Textured, Packed Color, with Two Volumes.
				10: ta_state <= 8'd24;		// (8 Words).  Non-Textured, Intensity, with Two Volumes.
				//
				11: ta_state <= 8'd25;		// (16 Words). Textured, Packed Color, with Two Volumes.
				12: ta_state <= 8'd25;		// (16 Words). Textured, Packed Color, with Two Volumes, 16-bit UV.
				//
				13: ta_state <= 8'd27;		// (16 Words). Textured, Intensity, with Two Volumes.
				14: ta_state <= 8'd27;		// (16 Words). Textures, Intensity, with Two Volumes, 16-bit UV.
				default: ta_state <= 8'd3;	// Invalid Vertex Parameter type! (ditch the last FIFO Words).
			endcase
		end
		
		// (VERTEX Polygon Type 0). Non-Textured, Packed Color.
		14: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x	   <= ta_fifo_dout;
				2: vert_a_y	   <= ta_fifo_dout;
				3: vert_a_z	   <= ta_fifo_dout;
				// 4: ignored.
				// 5: ignored.
				6: base_col_0  <= ta_fifo_dout;
				// 7: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 1). Non-Textured, Floating Color.
		15: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: base_col_a_0	<= ta_fifo_dout;
				5: base_col_r_0	<= ta_fifo_dout;
				6: base_col_g_0	<= ta_fifo_dout;
				7: base_col_b_0	<= ta_fifo_dout;
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 2). Non-Textured, Intensity.
		16: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				// 4: ignored.
				// 5: ignored.
				6: base_int_0	<= ta_fifo_dout;
				// 7: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 3). Packed Color.
		17: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: vert_u_0		<= ta_fifo_dout;
				5: vert_v_0		<= ta_fifo_dout;
				6: base_col_0	<= ta_fifo_dout;
				7: offs_col_0	<= ta_fifo_dout;
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 4). Packed Color, 16-bit UV.
		/*
		18: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: vert_u_0		<= ta_fifo_dout;	// U/V.
				// 5: ignored.
				6: base_col_0	<= ta_fifo_dout;
				7: offs_col_0	<= ta_fifo_dout;
				default: ;
			endcase
		end
		*/
		
		// (VERTEX Polygon Type 5). Floating Color.
		19: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x	<= ta_fifo_dout;
				2:  vert_a_y	<= ta_fifo_dout;
				3:  vert_a_z	<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;
				5:  vert_v_0	<= ta_fifo_dout;
				// 6: ignored.
				// 7: ignored.
				8:  base_col_a_0 <= ta_fifo_dout;
				9:  base_col_r_0 <= ta_fifo_dout;
				10: base_col_g_0 <= ta_fifo_dout;
				11: base_col_b_0 <= ta_fifo_dout;
				12: offs_col_a_0 <= ta_fifo_dout;
				13: offs_col_r_0 <= ta_fifo_dout;
				14: offs_col_g_0 <= ta_fifo_dout;
				15: offs_col_b_0 <= ta_fifo_dout;
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 6). Floating Color, 16-bit UV.
		/*
		20: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x		<= ta_fifo_dout;
				2:  vert_a_y		<= ta_fifo_dout;
				3:  vert_a_z		<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;	// U/V.
				// 5: ignored.
				// 6: ignored.
				// 7: ignored.
				8:  base_col_a_0 <= ta_fifo_dout;
				9:  base_col_r_0 <= ta_fifo_dout;
				10: base_col_g_0 <= ta_fifo_dout;
				11: base_col_b_0 <= ta_fifo_dout;
				12: offs_col_a_0 <= ta_fifo_dout;
				13: offs_col_r_0 <= ta_fifo_dout;
				14: offs_col_g_0 <= ta_fifo_dout;
				15: offs_col_b_0 <= ta_fifo_dout;
				default: ;
			endcase
		end
		*/
		
		// (VERTEX Polygon Type 7). Intensity.
		21: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: vert_u_0		<= ta_fifo_dout;
				5: vert_v_0		<= ta_fifo_dout;
				6: base_int_0 	<= ta_fifo_dout;
				7: offs_int_0	<= ta_fifo_dout;
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 8). Intensity, 16-bit UV.
		/*
		22: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: vert_u_0		<= ta_fifo_dout;	// U/V.
				// 5: ignored.
				6: base_int_0 	<= ta_fifo_dout;
				7: offs_int_0	<= ta_fifo_dout;
				default: ;
			endcase
		end
		*/
		
		// (VERTEX Polygon Type 9). Non-Textured, Packed Color, with Two Volumes.
		23: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		  <= ta_fifo_dout;
				2: vert_a_y		  <= ta_fifo_dout;
				3: vert_a_z		  <= ta_fifo_dout;
				4: base_col_0	  <= ta_fifo_dout;
				5: base_col_1	  <= ta_fifo_dout;
				// 6: ignored.
				// 7: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 10). Non-Textured, Intensity, with Two Volumes.
		24: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1: vert_a_x		<= ta_fifo_dout;
				2: vert_a_y		<= ta_fifo_dout;
				3: vert_a_z		<= ta_fifo_dout;
				4: base_int_0	<= ta_fifo_dout;
				5: base_int_1	<= ta_fifo_dout;
				// 6: ignored.
				// 7: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 11). Textured, Packed Color, with Two Volumes.
		25: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x		<= ta_fifo_dout;
				2:  vert_a_y		<= ta_fifo_dout;
				3:  vert_a_z		<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;
				5:  vert_v_0	<= ta_fifo_dout;
				6:  base_col_0	<= ta_fifo_dout;
				7:  offs_col_0	<= ta_fifo_dout;
				8:  vert_u_1	<= ta_fifo_dout;
				9:  vert_v_1	<= ta_fifo_dout;
				10: base_col_1	<= ta_fifo_dout;
				11: offs_col_1	<= ta_fifo_dout;
				// 12: ignored.
				// 13: ignored.
				// 14: ignored.
				// 15: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 12). Textured, Packed Color, 16-bit UV, with Two Volumes.
		/*
		26: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x		<= ta_fifo_dout;
				2:  vert_a_y		<= ta_fifo_dout;
				3:  vert_a_z		<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;	// U/V.
				// 5: ignored.
				6:  base_col_0	<= ta_fifo_dout;
				7:  offs_col_0	<= ta_fifo_dout;
				8:  vert_u_1	<= ta_fifo_dout;	// U/V.
				// 9: ignored.
				10: base_col_1	<= ta_fifo_dout;
				11: offs_col_1	<= ta_fifo_dout;
				// 12: ignored.
				// 13: ignored.
				// 14: ignored.
				// 15: ignored.
				default: ;
			endcase
		end
		*/
		
		// (VERTEX Polygon Type 13). Textured, Intensity, with Two Volumes.
		27: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x		<= ta_fifo_dout;
				2:  vert_a_y		<= ta_fifo_dout;
				3:  vert_a_z		<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;
				5:  vert_v_0	<= ta_fifo_dout;
				6:  base_int_0	<= ta_fifo_dout;
				7:  offs_int_0	<= ta_fifo_dout;
				8:  vert_u_1	<= ta_fifo_dout;
				9:  vert_v_1	<= ta_fifo_dout;
				10: base_int_1	<= ta_fifo_dout;
				11: offs_int_1	<= ta_fifo_dout;
				// 12: ignored.
				// 13: ignored.
				// 14: ignored.
				// 15: ignored.
				default: ;
			endcase
		end

		// (VERTEX Polygon Type 14). Textures, Intensity, 16-bit UV, with Two Volumes.
		/*
		28: begin
			if (curr_word==word_max) begin
				ta_state <= 8'd0;
			end
			else if (!ta_fifo_empty) begin
				ta_fifo_rd <= 1'b1;
				curr_word <= curr_word + 4'd1;
			end
			case (curr_word)
				// 0: PCW.
				1:  vert_a_x		<= ta_fifo_dout;
				2:  vert_a_y		<= ta_fifo_dout;
				3:  vert_a_z		<= ta_fifo_dout;
				4:  vert_u_0	<= ta_fifo_dout;	// U/V.
				// 5: ignored.
				6:  base_int_0	<= ta_fifo_dout;
				7:  offs_int_0	<= ta_fifo_dout;
				8:  vert_u_1	<= ta_fifo_dout;	// U/V.
				// 9: ignored.
				10: base_int_1	<= ta_fifo_dout;
				11: offs_int_1	<= ta_fifo_dout;
				// 12: ignored.
				// 13: ignored.
				// 14: ignored.
				// 15: ignored.
				default: ;
			endcase
		end
		*/
		
		// Start iterating through the tiles that the current Polygon covers...
		29: begin
			//curr_tile_x <= tile_x_min;
			//curr_tile_y <= tile_y_min;
			//ta_state <= ta_state + 8'd1;
		end
		
		default: ta_state <= 8'd0;
	endcase
end


ta_fifo  ta_fifo_inst(
	.clk( clock ),					// Clock
    .reset_n( reset_n ),			// Active low reset
	.data_in( ta_fifo_din ),		// Data input [31:0]
	.wr_en( ta_fifo_wr ),			// Write enable
	
	.rd_en( ta_fifo_rd ),			// Read enable
    .data_out( ta_fifo_dout ),		// Data output [31:0]
	.fifo_count( ta_fifo_used ),	// fifo_count [8:0]
	
    .empty( ta_fifo_empty ),		// FIFO empty flag
    .full( ta_fifo_full )			// FIFO full flag
);

endmodule


module ta_fifo (
    input               clk,
    input               reset_n,      // Active low reset
    input               wr_en,      // Write enable
	input       [31:0]  data_in,    // Data input (32-bit)
	
    input               rd_en,      // Read enable
    output reg  [31:0]  data_out,   // Data output (32-bit)
	
	output reg  [8:0]   fifo_count,	// Counter to track the number of elements in the FIFO
    output              empty,      // FIFO empty flag
    output              full        // FIFO full flag
);

    // FIFO memory array
    reg [31:0] fifo_mem [0:255];

    // Write and read pointers
    reg [7:0] wr_ptr;
    reg [7:0] rd_ptr;

    // Write operation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            fifo_mem[wr_ptr] <= data_in;  // Write data to FIFO
            wr_ptr <= wr_ptr + 1;         // Increment write pointer
        end
    end

    // Read operation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_ptr <= 0;
            data_out <= 0;
        end else if (rd_en && !empty) begin
            data_out <= fifo_mem[rd_ptr];  // Read data from FIFO
            rd_ptr <= rd_ptr + 1;          // Increment read pointer
        end
    end

    // FIFO count logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_count <= 0;
        end else begin
            case ({wr_en, rd_en})
                2'b01: fifo_count <= fifo_count - 1;  // Read only
                2'b10: fifo_count <= fifo_count + 1;  // Write only
                2'b11: fifo_count <= fifo_count;      // Read and write simultaneously
                default: fifo_count <= fifo_count;    // No operation
            endcase
        end
    end

    // Full and empty flags
    assign empty = (fifo_count == 0);
    assign full  = (fifo_count == 256);

endmodule
