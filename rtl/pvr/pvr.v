`timescale 1ns / 1ps
`default_nettype none

module pvr (
	input clock,
	input reset_n,
	
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
	
	input [31:0] PARAM_BASE,
	input [31:0] REGION_BASE,
	input [31:0] FPU_PARAM_CFG,
	input [31:0] TEXT_CONTROL,
	input [31:0] PAL_RAM_CTRL,
	input [31:0] TA_ALLOC_CTRL,
	
	input ta_fifo_wr,

	// To VRAM. Duh...
	input wire vram_wait,
	input wire vram_valid,
	output wire vram_rd,
	output wire vram_wr,
	output wire [23:0] vram_addr,
	input wire [63:0] vram_din,
	output wire [63:0] vram_dout,
	
	output [22:0] fb_addr,
	output [31:0] fb_writedata,
	output fb_we
);


// Main regs...
parameter ID_addr                 = 16'h0000; // R   Device ID
parameter REVISION_addr           = 16'h0004; // R   Revision number
parameter SOFTRESET_addr          = 16'h0008; // RW  CORE & TA software reset
	
parameter STARTRENDER_addr        = 16'h0014; // RW  Drawing start
parameter TEST_SELECT_addr        = 16'h0018; // RW  Test - writing this register is prohibited.

parameter PARAM_BASE_addr         = 16'h0020; // RW  Base address for ISP parameters

parameter REGION_BASE_addr        = 16'h002C; // RW  Base address for Region Array
parameter SPAN_SORT_CFG_addr      = 16'h0030; // RW  Span Sorter control

parameter VO_BORDER_COL_addr      = 16'h0040; // RW  Border area color
parameter FB_R_CTRL_addr          = 16'h0044; // RW  Frame buffer read control
parameter FB_W_CTRL_addr          = 16'h0048; // RW  Frame buffer write control
parameter FB_W_LINESTRIDE_addr    = 16'h004C; // RW  Frame buffer line stride

parameter FB_R_SOF1_addr          = 16'h0050; // RW  Read start address for field - 1/strip - 1
parameter FB_R_SOF2_addr          = 16'h0054; // RW  Read start address for field - 2/strip - 2
parameter FB_R_SIZE_addr          = 16'h005C; // RW  Frame buffer XY size	

parameter FB_W_SOF1_addr          = 16'h0060; // RW  Write start address for field - 1/strip - 1
parameter FB_W_SOF2_addr          = 16'h0064; // RW  Write start address for field - 2/strip - 2

parameter FB_X_CLIP_addr          = 16'h0068; // RW  Pixel clip X coordinate
parameter FB_Y_CLIP_addr          = 16'h006C; // RW  Pixel clip Y coordinate

parameter FPU_SHAD_SCALE_addr     = 16'h0074; // RW  Intensity Volume mode
parameter FPU_CULL_VAL_addr       = 16'h0078; // RW  Comparison value for culling
parameter FPU_PARAM_CFG_addr      = 16'h007C; // RW  Parameter read control
parameter HALF_OFFSET_addr        = 16'h0080; // RW  Pixel sampling control
parameter FPU_PERP_VAL_addr       = 16'h0084; // RW  Comparison value for perpendicular polygons
parameter ISP_BACKGND_D_addr      = 16'h0088; // RW  Background surface depth
parameter ISP_BACKGND_T_addr      = 16'h008C; // RW  Background surface tag

parameter ISP_FEED_CFG_addr       = 16'h0098; // RW  Translucent polygon sort mode

parameter SDRAM_REFRESH_addr      = 16'h00A0; // RW  Texture memory refresh counter
parameter SDRAM_ARB_CFG_addr      = 16'h00A4; // RW  Texture memory arbiter control
parameter SDRAM_CFG_addr          = 16'h00A8; // RW  Texture memory control

parameter FOG_COL_RAM_addr        = 16'h00B0; // RW  Color for Look Up table Fog
parameter FOG_COL_VERT_addr       = 16'h00B4; // RW  Color for vertex Fog
parameter FOG_DENSITY_addr        = 16'h00B8; // RW  Fog scale value
parameter FOG_CLAMP_MAX_addr      = 16'h00BC; // RW  Color clamping maximum value
parameter FOG_CLAMP_MIN_addr      = 16'h00C0; // RW  Color clamping minimum value
parameter SPG_TRIGGER_POS_addr    = 16'h00C4; // RW  External trigger signal HV counter value
parameter SPG_HBLANK_INT_addr     = 16'h00C8; // RW  H-blank interrupt control	
parameter SPG_VBLANK_INT_addr     = 16'h00CC; // RW  V-blank interrupt control	
parameter SPG_CONTROL_addr        = 16'h00D0; // RW  Sync pulse generator control
parameter SPG_HBLANK_addr         = 16'h00D4; // RW  H-blank control
parameter SPG_LOAD_addr           = 16'h00D8; // RW  HV counter load value
parameter SPG_VBLANK_addr         = 16'h00DC; // RW  V-blank control
parameter SPG_WIDTH_addr          = 16'h00E0; // RW  Sync width control
parameter TEXT_CONTROL_addr       = 16'h00E4; // RW  Texturing control
parameter VO_CONTROL_addr         = 16'h00E8; // RW  Video output control
parameter VO_STARTX_addr          = 16'h00Ec; // RW  Video output start X position
parameter VO_STARTY_addr          = 16'h00F0; // RW  Video output start Y position
parameter SCALER_CTL_addr         = 16'h00F4; // RW  X & Y scaler control
parameter PAL_RAM_CTRL_addr       = 16'h0108; // RW  Palette RAM control
parameter SPG_STATUS_addr         = 16'h010C; // R   Sync pulse generator status
parameter FB_BURSTCTRL_addr       = 16'h0110; // RW  Frame buffer burst control
parameter FB_C_SOF_addr           = 16'h0114; // R   Current frame buffer start address
parameter Y_COEFF_addr            = 16'h0118; // RW  Y scaling coefficient

parameter PT_ALPHA_REF_addr       = 16'h011C; // RW  Alpha value for Punch Through polygon comparison


// TA REGS
parameter TA_OL_BASE_addr         = 16'h0124; // RW  Object list write start address
parameter TA_ISP_BASE_addr        = 16'h0128; // RW  ISP/TSP Parameter write start address
parameter TA_OL_LIMIT_addr        = 16'h012C; // RW  Start address of next Object Pointer Block
parameter TA_ISP_LIMIT_addr       = 16'h0130; // RW  Current ISP/TSP Parameter write address
parameter TA_NEXT_OPB_addr        = 16'h0134; // R   Global Tile clip control
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

