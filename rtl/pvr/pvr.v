`timescale 1ns / 1ps
`default_nettype none

// Enable verbose ISP/TSP trace prints with +define+PVR_TSP_TRACE_PRINTS.
// `define PVR_TSP_TRACE_PRINTS
// Enable one-line per-tile render stats with +define+PVR_TILE_STATS_PRINTS.
// `define PVR_TILE_STATS_PRINTS

`define PVR_LITE_INTERP 1
`define PVR_LITE_INTRI_SIMPLE_EDGE 1
`define PVR_LITE_INTRI_TRI_ONLY 0

module pvr #(
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter FRAC_BITS   = 8'd12,	// 12 is about the max atm.
	parameter Z_FRAC_BITS = 8'd17,	// 17 is about the max atm.
	// Z_FRAC_BITS needs to be >= FRAC_BITS. (above about 18, and some HUD text on HOTD2 Gargoyle gets mirrored?)
	parameter FRAC_DIFF = (Z_FRAC_BITS-FRAC_BITS),

`ifndef VERILATOR
	parameter PVR_ENABLE_TEXTURE_PIPELINE = 1'b0,
	parameter PVR_ENABLE_GOURAUD_SHADE    = 1'b0,
	parameter PVR_ENABLE_OFFSET_SHADE     = 1'b0,
	parameter PVR_ENABLE_DEPTH_COMPARE    = 1'b1,
	parameter PVR_ENABLE_TILE_ARGB_BUFFER = 1'b1,
	parameter PVR_INTRI_PIXELS_PER_CYCLE  = 8
`else
	parameter PVR_ENABLE_TEXTURE_PIPELINE = 1'b1,
	parameter PVR_ENABLE_GOURAUD_SHADE    = 1'b1,
	parameter PVR_ENABLE_OFFSET_SHADE     = 1'b1,
	parameter PVR_ENABLE_DEPTH_COMPARE    = 1'b1,
	parameter PVR_ENABLE_TILE_ARGB_BUFFER = 1'b1,
	parameter PVR_INTRI_PIXELS_PER_CYCLE  = 8
`endif
) (
	input clock,
	input reset_n,
	
	input ra_trig,
	input bg_poly_en,
	output trig_pvr_update,
	input pvr_reg_update,

	input ta_fifo_cs,
	input ta_yuv_cs,
	input ta_tex_cs,
	
	// CPU / HOLLY interface to PVR...
	input pvr_reg_cs,
	input [15:0] pvr_addr,
	input [31:0] pvr_din,
	input pvr_rd,
	input pvr_wr,
	output reg [31:0] pvr_dout,
	
	input wire [10:0] sim_ui,
	input wire [10:0] sim_vi,
	
	input [31:0] TEST_SELECT,
	input [31:0] PARAM_BASE,
	input [31:0] REGION_BASE,
	
	input [31:0] FB_R_SOF1,
	input [31:0] FB_R_SOF2,
	
	input [31:0] FPU_PARAM_CFG,
	input [31:0] TEXT_CONTROL,
	input [31:0] PAL_RAM_CTRL,
	input [31:0] TA_ALLOC_CTRL,
	
	input ta_fifo_wr,

	// RA / ISP VRAM read busses (separate).
	input  wire        ra_vram_wait,
	input  wire        ra_vram_valid,
	input  wire        ra_vram_req_ack,
	output wire        ra_vram_rd,
	output wire        ra_vram_wr,
	output wire [23:0] ra_vram_addr,
	input  wire [63:0] ra_vram_din64,
	output wire [31:0] ra_vram_dout,

	input  wire        isp_vram_wait,
	input  wire        isp_vram_valid,
	input  wire        isp_vram_req_ack,
	output wire        isp_vram_rd,
	output wire        isp_vram_wr,
	output wire [23:0] isp_vram_addr,
	input  wire [63:0] isp_vram_din64,
	output wire [31:0] isp_vram_dout,

	output wire codebook_wait,

	input  wire        tex_cache_hit,
	output wire [23:0] tex_vram_addr,	// output  tex_vram_addr (BYTE address!)
	input tex_vram_wait,				// input  input tex_vram_wait,
	output wire tex_vram_rd,			// output  tex_vram_rd
	input wire tex_vram_valid,			// input   tex_vram_valid
	input wire [63:0] tex_vram_din,		// full 64-bit input [63:0]
	input tex_vram_req_ack,
	
	output [22:0] fb_addr,
	output [63:0] fb_writedata,
	output [7:0] fb_byteena,
	output fb_we,
	input fb_wait,
	output fb_pending,
	output wire tile_accum_done,
	output wire frame_done,

	input debug_ena_texel_reads,
	
	input [2:0] state_skip
);


// Main regs...
parameter ID_addr                 = 16'h0000; reg [31:0] ID;				// R   Device ID
parameter REVISION_addr           = 16'h0004; reg [31:0] REVISION;			// R   Revision number
parameter SOFTRESET_addr          = 16'h0008; reg [31:0] SOFTRESET;			// RW  CORE & TA software reset
	
parameter STARTRENDER_addr        = 16'h0014; reg [31:0] STARTRENDER;		// RW  Drawing start
parameter TEST_SELECT_addr        = 16'h0018; //reg [31:0] TEST_SELECT;		// RW  Test - writing this register is prohibited.

parameter PARAM_BASE_addr         = 16'h0020; //reg [31:0] PARAM_BASE;		// RW  Base address for ISP parameters

parameter REGION_BASE_addr        = 16'h002C; //reg [31:0] REGION_BASE;		// RW  Base address for Region Array
parameter SPAN_SORT_CFG_addr      = 16'h0030; reg [31:0] SPAN_SORT_CFG;		// RW  Span Sorter control

parameter VO_BORDER_COL_addr      = 16'h0040; reg [31:0] VO_BORDER_COL;		// RW  Border area color
parameter FB_R_CTRL_addr          = 16'h0044; reg [31:0] FB_R_CTRL;			// RW  Frame buffer read control
parameter FB_W_CTRL_addr          = 16'h0048; reg [31:0] FB_W_CTRL;			// RW  Frame buffer write control
parameter FB_W_LINESTRIDE_addr    = 16'h004C; reg [31:0] FB_W_LINESTRIDE;	// RW  Frame buffer line stride

parameter FB_R_SOF1_addr          = 16'h0050; //reg [31:0] FB_R_SOF1;		// RW  Read start address for field - 1/strip - 1
parameter FB_R_SOF2_addr          = 16'h0054; //reg [31:0] FB_R_SOF2;		// RW  Read start address for field - 2/strip - 2
parameter FB_R_SIZE_addr          = 16'h005C; reg [31:0] FB_R_SIZE;			// RW  Frame buffer XY size	

parameter FB_W_SOF1_addr          = 16'h0060; reg [31:0] FB_W_SOF1;			// RW  Write start address for field - 1/strip - 1
parameter FB_W_SOF2_addr          = 16'h0064; reg [31:0] FB_W_SOF2;			// RW  Write start address for field - 2/strip - 2

parameter FB_X_CLIP_addr          = 16'h0068; reg [31:0] FB_X_CLIP;			// RW  Pixel clip X coordinate
parameter FB_Y_CLIP_addr          = 16'h006C; reg [31:0] FB_Y_CLIP;			// RW  Pixel clip Y coordinate

parameter FPU_SHAD_SCALE_addr     = 16'h0074; reg [31:0] FPU_SHAD_SCALE;	// RW  Intensity Volume mode
parameter FPU_CULL_VAL_addr       = 16'h0078; reg [31:0] FPU_CULL_VAL;		// RW  Comparison value for culling
parameter FPU_PARAM_CFG_addr      = 16'h007C; //reg [31:0] FPU_PARAM_CFG;	// RW  Parameter read control
parameter HALF_OFFSET_addr        = 16'h0080; reg [31:0] HALF_OFFSET;		// RW  Pixel sampling control
parameter FPU_PERP_VAL_addr       = 16'h0084; reg [31:0] FPU_PERP_VAL;		// RW  Comparison value for perpendicular polygons
parameter ISP_BACKGND_D_addr      = 16'h0088; reg [31:0] ISP_BACKGND_D;		// RW  Background surface depth
parameter ISP_BACKGND_T_addr      = 16'h008C; reg [31:0] ISP_BACKGND_T;		// RW  Background surface tag

parameter ISP_FEED_CFG_addr       = 16'h0098; reg [31:0] ISP_FEED_CFG;		// RW  Translucent polygon sort mode

parameter SDRAM_REFRESH_addr      = 16'h00A0; reg [31:0] SDRAM_REFRESH;		// RW  Texture memory refresh counter
parameter SDRAM_ARB_CFG_addr      = 16'h00A4; reg [31:0] SDRAM_ARB_CFG;		// RW  Texture memory arbiter control
parameter SDRAM_CFG_addr          = 16'h00A8; reg [31:0] SDRAM_CFG;			// RW  Texture memory control

