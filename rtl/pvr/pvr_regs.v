`timescale 1ns / 1ps
`default_nettype none

module pvr_regs (
	input  wire        clock,
	input  wire        reset_n,
	input  wire        pvr_reg_cs,
	input  wire [15:0] pvr_addr,
	input  wire [31:0] pvr_din,
	input  wire        pvr_wr,
	output reg  [31:0] pvr_dout,

	input  wire [31:0] pal_dout,

	input  wire        mirror_wr,
	input  wire [15:0] mirror_addr,
	input  wire [63:0] mirror_din,
	input  wire  [1:0] mirror_word_en,

	output reg  [31:0] TEST_SELECT,
	output reg  [31:0] PARAM_BASE,
	output reg  [31:0] REGION_BASE,
	output reg  [31:0] FB_R_SOF1,
	output reg  [31:0] FB_R_SOF2,
	output reg  [31:0] FB_W_SOF1,
	output reg  [31:0] FB_W_SOF2,
	output reg  [31:0] FPU_PARAM_CFG,
	output reg  [31:0] TEXT_CONTROL,
	output reg  [31:0] PAL_RAM_CTRL,
	output reg  [31:0] TA_ALLOC_CTRL,

	output reg  [31:0] FPU_SHAD_SCALE,
	output reg  [31:0] ISP_BACKGND_D,
	output reg  [31:0] ISP_BACKGND_T
);

parameter ID_addr                    = 16'h0000;
parameter REVISION_addr              = 16'h0004;
parameter SOFTRESET_addr             = 16'h0008;
parameter STARTRENDER_addr           = 16'h0014;
parameter TEST_SELECT_addr           = 16'h0018;
parameter PARAM_BASE_addr            = 16'h0020;
parameter REGION_BASE_addr           = 16'h002C;
parameter SPAN_SORT_CFG_addr         = 16'h0030;
parameter VO_BORDER_COL_addr         = 16'h0040;
parameter FB_R_CTRL_addr             = 16'h0044;
parameter FB_W_CTRL_addr             = 16'h0048;
parameter FB_W_LINESTRIDE_addr       = 16'h004C;
parameter FB_R_SOF1_addr             = 16'h0050;
parameter FB_R_SOF2_addr             = 16'h0054;
parameter FB_R_SIZE_addr             = 16'h005C;
parameter FB_W_SOF1_addr             = 16'h0060;
parameter FB_W_SOF2_addr             = 16'h0064;
parameter FB_X_CLIP_addr             = 16'h0068;
parameter FB_Y_CLIP_addr             = 16'h006C;
parameter FPU_SHAD_SCALE_addr        = 16'h0074;
parameter FPU_CULL_VAL_addr          = 16'h0078;
parameter FPU_PARAM_CFG_addr         = 16'h007C;
parameter HALF_OFFSET_addr           = 16'h0080;
parameter FPU_PERP_VAL_addr          = 16'h0084;
parameter ISP_BACKGND_D_addr         = 16'h0088;
parameter ISP_BACKGND_T_addr         = 16'h008C;
parameter ISP_FEED_CFG_addr          = 16'h0098;
parameter SDRAM_REFRESH_addr         = 16'h00A0;
parameter SDRAM_ARB_CFG_addr         = 16'h00A4;
parameter SDRAM_CFG_addr             = 16'h00A8;
parameter FOG_COL_RAM_addr           = 16'h00B0;
parameter FOG_COL_VERT_addr          = 16'h00B4;
parameter FOG_DENSITY_addr           = 16'h00B8;
parameter FOG_CLAMP_MAX_addr         = 16'h00BC;
parameter FOG_CLAMP_MIN_addr         = 16'h00C0;
parameter SPG_TRIGGER_POS_addr       = 16'h00C4;
parameter SPG_HBLANK_INT_addr        = 16'h00C8;
parameter SPG_VBLANK_INT_addr        = 16'h00CC;
parameter SPG_CONTROL_addr           = 16'h00D0;
parameter SPG_HBLANK_addr            = 16'h00D4;
parameter SPG_LOAD_addr              = 16'h00D8;
parameter SPG_VBLANK_addr            = 16'h00DC;
parameter SPG_WIDTH_addr             = 16'h00E0;
parameter TEXT_CONTROL_addr          = 16'h00E4;
parameter VO_CONTROL_addr            = 16'h00E8;
parameter VO_STARTX_addr             = 16'h00EC;
parameter VO_STARTY_addr             = 16'h00F0;
parameter SCALER_CTL_addr            = 16'h00F4;
parameter PAL_RAM_CTRL_addr          = 16'h0108;
parameter SPG_STATUS_addr            = 16'h010C;
parameter FB_BURSTCTRL_addr          = 16'h0110;
parameter FB_C_SOF_addr              = 16'h0114;
parameter Y_COEFF_addr               = 16'h0118;
parameter PT_ALPHA_REF_addr          = 16'h011C;
parameter TA_OL_BASE_addr            = 16'h0124;
parameter TA_ISP_BASE_addr           = 16'h0128;
parameter TA_OL_LIMIT_addr           = 16'h012C;
parameter TA_ISP_LIMIT_addr          = 16'h0130;
parameter TA_NEXT_OPB_addr           = 16'h0134;
parameter TA_ISP_CURRENT_addr        = 16'h0138;
parameter TA_GLOB_TILE_CLIP_addr     = 16'h013C;
parameter TA_ALLOC_CTRL_addr         = 16'h0140;
parameter TA_LIST_INIT_addr          = 16'h0144;
parameter TA_YUV_TEX_BASE_addr       = 16'h0148;
parameter TA_YUV_TEX_CTRL_addr       = 16'h014C;
parameter TA_YUV_TEX_CNT_addr        = 16'h0150;
parameter TA_LIST_CONT_addr          = 16'h0160;
parameter TA_NEXT_OPB_INIT_addr      = 16'h0164;
parameter FOG_TABLE_START_addr       = 16'h0200;
parameter FOG_TABLE_END_addr         = 16'h03FC;
parameter TA_OL_POINTERS_START_addr  = 16'h0600;
parameter TA_OL_POINTERS_END_addr    = 16'h0F5C;
parameter PALETTE_RAM_START_addr     = 16'h1000;
parameter PALETTE_RAM_END_addr       = 16'h1FFC;