parameter PALETTE_RAM_START_addr      = 16'h1000; // RW  Palette RAM
parameter PALETTE_RAM_END_addr        = 16'h1FFC;


// Main regs...
reg [31:0] ID; 					// 16'h0000; R   Device ID
reg [31:0] REVISION; 			// 16'h0004; R   Revision number
reg [31:0] SOFTRESET; 			// 16'h0008; RW  CORE & TA software reset
	
reg [31:0] STARTRENDER; 		// 16'h0014; RW  Drawing start
reg [31:0] TEST_SELECT; 		// 16'h0018; RW  Test - writing this register is prohibited.

//reg [31:0] PARAM_BASE; 			// 16'h0020; RW  Base address for ISP regs
//reg [31:0] REGION_BASE; 		// 16'h002C; RW  Base address for Region Array

reg [31:0] SPAN_SORT_CFG; 		// 16'h0030; RW  Span Sorter control

reg [31:0] VO_BORDER_COL; 		// 16'h0040; RW  Border area color
reg [31:0] FB_R_CTRL; 			// 16'h0044; RW  Frame buffer read control
reg [31:0] FB_W_CTRL; 			// 16'h0048; RW  Frame buffer write control
reg [31:0] FB_W_LINESTRIDE; 	// 16'h004C; RW  Frame buffer line stride
reg [31:0] FB_R_SOF1; 			// 16'h0050; RW  Read start address for field - 1/strip - 1
reg [31:0] FB_R_SOF2; 			// 16'h0054; RW  Read start address for field - 2/strip - 2

reg [31:0] FB_R_SIZE; 			// 16'h005C; RW  Frame buffer XY size	
reg [31:0] FB_W_SOF1; 			// 16'h0060; RW  Write start address for field - 1/strip - 1
reg [31:0] FB_W_SOF2; 			// 16'h0064; RW  Write start address for field - 2/strip - 2
reg [31:0] FB_X_CLIP; 			// 16'h0068; RW  Pixel clip X coordinate
reg [31:0] FB_Y_CLIP; 			// 16'h006C; RW  Pixel clip Y coordinate


reg [31:0] FPU_SHAD_SCALE; 	// 16'h0074; RW  Intensity Volume mode
reg [31:0] FPU_CULL_VAL; 		// 16'h0078; RW  Comparison value for culling
//reg [31:0] FPU_PARAM_CFG; 		// 16'h007C; RW  register read control
reg [31:0] HALF_OFFSET; 		// 16'h0080; RW  Pixel sampling control
reg [31:0] FPU_PERP_VAL; 		// 16'h0084; RW  Comparison value for perpendicular polygons
reg [31:0] ISP_BACKGND_D; 		// 16'h0088; RW  Background surface depth
reg [31:0] ISP_BACKGND_T; 		// 16'h008C; RW  Background surface tag

reg [31:0] ISP_FEED_CFG; 		// 16'h0098; RW  Translucent polygon sort mode

reg [31:0] SDRAM_REFRESH; 		// 16'h00A0; RW  Texture memory refresh counter
reg [31:0] SDRAM_ARB_CFG; 		// 16'h00A4; RW  Texture memory arbiter control
reg [31:0] SDRAM_CFG; 			// 16'h00A8; RW  Texture memory control

reg [31:0] FOG_COL_RAM; 		// 16'h00B0; RW  Color for Look Up table Fog
reg [31:0] FOG_COL_VERT; 		// 16'h00B4; RW  Color for vertex Fog
reg [31:0] FOG_DENSITY; 		// 16'h00B8; RW  Fog scale value
reg [31:0] FOG_CLAMP_MAX; 		// 16'h00BC; RW  Color clamping maximum value
reg [31:0] FOG_CLAMP_MIN; 		// 16'h00C0; RW  Color clamping minimum value
reg [31:0] SPG_TRIGGER_POS; 	// 16'h00C4; RW  External trigger signal HV counter value
reg [31:0] SPG_HBLANK_INT; 	// 16'h00C8; RW  H-blank interrupt control	
reg [31:0] SPG_VBLANK_INT; 	// 16'h00CC; RW  V-blank interrupt control	
reg [31:0] SPG_CONTROL; 		// 16'h00D0; RW  Sync pulse generator control
reg [31:0] SPG_HBLANK; 			// 16'h00D4; RW  H-blank control
reg [31:0] SPG_LOAD; 			// 16'h00D8; RW  HV counter load value
reg [31:0] SPG_VBLANK; 			// 16'h00DC; RW  V-blank control
reg [31:0] SPG_WIDTH; 			// 16'h00E0; RW  Sync width control
//reg [31:0] TEXT_CONTROL; 		// 16'h00E4; RW  Texturing control
reg [31:0] VO_CONTROL; 			// 16'h00E8; RW  Video output control
reg [31:0] VO_STARTX; 			// 16'h00EC; RW  Video output start X position
reg [31:0] VO_STARTY; 			// 16'h00F0; RW  Video output start Y position
reg [31:0] SCALER_CTL; 			// 16'h00F4; RW  X & Y scaler control
//reg [31:0] PAL_RAM_CTRL; 		// 16'h0108; RW  Palette RAM control
reg [31:0] SPG_STATUS; 			// 16'h010C; R   Sync pulse generator status
reg [31:0] FB_BURSTCTRL; 		// 16'h0110; RW  Frame buffer burst control
reg [31:0] FB_C_SOF; 			// 16'h0114; R   Current frame buffer start address
reg [31:0] Y_COEFF; 				// 16'h0118; RW  Y scaling coefficient

reg [31:0] PT_ALPHA_REF; 		// 16'h011C; RW  Alpha value for Punch Through polygon comparison


// TA REGS
reg [31:0] TA_OL_BASE; 			// 16'h0124; RW  Object list write start address
reg [31:0] TA_ISP_BASE; 		// 16'h0128; RW  ISP/TSP register write start address
reg [31:0] TA_OL_LIMIT; 		// 16'h012C; RW  Start address of next Object Pointer Block
reg [31:0] TA_ISP_LIMIT; 		// 16'h0130; RW  Current ISP/TSP register write address
reg [31:0] TA_NEXT_OPB; 		// 16'h0134; R   Global Tile clip control
reg [31:0] TA_ISP_CURRENT; 	// 16'h0138; R   Current ISP/TSP register write address
reg [31:0] TA_GLOB_TILE_CLIP; // 16'h013C; RW  Global Tile clip control

//reg [31:0] TA_ALLOC_CTRL; 		// 16'h0140; RW  Object list control