parameter FOG_COL_RAM_addr        = 16'h00B0; reg [31:0] FOG_COL_RAM;		// RW  Color for Look Up table Fog
parameter FOG_COL_VERT_addr       = 16'h00B4; reg [31:0] FOG_COL_VERT;		// RW  Color for vertex Fog
parameter FOG_DENSITY_addr        = 16'h00B8; reg [31:0] FOG_DENSITY;		// RW  Fog scale value
parameter FOG_CLAMP_MAX_addr      = 16'h00BC; reg [31:0] FOG_CLAMP_MAX;		// RW  Color clamping maximum value
parameter FOG_CLAMP_MIN_addr      = 16'h00C0; reg [31:0] FOG_CLAMP_MIN;		// RW  Color clamping minimum value
parameter SPG_TRIGGER_POS_addr    = 16'h00C4; reg [31:0] SPG_TRIGGER_POS;	// RW  External trigger signal HV counter value
parameter SPG_HBLANK_INT_addr     = 16'h00C8; reg [31:0] SPG_HBLANK_INT;	// RW  H-blank interrupt control	
parameter SPG_VBLANK_INT_addr     = 16'h00CC; reg [31:0] SPG_VBLANK_INT;	// RW  V-blank interrupt control	
parameter SPG_CONTROL_addr        = 16'h00D0; reg [31:0] SPG_CONTROL;		// RW  Sync pulse generator control
parameter SPG_HBLANK_addr         = 16'h00D4; reg [31:0] SPG_HBLANK;		// RW  H-blank control
parameter SPG_LOAD_addr           = 16'h00D8; reg [31:0] SPG_LOAD;			// RW  HV counter load value
parameter SPG_VBLANK_addr         = 16'h00DC; reg [31:0] SPG_VBLANK;		// RW  V-blank control
parameter SPG_WIDTH_addr          = 16'h00E0; reg [31:0] SPG_WIDTH;			// RW  Sync width control
parameter TEXT_CONTROL_addr       = 16'h00E4; //reg [31:0] TEXT_CONTROL;	// RW  Texturing control
parameter VO_CONTROL_addr         = 16'h00E8; reg [31:0] VO_CONTROL;		// RW  Video output control
parameter VO_STARTX_addr          = 16'h00Ec; reg [31:0] VO_STARTX;			// RW  Video output start X position
parameter VO_STARTY_addr          = 16'h00F0; reg [31:0] VO_STARTY;			// RW  Video output start Y position
parameter SCALER_CTL_addr         = 16'h00F4; reg [31:0] SCALER_CTL;		// RW  X & Y scaler control
parameter PAL_RAM_CTRL_addr       = 16'h0108; //reg [31:0] PAL_RAM_CTRL;	// RW  Palette RAM control
parameter SPG_STATUS_addr         = 16'h010C; reg [31:0] SPG_STATUS;		// R   Sync pulse generator status
parameter FB_BURSTCTRL_addr       = 16'h0110; reg [31:0] FB_BURSTCTRL;		// RW  Frame buffer burst control
parameter FB_C_SOF_addr           = 16'h0114; reg [31:0] FB_C_SOF;			// R   Current frame buffer start address
parameter Y_COEFF_addr            = 16'h0118; reg [31:0] Y_COEFF;			// RW  Y scaling coefficient

parameter PT_ALPHA_REF_addr       = 16'h011C; reg [31:0] PT_ALPHA_REF;		// RW  Alpha value for Punch Through polygon comparison


// TA REGS
parameter TA_OL_BASE_addr         = 16'h0124; reg [31:0] TA_OL_BASE;		// RW  Object list write start address
parameter TA_ISP_BASE_addr        = 16'h0128; reg [31:0] TA_ISP_BASE;		// RW  ISP/TSP Parameter write start address
parameter TA_OL_LIMIT_addr        = 16'h012C; reg [31:0] TA_OL_LIMIT;		// RW  Start address of next Object Pointer Block
parameter TA_ISP_LIMIT_addr       = 16'h0130; reg [31:0] TA_ISP_LIMIT;		// RW  Current ISP/TSP Parameter write address
parameter TA_NEXT_OPB_addr        = 16'h0134; reg [31:0] TA_NEXT_OPB;		// R   Global Tile clip control
parameter TA_ISP_CURRENT_addr     = 16'h0138; reg [31:0] TA_ISP_CURRENT;	// R   Current ISP/TSP Parameter write address
parameter TA_GLOB_TILE_CLIP_addr  = 16'h013C; reg [31:0] TA_GLOB_TILE_CLIP;	// RW  Global Tile clip control
parameter TA_ALLOC_CTRL_addr      = 16'h0140; //reg [31:0] TA_ALLOC_CTRL;		// RW  Object list control
parameter TA_LIST_INIT_addr       = 16'h0144; reg [31:0] TA_LIST_INIT;		// RW  TA initialization
parameter TA_YUV_TEX_BASE_addr    = 16'h0148; reg [31:0] TA_YUV_TEX_BASE;	// RW  YUV422 texture write start address
parameter TA_YUV_TEX_CTRL_addr    = 16'h014C; reg [31:0] TA_YUV_TEX_CTRL;	// RW  YUV converter control
parameter TA_YUV_TEX_CNT_addr     = 16'h0150; reg [31:0] TA_YUV_TEX_CNT;	// R   YUV converter macro block counter value

parameter TA_LIST_CONT_addr       = 16'h0160; reg [31:0] TA_LIST_CONT;		// RW  TA continuation processing
parameter TA_NEXT_OPB_INIT_addr   = 16'h0164; reg [31:0] TA_NEXT_OPB_INIT;	// RW  Additional OPB starting address

parameter FOG_TABLE_START_addr        = 16'h0200; reg [31:0] FOG_TABLE_START;		// RW  Look-up table Fog data
parameter FOG_TABLE_END_addr          = 16'h03FC; reg [31:0] FOG_TABLE_END;

parameter TA_OL_POINTERS_START_addr   = 16'h0600; reg [31:0] TA_OL_POINTERS_START;	// R   TA object List Pointer data
parameter TA_OL_POINTERS_END_addr     = 16'h0F5C; reg [31:0] TA_OL_POINTERS_END;

parameter PALETTE_RAM_START_addr      = 16'h1000; reg [31:0] PALETTE_RAM_START;		// RW  Palette RAM
parameter PALETTE_RAM_END_addr        = 16'h1FFC; reg [31:0] PALETTE_RAM_END;

reg [31:0] dbg_cycle;
always @(posedge clock or negedge reset_n)
if (!reset_n)
	dbg_cycle <= 32'd0;
else
	dbg_cycle <= dbg_cycle + 32'd1;


always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	ID 		 <= 32'h17FD11DB;
	REVISION <= 32'h00000011;
