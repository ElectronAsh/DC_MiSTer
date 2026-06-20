`timescale 1ns / 1ps
`include "defines.v"
`default_nettype none

module simtop (
    input clk,
    input rst,
		
	input [7:0] FRAC_BITS,
	input [7:0] Z_FRAC_BITS,
	input [7:0] FRAC_DIFF,

	input wire [31:0] vert_a_x,
	input wire [31:0] vert_a_y,
	input wire [31:0] vert_a_z,
	input wire [31:0] vert_b_x,
	input wire [31:0] vert_b_y,
	input wire [31:0] vert_b_z,
	input wire [31:0] vert_c_x,
	input wire [31:0] vert_c_y,
	input wire [31:0] vert_c_z,
	
	output wire [47:0] FX1_FIXED,
	output wire [47:0] FY1_FIXED,
	output wire [47:0] FZ1_FIXED,
	output wire [47:0] FX2_FIXED,
	output wire [47:0] FY2_FIXED,
	output wire [47:0] FZ2_FIXED,
	output wire [47:0] FX3_FIXED,
	output wire [47:0] FY3_FIXED,
	output wire [47:0] FZ3_FIXED,
	
	input [10:0] x_ps,
	input [10:0] y_ps,

	output reg signed [63:0] BIG_C_z,

	output wire signed [47:0] IP_Z_INTERP,
	
    // Runtime Configuration
    input [31:0] boot_vector,
	
    // Instruction memory
    output wire [31:0] im_req_addr,
    output wire im_req_valid,
    input [31:0] im_resp_rdata,
    input im_resp_valid,
	
    // Data memory
    output wire [31:0] dm_req_addr,
    output wire [63:0] dm_req_wdata,
    output wire [7:0] dm_req_wmask,
    output wire dm_req_wen,
    output wire dm_req_valid,
    input [63:0] dm_resp_rdata,
    input dm_resp_valid,
	
    // Trace
    output wire trace_valid0,
    output wire [31:0] trace_pc0,
    output wire [15:0] trace_instr0,
    output wire trace_wen0,
    output wire [3:0] trace_wdst0,
    output wire [31:0] trace_wdata0,
    output wire trace_valid1,
    output wire [31:0] trace_pc1,
    output wire [15:0] trace_instr1,
    output wire trace_wen1,
    output wire [3:0] trace_wdst1,
    output wire [31:0] trace_wdata1,

	input [9:0] sim_ui,
	input [9:0] sim_vi,
	input [31:0] fb_w_sof1_mirror,

	// RA/ISP Reads...
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,
	
	// TSP (Texture) reads / (future) Tile writeback.
	output        DDRAM2_CLK,
	input         DDRAM2_BUSY,
	output  [7:0] DDRAM2_BURSTCNT,
	output [28:0] DDRAM2_ADDR,
	input  [63:0] DDRAM2_DOUT,
	input         DDRAM2_DOUT_READY,
	output        DDRAM2_RD,
	output [63:0] DDRAM2_DIN,
	output  [7:0] DDRAM2_BE,
	output        DDRAM2_WE,

	output [22:0] fb_addr,
	output [63:0] fb_writedata,
	output [7:0] fb_byteena,
	output fb_we
);

/* verilator lint_off PINCONNECTEMPTY */
/*
core  sh4_core (
	.clk(clk),
	.rst(rst),
	
	.boot_vector(boot_vector),
	
	.im_req_addr(im_req_addr),
	.im_req_valid(im_req_valid),
	.im_resp_rdata(im_resp_rdata),
	.im_resp_valid(im_resp_valid),
	
	.dm_req_addr(dm_req_addr),
	.dm_req_wdata(dm_req_wdata),
	.dm_req_wmask(dm_req_wmask),
	.dm_req_wen(dm_req_wen),
	.dm_req_valid(dm_req_valid),
	
	//.dm_resp_rdata(dm_resp_rdata),
	.dm_resp_rdata(sh4_dm_rdata),
	
	.dm_resp_valid(dm_resp_valid),
	
	.trace_valid0(trace_valid0),
	.trace_pc0(trace_pc0),
	.trace_instr0(trace_instr0),
	.trace_wen0(trace_wen0),
	.trace_wdst0(trace_wdst0),
	.trace_wdata0(trace_wdata0),
	.trace_valid1(trace_valid1),
	.trace_pc1(trace_pc1),
	.trace_instr1(trace_instr1),
	.trace_wen1(trace_wen1),
	.trace_wdst1(trace_wdst1),
	.trace_wdata1(trace_wdata1),
	
	// Unused pins
	.im_invalidate_req(),
	.im_invalidate_resp(1'b0),
	.dm_req_flush(),
	.dm_req_invalidate(),
	.dm_req_writeback(),
	.dm_req_prefetch(),
	.dm_req_nofill()
);
*/
/* verilator lint_on PINCONNECTEMPTY */

wire [28:0] req_addr = dm_req_addr[28:0];

/*
// Typo in Dreamcast_Hardware_Specification_Outline.pdf says "CS1", but this is "CS0" on the SH4..
//
wire sh4_cs0 = req_addr>=29'h00000000 && req_addr<=29'h01ffffff;	// BIOS,Flash,System,Maple,GD-ROM,G1,G2,PVR/TA,Modem,AICA etc.
wire sh4_cs1 = req_addr>=29'h04000000 && req_addr<=29'h057fffff;	// PVR VRAM.
wire sh4_cs2 = req_addr>=29'h08000000 && req_addr<=29'h0bffffff;	// Unassigned.
wire sh4_cs3 = req_addr>=29'h0c000000 && req_addr<=29'h0c7fffff;	// Work SDRAM.
wire sh4_cs4 = req_addr>=29'h10000000 && req_addr<=29'h117fffff;	// TA FIFO, YUV Converter, Texture Mem WRITE.
wire sh4_cs5 = req_addr>=29'h14000000 && req_addr<=29'h17ffffff;	// Ext. Device?
wire sh4_cs6 = req_addr>=29'h18000000 && req_addr<=29'h1bffffff;	// Unassigned.
*/

// HOLLY Address Decoding.
// CS0...
/* verilator lint_off UNSIGNED */
wire bios_cs     = im_req_addr>=21'h000000 && im_req_addr<=21'h1fffff;
/* verilator lint_on UNSIGNED */

wire flash_cs    = req_addr>=29'h00200000 && req_addr<=29'h0021ffff;
wire system_cs   = req_addr>=29'h005f6800 && req_addr<=29'h005f69ff;
wire maple_cs    = req_addr>=29'h005f6c00 && req_addr<=29'h005f6cff;
wire gdrom_cs    = req_addr>=29'h005f7000 && req_addr<=29'h005f70ff;
wire g1_reg_cs   = req_addr>=29'h005f7400 && req_addr<=29'h005f74ff;
wire g2_reg_cs   = req_addr>=29'h005f7800 && req_addr<=29'h005f78ff;
wire pvr_reg_cs  = req_addr>=29'h005f7c00 && req_addr<=29'h005f7cff;
wire ta_reg_cs   = req_addr>=29'h005f8000 && req_addr<=29'h005f9fff;
wire modem_cs    = req_addr>=29'h00600000 && req_addr<=29'h006007ff;
wire aica_reg_cs = req_addr>=29'h00700000 && req_addr<=29'h00707fff;
wire aica_rtc_cs = req_addr>=29'h00710000 && req_addr<=29'h00710007;
wire aica_ram_cs = req_addr>=29'h00800000 && req_addr<=29'h009fffff;
wire g2_ext_cs   = req_addr>=29'h01000000 && req_addr<=29'h01ffffff;

/// CS1...
wire vram_64_cs       = req_addr>=29'h04000000 && req_addr<=29'h047fffff;	// 8MB (64-bit access).
wire vram_32_cs       = req_addr>=29'h05000000 && req_addr<=29'h057fffff;	// 8MB (32-bit access).
wire vram_64_mirr_cs  = req_addr>=29'h06000000 && req_addr<=29'h067fffff;	// 8MB (Mirror. 64-bit access).
wire vram_32_mirr_cs  = req_addr>=29'h07000000 && req_addr<=29'h077fffff;	// 8MB (Mirror. 32-bit access).

// CS3...
wire sdram_cs	 = req_addr>=29'h08000000 && req_addr<=29'h0bffffff;

// CS4...
wire ta_fifo_cs  = req_addr>=29'h10000000 && req_addr<=29'h107fffff;
wire ta_yuv_cs   = req_addr>=29'h10800000 && req_addr<=29'h10ffffff;
wire ta_tex_cs   = req_addr>=29'h11000000 && req_addr<=29'h117fffff;


// SH4 Data read mux...
wire [63:0] sh4_dm_rdata = (pvr_reg_cs) ? {32'h00000000, pvr_dout} :
										  dm_resp_rdata;

wire pvr_rd = dm_req_valid && !dm_req_wen;
wire pvr_wr = dm_req_valid && dm_req_wen;

wire [31:0] pvr_dout;

/*
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_a_x (.float_in( vert_a_x ), .fixed( FX1_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_a_y (.float_in( vert_a_y ), .fixed( FY1_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_test_a_z (.float_in( vert_a_z ), .fixed( FZ1_FIXED ));

float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_b_x (.float_in( vert_b_x ), .fixed( FX2_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_b_y (.float_in( vert_b_y ), .fixed( FY2_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_test_b_z (.float_in( vert_b_z ), .fixed( FZ2_FIXED ));

float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_c_x (.float_in( vert_c_x ), .fixed( FX3_FIXED ));
float_to_fixed #(.FRAC_BITS(FRAC_BITS))   float_test_c_y (.float_in( vert_c_y ), .fixed( FY3_FIXED ));
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_test_c_z (.float_in( vert_c_z ), .fixed( FZ3_FIXED ));

reg signed [31:0] FY2_sub_FY1_z;
reg signed [31:0] FY3_sub_FY1_z;
reg signed [31:0] FX2_sub_FX1_z;
reg signed [31:0] FX3_sub_FX1_z;
reg signed [63:0] C_mult_1_z;
reg signed [63:0] C_mult_2_z;
//reg signed [63:0] BIG_C_z;

always @(*) begin
    // XY deltas — FRAC_BITS domain
	FY2_sub_FY1_z = (FY2_FIXED - FY1_FIXED);
	FY3_sub_FY1_z = (FY3_FIXED - FY1_FIXED);
	FX2_sub_FX1_z = (FX2_FIXED - FX1_FIXED);
	FX3_sub_FX1_z = (FX3_FIXED - FX1_FIXED);

    // Cross product (area * 2)
	C_mult_1_z = (FX2_sub_FX1_z * FY3_sub_FY1_z);
	C_mult_2_z = (FX3_sub_FX1_z * FY2_sub_FY1_z);
	//BIG_C_z  = (C_mult_2_z - C_mult_1_z) >>>(FRAC_BITS - FRAC_DIFF);
	BIG_C_z    = (C_mult_1_z - C_mult_2_z) >>>(FRAC_BITS - FRAC_DIFF);
end

//wire signed [47:0] IP_Z [0:31];	// [0:31] is the tile COLUMN.
//wire signed [47:0] IP_Z_INTERP;		// For sim C code debug.
interp  interp_inst_z (
	.clock( clk ),
	
	//.tri_setup( tri_setup ),

	.FRAC_BITS( FRAC_BITS ),		// input [7:0] FRAC_BITS
	.Z_FRAC_BITS( Z_FRAC_BITS ),	// input [7:0] Z_FRAC_BITS
	.FRAC_DIFF( FRAC_DIFF ),		// input [7:0] FRAC_DIFF

	// FRAC_BITS format...
	.FY2_sub_FY1( FY2_sub_FY1_z ),	// input signed [47:0]  
	.FY3_sub_FY1( FY3_sub_FY1_z ),	// input signed [47:0]  
	.FX2_sub_FX1( FX2_sub_FX1_z ),	// input signed [47:0]  
	.FX3_sub_FX1( FX3_sub_FX1_z ),	// input signed [47:0]  
	.FX1( FX1_FIXED ),				// input signed [47:0] x1
	.FY1( FY1_FIXED ),				// input signed [47:0] y1	

	// Now in Z_FRAC_BITS format...
	.BIG_C( BIG_C_z ),				// input signed [63:0] BIG_C
	.FZ1( FZ1_FIXED ),				// input signed [47:0] z1
	.FZ2( FZ2_FIXED ),				// input signed [47:0] z2
	.FZ3( FZ3_FIXED ),				// input signed [47:0] z3
	
	// Integer...
	.x_ps( x_ps ),		// input [10:0] x_ps
	.y_ps( y_ps ),		// input [10:0] y_ps
	
	.interp( IP_Z_INTERP )//,	// output signed [47:0]  interp

	//.interp0(  IP_Z[0] ),  .interp1(  IP_Z[1] ),  .interp2(  IP_Z[2] ),  .interp3(  IP_Z[3] ),  .interp4(  IP_Z[4] ),  .interp5(  IP_Z[5] ),  .interp6(  IP_Z[6] ),  .interp7(  IP_Z[7] ),
	//.interp8(  IP_Z[8] ),  .interp9(  IP_Z[9] ),  .interp10( IP_Z[10] ), .interp11( IP_Z[11] ), .interp12( IP_Z[12] ), .interp13( IP_Z[13] ), .interp14( IP_Z[14] ), .interp15( IP_Z[15] ),
	//.interp16( IP_Z[16] ), .interp17( IP_Z[17] ), .interp18( IP_Z[18] ), .interp19( IP_Z[19] ), .interp20( IP_Z[20] ), .interp21( IP_Z[21] ), .interp22( IP_Z[22] ), .interp23( IP_Z[23] ),
	//.interp24( IP_Z[24] ), .interp25( IP_Z[25] ), .interp26( IP_Z[26] ), .interp27( IP_Z[27] ), .interp28( IP_Z[28] ), .interp29( IP_Z[29] ), .interp30( IP_Z[30] ), .interp31( IP_Z[31] )
);
*/

wire [23:0] ra_vram_addr_core;
wire ra_vram_rd_core;
wire ra_vram_wr_core;
wire [63:0] ra_vram_din_core;
wire ra_vram_rd_wait_core;
wire ra_vram_wr_wait_core;
wire ra_vram_wait_core;
wire ra_vram_valid_core;
wire ra_vram_req_ack_core;
wire [31:0] ra_vram_dout_core;

wire [23:0] isp_vram_addr_core;
wire isp_vram_rd_core;
wire isp_vram_wr_core;
wire [63:0] isp_vram_din_core;
wire isp_vram_wait_core;
wire isp_vram_valid_core;
wire isp_vram_req_ack_core;
wire [31:0] isp_vram_dout_core;

wire codebook_wait;

wire tex_cache_hit;
wire [23:0] tex_vram_addr_core;
wire tex_vram_wait_core;
wire tex_vram_rd_core;
wire tex_vram_valid_core;
wire [63:0] tex_vram_din_core;
wire tex_vram_req_ack_core;
wire tile_accum_done_core;
wire fb_wait;
wire fb_pending;
wire pvr_trig_pvr_update_unused;
reg [31:0] pvr_test_select_mirror;

always @(posedge clk or posedge rst) begin
	if (rst) begin
		pvr_test_select_mirror <= 32'd0;
	end
	else if (pvr_reg_cs && pvr_wr && dm_req_addr[15:0] == 16'h0018) begin
		pvr_test_select_mirror <= dm_req_wdata;
	end
end

pvr pvr (
	.clock( clk ),					// input  clock
	.reset_n( !rst ),				// input  reset_n
	
	.ra_trig( 1'b1 ),
	.bg_poly_en( 1'b1 ),
	.trig_pvr_update( pvr_trig_pvr_update_unused ),
	.pvr_reg_update( 1'b0 ),

	.pvr_reg_cs( pvr_reg_cs ),		// input  pvr_reg_cs
	.ta_fifo_cs( ta_fifo_cs ),		// input  ta_fifo_cs
	.ta_yuv_cs( ta_yuv_cs ),		// input  ta_yuv_cs
	.ta_tex_cs( ta_tex_cs ),		// input  ta_tex_cs
	
	.pvr_addr( dm_req_addr[15:0] ),	// input [15:0]  pvr_addr  BYTE Address!
	.pvr_din( dm_req_wdata ),		// input [31:0]  pvr_din
	.pvr_rd( pvr_rd ),				// input  pvr_rd
	.pvr_wr( pvr_wr ),				// input  pvr_wr
	.pvr_dout( pvr_dout ),			// output [31:0]  pvr_dout

	.TEST_SELECT( pvr_test_select_mirror ),

	// RA / ISP VRAM reads (separate busses)...
	.ra_vram_wait( ra_vram_wait_core ),			// input  ra_vram_wait
	.ra_vram_valid( ra_vram_valid_core ),		// input  ra_vram_valid
	.ra_vram_req_ack( ra_vram_req_ack_core ),	// input  ra_vram_req_ack
	.ra_vram_rd( ra_vram_rd_core ),				// output ra_vram_rd
	.ra_vram_wr( ra_vram_wr_core ),				// output ra_vram_wr
	.ra_vram_addr( ra_vram_addr_core ),			// output [23:0] ra_vram_addr
	.ra_vram_din64( ra_vram_din_core ),			// input  [63:0] ra_vram_din64
	.ra_vram_dout( ra_vram_dout_core ),			// output [31:0] ra_vram_dout

	.isp_vram_wait( isp_vram_wait_core ),		// input  isp_vram_wait
	.isp_vram_valid( isp_vram_valid_core ),		// input  isp_vram_valid
	.isp_vram_req_ack( isp_vram_req_ack_core ),	// input  isp_vram_req_ack
	.isp_vram_rd( isp_vram_rd_core ),			// output isp_vram_rd
	.isp_vram_wr( isp_vram_wr_core ),			// output isp_vram_wr
	.isp_vram_addr( isp_vram_addr_core ),		// output [23:0] isp_vram_addr
	.isp_vram_din64( isp_vram_din_core ),		// input  [63:0] isp_vram_din64
	.isp_vram_dout( isp_vram_dout_core ),		// output [31:0] isp_vram_dout

	// Texture VRAM reads...
	.codebook_wait( codebook_wait ),				// output  codebook_wait

	.tex_cache_hit( tex_cache_hit ),				// input  tex_cache_hit
	.tex_vram_addr( tex_vram_addr_core ),			// output [23:0] tex_vram_addr
	.tex_vram_wait( tex_vram_wait_core ),			// input  input tex_vram_wait
	.tex_vram_rd( tex_vram_rd_core ),				// output  tex_vram_rd
	.tex_vram_valid( tex_vram_valid_core ),			// input   tex_vram_valid
	.tex_vram_din( tex_vram_din_core ),				// full 64-bit input [63:0]
	.tex_vram_req_ack( tex_vram_req_ack_core ),

	.sim_ui( sim_ui ),				// input [9:0]  sim_ui
	.sim_vi( sim_vi ),				// input [9:0]  sim_vi
	
	.fb_addr( fb_addr ),			// output [22:0]  fb_addr
	.fb_writedata( fb_writedata ),	// output [63:0]  fb_writedata
	.fb_byteena( fb_byteena ),		// output [7:0]  fb_byteena
	.fb_we( fb_we ),				// output  fb_we
	.fb_wait( fb_wait ),			// input  fb_wait
	.fb_pending( fb_pending ),		// output fb_pending
	.tile_accum_done( tile_accum_done_core ),
	
	.debug_ena_texel_reads( 1'b1 )	// input  debug_ena_texel_reads
);

wire ioctl_download = 1'b0;
wire [28:0] DDRAM_BASE = (32'h32000000 >> 3);	// 800MB. 64-bit WORD address.
wire [28:0] dl_word_addr = DDRAM_BASE;

wire [28:0] geo_ddram_addr_raw;
wire        geo_ddram_rd;
wire [63:0] geo_ddram_din;
wire [7:0]  geo_ddram_be;
wire        geo_ddram_we;
wire [7:0]  geo_ddram_burstcnt;

wire ra_vram_wr_selected = ra_vram_wr_core && !fb_pending;
wire [20:0] fb_wr_word_addr = fb_w_sof1_mirror[22:2] + {1'b0, fb_addr[19:0]};
wire [28:0] fb_wr_addr_side = {9'd0, fb_wr_word_addr[19:0]};
wire [7:0]  fb_wr_be_side = fb_wr_word_addr[20] ? {fb_byteena[3:0], 4'b0000} : {4'b0000, fb_byteena[3:0]};
wire [28:0] geo_wr_addr = ra_vram_wr_selected ? {9'd0, ra_vram_addr_core[21:2]} :
                                               fb_wr_addr_side;
wire [63:0] geo_wr_dout = ra_vram_wr_selected ? {ra_vram_dout_core, ra_vram_dout_core} : fb_writedata;
wire [7:0]  geo_wr_be   = ra_vram_wr_selected ? (ra_vram_addr_core[22] ? 8'b11110000 : 8'b00001111) :
                                               fb_wr_be_side;
// Use single-word writes for bring-up; this avoids relying on DDR burst-write data phasing.
wire [7:0]  geo_wr_burstcnt = 8'd1;
wire        geo_wr_pending = fb_pending || ra_vram_wr_core;
wire        geo_wr_we = ra_vram_wr_selected ? ra_vram_wr_core : fb_we;
wire        geo_wr_wait;
assign fb_wait = geo_wr_wait | ra_vram_wr_selected;
assign ra_vram_wr_wait_core = geo_wr_wait | fb_pending;
assign ra_vram_wait_core = ra_vram_wr_core ? ra_vram_wr_wait_core : ra_vram_rd_wait_core;

vram_read_arbiter_2c vram_read_arbiter_geo (
	.clock( clk ),
	.reset_n( !rst ),

	.a_rd( ra_vram_rd_core ),
	.a_addr( ra_vram_addr_core[21:0] ),
	.a_din( ra_vram_din_core ),
	.a_wait( ra_vram_rd_wait_core ),
	.a_valid( ra_vram_valid_core ),
	.a_req_ack( ra_vram_req_ack_core ),

	.b_rd( isp_vram_rd_core ),
	.b_addr( isp_vram_addr_core[21:0] ),
	.b_din( isp_vram_din_core ),
	.b_wait( isp_vram_wait_core ),
	.b_valid( isp_vram_valid_core ),
	.b_req_ack( isp_vram_req_ack_core ),

	.c_pending( geo_wr_pending ),
	.c_wr( geo_wr_we ),
	.c_addr( geo_wr_addr ),
	.c_dout( geo_wr_dout ),
	.c_be( geo_wr_be ),
	.c_burstcnt( geo_wr_burstcnt ),
	.c_wait( geo_wr_wait ),

	.DDRAM_ADDR( geo_ddram_addr_raw ),
	.DDRAM_RD( geo_ddram_rd ),
	.DDRAM_DIN( geo_ddram_din ),
	.DDRAM_BE( geo_ddram_be ),
	.DDRAM_WE( geo_ddram_we ),
	.DDRAM_BURSTCNT( geo_ddram_burstcnt ),
	.DDRAM_DOUT( DDRAM_DOUT ),
	.DDRAM_DOUT_READY( DDRAM_DOUT_READY ),
	.DDRAM_BUSY( DDRAM_BUSY ),
	.DDRAM_PAUSE( 1'b0 )
);

assign DDRAM_CLK      = clk;
assign DDRAM_BURSTCNT = ioctl_download ? 8'd1 : geo_ddram_burstcnt;
assign DDRAM_ADDR     = ioctl_download ? dl_word_addr : (DDRAM_BASE + geo_ddram_addr_raw);
assign DDRAM_RD       = ioctl_download ? 1'b0 : geo_ddram_rd;
assign DDRAM_DIN      = ioctl_download ? 64'd0 : geo_ddram_din;
assign DDRAM_BE       = ioctl_download ? 8'hff : geo_ddram_be;
assign DDRAM_WE       = ioctl_download ? 1'b0 : geo_ddram_we;


wire [28:0] tex_ddram_addr_raw;

`ifndef VERILATOR
localparam TEX_NEXT_LINE_PREFETCH = 1'b0;
localparam TEX_HIT_UNDER_MISS     = 1'b0;
localparam TEX_CACHE_ENABLE       = 1'b0;
`else
localparam TEX_NEXT_LINE_PREFETCH = 1'b1;
localparam TEX_HIT_UNDER_MISS     = 1'b1;
localparam TEX_CACHE_ENABLE       = 1'b1;
`endif