reg [31:0] TA_LIST_INIT; 		// 16'h0144; RW  TA initialization
reg [31:0] TA_YUV_TEX_BASE; 	// 16'h0148; RW  YUV422 texture write start address
reg [31:0] TA_YUV_TEX_CTRL; 	// 16'h014C; RW  YUV converter control
reg [31:0] TA_YUV_TEX_CNT; 		// 16'h0150; R   YUV converter macro block counter value

reg [31:0] TA_LIST_CONT; 		// 16'h0160; RW  TA continuation processing
reg [31:0] TA_NEXT_OPB_INIT; 	// 16'h0164; RW  Additional OPB starting address

reg [31:0] FOG_TABLE_START; 	// 16'h0200; RW  Look-up table Fog data
reg [31:0] FOG_TABLE_END;		// 16'h03FC;

reg [31:0] TA_OL_POINTERS_START;// 16'h0600; R   TA object List Pointer data
reg [31:0] TA_OL_POINTERS_END;	// 16'h0F5C;

reg [31:0] PALETTE_RAM_START; 	// 16'h1000; RW  Palette RAM
reg [31:0] PALETTE_RAM_END;		// 16'h1FFC;



always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	ID 		<= 32'h17FD11DB;
	REVISION <= 32'h00000011;
end
else begin
	// Handle PVR and TA reg Writes...
	if (pvr_reg_cs && pvr_wr) begin
		case (pvr_addr)
			// Main HOLLY/PVR regs
			//ID_addr: 				  ID <= pvr_din;					// 16'h0000; R   Device ID
			//REVISION_addr: REVISION <= pvr_din; 					// 16'h0004; R   Revision number
			SOFTRESET_addr: SOFTRESET <= pvr_din; 					// 16'h0008; RW  CORE & TA software reset
				
			STARTRENDER_addr: STARTRENDER <= pvr_din; 			// 16'h0014; RW  Drawing start
			TEST_SELECT_addr: TEST_SELECT <= pvr_din; 			// 16'h0018; RW  Test - writing this register is prohibited.

			//PARAM_BASE_addr: PARAM_BASE <= pvr_din; 			// 16'h0020; RW  Base address for ISP regs
			//REGION_BASE_addr: REGION_BASE <= pvr_din; 			// 16'h002C; RW  Base address for Region Array
			
			SPAN_SORT_CFG_addr: SPAN_SORT_CFG <= pvr_din; 		// 16'h0030; RW  Span Sorter control

			VO_BORDER_COL_addr: VO_BORDER_COL <= pvr_din; 		// 16'h0040; RW  Border area color
			FB_R_CTRL_addr: FB_R_CTRL <= pvr_din; 					// 16'h0044; RW  Frame buffer read control
			FB_W_CTRL_addr: FB_W_CTRL <= pvr_din; 					// 16'h0048; RW  Frame buffer write control
			FB_W_LINESTRIDE_addr: FB_W_LINESTRIDE <= pvr_din; 	// 16'h004C; RW  Frame buffer line stride
			FB_R_SOF1_addr: FB_R_SOF1 <= pvr_din; 					// 16'h0050; RW  Read start address for field - 1/strip - 1
			FB_R_SOF2_addr: FB_R_SOF2 <= pvr_din; 					// 16'h0054; RW  Read start address for field - 2/strip - 2

			FB_R_SIZE_addr: FB_R_SIZE <= pvr_din; 					// 16'h005C; RW  Frame buffer XY size	
			FB_W_SOF1_addr: FB_W_SOF1 <= pvr_din; 					// 16'h0060; RW  Write start address for field - 1/strip - 1
			FB_W_SOF2_addr: FB_W_SOF2 <= pvr_din; 					// 16'h0064; RW  Write start address for field - 2/strip - 2
			FB_X_CLIP_addr: FB_X_CLIP <= pvr_din; 					// 16'h0068; RW  Pixel clip X coordinate
			FB_Y_CLIP_addr: FB_Y_CLIP <= pvr_din; 					// 16'h006C; RW  Pixel clip Y coordinate

			FPU_SHAD_SCALE_addr: FPU_SHAD_SCALE <= pvr_din; 	// 16'h0074; RW  Intensity Volume mode
			FPU_CULL_VAL_addr: FPU_CULL_VAL <= pvr_din; 			// 16'h0078; RW  Comparison value for culling
			//FPU_PARAM_CFG_addr: FPU_PARAM_CFG <= pvr_din; 		// 16'h007C; RW  Parameter read control
			HALF_OFFSET_addr: HALF_OFFSET <= pvr_din; 			// 16'h0080; RW  Pixel sampling control
			FPU_PERP_VAL_addr: FPU_PERP_VAL <= pvr_din; 			// 16'h0084; RW  Comparison value for perpendicular polygons
			ISP_BACKGND_D_addr: ISP_BACKGND_D <= pvr_din; 		// 16'h0088; RW  Background surface depth
			ISP_BACKGND_T_addr: ISP_BACKGND_T <= pvr_din; 		// 16'h008C; RW  Background surface tag

			ISP_FEED_CFG_addr: ISP_FEED_CFG <= pvr_din; 			// 16'h0098; RW  Translucent polygon sort mode

			SDRAM_REFRESH_addr: SDRAM_REFRESH <= pvr_din; 		// 16'h00A0; RW  Texture memory refresh counter
			SDRAM_ARB_CFG_addr: SDRAM_ARB_CFG <= pvr_din; 		// 16'h00A4; RW  Texture memory arbiter control
			SDRAM_CFG_addr: SDRAM_CFG <= pvr_din; 					// 16'h00A8; RW  Texture memory control

			FOG_COL_RAM_addr: FOG_COL_RAM <= pvr_din; 			// 16'h00B0; RW  Color for Look Up table Fog
			FOG_COL_VERT_addr: FOG_COL_VERT <= pvr_din; 			// 16'h00B4; RW  Color for vertex Fog
			FOG_DENSITY_addr: FOG_DENSITY <= pvr_din; 			// 16'h00B8; RW  Fog scale value
			FOG_CLAMP_MAX_addr: FOG_CLAMP_MAX <= pvr_din; 		// 16'h00BC; RW  Color clamping maximum value
			FOG_CLAMP_MIN_addr: FOG_CLAMP_MIN <= pvr_din; 		// 16'h00C0; RW  Color clamping minimum value
			SPG_TRIGGER_POS_addr: SPG_TRIGGER_POS <= pvr_din; 	// 16'h00C4; RW  External trigger signal HV counter value
			SPG_HBLANK_INT_addr: SPG_HBLANK_INT <= pvr_din; 	// 16'h00C8; RW  H-blank interrupt control	
			SPG_VBLANK_INT_addr: SPG_VBLANK_INT <= pvr_din; 	// 16'h00CC; RW  V-blank interrupt control	
			SPG_CONTROL_addr: SPG_CONTROL <= pvr_din; 			// 16'h00D0; RW  Sync pulse generator control
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
			TA_ISP_BASE_addr: TA_ISP_BASE <= pvr_din; 			// 16'h0128; RW  ISP/TSP Parameter write start address
			TA_OL_LIMIT_addr: TA_OL_LIMIT <= pvr_din; 			// 16'h012C; RW  Start address of next Object Pointer Block
			TA_ISP_LIMIT_addr: TA_ISP_LIMIT <= pvr_din; 			// 16'h0130; RW  Current ISP/TSP Parameter write address
			TA_NEXT_OPB_addr: TA_NEXT_OPB <= pvr_din; 				// 16'h0134; R   Global Tile clip control
			TA_ISP_CURRENT_addr: TA_ISP_CURRENT <= pvr_din; 		// 16'h0138; R   Current ISP/TSP Parameter write address
			TA_GLOB_TILE_CLIP_addr: TA_GLOB_TILE_CLIP <= pvr_din;	// 16'h013C; RW  Global Tile clip control
			
			//TA_ALLOC_CTRL_addr: TA_ALLOC_CTRL <= pvr_din; 		// 16'h0140; RW  Object list control
			
			TA_LIST_INIT_addr: TA_LIST_INIT <= pvr_din; 				// 16'h0144; RW  TA initialization
			TA_YUV_TEX_BASE_addr: TA_YUV_TEX_BASE <= pvr_din; 		// 16'h0148; RW  YUV422 texture write start address
			TA_YUV_TEX_CTRL_addr: TA_YUV_TEX_CTRL <= pvr_din; 		// 16'h014C; RW  YUV converter control
			TA_YUV_TEX_CNT_addr: TA_YUV_TEX_CNT <= pvr_din; 		// 16'h0150; R   YUV converter macro block counter value

			TA_LIST_CONT_addr: TA_LIST_CONT <= pvr_din; 				// 16'h0160; RW  TA continuation processing
			TA_NEXT_OPB_INIT_addr: TA_NEXT_OPB_INIT <= pvr_din; 	// 16'h0164; RW  Additional OPB starting address

			FOG_TABLE_START_addr: FOG_TABLE_START <= pvr_din; 		// 16'h0200; RW  Look-up table Fog data
			FOG_TABLE_END_addr: FOG_TABLE_END <= pvr_din;			// 16'h03FC;

			TA_OL_POINTERS_START_addr: TA_OL_POINTERS_START <= pvr_din; // 16'h0600; R   TA object List Pointer data
			TA_OL_POINTERS_END_addr: TA_OL_POINTERS_END <= pvr_din;		// 16'h0F5C;

			PALETTE_RAM_START_addr: PALETTE_RAM_START <= pvr_din; 	// 16'h1000; RW  Palette RAM
			PALETTE_RAM_END_addr: PALETTE_RAM_END <= pvr_din;			// 16'h1FFC;
			default: ;
		endcase
	end