end
else begin
	// Handle PVR and TA reg Writes...
	if (pvr_reg_cs && pvr_wr) begin
		case (pvr_addr)
			// Main HOLLY/PVR regs
			//ID_addr: 			   ID <= pvr_din;					// 16'h0000; R   Device ID
			//REVISION_addr: REVISION <= pvr_din; 					// 16'h0004; R   Revision number
			SOFTRESET_addr: SOFTRESET <= pvr_din; 					// 16'h0008; RW  CORE & TA software reset
				
			STARTRENDER_addr: STARTRENDER <= pvr_din; 				// 16'h0014; RW  Drawing start
			//TEST_SELECT_addr: TEST_SELECT <= pvr_din; 			// 16'h0018; RW  Test - writing this register is prohibited.

			//PARAM_BASE_addr: PARAM_BASE <= pvr_din; 				// 16'h0020; RW  Base address for ISP regs
			//REGION_BASE_addr: REGION_BASE <= pvr_din; 			// 16'h002C; RW  Base address for Region Array
			
			SPAN_SORT_CFG_addr: SPAN_SORT_CFG <= pvr_din; 			// 16'h0030; RW  Span Sorter control

			VO_BORDER_COL_addr: VO_BORDER_COL <= pvr_din; 			// 16'h0040; RW  Border area color
			FB_R_CTRL_addr: FB_R_CTRL <= pvr_din; 					// 16'h0044; RW  Frame buffer read control
			FB_W_CTRL_addr: FB_W_CTRL <= pvr_din; 					// 16'h0048; RW  Frame buffer write control
			FB_W_LINESTRIDE_addr: FB_W_LINESTRIDE <= pvr_din; 		// 16'h004C; RW  Frame buffer line stride
			//FB_R_SOF1_addr: FB_R_SOF1 <= pvr_din; 				// 16'h0050; RW  Read start address for field - 1/strip - 1
			//FB_R_SOF2_addr: FB_R_SOF2 <= pvr_din; 				// 16'h0054; RW  Read start address for field - 2/strip - 2

			FB_R_SIZE_addr: FB_R_SIZE <= pvr_din; 					// 16'h005C; RW  Frame buffer XY size	
			FB_W_SOF1_addr: FB_W_SOF1 <= pvr_din; 					// 16'h0060; RW  Write start address for field - 1/strip - 1
			FB_W_SOF2_addr: FB_W_SOF2 <= pvr_din; 					// 16'h0064; RW  Write start address for field - 2/strip - 2
			FB_X_CLIP_addr: FB_X_CLIP <= pvr_din; 					// 16'h0068; RW  Pixel clip X coordinate
			FB_Y_CLIP_addr: FB_Y_CLIP <= pvr_din; 					// 16'h006C; RW  Pixel clip Y coordinate

			FPU_SHAD_SCALE_addr: FPU_SHAD_SCALE <= pvr_din; 		// 16'h0074; RW  Intensity Volume mode
			FPU_CULL_VAL_addr: FPU_CULL_VAL <= pvr_din; 			// 16'h0078; RW  Comparison value for culling
			//FPU_PARAM_CFG_addr: FPU_PARAM_CFG <= pvr_din; 		// 16'h007C; RW  Parameter read control
			HALF_OFFSET_addr: HALF_OFFSET <= pvr_din; 				// 16'h0080; RW  Pixel sampling control
			FPU_PERP_VAL_addr: FPU_PERP_VAL <= pvr_din; 			// 16'h0084; RW  Comparison value for perpendicular polygons
			ISP_BACKGND_D_addr: ISP_BACKGND_D <= pvr_din; 			// 16'h0088; RW  Background surface depth
			ISP_BACKGND_T_addr: ISP_BACKGND_T <= pvr_din; 			// 16'h008C; RW  Background surface tag

			ISP_FEED_CFG_addr: ISP_FEED_CFG <= pvr_din; 			// 16'h0098; RW  Translucent polygon sort mode

			SDRAM_REFRESH_addr: SDRAM_REFRESH <= pvr_din; 			// 16'h00A0; RW  Texture memory refresh counter
			SDRAM_ARB_CFG_addr: SDRAM_ARB_CFG <= pvr_din; 			// 16'h00A4; RW  Texture memory arbiter control
			SDRAM_CFG_addr: SDRAM_CFG <= pvr_din; 					// 16'h00A8; RW  Texture memory control

			FOG_COL_RAM_addr: FOG_COL_RAM <= pvr_din; 				// 16'h00B0; RW  Color for Look Up table Fog
			FOG_COL_VERT_addr: FOG_COL_VERT <= pvr_din; 			// 16'h00B4; RW  Color for vertex Fog
			FOG_DENSITY_addr: FOG_DENSITY <= pvr_din; 				// 16'h00B8; RW  Fog scale value
			FOG_CLAMP_MAX_addr: FOG_CLAMP_MAX <= pvr_din; 			// 16'h00BC; RW  Color clamping maximum value
			FOG_CLAMP_MIN_addr: FOG_CLAMP_MIN <= pvr_din; 			// 16'h00C0; RW  Color clamping minimum value
			SPG_TRIGGER_POS_addr: SPG_TRIGGER_POS <= pvr_din; 		// 16'h00C4; RW  External trigger signal HV counter value
			SPG_HBLANK_INT_addr: SPG_HBLANK_INT <= pvr_din; 		// 16'h00C8; RW  H-blank interrupt control	
			SPG_VBLANK_INT_addr: SPG_VBLANK_INT <= pvr_din; 		// 16'h00CC; RW  V-blank interrupt control	
			SPG_CONTROL_addr: SPG_CONTROL <= pvr_din; 				// 16'h00D0; RW  Sync pulse generator control
			SPG_HBLANK_addr: SPG_HBLANK <= pvr_din; 				// 16'h00D4; RW  H-blank control
			SPG_LOAD_addr: SPG_LOAD <= pvr_din; 					// 16'h00D8; RW  HV counter load value
			SPG_VBLANK_addr: SPG_VBLANK <= pvr_din; 				// 16'h00DC; RW  V-blank control
			SPG_WIDTH_addr: SPG_WIDTH <= pvr_din; 					// 16'h00E0; RW  Sync width control
			//TEXT_CONTROL_addr: TEXT_CONTROL <= pvr_din; 			// 16'h00E4; RW  Texturing control
			VO_CONTROL_addr: VO_CONTROL <= pvr_din; 				// 16'h00E8; RW  Video output control
			VO_STARTX_addr: VO_STARTX <= pvr_din; 					// 16'h00EC; RW  Video output start X position
			VO_STARTY_addr: VO_STARTY <= pvr_din; 					// 16'h00F0; RW  Video output start Y position
			SCALER_CTL_addr: SCALER_CTL <= pvr_din; 				// 16'h00F4; RW  X & Y scaler control
			//PAL_RAM_CTRL_addr: PAL_RAM_CTRL <= pvr_din; 			// 16'h0108; RW  Palette RAM control
			SPG_STATUS_addr: SPG_STATUS <= pvr_din; 				// 16'h010C; R   Sync pulse generator status
			FB_BURSTCTRL_addr: FB_BURSTCTRL <= pvr_din; 			// 16'h0110; RW  Frame buffer burst control
			FB_C_SOF_addr: FB_C_SOF <= pvr_din; 					// 16'h0114; R   Current frame buffer start address
			Y_COEFF_addr: Y_COEFF <= pvr_din; 						// 16'h0118; RW  Y scaling coefficient
	
			PT_ALPHA_REF_addr: PT_ALPHA_REF <= pvr_din; 			// 16'h011C; RW  Alpha value for Punch Through polygon comparison

			// TA REGS
			TA_OL_BASE_addr: TA_OL_BASE <= pvr_din; 				// 16'h0124; RW  Object list write start address
			TA_ISP_BASE_addr: TA_ISP_BASE <= pvr_din; 				// 16'h0128; RW  ISP/TSP Parameter write start address
			TA_OL_LIMIT_addr: TA_OL_LIMIT <= pvr_din; 				// 16'h012C; RW  Start address of next Object Pointer Block
			TA_ISP_LIMIT_addr: TA_ISP_LIMIT <= pvr_din; 			// 16'h0130; RW  Current ISP/TSP Parameter write address
			TA_NEXT_OPB_addr: TA_NEXT_OPB <= pvr_din; 				// 16'h0134; R   Global Tile clip control
			TA_ISP_CURRENT_addr: TA_ISP_CURRENT <= pvr_din; 		// 16'h0138; R   Current ISP/TSP Parameter write address
			TA_GLOB_TILE_CLIP_addr: TA_GLOB_TILE_CLIP <= pvr_din;	// 16'h013C; RW  Global Tile clip control
			
			//TA_ALLOC_CTRL_addr: TA_ALLOC_CTRL <= pvr_din; 		// 16'h0140; RW  Object list control
			
			TA_LIST_INIT_addr: TA_LIST_INIT <= pvr_din; 				// 16'h0144; RW  TA initialization
			TA_YUV_TEX_BASE_addr: TA_YUV_TEX_BASE <= pvr_din; 			// 16'h0148; RW  YUV422 texture write start address
			TA_YUV_TEX_CTRL_addr: TA_YUV_TEX_CTRL <= pvr_din; 			// 16'h014C; RW  YUV converter control
			TA_YUV_TEX_CNT_addr: TA_YUV_TEX_CNT <= pvr_din; 			// 16'h0150; R   YUV converter macro block counter value

			TA_LIST_CONT_addr: TA_LIST_CONT <= pvr_din; 				// 16'h0160; RW  TA continuation processing
			TA_NEXT_OPB_INIT_addr: TA_NEXT_OPB_INIT <= pvr_din; 		// 16'h0164; RW  Additional OPB starting address

			FOG_TABLE_START_addr: FOG_TABLE_START <= pvr_din; 			// 16'h0200; RW  Look-up table Fog data
			FOG_TABLE_END_addr: FOG_TABLE_END <= pvr_din;				// 16'h03FC;

			TA_OL_POINTERS_START_addr: TA_OL_POINTERS_START <= pvr_din; // 16'h0600; R   TA object List Pointer data
			TA_OL_POINTERS_END_addr: TA_OL_POINTERS_END <= pvr_din;		// 16'h0F5C;

			PALETTE_RAM_START_addr: PALETTE_RAM_START <= pvr_din; 		// 16'h1000; RW  Palette RAM
			PALETTE_RAM_END_addr: PALETTE_RAM_END <= pvr_din;			// 16'h1FFC;
			default: ;
		endcase
	end
end