`ifdef VERILATOR
vram_read_cache  #(
	.TEX_COMBO_HIT(0),
	.CACHE_LINES(2),
	.CRITICAL_WORD_FIRST(1),
	.NEXT_LINE_PREFETCH(TEX_NEXT_LINE_PREFETCH),
	.HIT_UNDER_MISS(TEX_HIT_UNDER_MISS)
) vram_read_cache_tex (
	.clock( clk ),
	.reset_n( !rst ),

	// =========================
	// TSP-side VRAM read port
	// =========================
	.vram_addr( tex_vram_addr_core[21:0] ),	// input [21:0] vram_addr (from core). VRAM BYTE address. Ignore bit 22!
	.vram_rd( tex_vram_rd_core ),			// input  vram_rd (from core).
	.vram_din( tex_vram_din_core ),			// output [63:0] vram_din (TO core).
	.vram_wait( tex_vram_wait_core ),		// output  vram_wait (TO core).
	.vram_valid( tex_vram_valid_core ),		// output  vram_valid (TO core).
	.vram_req_ack( tex_vram_req_ack_core ),	// output  vram_req_ack (TO core).

	.cache_hit( tex_cache_hit ),			// output tex_cache_hit.

	// =========================
	// MiSTer DDRAM interface
	// =========================
	.DDRAM_ADDR( tex_ddram_addr_raw ),		// output [28:0]. 64-bit WORD address.
	.DDRAM_RD( DDRAM2_RD ),					// output 
	.DDRAM_BURSTCNT( DDRAM2_BURSTCNT ),		// output [7:0]
	.DDRAM_DOUT( DDRAM2_DOUT ),				// input [63:0].
	.DDRAM_DOUT_READY( DDRAM2_DOUT_READY ),	// input 
	.DDRAM_BUSY( DDRAM2_BUSY )				// input 
);
`else
generate
if (TEX_CACHE_ENABLE) begin : g_tex_cache
vram_read_cache  #(
	.TEX_COMBO_HIT(0),
	.CACHE_LINES(2),
	.CRITICAL_WORD_FIRST(1),
	.NEXT_LINE_PREFETCH(TEX_NEXT_LINE_PREFETCH),
	.HIT_UNDER_MISS(TEX_HIT_UNDER_MISS)
) vram_read_cache_tex (
	.clock( clk ),
	.reset_n( !rst ),

	// =========================
	// TSP-side VRAM read port
	// =========================
	.vram_addr( tex_vram_addr_core[21:0] ),	// input [21:0] vram_addr (from core). VRAM BYTE address. Ignore bit 22!
	.vram_rd( tex_vram_rd_core ),			// input  vram_rd (from core).
	.vram_din( tex_vram_din_core ),			// output [63:0] vram_din (TO core).
	.vram_wait( tex_vram_wait_core ),		// output  vram_wait (TO core).
	.vram_valid( tex_vram_valid_core ),		// output  vram_valid (TO core).
	.vram_req_ack( tex_vram_req_ack_core ),	// output  vram_req_ack (TO core).

	.cache_hit( tex_cache_hit ),			// output tex_cache_hit.

	// =========================
	// MiSTer DDRAM interface
	// =========================
	.DDRAM_ADDR( tex_ddram_addr_raw ),		// output [28:0]. 64-bit WORD address.
	.DDRAM_RD( DDRAM2_RD ),					// output 
	.DDRAM_BURSTCNT( DDRAM2_BURSTCNT ),		// output [7:0]
	.DDRAM_DOUT( DDRAM2_DOUT ),				// input [63:0].
	.DDRAM_DOUT_READY( DDRAM2_DOUT_READY ),	// input 
	.DDRAM_BUSY( DDRAM2_BUSY )				// input 
);
end
else begin : g_no_tex_cache
	assign tex_vram_din_core = 64'd0;
	assign tex_vram_wait_core = 1'b0;
	assign tex_vram_valid_core = 1'b0;
	assign tex_vram_req_ack_core = 1'b0;
	assign tex_cache_hit = 1'b0;
	assign tex_ddram_addr_raw = 29'd0;
	assign DDRAM2_RD = 1'b0;
	assign DDRAM2_BURSTCNT = 8'd0;
end
endgenerate
`endif

assign DDRAM2_CLK = clk;
assign DDRAM2_ADDR = DDRAM_BASE + tex_ddram_addr_raw;
assign DDRAM2_DIN = 64'd0;
assign DDRAM2_BE  = 8'b11111111;
assign DDRAM2_WE  = 1'b0;

endmodule