end


always @(posedge clock) begin
	// Handle PVR and TA reg Reads...

	// Main HOLLY/PVR regs
	casez (pvr_addr)
		ID_addr:                pvr_dout[31:0] <= ID; 						// R   16'h0000; Device ID
		REVISION_addr:          pvr_dout[31:0] <= REVISION; 				// R   16'h0004; Revision number
		SOFTRESET_addr:         pvr_dout[31:0] <= SOFTRESET; 				// RW  16'h0008; CORE & TA software reset
			
		STARTRENDER_addr:       pvr_dout[31:0] <= STARTRENDER; 			// RW  16'h0014; Drawing start
		TEST_SELECT_addr:       pvr_dout[31:0] <= TEST_SELECT; 			// RW  16'h0018; Test - writing this register is prohibited.

		PARAM_BASE_addr:        pvr_dout[31:0] <= PARAM_BASE; 			// RW  16'h0020; Base address for ISP regs

		REGION_BASE_addr:       pvr_dout[31:0] <= REGION_BASE; 			// RW  16'h002C; Base address for Region Array
		SPAN_SORT_CFG_addr:     pvr_dout[31:0] <= SPAN_SORT_CFG; 		// RW  16'h0030; Span Sorter control

		VO_BORDER_COL_addr:     pvr_dout[31:0] <= VO_BORDER_COL; 		// RW  16'h0040; Border area color
		FB_R_CTRL_addr:         pvr_dout[31:0] <= FB_R_CTRL; 				// RW  16'h0044; Frame buffer read control
		FB_W_CTRL_addr:         pvr_dout[31:0] <= FB_W_CTRL; 				// RW  16'h0048; Frame buffer write control
		FB_W_LINESTRIDE_addr:   pvr_dout[31:0] <= FB_W_LINESTRIDE; 		// RW  16'h004C; Frame buffer line stride
		FB_R_SOF1_addr:         pvr_dout[31:0] <= FB_R_SOF1; 				// RW  16'h0050; Read start address for field - 1/strip - 1
		FB_R_SOF2_addr:         pvr_dout[31:0] <= FB_R_SOF2; 				// RW  16'h0054; Read start address for field - 2/strip - 2
	
		FB_R_SIZE_addr:         pvr_dout[31:0] <= FB_R_SIZE; 				// RW  16'h005C; Frame buffer XY size	
		FB_W_SOF1_addr:         pvr_dout[31:0] <= FB_W_SOF1; 				// RW  16'h0060; Write start address for field - 1/strip - 1
		FB_W_SOF2_addr:         pvr_dout[31:0] <= FB_W_SOF2; 				// RW  16'h0064; Write start address for field - 2/strip - 2
		FB_X_CLIP_addr:         pvr_dout[31:0] <= FB_X_CLIP; 				// RW  16'h0068; Pixel clip X coordinate
		FB_Y_CLIP_addr:         pvr_dout[31:0] <= FB_Y_CLIP; 				// RW  16'h006C; Pixel clip Y coordinate

		FPU_SHAD_SCALE_addr:    pvr_dout[31:0] <= FPU_SHAD_SCALE; 		// RW  16'h0074; Intensity Volume mode
		FPU_CULL_VAL_addr:      pvr_dout[31:0] <= FPU_CULL_VAL; 			// RW  16'h0078; Comparison value for culling
		FPU_PARAM_CFG_addr:     pvr_dout[31:0] <= FPU_PARAM_CFG; 		// RW  16'h007C; Parameter read control
		HALF_OFFSET_addr:       pvr_dout[31:0] <= HALF_OFFSET; 			// RW  16'h0080; Pixel sampling control
		FPU_PERP_VAL_addr:      pvr_dout[31:0] <= FPU_PERP_VAL; 			// RW  16'h0084; Comparison value for perpendicular polygons
		ISP_BACKGND_D_addr:     pvr_dout[31:0] <= ISP_BACKGND_D; 		// RW  16'h0088; Background surface depth
		ISP_BACKGND_T_addr:     pvr_dout[31:0] <= ISP_BACKGND_T; 		// RW  16'h008C; Background surface tag

		ISP_FEED_CFG_addr:      pvr_dout[31:0] <= ISP_FEED_CFG; 			// RW  16'h0098; Translucent polygon sort mode

		SDRAM_REFRESH_addr:     pvr_dout[31:0] <= SDRAM_REFRESH; 		// RW  16'h00A0; Texture memory refresh counter
		SDRAM_ARB_CFG_addr:     pvr_dout[31:0] <= SDRAM_ARB_CFG; 		// RW  16'h00A4; Texture memory arbiter control
		SDRAM_CFG_addr:         pvr_dout[31:0] <= SDRAM_CFG; 				// RW  16'h00A8; Texture memory control

		FOG_COL_RAM_addr:       pvr_dout[31:0] <= FOG_COL_RAM; 			// RW  16'h00B0; Color for Look Up table Fog
		FOG_COL_VERT_addr:      pvr_dout[31:0] <= FOG_COL_VERT; 			// RW  16'h00B4; Color for vertex Fog
		FOG_DENSITY_addr:       pvr_dout[31:0] <= FOG_DENSITY; 			// RW  16'h00B8; Fog scale value
		FOG_CLAMP_MAX_addr:     pvr_dout[31:0] <= FOG_CLAMP_MAX; 		// RW  16'h00BC; Color clamping maximum value
		FOG_CLAMP_MIN_addr:     pvr_dout[31:0] <= FOG_CLAMP_MIN; 		// RW  16'h00C0; Color clamping minimum value
		SPG_TRIGGER_POS_addr:   pvr_dout[31:0] <= SPG_TRIGGER_POS; 		// RW  16'h00C4; External trigger signal HV counter value
		SPG_HBLANK_INT_addr:    pvr_dout[31:0] <= SPG_HBLANK_INT; 		// RW  16'h00C8; H-blank interrupt control	
		SPG_VBLANK_INT_addr:    pvr_dout[31:0] <= SPG_VBLANK_INT; 		// RW  16'h00CC; V-blank interrupt control	
		SPG_CONTROL_addr:       pvr_dout[31:0] <= SPG_CONTROL; 			// RW  16'h00D0; Sync pulse generator control
		SPG_HBLANK_addr:        pvr_dout[31:0] <= SPG_HBLANK; 			// RW  16'h00D4; H-blank control
		SPG_LOAD_addr:          pvr_dout[31:0] <= SPG_LOAD; 				// RW  16'h00D8; HV counter load value
		SPG_VBLANK_addr:        pvr_dout[31:0] <= SPG_VBLANK; 			// RW  16'h00DC; V-blank control
		SPG_WIDTH_addr:         pvr_dout[31:0] <= SPG_WIDTH; 				// RW  16'h00E0; Sync width control
		TEXT_CONTROL_addr:      pvr_dout[31:0] <= TEXT_CONTROL; 			// RW  16'h00E4; Texturing control
		VO_CONTROL_addr:        pvr_dout[31:0] <= VO_CONTROL; 			// RW  16'h00E8; Video output control
		VO_STARTX_addr:         pvr_dout[31:0] <= VO_STARTX; 				// RW  16'h00EC; Video output start X position
		VO_STARTY_addr:         pvr_dout[31:0] <= VO_STARTY; 				// RW  16'h00F0; Video output start Y position
		SCALER_CTL_addr:        pvr_dout[31:0] <= SCALER_CTL; 			// RW  16'h00F4; X & Y scaler control
		PAL_RAM_CTRL_addr:      pvr_dout[31:0] <= PAL_RAM_CTRL; 			// RW  16'h0108; Palette RAM control
		SPG_STATUS_addr:        pvr_dout[31:0] <= SPG_STATUS; 			// R   16'h010C; Sync pulse generator status
		FB_BURSTCTRL_addr:      pvr_dout[31:0] <= FB_BURSTCTRL; 			// RW  16'h0110; Frame buffer burst control
		FB_C_SOF_addr:          pvr_dout[31:0] <= FB_C_SOF; 				// R   16'h0114; Current frame buffer start address
		Y_COEFF_addr:           pvr_dout[31:0] <= Y_COEFF; 				// RW  16'h0118; Y scaling coefficient

		PT_ALPHA_REF_addr:      pvr_dout[31:0] <=  PT_ALPHA_REF; 		// RW  16'h011C; Alpha value for Punch Through polygon comparison

		// TA REGS
		TA_OL_BASE_addr:        pvr_dout[31:0] <= TA_OL_BASE; 			// RW  16'h0124; Object list write start address
		TA_ISP_BASE_addr:       pvr_dout[31:0] <= TA_ISP_BASE; 			// RW  16'h0128; ISP/TSP Parameter write start address
		TA_OL_LIMIT_addr:       pvr_dout[31:0] <= TA_OL_LIMIT; 			// RW  16'h012C; Start address of next Object Pointer Block
		TA_ISP_LIMIT_addr:      pvr_dout[31:0] <= TA_ISP_LIMIT; 			// RW  16'h0130; Current ISP/TSP Parameter write address
		TA_NEXT_OPB_addr:       pvr_dout[31:0] <= TA_NEXT_OPB; 			// R   16'h0134; Global Tile clip control
		TA_ISP_CURRENT_addr:    pvr_dout[31:0] <= TA_ISP_CURRENT; 		// R   16'h0138; Current ISP/TSP Parameter write address
		TA_GLOB_TILE_CLIP_addr: pvr_dout[31:0] <= TA_GLOB_TILE_CLIP;	// RW  16'h013C; Global Tile clip control
		TA_ALLOC_CTRL_addr:     pvr_dout[31:0] <= TA_ALLOC_CTRL; 		// RW  16'h0140; Object list control
		TA_LIST_INIT_addr:      pvr_dout[31:0] <= TA_LIST_INIT; 			// RW  16'h0144; TA initialization
		TA_YUV_TEX_BASE_addr:   pvr_dout[31:0] <= TA_YUV_TEX_BASE; 		// RW  16'h0148; YUV422 texture write start address
		TA_YUV_TEX_CTRL_addr:   pvr_dout[31:0] <= TA_YUV_TEX_CTRL; 		// RW  16'h014C; YUV converter control
		TA_YUV_TEX_CNT_addr:    pvr_dout[31:0] <= TA_YUV_TEX_CNT; 		// R   16'h0150; YUV converter macro block counter value

		TA_LIST_CONT_addr:      pvr_dout[31:0] <= TA_LIST_CONT; 			// RW  16'h0160; TA continuation processing
		TA_NEXT_OPB_INIT_addr:  pvr_dout[31:0] <= TA_NEXT_OPB_INIT; 	// RW  16'h0164; Additional OPB starting address

		FOG_TABLE_START_addr:   pvr_dout[31:0] <= FOG_TABLE_START; 		// RW  16'h0200; Look-up table Fog data
		FOG_TABLE_END_addr:     pvr_dout[31:0] <= FOG_TABLE_END;			//     16'h03FC;

		TA_OL_POINTERS_START_addr: pvr_dout[31:0] <= TA_OL_POINTERS_START;	// 16'h0600; R  TA object List Pointer data
		TA_OL_POINTERS_END_addr:   pvr_dout[31:0] <= TA_OL_POINTERS_END;		// 16'h0F5C;

		//PALETTE_RAM_START_addr:    pvr_dout[31:0] <= PALETTE_RAM_START; 		// 16'h1000; RW  Palette RAM
		//PALETTE_RAM_END_addr:      pvr_dout[31:0] <= PALETTE_RAM_END;			// 16'h1FFC;
		16'b0001????????????:      pvr_dout[31:0] <= pal_dout;

		default: ;
	endcase