reg [31:0] ID;
reg [31:0] REVISION;
reg [31:0] SOFTRESET;
reg [31:0] STARTRENDER;
reg [31:0] SPAN_SORT_CFG;
reg [31:0] VO_BORDER_COL;
reg [31:0] FB_R_CTRL;
reg [31:0] FB_W_CTRL;
reg [31:0] FB_W_LINESTRIDE;
reg [31:0] FB_R_SIZE;
reg [31:0] FB_X_CLIP;
reg [31:0] FB_Y_CLIP;
reg [31:0] FPU_CULL_VAL;
reg [31:0] HALF_OFFSET;
reg [31:0] FPU_PERP_VAL;
reg [31:0] ISP_FEED_CFG;
reg [31:0] SDRAM_REFRESH;
reg [31:0] SDRAM_ARB_CFG;
reg [31:0] SDRAM_CFG;
reg [31:0] FOG_COL_RAM;
reg [31:0] FOG_COL_VERT;
reg [31:0] FOG_DENSITY;
reg [31:0] FOG_CLAMP_MAX;
reg [31:0] FOG_CLAMP_MIN;
reg [31:0] SPG_TRIGGER_POS;
reg [31:0] SPG_HBLANK_INT;
reg [31:0] SPG_VBLANK_INT;
reg [31:0] SPG_CONTROL;
reg [31:0] SPG_HBLANK;
reg [31:0] SPG_LOAD;
reg [31:0] SPG_VBLANK;
reg [31:0] SPG_WIDTH;
reg [31:0] VO_CONTROL;
reg [31:0] VO_STARTX;
reg [31:0] VO_STARTY;
reg [31:0] SCALER_CTL;
reg [31:0] SPG_STATUS;
reg [31:0] FB_BURSTCTRL;
reg [31:0] FB_C_SOF;
reg [31:0] Y_COEFF;
reg [31:0] PT_ALPHA_REF;
reg [31:0] TA_OL_BASE;
reg [31:0] TA_ISP_BASE;
reg [31:0] TA_OL_LIMIT;
reg [31:0] TA_ISP_LIMIT;
reg [31:0] TA_NEXT_OPB;
reg [31:0] TA_ISP_CURRENT;
reg [31:0] TA_GLOB_TILE_CLIP;
reg [31:0] TA_LIST_INIT;
reg [31:0] TA_YUV_TEX_BASE;
reg [31:0] TA_YUV_TEX_CTRL;
reg [31:0] TA_YUV_TEX_CNT;
reg [31:0] TA_LIST_CONT;
reg [31:0] TA_NEXT_OPB_INIT;
reg [31:0] FOG_TABLE_START;
reg [31:0] FOG_TABLE_END;
reg [31:0] TA_OL_POINTERS_START;
reg [31:0] TA_OL_POINTERS_END;
reg [31:0] PALETTE_RAM_START;
reg [31:0] PALETTE_RAM_END;