always @(posedge clock) begin
	// Handle PVR and TA reg Reads...

	// Main HOLLY/PVR regs
	casez (pvr_addr)
		ID_addr:                pvr_dout[31:0] <= ID; 					// R   16'h0000; Device ID
		REVISION_addr:          pvr_dout[31:0] <= REVISION; 			// R   16'h0004; Revision number
		SOFTRESET_addr:         pvr_dout[31:0] <= SOFTRESET; 			// RW  16'h0008; CORE & TA software reset
			
		STARTRENDER_addr:       pvr_dout[31:0] <= STARTRENDER; 			// RW  16'h0014; Drawing start
		TEST_SELECT_addr:       pvr_dout[31:0] <= TEST_SELECT; 			// RW  16'h0018; Test - writing this register is prohibited.

		PARAM_BASE_addr:        pvr_dout[31:0] <= PARAM_BASE; 			// RW  16'h0020; Base address for ISP regs

		REGION_BASE_addr:       pvr_dout[31:0] <= REGION_BASE; 			// RW  16'h002C; Base address for Region Array
		SPAN_SORT_CFG_addr:     pvr_dout[31:0] <= SPAN_SORT_CFG; 		// RW  16'h0030; Span Sorter control

		VO_BORDER_COL_addr:     pvr_dout[31:0] <= VO_BORDER_COL; 		// RW  16'h0040; Border area color
		FB_R_CTRL_addr:         pvr_dout[31:0] <= FB_R_CTRL; 			// RW  16'h0044; Frame buffer read control
		FB_W_CTRL_addr:         pvr_dout[31:0] <= FB_W_CTRL; 			// RW  16'h0048; Frame buffer write control
		FB_W_LINESTRIDE_addr:   pvr_dout[31:0] <= FB_W_LINESTRIDE; 		// RW  16'h004C; Frame buffer line stride
		FB_R_SOF1_addr:         pvr_dout[31:0] <= FB_R_SOF1; 			// RW  16'h0050; Read start address for field - 1/strip - 1
		FB_R_SOF2_addr:         pvr_dout[31:0] <= FB_R_SOF2; 			// RW  16'h0054; Read start address for field - 2/strip - 2
	
		FB_R_SIZE_addr:         pvr_dout[31:0] <= FB_R_SIZE; 			// RW  16'h005C; Frame buffer XY size	
		FB_W_SOF1_addr:         pvr_dout[31:0] <= FB_W_SOF1; 			// RW  16'h0060; Write start address for field - 1/strip - 1
		FB_W_SOF2_addr:         pvr_dout[31:0] <= FB_W_SOF2; 			// RW  16'h0064; Write start address for field - 2/strip - 2
		FB_X_CLIP_addr:         pvr_dout[31:0] <= FB_X_CLIP; 			// RW  16'h0068; Pixel clip X coordinate
		FB_Y_CLIP_addr:         pvr_dout[31:0] <= FB_Y_CLIP; 			// RW  16'h006C; Pixel clip Y coordinate

		FPU_SHAD_SCALE_addr:    pvr_dout[31:0] <= FPU_SHAD_SCALE; 		// RW  16'h0074; Intensity Volume mode
		FPU_CULL_VAL_addr:      pvr_dout[31:0] <= FPU_CULL_VAL; 		// RW  16'h0078; Comparison value for culling
		FPU_PARAM_CFG_addr:     pvr_dout[31:0] <= FPU_PARAM_CFG; 		// RW  16'h007C; Parameter read control
		HALF_OFFSET_addr:       pvr_dout[31:0] <= HALF_OFFSET; 			// RW  16'h0080; Pixel sampling control
		FPU_PERP_VAL_addr:      pvr_dout[31:0] <= FPU_PERP_VAL; 		// RW  16'h0084; Comparison value for perpendicular polygons
		ISP_BACKGND_D_addr:     pvr_dout[31:0] <= ISP_BACKGND_D; 		// RW  16'h0088; Background surface depth
		ISP_BACKGND_T_addr:     pvr_dout[31:0] <= ISP_BACKGND_T; 		// RW  16'h008C; Background surface tag

		ISP_FEED_CFG_addr:      pvr_dout[31:0] <= ISP_FEED_CFG; 		// RW  16'h0098; Translucent polygon sort mode

		SDRAM_REFRESH_addr:     pvr_dout[31:0] <= SDRAM_REFRESH; 		// RW  16'h00A0; Texture memory refresh counter
		SDRAM_ARB_CFG_addr:     pvr_dout[31:0] <= SDRAM_ARB_CFG; 		// RW  16'h00A4; Texture memory arbiter control
		SDRAM_CFG_addr:         pvr_dout[31:0] <= SDRAM_CFG; 			// RW  16'h00A8; Texture memory control

		FOG_COL_RAM_addr:       pvr_dout[31:0] <= FOG_COL_RAM; 			// RW  16'h00B0; Color for Look Up table Fog
		FOG_COL_VERT_addr:      pvr_dout[31:0] <= FOG_COL_VERT; 		// RW  16'h00B4; Color for vertex Fog
		FOG_DENSITY_addr:       pvr_dout[31:0] <= FOG_DENSITY; 			// RW  16'h00B8; Fog scale value
		FOG_CLAMP_MAX_addr:     pvr_dout[31:0] <= FOG_CLAMP_MAX; 		// RW  16'h00BC; Color clamping maximum value
		FOG_CLAMP_MIN_addr:     pvr_dout[31:0] <= FOG_CLAMP_MIN; 		// RW  16'h00C0; Color clamping minimum value
		SPG_TRIGGER_POS_addr:   pvr_dout[31:0] <= SPG_TRIGGER_POS; 		// RW  16'h00C4; External trigger signal HV counter value
		SPG_HBLANK_INT_addr:    pvr_dout[31:0] <= SPG_HBLANK_INT; 		// RW  16'h00C8; H-blank interrupt control	
		SPG_VBLANK_INT_addr:    pvr_dout[31:0] <= SPG_VBLANK_INT; 		// RW  16'h00CC; V-blank interrupt control	
		SPG_CONTROL_addr:       pvr_dout[31:0] <= SPG_CONTROL; 			// RW  16'h00D0; Sync pulse generator control
		SPG_HBLANK_addr:        pvr_dout[31:0] <= SPG_HBLANK; 			// RW  16'h00D4; H-blank control
		SPG_LOAD_addr:          pvr_dout[31:0] <= SPG_LOAD; 			// RW  16'h00D8; HV counter load value
		SPG_VBLANK_addr:        pvr_dout[31:0] <= SPG_VBLANK; 			// RW  16'h00DC; V-blank control
		SPG_WIDTH_addr:         pvr_dout[31:0] <= SPG_WIDTH; 			// RW  16'h00E0; Sync width control
		TEXT_CONTROL_addr:      pvr_dout[31:0] <= TEXT_CONTROL; 		// RW  16'h00E4; Texturing control
		VO_CONTROL_addr:        pvr_dout[31:0] <= VO_CONTROL; 			// RW  16'h00E8; Video output control
		VO_STARTX_addr:         pvr_dout[31:0] <= VO_STARTX; 			// RW  16'h00EC; Video output start X position
		VO_STARTY_addr:         pvr_dout[31:0] <= VO_STARTY; 			// RW  16'h00F0; Video output start Y position
		SCALER_CTL_addr:        pvr_dout[31:0] <= SCALER_CTL; 			// RW  16'h00F4; X & Y scaler control
		PAL_RAM_CTRL_addr:      pvr_dout[31:0] <= PAL_RAM_CTRL; 		// RW  16'h0108; Palette RAM control
		SPG_STATUS_addr:        pvr_dout[31:0] <= SPG_STATUS; 			// R   16'h010C; Sync pulse generator status
		FB_BURSTCTRL_addr:      pvr_dout[31:0] <= FB_BURSTCTRL; 		// RW  16'h0110; Frame buffer burst control
		FB_C_SOF_addr:          pvr_dout[31:0] <= FB_C_SOF; 			// R   16'h0114; Current frame buffer start address
		Y_COEFF_addr:           pvr_dout[31:0] <= Y_COEFF; 				// RW  16'h0118; Y scaling coefficient

		PT_ALPHA_REF_addr:      pvr_dout[31:0] <=  PT_ALPHA_REF; 		// RW  16'h011C; Alpha value for Punch Through polygon comparison

		// TA REGS
		TA_OL_BASE_addr:        pvr_dout[31:0] <= TA_OL_BASE; 			// RW  16'h0124; Object list write start address
		TA_ISP_BASE_addr:       pvr_dout[31:0] <= TA_ISP_BASE; 			// RW  16'h0128; ISP/TSP Parameter write start address
		TA_OL_LIMIT_addr:       pvr_dout[31:0] <= TA_OL_LIMIT; 			// RW  16'h012C; Start address of next Object Pointer Block
		TA_ISP_LIMIT_addr:      pvr_dout[31:0] <= TA_ISP_LIMIT; 		// RW  16'h0130; Current ISP/TSP Parameter write address
		TA_NEXT_OPB_addr:       pvr_dout[31:0] <= TA_NEXT_OPB; 			// R   16'h0134; Global Tile clip control
		TA_ISP_CURRENT_addr:    pvr_dout[31:0] <= TA_ISP_CURRENT; 		// R   16'h0138; Current ISP/TSP Parameter write address
		TA_GLOB_TILE_CLIP_addr: pvr_dout[31:0] <= TA_GLOB_TILE_CLIP;	// RW  16'h013C; Global Tile clip control
		TA_ALLOC_CTRL_addr:     pvr_dout[31:0] <= TA_ALLOC_CTRL; 		// RW  16'h0140; Object list control
		TA_LIST_INIT_addr:      pvr_dout[31:0] <= TA_LIST_INIT; 		// RW  16'h0144; TA initialization
		TA_YUV_TEX_BASE_addr:   pvr_dout[31:0] <= TA_YUV_TEX_BASE; 		// RW  16'h0148; YUV422 texture write start address
		TA_YUV_TEX_CTRL_addr:   pvr_dout[31:0] <= TA_YUV_TEX_CTRL; 		// RW  16'h014C; YUV converter control
		TA_YUV_TEX_CNT_addr:    pvr_dout[31:0] <= TA_YUV_TEX_CNT; 		// R   16'h0150; YUV converter macro block counter value

		TA_LIST_CONT_addr:      pvr_dout[31:0] <= TA_LIST_CONT; 		// RW  16'h0160; TA continuation processing
		TA_NEXT_OPB_INIT_addr:  pvr_dout[31:0] <= TA_NEXT_OPB_INIT; 	// RW  16'h0164; Additional OPB starting address

		FOG_TABLE_START_addr:   pvr_dout[31:0] <= FOG_TABLE_START; 		// RW  16'h0200; Look-up table Fog data
		FOG_TABLE_END_addr:     pvr_dout[31:0] <= FOG_TABLE_END;		//     16'h03FC;

		TA_OL_POINTERS_START_addr: pvr_dout[31:0] <= TA_OL_POINTERS_START;	// 16'h0600; R  TA object List Pointer data
		TA_OL_POINTERS_END_addr:   pvr_dout[31:0] <= TA_OL_POINTERS_END;	// 16'h0F5C;

		//PALETTE_RAM_START_addr:    pvr_dout[31:0] <= PALETTE_RAM_START; 	// 16'h1000; RW  Palette RAM
		//PALETTE_RAM_END_addr:      pvr_dout[31:0] <= PALETTE_RAM_END;		// 16'h1FFC;
		16'b0001????????????:      pvr_dout[31:0] <= pal_dout;

		default: ;
	endcase
end

wire render_bg;

wire [31:0] ra_control;
wire ra_cont_last;
wire ra_cont_zclear_n;
wire ra_cont_flush_n;
wire [5:0] ra_cont_tiley;
wire [5:0] ra_cont_tilex;

wire [31:0] ra_opaque;
wire [31:0] ra_op_mod;
wire [31:0] ra_trans;
wire [31:0] ra_tr_mod;
wire [31:0] ra_puncht;

wire ra_entry_valid;

wire [31:0] opb_word;
wire [23:0] poly_addr;
wire render_poly;
wire render_to_tile;
wire [2:0] type_cnt;

wire ra_new_tile_start;