end

/*
wire [21:0] param_req_addr = (vram_addr>>2);
wire param_read = 1'b0;

wire [31:0] param_dout;
wire param_data_ready;

param_cache  param_cache_inst (
	.reset_n( reset_n ),
	.clock( clock ),

	.param_req_addr( param_req_addr ),			// input [21:0]  param_req_addr
	.param_read( param_read ),					// input  param_read
	
	.ddram_waitrequest( ddram_waitrequest ),	// input  ddram_waitrequest
	.ddram_addr( ddram_addr ),					// output [21:0]  ddram_addr
	.ddram_read_burst( ddram_read_burst ),		// output  ddram_read_burst
	.ddram_readdata( ddram_readdata ),			// input [31:0]  ddram_readdata
	.ddram_readdata_valid( ddram_readdata_valid ),	// input  ddram_readdata_valid
	
	.param_dout( param_dout ),					// output [31:0]  param_dout
	.param_data_ready( param_data_ready )		// output  param_data_ready
);
*/

wire ra_trig = 1'b1;

wire ra_vram_rd;
wire ra_vram_wr;
wire [23:0] ra_vram_addr;
wire [31:0] ra_vram_din = (!ra_vram_addr[22]) ? vram_din[31:0] : vram_din[63:32];

wire [31:0] ra_control;
wire ra_cont_last;
wire ra_cont_zclear;
wire ra_cont_flush;
wire [5:0] ra_cont_tiley;
wire [5:0] ra_cont_tilex;