task automatic write_mirror_register;
	input [15:0] write_addr;
	input [31:0] write_data;
begin
	case (write_addr)
		ID_addr:                ID <= write_data;
		REVISION_addr:          REVISION <= write_data;
		SOFTRESET_addr:         SOFTRESET <= write_data;
		STARTRENDER_addr:       STARTRENDER <= write_data;
		TEST_SELECT_addr:       TEST_SELECT <= write_data;
		PARAM_BASE_addr:        PARAM_BASE <= write_data;
		REGION_BASE_addr:       REGION_BASE <= write_data;
		SPAN_SORT_CFG_addr:     SPAN_SORT_CFG <= write_data;
		VO_BORDER_COL_addr:     VO_BORDER_COL <= write_data;
		FB_R_CTRL_addr:         FB_R_CTRL <= write_data;
		FB_W_CTRL_addr:         FB_W_CTRL <= write_data;
		FB_W_LINESTRIDE_addr:   FB_W_LINESTRIDE <= write_data;
		FB_R_SOF1_addr:         FB_R_SOF1 <= write_data;
		FB_R_SOF2_addr:         FB_R_SOF2 <= write_data;
		FB_R_SIZE_addr:         FB_R_SIZE <= write_data;
		FB_W_SOF1_addr:         FB_W_SOF1 <= write_data;
		FB_W_SOF2_addr:         FB_W_SOF2 <= write_data;
		FB_X_CLIP_addr:         FB_X_CLIP <= write_data;
		FB_Y_CLIP_addr:         FB_Y_CLIP <= write_data;
		FPU_SHAD_SCALE_addr:    FPU_SHAD_SCALE <= write_data;
		FPU_CULL_VAL_addr:      FPU_CULL_VAL <= write_data;
		FPU_PARAM_CFG_addr:     FPU_PARAM_CFG <= write_data;
		HALF_OFFSET_addr:       HALF_OFFSET <= write_data;
		FPU_PERP_VAL_addr:      FPU_PERP_VAL <= write_data;
		ISP_BACKGND_D_addr:     ISP_BACKGND_D <= write_data;
		ISP_BACKGND_T_addr:     ISP_BACKGND_T <= write_data;
		ISP_FEED_CFG_addr:      ISP_FEED_CFG <= write_data;
		SDRAM_REFRESH_addr:     SDRAM_REFRESH <= write_data;
		SDRAM_ARB_CFG_addr:     SDRAM_ARB_CFG <= write_data;
		SDRAM_CFG_addr:         SDRAM_CFG <= write_data;
		FOG_COL_RAM_addr:       FOG_COL_RAM <= write_data;
		FOG_COL_VERT_addr:      FOG_COL_VERT <= write_data;
		FOG_DENSITY_addr:       FOG_DENSITY <= write_data;
		FOG_CLAMP_MAX_addr:     FOG_CLAMP_MAX <= write_data;
		FOG_CLAMP_MIN_addr:     FOG_CLAMP_MIN <= write_data;
		SPG_TRIGGER_POS_addr:   SPG_TRIGGER_POS <= write_data;
		SPG_HBLANK_INT_addr:    SPG_HBLANK_INT <= write_data;
		SPG_VBLANK_INT_addr:    SPG_VBLANK_INT <= write_data;
		SPG_CONTROL_addr:       SPG_CONTROL <= write_data;
		SPG_HBLANK_addr:        SPG_HBLANK <= write_data;
		SPG_LOAD_addr:          SPG_LOAD <= write_data;
		SPG_VBLANK_addr:        SPG_VBLANK <= write_data;
		SPG_WIDTH_addr:         SPG_WIDTH <= write_data;
		TEXT_CONTROL_addr:      TEXT_CONTROL <= write_data;
		VO_CONTROL_addr:        VO_CONTROL <= write_data;
		VO_STARTX_addr:         VO_STARTX <= write_data;
		VO_STARTY_addr:         VO_STARTY <= write_data;
		SCALER_CTL_addr:        SCALER_CTL <= write_data;
		PAL_RAM_CTRL_addr:      PAL_RAM_CTRL <= write_data;
		SPG_STATUS_addr:        SPG_STATUS <= write_data;
		FB_BURSTCTRL_addr:      FB_BURSTCTRL <= write_data;
		FB_C_SOF_addr:          FB_C_SOF <= write_data;
		Y_COEFF_addr:           Y_COEFF <= write_data;
		PT_ALPHA_REF_addr:      PT_ALPHA_REF <= write_data;
		TA_OL_BASE_addr:        TA_OL_BASE <= write_data;
		TA_ISP_BASE_addr:       TA_ISP_BASE <= write_data;
		TA_OL_LIMIT_addr:       TA_OL_LIMIT <= write_data;
		TA_ISP_LIMIT_addr:      TA_ISP_LIMIT <= write_data;
		TA_NEXT_OPB_addr:       TA_NEXT_OPB <= write_data;
		TA_ISP_CURRENT_addr:    TA_ISP_CURRENT <= write_data;
		TA_GLOB_TILE_CLIP_addr: TA_GLOB_TILE_CLIP <= write_data;
		TA_ALLOC_CTRL_addr:     TA_ALLOC_CTRL <= write_data;
		TA_LIST_INIT_addr:      TA_LIST_INIT <= write_data;
		TA_YUV_TEX_BASE_addr:   TA_YUV_TEX_BASE <= write_data;
		TA_YUV_TEX_CTRL_addr:   TA_YUV_TEX_CTRL <= write_data;
		TA_YUV_TEX_CNT_addr:    TA_YUV_TEX_CNT <= write_data;
		TA_LIST_CONT_addr:      TA_LIST_CONT <= write_data;
		TA_NEXT_OPB_INIT_addr:  TA_NEXT_OPB_INIT <= write_data;
		FOG_TABLE_START_addr:   FOG_TABLE_START <= write_data;
		default: ;
	endcase