wire isp_idle = (isp_state==8'd0);
wire tsp_busy;
wire isp_prefetch_ready;

ra_parser  ra_parser_inst (
	.clock( clock ),		// input  clock
	.reset_n( reset_n ),	// input  reset_n
	
	.TEST_SELECT( TEST_SELECT ),
	.ra_trig( ra_trig ),	// input  ra_trig
	.bg_poly_en( bg_poly_en ),
	.trig_pvr_update( trig_pvr_update ),
	.pvr_reg_update( pvr_reg_update ),
	
	.ISP_BACKGND_D( ISP_BACKGND_D ),	// input [31:0]  ISP_BACKGND_D
	.ISP_BACKGND_T( ISP_BACKGND_T ),	// input [31:0]  ISP_BACKGND_T
	.render_bg( render_bg ),			// output  render_bg

	.PARAM_BASE( PARAM_BASE ),			// input [31:0]  PARAM_BASE  0x20.
	.REGION_BASE( REGION_BASE ),		// input [31:0]  REGION_BASE 0x2C.
	.TA_ALLOC_CTRL( TA_ALLOC_CTRL ),	// input [31:0]  TA_ALLOC_CTRL 0x140.
	.FPU_PARAM_CFG( FPU_PARAM_CFG ),	// input [31:0]  FPU_PARAM_CFG. 0x7C.
	
	.ra_vram_wait( ra_vram_wait ),		// input  ra_vram_wait
	.ra_vram_valid( ra_vram_valid ),	// input  ra_vram_valid
	.ra_vram_rd( ra_vram_rd ),			// output  ra_vram_rd
	.ra_vram_wr( ra_vram_wr ),			// output  ra_vram_wr
	.ra_vram_addr( ra_vram_addr ),		// output [23:0]  ra_vram_addr
	.ra_vram_din( ra_vram_din ),		// input [31:0]   ra_vram_din
	.ra_vram_dout( ra_vram_dout ),		// output [31:0]   ra_vram_dout
	
	.ra_control( ra_control ),			// output [31:0]  ra_control
	.ra_cont_last( ra_cont_last ),		// output ra_cont_last
	.ra_cont_zclear_n( ra_cont_zclear_n ),	// output ra_cont_zclear
	.ra_cont_flush_n( ra_cont_flush_n ),	// output ra_cont_flush_n
	.ra_cont_tiley( ra_cont_tiley ),	// output [5:0]  ra_cont_tiley
	.ra_cont_tilex( ra_cont_tilex ),	// output [5:0]  ra_cont_tilex

	.ra_new_tile_start( ra_new_tile_start ),	// output  ra_new_tile_start
	.type_cnt( type_cnt ),				// output [2:0]  type_cnt
	
	.isp_idle( isp_idle ),
	.isp_prefetch_ready( isp_prefetch_ready ),
	.tsp_busy( tsp_busy ),

	.ra_opaque( ra_opaque ),			// output [31:0]  ra_opaque
	.ra_op_mod( ra_op_mod ),			// output [31:0]  ra_op_mod
	.ra_trans( ra_trans ),				// output [31:0]  ra_trans
	.ra_tr_mod( ra_tr_mod ),			// output [31:0]  ra_tr_mod
	.ra_puncht( ra_puncht ),			// output [31:0]  ra_puncht
	
	.ra_entry_valid( ra_entry_valid ),	// output  ra_entry_valid
	
	.opb_word( opb_word ),				// output [31:0]  opb_word
	
	.poly_addr( poly_addr ),			// output [23:0]  poly_addr
	.render_poly( render_poly ),		// output  render_poly
	.render_to_tile( render_to_tile ),	// output  render_to_tile
	
	.poly_drawn( poly_drawn ),			// input  poly_drawn
	.tile_prims_done( tile_prims_done ),	// output tile_prims_done
	
	.tile_accum_done( tile_accum_done ),	// input  tile_accum_done
	.frame_done( frame_done )
);


wire tile_prims_done;
wire poly_drawn;
wire isp_tile_accum_done;
wire tile_wb_req = isp_tile_accum_done;
wire tile_wb_done;
wire tile_wb_busy;

assign tile_accum_done = tile_wb_done;

wire isp_entry_valid;

// Side-by-side VRAM layout selected by address bit 22.
wire [31:0] ra_vram_din  = (ra_vram_addr[22])  ? ra_vram_din64[63:32]  : ra_vram_din64[31:00];
wire [31:0] isp_vram_din = (isp_vram_addr[22]) ? isp_vram_din64[63:32] : isp_vram_din64[31:00];

wire [8:0] isp_state;
wire [7:0] cache_ddr_burstcnt;
wire [31:0] pal_dout;

wire tsp_pipe_flush;
wire tsp_read_codebook;
wire tsp_cb_cache_clear;
wire tsp_cb_cache_hit;
wire [31:0] tsp_isp_inst_out;
wire [31:0] tsp_tsp_inst_out;
wire [31:0] tsp_tcw_word_out;
wire signed [31:0] tsp_FDDX_BASE_A, tsp_FDDY_BASE_A, tsp_c_BASE_A;
wire signed [31:0] tsp_FDDX_BASE_R, tsp_FDDY_BASE_R, tsp_c_BASE_R;
wire signed [31:0] tsp_FDDX_BASE_G, tsp_FDDY_BASE_G, tsp_c_BASE_G;
wire signed [31:0] tsp_FDDX_BASE_B, tsp_FDDY_BASE_B, tsp_c_BASE_B;
wire signed [47:0] tsp_FDDX_U, tsp_FDDY_U, tsp_small_c_u;
wire signed [47:0] tsp_FDDX_V, tsp_FDDY_V, tsp_small_c_v;
wire signed [31:0] tsp_FDDX_OFFS_A, tsp_FDDY_OFFS_A, tsp_c_OFFS_A;
wire signed [31:0] tsp_FDDX_OFFS_R, tsp_FDDY_OFFS_R, tsp_c_OFFS_R;
wire signed [31:0] tsp_FDDX_OFFS_G, tsp_FDDY_OFFS_G, tsp_c_OFFS_G;
wire signed [31:0] tsp_FDDX_OFFS_B, tsp_FDDY_OFFS_B, tsp_c_OFFS_B;
wire [10:0] tsp_x_ps_cmd;
wire [10:0] tsp_y_ps_cmd;
wire signed [47:0] tsp_z_out;
wire [2:0] tsp_type_cnt_cmd;
wire [5:0] tsp_tilex_cmd;
wire [5:0] tsp_tiley_cmd;
wire tsp_pix_wr_cmd;
wire tsp_tex_data_ready;
wire tsp_transfer_z;
wire [11:0] tsp_rle_tag;
wire [9:0] tsp_rle_count;
wire [4:0] tsp_rle_row_start;
wire [4:0] tsp_rle_col_start;
wire tsp_rle_valid;
wire tsp_rle_busy;
wire tsp_rle_param_load;
wire tsp_rle_done;
wire [21:0] tsp_tex_word_addr;
wire tsp_pipeline_stall;
wire tsp_pipeline_busy;
wire tsp_texel_valid;
wire [31:0] tsp_texel_argb;
wire [31:0] tsp_final_argb;
wire [15:0] tsp_pix_565;
wire [9:0] tsp_x_ps_out;
wire [9:0] tsp_y_ps_out;
wire tsp_pix_valid;
wire [22:0] tsp_tile_fb_addr;
wire [63:0] tsp_tile_fb_writedata;
wire [7:0] tsp_tile_fb_byteena;
wire tsp_tile_fb_we;

isp_parser #(
	.PIXEL_CENTER_SAMPLE ( PIXEL_CENTER_SAMPLE ),
	.FRAC_BITS       ( FRAC_BITS ),
	.Z_FRAC_BITS     ( Z_FRAC_BITS ),
	.FRAC_DIFF       ( FRAC_DIFF ),
	.ENABLE_TEXTURE_PIPELINE ( PVR_ENABLE_TEXTURE_PIPELINE ),
	.ENABLE_TEXTURE_PARAMS ( PVR_ENABLE_TEXTURE_PIPELINE ),
	.ENABLE_GOURAUD_PARAMS ( PVR_ENABLE_GOURAUD_SHADE ),
	.ENABLE_OFFSET_PARAMS  ( PVR_ENABLE_OFFSET_SHADE ),
	.ENABLE_DEPTH_COMPARE  ( PVR_ENABLE_DEPTH_COMPARE ),
	.INTRI_PIXELS_PER_CYCLE( PVR_INTRI_PIXELS_PER_CYCLE )
) isp_parser_inst (
	.clock( clock ),					// input  clock
	.reset_n( reset_n ),				// input  reset_n

	.disable_alpha( 1'b0 ),				// input  disable_alpha
	
	.ISP_BACKGND_D( ISP_BACKGND_D ),	// input [31:0]  ISP_BACKGND_D
	.ISP_BACKGND_T( ISP_BACKGND_T ),	// input [31:0]  ISP_BACKGND_T
	.render_bg( render_bg ),			// input  render_bg
	
	.dbg_cycle( dbg_cycle ),			// input [31:0]
	
	.opb_word( opb_word ),				// input [31:0]  opb_word
	.type_cnt( type_cnt ),				// input [2:0]  type_cnt
	
	.ra_cont_zclear_n( ra_cont_zclear_n ),		// input  ra_cont_zclear_n
	.ra_cont_flush_n( ra_cont_flush_n ),		// input ra_cont_flush
	.poly_addr( poly_addr ),					// input [23:0]  poly_addr
	.render_poly( render_poly ),				// input  render_poly
	.render_to_tile( render_to_tile ),			// input  render_to_tile
	
	.isp_vram_addr( isp_vram_addr ),			// output [23:0]  isp_vram_addr_out
	.isp_vram_rd( isp_vram_rd ),				// output  isp_vram_rd
	.isp_vram_valid( isp_vram_valid ),			// input  vram_valid
	.isp_vram_req_ack( isp_vram_req_ack ),		// input  vram_req_ack
	.isp_vram_din( isp_vram_din ),				// input  [31:0]  isp_vram_din

	.isp_vram_wait( isp_vram_wait ),			// input  isp_vram_wait
	.isp_vram_wr( isp_vram_wr ),				// output  isp_vram_wr
	.isp_vram_dout( isp_vram_dout ),			// output  [31:0]  isp_vram_dout
	
	.codebook_wait( codebook_wait ),			// output  codebook_wait

	.tex_cache_hit( tex_cache_hit ),			// input  tex_cache_hit
	.tex_vram_addr( tex_vram_addr ),			// output [23:0] tex_vram_addr
	.tex_vram_wait( tex_vram_wait ),			// input tex_vram_wait
	.tex_vram_rd( tex_vram_rd ),				// output  tex_vram_rd
	.tex_vram_valid( tex_vram_valid ),			// input   tex_vram_valid
	.tex_vram_req_ack( tex_vram_req_ack ),		// input  tex_vram_req_ack
	
	.isp_entry_valid( isp_entry_valid ),		// output  isp_entry_valid
	
	.ra_new_tile_start( ra_new_tile_start ),	// input  ra_new_tile_start
	.ra_entry_valid( ra_entry_valid ),			// New Region Array entry read / new tile.
	.tile_prims_done( tile_prims_done ),		// input tile_prims_done
	
	.poly_drawn( poly_drawn ),					// output poly_drawn
	.tile_accum_done( isp_tile_accum_done ),		// output  tile_accum_done
	.isp_prefetch_ready( isp_prefetch_ready ),
	
	.tilex( ra_cont_tilex ),
	.tiley( ra_cont_tiley ),
	
	.sim_ui( sim_ui ),
	.sim_vi( sim_vi ),
	
	.FB_R_SOF1( FB_R_SOF1 ),
	.FB_R_SOF2( FB_R_SOF2 ),
	
	.isp_state( isp_state ),						// output [7:0]  isp_state
	
	.debug_ena_texel_reads( debug_ena_texel_reads ),	// input  debug_ena_texel_reads
	
	.tsp_busy( tsp_busy ),								// output tsp_busy
	
	.state_skip( state_skip ),							// input [2:0]  state_skip

	.tsp_pipe_flush( tsp_pipe_flush ),
	.tsp_read_codebook( tsp_read_codebook ),
	.tsp_cb_cache_clear( tsp_cb_cache_clear ),
	.tsp_cb_cache_hit( tsp_cb_cache_hit ),
	.tsp_isp_inst_out( tsp_isp_inst_out ),
	.tsp_tsp_inst_out( tsp_tsp_inst_out ),
	.tsp_tcw_word_out( tsp_tcw_word_out ),
	.tsp_FDDX_BASE_A( tsp_FDDX_BASE_A ), .tsp_FDDY_BASE_A( tsp_FDDY_BASE_A ), .tsp_c_BASE_A( tsp_c_BASE_A ),
	.tsp_FDDX_BASE_R( tsp_FDDX_BASE_R ), .tsp_FDDY_BASE_R( tsp_FDDY_BASE_R ), .tsp_c_BASE_R( tsp_c_BASE_R ),
	.tsp_FDDX_BASE_G( tsp_FDDX_BASE_G ), .tsp_FDDY_BASE_G( tsp_FDDY_BASE_G ), .tsp_c_BASE_G( tsp_c_BASE_G ),
	.tsp_FDDX_BASE_B( tsp_FDDX_BASE_B ), .tsp_FDDY_BASE_B( tsp_FDDY_BASE_B ), .tsp_c_BASE_B( tsp_c_BASE_B ),
	.tsp_FDDX_U( tsp_FDDX_U ), .tsp_FDDY_U( tsp_FDDY_U ), .tsp_small_c_u( tsp_small_c_u ),
	.tsp_FDDX_V( tsp_FDDX_V ), .tsp_FDDY_V( tsp_FDDY_V ), .tsp_small_c_v( tsp_small_c_v ),
	.tsp_FDDX_OFFS_A( tsp_FDDX_OFFS_A ), .tsp_FDDY_OFFS_A( tsp_FDDY_OFFS_A ), .tsp_c_OFFS_A( tsp_c_OFFS_A ),
	.tsp_FDDX_OFFS_R( tsp_FDDX_OFFS_R ), .tsp_FDDY_OFFS_R( tsp_FDDY_OFFS_R ), .tsp_c_OFFS_R( tsp_c_OFFS_R ),
	.tsp_FDDX_OFFS_G( tsp_FDDX_OFFS_G ), .tsp_FDDY_OFFS_G( tsp_FDDY_OFFS_G ), .tsp_c_OFFS_G( tsp_c_OFFS_G ),
	.tsp_FDDX_OFFS_B( tsp_FDDX_OFFS_B ), .tsp_FDDY_OFFS_B( tsp_FDDY_OFFS_B ), .tsp_c_OFFS_B( tsp_c_OFFS_B ),
	.tsp_x_ps_cmd( tsp_x_ps_cmd ),
	.tsp_y_ps_cmd( tsp_y_ps_cmd ),
	.tsp_z_out( tsp_z_out ),
	.tsp_type_cnt_cmd( tsp_type_cnt_cmd ),
	.tsp_tilex_cmd( tsp_tilex_cmd ),
	.tsp_tiley_cmd( tsp_tiley_cmd ),
	.tsp_pix_wr_cmd( tsp_pix_wr_cmd ),
	.tsp_tex_data_ready( tsp_tex_data_ready ),
	.tsp_transfer_z( tsp_transfer_z ),
	.tsp_rle_tag( tsp_rle_tag ),
	.tsp_rle_count( tsp_rle_count ),
	.tsp_rle_row_start( tsp_rle_row_start ),
	.tsp_rle_col_start( tsp_rle_col_start ),
	.tsp_rle_valid( tsp_rle_valid ),
	.tsp_rle_busy( tsp_rle_busy ),
	.tsp_rle_param_load( tsp_rle_param_load ),
	.tsp_rle_done( tsp_rle_done ),
	.tsp_tex_word_addr( tsp_tex_word_addr ),
	.tsp_pipeline_stall( tsp_pipeline_stall ),
	.tsp_pipeline_busy( tsp_pipeline_busy ),
	.tsp_texel_valid( tsp_texel_valid ),
	.tsp_pix_valid( tsp_pix_valid )
);

tsp #(
	.FRAC_BITS       ( FRAC_BITS ),
	.Z_FRAC_BITS     ( Z_FRAC_BITS ),
	.FRAC_DIFF       ( FRAC_DIFF ),
	.ENABLE_TEXTURE_PIPELINE ( PVR_ENABLE_TEXTURE_PIPELINE ),
	.ENABLE_GOURAUD_SHADE    ( PVR_ENABLE_GOURAUD_SHADE ),
	.ENABLE_OFFSET_SHADE     ( PVR_ENABLE_OFFSET_SHADE ),
	.ENABLE_TILE_ARGB_BUFFER ( PVR_ENABLE_TILE_ARGB_BUFFER )
)
tsp_top (
	.clock           ( clock ),
	.reset_n         ( reset_n ),
	.pipe_flush      ( tsp_pipe_flush ),

	.TEXT_CONTROL    ( TEXT_CONTROL ),
	.PAL_RAM_CTRL    ( PAL_RAM_CTRL ),
	.FPU_SHAD_SCALE  ( FPU_SHAD_SCALE ),
	.dbg_cycle       ( dbg_cycle ),

	.pal_addr        ( pvr_addr[11:2] ),
	.pal_din         ( pvr_din ),
	.pal_wr          ( pvr_addr[15:12]==4'b0001 && pvr_wr ),
	.pal_rd          ( pvr_rd ),
	.pal_dout        ( pal_dout ),

	.read_codebook   ( tsp_read_codebook ),
	.codebook_wait   ( codebook_wait ),
	.cb_cache_clear  ( tsp_cb_cache_clear ),
	.cb_cache_hit    ( tsp_cb_cache_hit ),

	.isp_inst_out    ( tsp_isp_inst_out ),
	.tsp_inst_out    ( tsp_tsp_inst_out ),
	.tcw_word_out    ( tsp_tcw_word_out ),

	.FDDX_BASE_A     ( tsp_FDDX_BASE_A ), .FDDY_BASE_A( tsp_FDDY_BASE_A ), .c_BASE_A( tsp_c_BASE_A ),
	.FDDX_BASE_R     ( tsp_FDDX_BASE_R ), .FDDY_BASE_R( tsp_FDDY_BASE_R ), .c_BASE_R( tsp_c_BASE_R ),
	.FDDX_BASE_G     ( tsp_FDDX_BASE_G ), .FDDY_BASE_G( tsp_FDDY_BASE_G ), .c_BASE_G( tsp_c_BASE_G ),
	.FDDX_BASE_B     ( tsp_FDDX_BASE_B ), .FDDY_BASE_B( tsp_FDDY_BASE_B ), .c_BASE_B( tsp_c_BASE_B ),

	.FDDX_U          ( tsp_FDDX_U ), .FDDY_U( tsp_FDDY_U ), .small_c_u( tsp_small_c_u ),
	.FDDX_V          ( tsp_FDDX_V ), .FDDY_V( tsp_FDDY_V ), .small_c_v( tsp_small_c_v ),

	.FDDX_OFFS_A     ( tsp_FDDX_OFFS_A ), .FDDY_OFFS_A( tsp_FDDY_OFFS_A ), .c_OFFS_A( tsp_c_OFFS_A ),
	.FDDX_OFFS_R     ( tsp_FDDX_OFFS_R ), .FDDY_OFFS_R( tsp_FDDY_OFFS_R ), .c_OFFS_R( tsp_c_OFFS_R ),
	.FDDX_OFFS_G     ( tsp_FDDX_OFFS_G ), .FDDY_OFFS_G( tsp_FDDY_OFFS_G ), .c_OFFS_G( tsp_c_OFFS_G ),
	.FDDX_OFFS_B     ( tsp_FDDX_OFFS_B ), .FDDY_OFFS_B( tsp_FDDY_OFFS_B ), .c_OFFS_B( tsp_c_OFFS_B ),

	.x_ps            ( tsp_x_ps_cmd ),
	.y_ps            ( tsp_y_ps_cmd ),
	.z_out           ( tsp_z_out ),
	.prim_tag_out    ( 12'd0 ),
	.type_cnt        ( tsp_type_cnt_cmd ),

	.row_sel         ( 5'd0 ),
	.col_sel         ( 5'd0 ),
	.transfer_z      ( tsp_transfer_z ),
	.rle_tag         ( tsp_rle_tag ),
	.rle_count       ( tsp_rle_count ),
	.rle_row_start   ( tsp_rle_row_start ),
	.rle_col_start   ( tsp_rle_col_start ),
	.rle_valid       ( tsp_rle_valid ),
	.rle_busy        ( tsp_rle_busy ),
	.rle_param_load  ( tsp_rle_param_load ),
	.rle_done        ( tsp_rle_done ),

	.disable_alpha         ( 1'b0 ),
	.debug_ena_texel_reads ( debug_ena_texel_reads ),

	.tsp_tex_word_addr( tsp_tex_word_addr ),
	.tex_vram_din     ( tex_vram_din ),
	.vram_wait        ( tex_vram_wait ),
	.tex_vram_valid   ( tex_vram_valid ),
	.tex_data_ready   ( tsp_tex_data_ready ),

	.wr_pix           ( 1'b0 ),
	.tile_wb          ( tile_wb_req ),
	.wb_done          ( tile_wb_done ),
	.tilex            ( tsp_tilex_cmd ),
	.tiley            ( tsp_tiley_cmd ),

	.pipeline_stall   ( tsp_pipeline_stall ),
	.pipeline_busy    ( tsp_pipeline_busy ),
	.tsp_pix_wr       ( tsp_pix_wr_cmd ),

	.texel_argb       ( tsp_texel_argb ),
	.texel_valid      ( tsp_texel_valid ),
	.final_argb       ( tsp_final_argb ),
	.pix_565          ( tsp_pix_565 ),
	.x_ps_out         ( tsp_x_ps_out ),
	.y_ps_out         ( tsp_y_ps_out ),
	.pix_valid        ( tsp_pix_valid ),
	.fb_addr          ( tsp_tile_fb_addr ),
	.fb_writedata     ( tsp_tile_fb_writedata ),
	.fb_byteena       ( tsp_tile_fb_byteena ),
	.fb_we            ( tsp_tile_fb_we ),
	.fb_wait          ( fb_wait ),
	.tile_wb_busy     ( tile_wb_busy )
);

assign fb_byteena = tsp_tile_fb_byteena;
assign fb_addr = tsp_tile_fb_addr;
assign fb_writedata = tsp_tile_fb_writedata;
assign fb_we = tsp_tile_fb_we;
assign fb_pending = tile_wb_busy;

(* keep *) reg [31:0] dbg_tsp_pix_valid_count;
(* keep *) reg [31:0] dbg_fb_we_count;
(* keep *) reg [31:0] dbg_tile_wb_req_count;
(* keep *) reg [31:0] dbg_tile_wb_done_count;
(* keep *) reg [22:0] dbg_last_fb_addr;
(* keep *) reg [63:0] dbg_last_fb_writedata;

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		dbg_tsp_pix_valid_count <= 32'd0;
		dbg_fb_we_count <= 32'd0;
		dbg_tile_wb_req_count <= 32'd0;
		dbg_tile_wb_done_count <= 32'd0;
		dbg_last_fb_addr <= 23'd0;
		dbg_last_fb_writedata <= 64'd0;
	end
	else begin
		if (tsp_pix_valid) dbg_tsp_pix_valid_count <= dbg_tsp_pix_valid_count + 32'd1;
		if (fb_we && !fb_wait) begin
			dbg_fb_we_count <= dbg_fb_we_count + 32'd1;
			dbg_last_fb_addr <= fb_addr;
			dbg_last_fb_writedata <= fb_writedata;
		end
		if (tile_wb_req) dbg_tile_wb_req_count <= dbg_tile_wb_req_count + 32'd1;
		if (tile_wb_done) dbg_tile_wb_done_count <= dbg_tile_wb_done_count + 32'd1;
	end
end

`ifdef VERILATOR
`ifdef PVR_TILE_STATS_PRINTS
reg [31:0] tile_stat_cycles;
reg [31:0] tile_stat_ra_rd;
reg [31:0] tile_stat_isp_rd;
reg [31:0] tile_stat_tex_rd;
reg [31:0] tile_stat_fb_we;
reg [31:0] tile_stat_hsr_cycles;
reg [31:0] tile_stat_tsp_cycles;
reg [31:0] tile_stat_tsp_tex_wait_cycles;
reg [31:0] tile_stat_tsp_drain_cycles;
reg [31:0] tile_stat_tri_prev;
reg [31:0] tile_stat_vis_prev;
reg [31:0] tile_stat_tag_prev;
reg [31:0] tile_stat_cb_prev;
reg [31:0] tile_stat_tsp_tex_wait_prev;
reg [31:0] tile_stat_tsp_empty_prev;
reg [31:0] tile_stat_tsp_empty_row_prev;
reg [31:0] tile_stat_print_tri;
reg [31:0] tile_stat_print_vis;
reg [31:0] tile_stat_print_tag;
reg [31:0] tile_stat_print_cb;
reg [31:0] tile_stat_print_tsp_tex_wait;
reg [31:0] tile_stat_print_tsp_empty;
reg [31:0] tile_stat_print_tsp_empty_row;
reg [31:0] tile_stat_poly_refs;
reg [31:0] tile_stat_poly_hits;
reg [31:0] tile_stat_poly_consec;
reg [5:0] tile_stat_poly_unique;
reg [23:0] tile_stat_poly_last;
reg tile_stat_poly_last_valid;
reg [23:0] tile_stat_poly_addr [0:31];
reg [31:0] tile_stat_poly_valid;
integer tile_stat_poly_i;
reg tile_stat_poly_found;
reg [31:0] tile_stat_poly_global_hits;
reg [23:0] tile_stat_poly_global_addr [0:127];
reg [127:0] tile_stat_poly_global_valid;
reg [6:0] tile_stat_poly_global_wr;
integer tile_stat_poly_global_i;
reg tile_stat_poly_global_found;

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		tile_stat_cycles <= 32'd0;
		tile_stat_ra_rd <= 32'd0;
		tile_stat_isp_rd <= 32'd0;
		tile_stat_tex_rd <= 32'd0;
		tile_stat_fb_we <= 32'd0;
		tile_stat_hsr_cycles <= 32'd0;
		tile_stat_tsp_cycles <= 32'd0;
		tile_stat_tsp_tex_wait_cycles <= 32'd0;
		tile_stat_tsp_drain_cycles <= 32'd0;
		tile_stat_tri_prev <= 32'd0;
		tile_stat_vis_prev <= 32'd0;
		tile_stat_tag_prev <= 32'd0;
		tile_stat_cb_prev <= 32'd0;
		tile_stat_tsp_tex_wait_prev <= 32'd0;
		tile_stat_tsp_empty_prev <= 32'd0;
		tile_stat_tsp_empty_row_prev <= 32'd0;
		tile_stat_print_tri <= 32'd0;
		tile_stat_print_vis <= 32'd0;
		tile_stat_print_tag <= 32'd0;
		tile_stat_print_cb <= 32'd0;
		tile_stat_print_tsp_tex_wait <= 32'd0;
		tile_stat_print_tsp_empty <= 32'd0;
		tile_stat_print_tsp_empty_row <= 32'd0;
		tile_stat_poly_refs <= 32'd0;
		tile_stat_poly_hits <= 32'd0;
		tile_stat_poly_consec <= 32'd0;
		tile_stat_poly_unique <= 6'd0;
		tile_stat_poly_last <= 24'd0;
		tile_stat_poly_last_valid <= 1'b0;
		tile_stat_poly_valid <= 32'd0;
		tile_stat_poly_global_hits <= 32'd0;
		tile_stat_poly_global_valid <= 128'd0;
		tile_stat_poly_global_wr <= 7'd0;
	end
	else begin
		tile_stat_cycles <= tile_stat_cycles + 32'd1;
		if (ra_vram_rd) tile_stat_ra_rd <= tile_stat_ra_rd + 32'd1;
		if (isp_vram_rd) tile_stat_isp_rd <= tile_stat_isp_rd + 32'd1;
		if (tex_vram_rd) tile_stat_tex_rd <= tile_stat_tex_rd + 32'd1;
		if (fb_we) tile_stat_fb_we <= tile_stat_fb_we + 32'd1;
		if (isp_state == 9'd50) tile_stat_hsr_cycles <= tile_stat_hsr_cycles + 32'd1;
		if (isp_parser_inst.tsp_state != 9'd0) tile_stat_tsp_cycles <= tile_stat_tsp_cycles + 32'd1;
		if (isp_parser_inst.tsp_tex_waiting) tile_stat_tsp_tex_wait_cycles <= tile_stat_tsp_tex_wait_cycles + 32'd1;
		if (isp_parser_inst.tsp_state == 9'd54) tile_stat_tsp_drain_cycles <= tile_stat_tsp_drain_cycles + 32'd1;
		if (render_poly) begin
			tile_stat_poly_found = 1'b0;
			for (tile_stat_poly_i = 0; tile_stat_poly_i < 32; tile_stat_poly_i = tile_stat_poly_i + 1) begin
				if (tile_stat_poly_valid[tile_stat_poly_i] && (tile_stat_poly_addr[tile_stat_poly_i] == poly_addr))
					tile_stat_poly_found = 1'b1;
			end
			tile_stat_poly_global_found = 1'b0;
			for (tile_stat_poly_global_i = 0; tile_stat_poly_global_i < 128; tile_stat_poly_global_i = tile_stat_poly_global_i + 1) begin
				if (tile_stat_poly_global_valid[tile_stat_poly_global_i] &&
					(tile_stat_poly_global_addr[tile_stat_poly_global_i] == poly_addr))
					tile_stat_poly_global_found = 1'b1;
			end

			tile_stat_poly_refs <= tile_stat_poly_refs + 32'd1;
			if (tile_stat_poly_found) begin
				tile_stat_poly_hits <= tile_stat_poly_hits + 32'd1;
			end
			else if (tile_stat_poly_unique < 6'd32) begin
				tile_stat_poly_addr[tile_stat_poly_unique[4:0]] <= poly_addr;
				tile_stat_poly_valid[tile_stat_poly_unique[4:0]] <= 1'b1;
				tile_stat_poly_unique <= tile_stat_poly_unique + 6'd1;
			end

			if (tile_stat_poly_last_valid && (tile_stat_poly_last == poly_addr))
				tile_stat_poly_consec <= tile_stat_poly_consec + 32'd1;
			if (tile_stat_poly_global_found) begin
				tile_stat_poly_global_hits <= tile_stat_poly_global_hits + 32'd1;
			end
			else begin
				tile_stat_poly_global_addr[tile_stat_poly_global_wr] <= poly_addr;
				tile_stat_poly_global_valid[tile_stat_poly_global_wr] <= 1'b1;
				tile_stat_poly_global_wr <= tile_stat_poly_global_wr + 7'd1;
			end
			tile_stat_poly_last <= poly_addr;
			tile_stat_poly_last_valid <= 1'b1;
		end

		if (tile_accum_done) begin
			tile_stat_print_tri = isp_parser_inst.total_tri_count - tile_stat_tri_prev;
			tile_stat_print_vis = isp_parser_inst.total_vis_count - tile_stat_vis_prev;
			tile_stat_print_tag = isp_parser_inst.tag_switch_count - tile_stat_tag_prev;
			tile_stat_print_cb  = isp_parser_inst.cb_word_count - tile_stat_cb_prev;
			tile_stat_print_tsp_tex_wait = isp_parser_inst.tsp_tex_wait_cycle_count - tile_stat_tsp_tex_wait_prev;
			tile_stat_print_tsp_empty = isp_parser_inst.tsp_empty_tile_skip_count - tile_stat_tsp_empty_prev;
			tile_stat_print_tsp_empty_row = isp_parser_inst.tsp_empty_row_skip_count - tile_stat_tsp_empty_row_prev;
			$display("[PVR/TILE] cyc=%0d tile=%0d,%0d type=%0d cycles=%0d hsr=%0d tsp=%0d tex_wait_cyc=%0d tex_wait_cnt=%0d tsp_drain=%0d empty_skip=%0d empty_row_skip=%0d ra_rd=%0d isp_rd=%0d tex_rd=%0d cb_rd=%0d fb_we=%0d prim_in=%0d prim_vis=%0d tag_changes=%0d poly_refs=%0d poly_uniq32=%0d poly_hits32=%0d poly_recent128_hits=%0d poly_consec=%0d poly_last=%06x",
				dbg_cycle, ra_cont_tilex, ra_cont_tiley, type_cnt, tile_stat_cycles,
				tile_stat_hsr_cycles, tile_stat_tsp_cycles, tile_stat_tsp_tex_wait_cycles,
				tile_stat_print_tsp_tex_wait, tile_stat_tsp_drain_cycles, tile_stat_print_tsp_empty,
				tile_stat_print_tsp_empty_row,
				tile_stat_ra_rd, tile_stat_isp_rd, tile_stat_tex_rd, tile_stat_print_cb,
				tile_stat_fb_we, tile_stat_print_tri, tile_stat_print_vis, tile_stat_print_tag,
				tile_stat_poly_refs, tile_stat_poly_unique, tile_stat_poly_hits, tile_stat_poly_global_hits,
				tile_stat_poly_consec, tile_stat_poly_last);
			tile_stat_cycles <= 32'd0;
			tile_stat_ra_rd <= 32'd0;
			tile_stat_isp_rd <= 32'd0;
			tile_stat_tex_rd <= 32'd0;
			tile_stat_fb_we <= 32'd0;
			tile_stat_hsr_cycles <= 32'd0;
			tile_stat_tsp_cycles <= 32'd0;
			tile_stat_tsp_tex_wait_cycles <= 32'd0;
			tile_stat_tsp_drain_cycles <= 32'd0;
			tile_stat_poly_refs <= 32'd0;
			tile_stat_poly_hits <= 32'd0;
			tile_stat_poly_consec <= 32'd0;
			tile_stat_poly_unique <= 6'd0;
			tile_stat_poly_last <= 24'd0;
			tile_stat_poly_last_valid <= 1'b0;
			tile_stat_poly_valid <= 32'd0;
			tile_stat_poly_global_hits <= 32'd0;
			tile_stat_tri_prev <= isp_parser_inst.total_tri_count;
			tile_stat_vis_prev <= isp_parser_inst.total_vis_count;
			tile_stat_tag_prev <= isp_parser_inst.tag_switch_count;
			tile_stat_cb_prev <= isp_parser_inst.cb_word_count;
			tile_stat_tsp_tex_wait_prev <= isp_parser_inst.tsp_tex_wait_cycle_count;
			tile_stat_tsp_empty_prev <= isp_parser_inst.tsp_empty_tile_skip_count;
			tile_stat_tsp_empty_row_prev <= isp_parser_inst.tsp_empty_row_skip_count;
		end
	end
end
`endif
`endif

`ifdef VERILATOR
`ifdef PVR_TSP_TRACE_PRINTS
reg [10:0] dbg_tsp_sample_x;
reg [10:0] dbg_tsp_sample_y;
reg        dbg_tsp_sample_wr;
reg        dbg_tsp_sample_ready;
reg [21:0] dbg_tsp_sample_tex_word;
reg [31:0] dbg_tsp_sample_cycle;
reg [9:0]  dbg_tsp_sample_out_x;
reg [9:0]  dbg_tsp_sample_out_y;
reg        dbg_tsp_sample_texel_valid;
reg        dbg_tsp_sample_pix_valid;
reg        dbg_tsp_sample_stall;
reg        dbg_tsp_sample_fb_we;
reg [22:0] dbg_tsp_sample_fb_addr;
reg [31:0] dbg_tsp_sample_fb_data;

always @(posedge clock) begin
	dbg_tsp_sample_cycle = dbg_cycle;
	dbg_tsp_sample_x = tsp_x_ps_cmd;
	dbg_tsp_sample_y = tsp_y_ps_cmd;
	dbg_tsp_sample_wr = tsp_pix_wr_cmd;
	dbg_tsp_sample_ready = tsp_tex_data_ready;
	dbg_tsp_sample_tex_word = tsp_tex_word_addr;
	dbg_tsp_sample_out_x = tsp_x_ps_out;
	dbg_tsp_sample_out_y = tsp_y_ps_out;
	dbg_tsp_sample_texel_valid = tsp_texel_valid;
	dbg_tsp_sample_pix_valid = tsp_pix_valid;
	dbg_tsp_sample_stall = tsp_pipeline_stall;
	dbg_tsp_sample_fb_we = fb_we;
	dbg_tsp_sample_fb_addr = fb_addr;
	dbg_tsp_sample_fb_data = fb_writedata[31:0];
	if (reset_n && debug_ena_texel_reads &&
		(tsp_pix_wr_cmd || tsp_texel_valid || tsp_pix_valid || fb_we || tsp_pipeline_stall)) begin
		$strobe("[PVR/TSP/FB] cyc=%0d sample_xy=%0d,%0d cmd_xy=%0d,%0d sample_out=%0d,%0d out_xy=%0d,%0d sample_wr=%0b wr_cmd=%0b sample_ready=%0b tex_ready=%0b sample_texel=%0b texel_valid=%0b sample_pix=%0b pix_valid=%0b sample_stall=%0b stall=%0b sample_fb_we=%0b fb_we=%0b sample_fb_addr=%06x fb_addr=%06x sample_fb_data=%08x fb_data=%08x fb_be=%02x sample_tex=%06x tex_word=%06x",
			dbg_tsp_sample_cycle, dbg_tsp_sample_x, dbg_tsp_sample_y,
			tsp_x_ps_cmd, tsp_y_ps_cmd, dbg_tsp_sample_out_x, dbg_tsp_sample_out_y,
			tsp_x_ps_out, tsp_y_ps_out,
			dbg_tsp_sample_wr,
			tsp_pix_wr_cmd, dbg_tsp_sample_ready, tsp_tex_data_ready,
			dbg_tsp_sample_texel_valid, tsp_texel_valid, dbg_tsp_sample_pix_valid, tsp_pix_valid,
			dbg_tsp_sample_stall, tsp_pipeline_stall,
			dbg_tsp_sample_fb_we, fb_we,
			dbg_tsp_sample_fb_addr, fb_addr, dbg_tsp_sample_fb_data, fb_writedata[31:0],
			fb_byteena, dbg_tsp_sample_tex_word, tsp_tex_word_addr);
	end
end
`endif
`endif

endmodule