wire [31:0] ra_opaque;
wire [31:0] ra_opaque_mod;
wire [31:0] ra_trans;
wire [31:0] ra_trans_mod;
wire [31:0] ra_puncht;

wire ra_entry_valid;

wire [31:0] opb_word;

wire [23:0] poly_addr;
wire render_poly;

wire [2:0] type_cnt;

ra_parser ra_parser_inst (
	.clock( clock ),		// input  clock
	.reset_n( reset_n ),	// input  reset_n
	
	.ra_trig( ra_trig ),	// input  ra_trig

	.PARAM_BASE( PARAM_BASE ),			// input [31:0]  PARAM_BASE  0x20.
	.REGION_BASE( REGION_BASE ),		// input [31:0]  REGION_BASE 0x2C.
	.TA_ALLOC_CTRL( TA_ALLOC_CTRL ),	// input [31:0]  TA_ALLOC_CTRL 0x140.
	.FPU_PARAM_CFG( FPU_PARAM_CFG ),	// input [31:0]  FPU_PARAM_CFG.
	
	.vram_wait( vram_wait ),			// input  vram_wait
	.vram_valid( vram_valid ),			// input  vram_valid
	.ra_vram_rd( ra_vram_rd ),			// output  ra_vram_rd
	.ra_vram_wr( ra_vram_wr ),			// output  ra_vram_wr
	.ra_vram_addr( ra_vram_addr ),	// output [23:0]  ra_vram_addr
	.ra_vram_din( ra_vram_din ),		// input [31:0]   ra_vram_din
	
	.ra_control( ra_control ),			// output [31:0]  ra_control
	.ra_cont_last( ra_cont_last ),		// output ra_cont_last
	.ra_cont_zclear( ra_cont_zclear ),	// output ra_cont_zclear
	.ra_cont_flush( ra_cont_flush ),	// output ra_cont_flush
	.ra_cont_tiley( ra_cont_tiley ),	// output [5:0]  ra_cont_tiley
	.ra_cont_tilex( ra_cont_tilex ),	// output [5:0]  ra_cont_tilex

	.type_cnt( type_cnt ),				// output [2:0]  type_cnt

	.ra_opaque( ra_opaque ),			// output [31:0]  ra_opaque
	.ra_opaque_mod( ra_opaque_mod ),	// output [31:0]  ra_opaque_mod
	.ra_trans( ra_trans ),				// output [31:0]  ra_trans
	.ra_trans_mod( ra_trans_mod ),	// output [31:0]  ra_trans_mod
	.ra_puncht( ra_puncht ),			// output [31:0]  ra_puncht
	
	.ra_entry_valid( ra_entry_valid ),	// output  ra_entry_valid
	
	.opb_word( opb_word ),				// output [31:0]  opb_word
	
	.poly_addr( poly_addr ),			// output [23:0]  poly_addr
	.render_poly( render_poly ),		// output  render_poly
	
	.poly_drawn( poly_drawn ),			// input  poly_drawn
	.tile_prims_done( tile_prims_done )	// output tile_prims_done
);

wire tile_prims_done;
wire poly_drawn;

wire [23:0] isp_vram_addr_out;
wire isp_vram_rd;
wire isp_vram_wr;