end
endtask

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		ID       <= 32'h17FD11DB;
		REVISION <= 32'h00000011;
	end
	else begin
		if (pvr_reg_cs && pvr_wr) begin
			case (pvr_addr)
			SOFTRESET_addr:         SOFTRESET <= pvr_din;
			STARTRENDER_addr:       STARTRENDER <= pvr_din;
			TEST_SELECT_addr:       TEST_SELECT <= pvr_din;
			PARAM_BASE_addr:        PARAM_BASE <= pvr_din;
			REGION_BASE_addr:       REGION_BASE <= pvr_din;
			SPAN_SORT_CFG_addr:     SPAN_SORT_CFG <= pvr_din;
			VO_BORDER_COL_addr:     VO_BORDER_COL <= pvr_din;
			FB_R_CTRL_addr:         FB_R_CTRL <= pvr_din;
			FB_W_CTRL_addr:         FB_W_CTRL <= pvr_din;
			FB_W_LINESTRIDE_addr:   FB_W_LINESTRIDE <= pvr_din;
			FB_R_SOF1_addr:         FB_R_SOF1 <= pvr_din;
			FB_R_SOF2_addr:         FB_R_SOF2 <= pvr_din;
			FB_R_SIZE_addr:         FB_R_SIZE <= pvr_din;
			FB_W_SOF1_addr:         FB_W_SOF1 <= pvr_din;
			FB_W_SOF2_addr:         FB_W_SOF2 <= pvr_din;
			FB_X_CLIP_addr:         FB_X_CLIP <= pvr_din;
			FB_Y_CLIP_addr:         FB_Y_CLIP <= pvr_din;
			FPU_SHAD_SCALE_addr:    FPU_SHAD_SCALE <= pvr_din;
			FPU_CULL_VAL_addr:      FPU_CULL_VAL <= pvr_din;
			FPU_PARAM_CFG_addr:     FPU_PARAM_CFG <= pvr_din;
			HALF_OFFSET_addr:       HALF_OFFSET <= pvr_din;
			FPU_PERP_VAL_addr:      FPU_PERP_VAL <= pvr_din;
			ISP_BACKGND_D_addr:     ISP_BACKGND_D <= pvr_din;
			ISP_BACKGND_T_addr:     ISP_BACKGND_T <= pvr_din;
			ISP_FEED_CFG_addr:      ISP_FEED_CFG <= pvr_din;
			SDRAM_REFRESH_addr:     SDRAM_REFRESH <= pvr_din;
			SDRAM_ARB_CFG_addr:     SDRAM_ARB_CFG <= pvr_din;
			SDRAM_CFG_addr:         SDRAM_CFG <= pvr_din;
			FOG_COL_RAM_addr:       FOG_COL_RAM <= pvr_din;
			FOG_COL_VERT_addr:      FOG_COL_VERT <= pvr_din;
			FOG_DENSITY_addr:       FOG_DENSITY <= pvr_din;
			FOG_CLAMP_MAX_addr:     FOG_CLAMP_MAX <= pvr_din;
			FOG_CLAMP_MIN_addr:     FOG_CLAMP_MIN <= pvr_din;
			SPG_TRIGGER_POS_addr:   SPG_TRIGGER_POS <= pvr_din;
			SPG_HBLANK_INT_addr:    SPG_HBLANK_INT <= pvr_din;
			SPG_VBLANK_INT_addr:    SPG_VBLANK_INT <= pvr_din;
			SPG_CONTROL_addr:       SPG_CONTROL <= pvr_din;
			SPG_HBLANK_addr:        SPG_HBLANK <= pvr_din;
			SPG_LOAD_addr:          SPG_LOAD <= pvr_din;
			SPG_VBLANK_addr:        SPG_VBLANK <= pvr_din;
			SPG_WIDTH_addr:         SPG_WIDTH <= pvr_din;
			TEXT_CONTROL_addr:      TEXT_CONTROL <= pvr_din;
			VO_CONTROL_addr:        VO_CONTROL <= pvr_din;
			VO_STARTX_addr:         VO_STARTX <= pvr_din;
			VO_STARTY_addr:         VO_STARTY <= pvr_din;
			SCALER_CTL_addr:        SCALER_CTL <= pvr_din;
			PAL_RAM_CTRL_addr:      PAL_RAM_CTRL <= pvr_din;
			SPG_STATUS_addr:        SPG_STATUS <= pvr_din;
			FB_BURSTCTRL_addr:      FB_BURSTCTRL <= pvr_din;
			FB_C_SOF_addr:          FB_C_SOF <= pvr_din;
			Y_COEFF_addr:           Y_COEFF <= pvr_din;
			PT_ALPHA_REF_addr:      PT_ALPHA_REF <= pvr_din;
			TA_OL_BASE_addr:        TA_OL_BASE <= pvr_din;
			TA_ISP_BASE_addr:       TA_ISP_BASE <= pvr_din;
			TA_OL_LIMIT_addr:       TA_OL_LIMIT <= pvr_din;
			TA_ISP_LIMIT_addr:      TA_ISP_LIMIT <= pvr_din;
			TA_NEXT_OPB_addr:       TA_NEXT_OPB <= pvr_din;
			TA_ISP_CURRENT_addr:    TA_ISP_CURRENT <= pvr_din;
			TA_GLOB_TILE_CLIP_addr: TA_GLOB_TILE_CLIP <= pvr_din;
			TA_ALLOC_CTRL_addr:     TA_ALLOC_CTRL <= pvr_din;
			TA_LIST_INIT_addr:      TA_LIST_INIT <= pvr_din;
			TA_YUV_TEX_BASE_addr:   TA_YUV_TEX_BASE <= pvr_din;
			TA_YUV_TEX_CTRL_addr:   TA_YUV_TEX_CTRL <= pvr_din;
			TA_YUV_TEX_CNT_addr:    TA_YUV_TEX_CNT <= pvr_din;
			TA_LIST_CONT_addr:      TA_LIST_CONT <= pvr_din;
			TA_NEXT_OPB_INIT_addr:  TA_NEXT_OPB_INIT <= pvr_din;
			FOG_TABLE_START_addr:   FOG_TABLE_START <= pvr_din;
			FOG_TABLE_END_addr:     FOG_TABLE_END <= pvr_din;
			TA_OL_POINTERS_START_addr: TA_OL_POINTERS_START <= pvr_din;
			TA_OL_POINTERS_END_addr:   TA_OL_POINTERS_END <= pvr_din;
			PALETTE_RAM_START_addr: PALETTE_RAM_START <= pvr_din;
			PALETTE_RAM_END_addr:   PALETTE_RAM_END <= pvr_din;
				default: ;
			endcase
		end

		if (mirror_wr) begin
			if (mirror_word_en[0])
				write_mirror_register(mirror_addr, mirror_din[31:0]);
			if (mirror_word_en[1])
				write_mirror_register(mirror_addr + 16'd4, mirror_din[63:32]);
		end
	end
end

always @(posedge clock) begin
	casez (pvr_addr)
		ID_addr:                pvr_dout <= ID;
		REVISION_addr:          pvr_dout <= REVISION;
		SOFTRESET_addr:         pvr_dout <= SOFTRESET;
		STARTRENDER_addr:       pvr_dout <= STARTRENDER;
		TEST_SELECT_addr:       pvr_dout <= TEST_SELECT;
		PARAM_BASE_addr:        pvr_dout <= PARAM_BASE;
		REGION_BASE_addr:       pvr_dout <= REGION_BASE;
		SPAN_SORT_CFG_addr:     pvr_dout <= SPAN_SORT_CFG;
		VO_BORDER_COL_addr:     pvr_dout <= VO_BORDER_COL;
		FB_R_CTRL_addr:         pvr_dout <= FB_R_CTRL;
		FB_W_CTRL_addr:         pvr_dout <= FB_W_CTRL;
		FB_W_LINESTRIDE_addr:   pvr_dout <= FB_W_LINESTRIDE;
		FB_R_SOF1_addr:         pvr_dout <= FB_R_SOF1;
		FB_R_SOF2_addr:         pvr_dout <= FB_R_SOF2;
		FB_R_SIZE_addr:         pvr_dout <= FB_R_SIZE;
		FB_W_SOF1_addr:         pvr_dout <= FB_W_SOF1;
		FB_W_SOF2_addr:         pvr_dout <= FB_W_SOF2;
		FB_X_CLIP_addr:         pvr_dout <= FB_X_CLIP;
		FB_Y_CLIP_addr:         pvr_dout <= FB_Y_CLIP;
		FPU_SHAD_SCALE_addr:    pvr_dout <= FPU_SHAD_SCALE;
		FPU_CULL_VAL_addr:      pvr_dout <= FPU_CULL_VAL;
		FPU_PARAM_CFG_addr:     pvr_dout <= FPU_PARAM_CFG;
		HALF_OFFSET_addr:       pvr_dout <= HALF_OFFSET;
		FPU_PERP_VAL_addr:      pvr_dout <= FPU_PERP_VAL;
		ISP_BACKGND_D_addr:     pvr_dout <= ISP_BACKGND_D;
		ISP_BACKGND_T_addr:     pvr_dout <= ISP_BACKGND_T;
		ISP_FEED_CFG_addr:      pvr_dout <= ISP_FEED_CFG;
		SDRAM_REFRESH_addr:     pvr_dout <= SDRAM_REFRESH;
		SDRAM_ARB_CFG_addr:     pvr_dout <= SDRAM_ARB_CFG;
		SDRAM_CFG_addr:         pvr_dout <= SDRAM_CFG;
		FOG_COL_RAM_addr:       pvr_dout <= FOG_COL_RAM;
		FOG_COL_VERT_addr:      pvr_dout <= FOG_COL_VERT;
		FOG_DENSITY_addr:       pvr_dout <= FOG_DENSITY;
		FOG_CLAMP_MAX_addr:     pvr_dout <= FOG_CLAMP_MAX;
		FOG_CLAMP_MIN_addr:     pvr_dout <= FOG_CLAMP_MIN;
		SPG_TRIGGER_POS_addr:   pvr_dout <= SPG_TRIGGER_POS;
		SPG_HBLANK_INT_addr:    pvr_dout <= SPG_HBLANK_INT;
		SPG_VBLANK_INT_addr:    pvr_dout <= SPG_VBLANK_INT;
		SPG_CONTROL_addr:       pvr_dout <= SPG_CONTROL;
		SPG_HBLANK_addr:        pvr_dout <= SPG_HBLANK;
		SPG_LOAD_addr:          pvr_dout <= SPG_LOAD;
		SPG_VBLANK_addr:        pvr_dout <= SPG_VBLANK;
		SPG_WIDTH_addr:         pvr_dout <= SPG_WIDTH;
		TEXT_CONTROL_addr:      pvr_dout <= TEXT_CONTROL;
		VO_CONTROL_addr:        pvr_dout <= VO_CONTROL;
		VO_STARTX_addr:         pvr_dout <= VO_STARTX;
		VO_STARTY_addr:         pvr_dout <= VO_STARTY;
		SCALER_CTL_addr:        pvr_dout <= SCALER_CTL;
		PAL_RAM_CTRL_addr:      pvr_dout <= PAL_RAM_CTRL;
		SPG_STATUS_addr:        pvr_dout <= SPG_STATUS;
		FB_BURSTCTRL_addr:      pvr_dout <= FB_BURSTCTRL;
		FB_C_SOF_addr:          pvr_dout <= FB_C_SOF;
		Y_COEFF_addr:           pvr_dout <= Y_COEFF;
		PT_ALPHA_REF_addr:      pvr_dout <= PT_ALPHA_REF;
		TA_OL_BASE_addr:        pvr_dout <= TA_OL_BASE;
		TA_ISP_BASE_addr:       pvr_dout <= TA_ISP_BASE;
		TA_OL_LIMIT_addr:       pvr_dout <= TA_OL_LIMIT;
		TA_ISP_LIMIT_addr:      pvr_dout <= TA_ISP_LIMIT;
		TA_NEXT_OPB_addr:       pvr_dout <= TA_NEXT_OPB;
		TA_ISP_CURRENT_addr:    pvr_dout <= TA_ISP_CURRENT;
		TA_GLOB_TILE_CLIP_addr: pvr_dout <= TA_GLOB_TILE_CLIP;
		TA_ALLOC_CTRL_addr:     pvr_dout <= TA_ALLOC_CTRL;
		TA_LIST_INIT_addr:      pvr_dout <= TA_LIST_INIT;
		TA_YUV_TEX_BASE_addr:   pvr_dout <= TA_YUV_TEX_BASE;
		TA_YUV_TEX_CTRL_addr:   pvr_dout <= TA_YUV_TEX_CTRL;
		TA_YUV_TEX_CNT_addr:    pvr_dout <= TA_YUV_TEX_CNT;
		TA_LIST_CONT_addr:      pvr_dout <= TA_LIST_CONT;
		TA_NEXT_OPB_INIT_addr:  pvr_dout <= TA_NEXT_OPB_INIT;
		FOG_TABLE_START_addr:   pvr_dout <= FOG_TABLE_START;
		FOG_TABLE_END_addr:     pvr_dout <= FOG_TABLE_END;
		TA_OL_POINTERS_START_addr: pvr_dout <= TA_OL_POINTERS_START;
		TA_OL_POINTERS_END_addr:   pvr_dout <= TA_OL_POINTERS_END;
		16'b0001????????????:    pvr_dout <= pal_dout;
		default: ;
	endcase
end

endmodule