// Keep this as 32-bit for now. Only textures are read aas 64-bit wide.
wire [31:0] isp_vram_din = (!isp_vram_addr_out[22]) ? vram_din[31:0] : vram_din[63:32];	// TESTING! Loading 4MB halves of VRAM dumps into lower and upper DDR3.
wire [31:0] isp_vram_dout;

wire isp_entry_valid;

reg isp_switch;
always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	isp_switch <= 1'b0;
end
else begin
	if (render_poly) isp_switch <= 1'b1;
	if (poly_drawn) isp_switch <= 1'b0;
end

assign vram_addr = (isp_switch) ? isp_vram_addr_out : ra_vram_addr;
assign vram_rd   = (isp_switch) ? isp_vram_rd : ra_vram_rd;
assign vram_wr   = (isp_switch) ? isp_vram_wr : ra_vram_wr;
assign vram_dout = isp_vram_dout;


isp_parser isp_parser_inst (
	.clock( clock ),						// input  clock
	.reset_n( reset_n ),					// input  reset_n
	
	.opb_word( opb_word ),				// input [31:0]  opb_word
	
	.type_cnt( type_cnt ),				// input [2:0]  type_cnt
	
	.poly_addr( poly_addr ),			// input [23:0]  poly_addr
	.render_poly( render_poly ),		// input  render_poly
	
	.vram_wait( vram_wait ),			// input  vram_wait
	.vram_valid( vram_valid ),			// input  vram_valid
	.isp_vram_rd( isp_vram_rd ),		// output  isp_vram_rd
	.isp_vram_wr( isp_vram_wr ),		// output  isp_vram_wr
	.isp_vram_addr_out( isp_vram_addr_out ),	// output [23:0]  isp_vram_addr_out
	.isp_vram_din( isp_vram_din ),		// input  [31:0]  isp_vram_din
	.isp_vram_dout( isp_vram_dout ),		// output  [31:0]  isp_vram_dout
	
	.tex_vram_din( vram_din ),				// full 64-bit input [63:0]
	
	.fb_addr( fb_addr ),						// output [22:0]  fb_addr
	.fb_writedata( fb_writedata ),		// output [31:0]  fb_writedata
	.fb_we( fb_we ),							// output  fb_we
	
	.isp_entry_valid( isp_entry_valid ),// output  isp_entry_valid
	
	.ra_entry_valid( ra_entry_valid ),	// New Region Array entry read / new tile.
	.tile_prims_done( tile_prims_done ),// input tile_prims_done
	
	.poly_drawn( poly_drawn ),			// output poly_drawn
	
	.tilex( ra_cont_tilex ),
	.tiley( ra_cont_tiley ),
	
	.TEXT_CONTROL( TEXT_CONTROL ),		// From TEXT_CONTROL reg. (0xE4 in PVR regs).
	.PAL_RAM_CTRL( PAL_RAM_CTRL[1:0] ),	// From PAL_RAM_CTRL reg, bits [1:0].
	
	.pal_addr( pvr_addr[11:2] ),	// input [9:0]  pal_addr
	.pal_din( pvr_din ),				// input [31:0]  pal_din
	.pal_wr( pvr_addr[15:12]==4'b0001 && pvr_wr ),	// input  pal_wr
	.pal_rd( pvr_rd ),				// input  pal_rd
	.pal_dout( pal_dout )			// output [31:0]  pal_dout
);

wire [31:0] pal_dout;


/*
wire ta_fifo_full;
wire ta_fifo_empty;
wire [8:0] ta_fifo_words;

wire [31:0] ta_fifo_din = pvr_din;
wire [31:0] ta_fifo_dout;

// TA Command List FIFO...
fifo fifo_inst (
	.clk_i( clock ),				// input  clk_i
	.reset_n_i( reset_n ),			// input  reset_n_i (active-LOW)
	
	.write_i( ta_fifo_wr ),			// input  write_i
	.packet_i( ta_fifo_din ),		// input  [31:0] packet_i
	  
	.read_i( ta_fifo_read ),		// input  read_i
	.packet_o( ta_fifo_dout ),		// output  [31:0] packet_o
	
	.fifoFull_o( ta_fifo_full ),	// output  fifoFull_o
	.fifoEmpty_o( ta_fifo_empty ),	// output  fifoEmpty_o
	
	.writePtr( ta_fifo_words )		// output  [8:0] writePtr
);


// TA FIFO read state machine...
reg [7:0] ta_state;

reg ta_fifo_read;

reg [31:0] ta_command;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	ta_state <= 8'd0;
	ta_fifo_read <= 1'b0;
end
else begin
	ta_fifo_read <= 1'b0;

	case (ta_state)
		0: begin
			if (ta_fifo_words>=8) begin
				ta_state <= ta_state + 8'd1;
			end
			//end
		end
		
		1: begin
			
			ta_state <= ta_state + 1;
		end
		
		2: begin
			ta_command <= vram_din;
			ta_state <= ta_state + 1;
		end
		
		3: begin
			// 	 +-----------------+	
			// bit: | 31-29 |  28-0   |
			// name:|  cmd  | options |
			// 	 +-----------------+
			// cmd: 0 - END_OF_LIST
			// 	    1 - USER_CLIP
			// 	    2 - ???
			// 	    3 - ???
			// 	    4 - POLYGON / MODIFIER_VOLUME
			// 	    5 - SPRITE
			// 	    6 - ???
			// 	    7 - VERTEX
		
			case (ta_command[31:29])
				0: begin	// END_OF_LIST.
					ta_state <= 8'd0;
				end
				
				1: begin	// USER_CLIP.
				
				end

				2: ta_state <= 8'd0;	// not used.
				3: ta_state <= 8'd0;	// not used.

				4: begin	// POLYGON / MODIFIER_VOLUME.
				
				end

				5: begin	// SPRITE.
				
				end

				6: ta_state <= 8'd0;	// not used.

				7: begin	// VERTEX
				
				end
				default: ;
			endcase

			ta_state <= ta_state + 1;
		end
		
		4: begin
			ta_state <= 8'd0;					// Done!
		end
		
		default: ;
	endcase

end
*/


/*
parameter FPU_ADD = 2'd0;
parameter FPU_SUB = 2'd1;
parameter FPU_DIV = 2'd2;
parameter FPU_MUL = 2'd3;

reg [31:0] fpu_a;
reg [31:0] fpu_b;
reg [1:0] fpu_op;
wire [31:0] fpu_res;
my_fpu  my_fpu_inst(
	.clk( clock ),
	.A( fpu_a ),
	.B( fpu_b ),
	.op( fpu_op ),	// 0=ADD, 1=SUB, 2=DIV, 3=MUL.
	.O( fpu_res )
);


//	X1: 43AF5F3B 350.743988  X2: 43A1A798 323.309326  X3: 43AFB9B7 351.450897  X4: 00000000 0.000000
//	Y1: 43DE6D90 444.855957  Y2: 43E744E2 462.538147  Y3: 43DBF411 439.906769  Y4: 00000000 0.000000
//	area: 42F68F27 123.279594

//	X1: 43A1A798 323.309326  X2: 43AFB9B7 351.450897  X3: 43A03B11 320.461456  X4: 00000000 0.000000
//	Y1: 43E744E2 462.538147  Y2: 43DBF411 439.906769  Y3: 43D94FF1 434.624542  Y4: 00000000 0.000000
//	area: C4547EF7 -849.983826


wire [31:0] v1_x = 32'h43AF5F3B;
wire [31:0] v2_x = 32'h43A1A798;
wire [31:0] v3_x = 32'h43AFB9B7;
wire [31:0] v4_x = 32'h00000000;
wire [31:0] x1 = FLUSH_NAN(v1_x);
wire [31:0] x2 = FLUSH_NAN(v2_x);
wire [31:0] x3 = FLUSH_NAN(v3_x);
//wire [31:0] x4 = v4 ? FLUSH_NAN(v4_X) : 0;


wire [31:0] v1_y = 32'h43DE6D90;
wire [31:0] v2_y = 32'h43E744E2;
wire [31:0] v3_y = 32'h43DBF411;
wire [31:0] v4_y = 32'h00000000;
wire [31:0] y1 = FLUSH_NAN(v1_y);
wire [31:0] y2 = FLUSH_NAN(v2_y);
wire [31:0] y3 = FLUSH_NAN(v3_y);
//wire [31:0] y4 = v4 ? FLUSH_NAN(v4_y) : 0;


reg [31:0] x1_sub_x3;
reg [31:0] y2_sub_y3;
reg [31:0] y1_sub_y3;
reg [31:0] x2_sub_x3;

reg [31:0] x1x3_mul_y2y3;
reg [31:0] y1y3_mul_x2x3;

//wire [31:0] area = ((X1 - X3) * (Y2 - Y3) - (Y1 - Y3) * (X2 - X3));

reg [31:0] area;

reg trig_calcs;
reg [7:0] calc_state;

reg [7:0] delay;
parameter delay_amt = 8'd1;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	trig_calcs <= 1'b0;
	calc_state <= 8'd0;
end
else begin

	case (calc_state)
		0: begin
			//if (trig_calcs) begin
			begin
				fpu_a <= x1;
				fpu_b <= x3;
				fpu_op <= FPU_SUB;
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		1: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		2: begin
			x1_sub_x3 <= fpu_res;
		
			fpu_a <= y2;
			fpu_b <= y3;
			fpu_op <= FPU_SUB;
			calc_state <= calc_state + 8'd1;
		end
		
		3: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		4: begin
			y2_sub_y3 <= fpu_res;
		
			fpu_a <= y1;
			fpu_b <= y3;
			fpu_op <= FPU_SUB;
			calc_state <= calc_state + 8'd1;
		end
		
		5: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		6: begin
			y1_sub_y3 <= fpu_res;
		
			fpu_a <= x2;
			fpu_b <= x3;
			fpu_op <= FPU_SUB;
			calc_state <= calc_state + 8'd1;
		end

		7: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		8: begin
			x2_sub_x3 <= fpu_res;
			
			fpu_a <= x1_sub_x3;
			fpu_b <= y2_sub_y3;
			fpu_op <= FPU_MUL;
			calc_state <= calc_state + 8'd1;
		end

		9: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		10: begin
			x1x3_mul_y2y3 <= fpu_res;
		
			fpu_a <= y1_sub_y3;
			fpu_b <= x2_sub_x3;
			fpu_op <= FPU_MUL;
			calc_state <= calc_state + 8'd1;
		end

		11: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		12: begin
			y1y3_mul_x2x3 <= fpu_res;
			calc_state <= calc_state + 8'd1;
		end

		13: begin				
			fpu_a <= x1x3_mul_y2y3;
			fpu_b <= fpu_res;
			fpu_op <= FPU_SUB;
			calc_state <= calc_state + 8'd1;
		end
		
		14: begin
			if (delay>0) delay <= delay - 8'd1;
			else begin
				delay <= delay_amt;
				calc_state <= calc_state + 8'd1;
			end
		end
		
		15: begin
			area <= fpu_res;
		end
		
		default: ;
	endcase
end

wire sgn = !area[31];
*/

endmodule

/*
module fifo #(
  parameter PACKET_WIDTH = 32,
  parameter FIFO_DEPTH   = 256, 
  parameter PTR_MSB      = 8,
  parameter ADDR_MSB     = 7
  )
  (
	  input                           clk_i,
	  input                           reset_n_i,
	  input                           read_i,
	  input                           write_i,
	  input        [PACKET_WIDTH-1:0] packet_i,
	  output logic [PACKET_WIDTH-1:0] packet_o,
	  output logic                    fifoFull_o,
	  output logic                    fifoEmpty_o,
	  output logic [PTR_MSB:0]        writePtr
  );
  
  logic [PACKET_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
  logic [       PTR_MSB:0] readPtr;
  //logic [       PTR_MSB:0] writePtr;
  wire  [      ADDR_MSB:0] writeAddr = writePtr[ADDR_MSB:0];
  wire  [      ADDR_MSB:0] readAddr = readPtr[ADDR_MSB:0]; 
  
always_ff@(posedge clk_i or negedge reset_n_i)begin
if(~reset_n_i)begin
	readPtr     <= '0;
	writePtr    <= '0;
end
else begin
	if(write_i && ~fifoFull_o)begin
		memory[writeAddr] <= packet_i;
		writePtr         <= writePtr + 1;
	end
	if(read_i && ~fifoEmpty_o)begin
		packet_o <= memory[readAddr];
		readPtr <= readPtr + 1;
	end
end
end
  
assign fifoEmpty_o = (writePtr == readPtr) ? 1'b1: 1'b0;
assign fifoFull_o  = ((writePtr[ADDR_MSB:0] == readPtr[ADDR_MSB:0])&(writePtr[PTR_MSB] != readPtr[PTR_MSB])) ? 1'b1 : 1'b0;


endmodule


function [31:0] FLUSH_NAN;  
	input [31:0] in;  
	begin  
		FLUSH_NAN = (in[30:23]==8'd255 && in[22:0]!=0) ? 32'h00000000 :	// If the input value is NaN, return zero.
																	in;	// Else, return the input value.
	end
endfunction
*/
