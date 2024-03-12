//============================================================================
//  FPGAGen port to MiSTer
//  Copyright (c) 2017-2019 Sorgelig
//
//  YM2612 implementation by Jose Tejada Gomez. Twitter: @topapate
//  Original Genesis code: Copyright (c) 2010-2013 Gregory Estrade (greg@torlus.com) 
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

//`define SH4_HAT

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,
`endif

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif

/*
`ifdef SH4_HAT
	output        SH4_RESET_N,
	output        SH4_CLK33M,

	// Main bus stuff...
	input         SH4_CKIO2,
	inout [63:0]  SH4_AD,
	input         SH4_FRAME2_N,
	input         SH4_RD_WRN,
	input         SH4_RD_WR2N,
	output reg	  SH4_RDY_N,		// Insert a Wait State if HIGH.
	
	// Memory area Chip Selects...
	input         SH4_CS0_N, SH4_CS1_N,  SH4_CS2_N,  SH4_CS3_N,  SH4_CS4_N,  SH4_CS5_N,
	
	// DMAC DDT (on-Demand Data Transfer)...
	output        SH4_DBREQ_N,		// Data Bus Request to SH4.
	output        SH4_TR_N,			// Transfer Request to SH4.
	input         SH4_TDACK_N,		// Reply strobe from SH4 DMAC.
	input         SH4_BAVL_N,		// Data Bus Release notification from SH4.
	
	//Notification of channel number to external device at same time as TDACK output...
	input         SH4_ID1,			// DRAK1.
	input         SH4_IO0,			// DACK1.
	
	// IRQ Levels, and NMI...
	output        SH4_IRL3_N, SH4_IRL2_N, SH4_IRL1_N, SH4_IRL0_N,
	output        SH4_NMI_N,
*/
	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
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
	
	// This still gets routed to Ascal, for HDMI output...
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    	// = ~(VBlank | HBlank)

	output        VGA_SCALER, 	// Force VGA scaler
	output        VGA_DISABLE, // analog out is off
//`else

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
//`endif

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	output        VGA_F1,
	output [1:0]  VGA_SL,

	input         SD_CD,
	
	//ADC
	inout   [3:0] ADC_BUS,

	input         OSD_STATUS
);

/*
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign BUTTONS   = osd_btn;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = rom_download;

assign AUDIO_S = 1;
assign AUDIO_MIX = 0;
*/

assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;

assign ADC_BUS  = 'Z;

assign HDMI_FREEZE = 0;

wire [1:0] ar = status[49:48];
wire [7:0] arx = 8'd4;
wire [7:0] ary = 8'd3;

/*
always_comb begin
	case(res) // {V30, H40}
		2'b00: begin // 256 x 224
			arx = 8'd64;
			ary = 8'd49;
		end

		2'b01: begin // 320 x 224
			arx = status[30] ? 8'd10: 8'd64;
			ary = status[30] ? 8'd7 : 8'd49;
		end

		2'b10: begin // 256 x 240
			arx = 8'd128;
			ary = 8'd105;
		end

		2'b11: begin // 320 x 240
			arx = status[30] ? 8'd4 : 8'd128;
			ary = status[30] ? 8'd3 : 8'd105;
		end
	endcase
end
*/

wire       vcrop_en = status[34];
wire [3:0] vcopt    = status[53:50];
reg        en216p;
reg  [4:0] voff;
always @(posedge CLK_VIDEO) begin
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);
	voff <= (vcopt < 6) ? {vcopt,1'b0} : ({vcopt,1'b0} - 5'd24);
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? arx : (ar - 1'd1)),
	.ARY((!ar) ? ary : 12'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(voff),
	.SCALE(status[55:54])
);


// Status Bit Map:
//             Upper                             Lower              
// 0         1         2         3          4         5         6   
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXX XXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXXX

`include "build_id.v"
localparam CONF_STR = {
	"Dreamcast;UART115200:31250:19200:9600;",
	"-;",
	"FC2,BIN,Load PVR Regs;",
	"FC3,BIN,Load VRAM Dump;",
	"-;",
	"P1,Audio & Video;", 
 	"P1O[2],Video Standard,PAL,NTSC;",
	"-;",
	"P1O[5:4],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[10:8],Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%,CRT 75%;",
	"d1P1O[32],Vertical Crop,No,Yes;",
	"P1O[31:30],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	
	"-;",
	"O[3],Swap Joysticks,No,Yes;",
	"-;",
	"T[0],Reset;",
	"J,A,B,X,Y,LS,RS,Start;",
	"V,v",`BUILD_DATE
};


wire [63:0] status;
wire  [1:0] buttons;

wire [11:0] joystick_0,joystick_1,joystick_2,joystick_3,joystick_4;
wire  [7:0] paddle_0,paddle_1,paddle_2,paddle_3;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire  [7:0] ioctl_index;
reg         ioctl_wait = 0;

wire [31:0] sd_lba[2];
wire  [5:0] sd_blk_cnt[2];
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[2];
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;
wire        img_readonly;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(2), .BLKSZ(1), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),

	.paddle_0(paddle_0),
	.paddle_1(paddle_1),
	.paddle_2(paddle_2),
	.paddle_3(paddle_3),

	.status(status),
	//.status_menumask({~status[69], ~status[66], status[58], |status[47:46], status[16], status[13], tap_loaded, 1'b0, |vcrop, status[56]}),
	.buttons(buttons),
	//.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	//.RTC(RTC),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait)
);

//wire rom_download = ioctl_download;


///////////////////////////////////////////////////
/*
	// Main bus stuff...
	input         SH4_CKIO2,
	inout [63:0]  SH4_AD,
	input         SH4_FRAME2_N,
	input         SH4_RD_WRN,
	input         SH4_RD_WR2N,
	input         SH4_RDY_N,
	
	// Memory area Chip Selects...
	input         SH4_CS0_N, SH4_CS1_N,  SH4_CS2_N,  SH4_CS3_N,  SH4_CS4_N,  SH4_CS5_N;
	
	output        SH4_DBREQ_N,		// Data Bus Request to SH4.
	output        SH4_TR_N,			// Transfer Request to SH4.
	input         SH4_TDACK_N,		// Reply strobe from SH4 DMAC.
	input         SH4_BAVL_N,		// Data Bus Release notification from SH4.
	
	//Notification of channel number to external device at same time as TDACK output...
	input         SH4_ID1,			// DRAK1.
	input         SH4_IO0,			// DACK1.
	
	// IRQ Levels, and NMI...
	output        SH4_IRL3_N, SH4_IRL2_N, SH4_IRL1_N, SH4_IRL0_N,
	output        SH4_NMI_N,
*/

/*
assign SH4_RESET_N = !reset;
assign SH4_CLK33M = clk_sys;	// 33.333 MHz to SH4 clock input.

//assign SH4_RDY_N = 1'b0;	// No wait state / allow memory transfer.

assign SH4_DBREQ_N = 1'b1;	// Data Bus Request to the SH4.
assign SH4_TR_N    = 1'b1;	// Transfer Request to the SH4.

assign SH4_IRL3_N = 1'b1;	// SH4 IRQ Level
assign SH4_IRL2_N = 1'b1;
assign SH4_IRL1_N = 1'b1;
assign SH4_IRL0_N = 1'b1;
dr
assign SH4_NMI_N  = 1'b1;	// SH4 NMI.


(*noprune*)reg sh4_oe;

//assign SH4_AD = (sh4_oe) ? {bios_data, bios_data} : 64'hzzzzzzzzzzzzzzzz;
//assign SH4_AD = (sh4_oe) ? sh4_readdata : 64'hzzzzzzzzzzzzzzzz;
assign SH4_AD = (sh4_oe) ? sh4_readdata_d : 64'hzzzzzzzzzzzzzzzz;


reg [63:0] sh4_readdata;

reg SH4_CS0_N_D;
reg SH4_CS1_N_D;
reg SH4_CS2_N_D;
reg SH4_CS3_N_D;
reg SH4_CS4_N_D;
reg SH4_CS5_N_D;
wire cs0_n_rising = !SH4_CS0_N_D && SH4_CS0_N;
wire cs1_n_rising = !SH4_CS1_N_D && SH4_CS1_N;
wire cs2_n_rising = !SH4_CS2_N_D && SH4_CS2_N;
wire cs3_n_rising = !SH4_CS3_N_D && SH4_CS3_N;
wire cs4_n_rising = !SH4_CS4_N_D && SH4_CS4_N;
wire cs5_n_rising = !SH4_CS5_N_D && SH4_CS5_N;

wire any_csn_rising = (cs0_n_rising | cs1_n_rising | cs2_n_rising | cs3_n_rising | cs4_n_rising | cs5_n_rising);

reg SH4_FRAME2_N_D;
wire frame_n_rising  = !SH4_FRAME2_N_D && SH4_FRAME2_N;
wire frame_n_falling = SH4_FRAME2_N_D && !SH4_FRAME2_N;

(*noprune*)reg [31:0] frame_cnt;

(*noprune*)reg [2:0] access_size;

(*noprune*)reg read;
(*noprune*)reg write;
(*noprune*)reg [7:0] burstcnt;
(*noprune*)reg burst;

(*noprune*)reg rdy_n_reg;

(*noprune*)reg [7:0] state;
(*noprune*)reg [63:0] sh4_readdata_d;
(*noprune*)reg [31:0] sh4_addr;
(*noprune*)reg [31:0] sh4_addr_d;


always @(posedge SH4_CKIO2 or posedge reset)
if (reset) begin
	state <= 8'd0;
	sh4_oe <= 1'b0;
	rdy_n_reg <= 1'b1;
	SH4_FRAME2_N_D <= 1'b1;
	SH4_CS0_N_D <= 1'b1;
	SH4_CS1_N_D <= 1'b1;
	SH4_CS2_N_D <= 1'b1;
	SH4_CS3_N_D <= 1'b1;
	SH4_CS4_N_D <= 1'b1;
	SH4_CS5_N_D <= 1'b1;
	frame_cnt <= 32'd0;
	read <= 1'b0;
	write <= 1'b0;
	burst <= 1'b0;
	burstcnt <= 8'd1;
end
else begin
	sh4_readdata_d <= sh4_readdata;
	sh4_addr_d <= sh4_addr;

	SH4_FRAME2_N_D <= SH4_FRAME2_N;
	SH4_CS0_N_D <= SH4_CS0_N;
	SH4_CS1_N_D <= SH4_CS1_N;
	SH4_CS2_N_D <= SH4_CS2_N;
	SH4_CS3_N_D <= SH4_CS3_N;
	SH4_CS4_N_D <= SH4_CS4_N;
	SH4_CS5_N_D <= SH4_CS5_N;

	case (state)
		0: begin
			sh4_oe <= 1'b0;
			rdy_n_reg <= 1'b1;
			if (!SH4_FRAME2_N && !SH4_CS0_N) begin		// As SOON as we see FRAME2_N go Low!...
				frame_cnt <= frame_cnt + 32'd1;
				access_size <= SH4_AD[63:61];
				burst <= SH4_AD[63];
				burstcnt <= (SH4_AD[63]) ? 8'd4 : 8'd1;	// SH4 AD MSB bit denotes this a Burst transfer. (32-BYTE transfer, so four 64-bit words!)
				sh4_addr <= SH4_AD[31:0];			// Latch the Address.
				if (SH4_RD_WR2N) begin
					read <= 1'b1;
					sh4_oe <= 1'b1;	// Bus turnaround.
					state <= 8'd1;		// READ.
				end
				else begin
					write <= 1'b1;
					//rdy_n_reg <= 1'b0;	// We could probably accept the data right away, then write to DDRAM (or regs) later??
					state <= 8'd2;		// WRITE.
				end
			end
		end

		// READ.		
		1: begin
			if (!DDRAM_BUSY) begin
				read <= 1'b0;				// Don't de-assert read unless DDRAM_BUSY is Low!
				if (DDRAM_DOUT_READY) begin
					rdy_n_reg <= 1'b0;
					sh4_readdata <= DDRAM_DOUT;		// Data will be output one clock after RDY_N first goes low, via sh4_readdata_d.
					if (burstcnt>1) begin
						burstcnt <= burstcnt - 8'd1;	// Burst READ.
						sh4_addr <= sh4_addr + 8;		// DDR3 controller doesn't need this for bursts, but it can be helpful for SignalTap.
					end
					else begin
						if (burst) sh4_addr <= sh4_addr + 8;	// For the last word of a burst.
						state <= 8'd3;						// Single READ.
					end
				end
				//if (any_csn_rising) state <= 8'd5;	// Timeout?
			end
		end
		
		// WRITE.
		2: begin
			if (!DDRAM_BUSY) begin
				write <= 1'b0;				// Don't de-assert write unless DDRAM_BUSY is Low!
				rdy_n_reg <= 1'b0;
				if (burstcnt>1) begin
					burstcnt <= burstcnt - 8'd1;		// Burst WRITE.
					sh4_addr <= sh4_addr + 8;			// DDR3 controller doesn't need this for bursts, but it can be helpful for SignalTap.
				end
				else begin
					if (burst) sh4_addr <= sh4_addr + 8;	// For the last word of a burst.
					state <= 8'd3;							// Single WRITE.
				end
			end
			//if (any_csn_rising) state <= 8'd5;	// Timeout?
		end
		
		// Done.
		3: begin
			//rdy_n_reg <= 1'b1;
			state <= 8'd0;
		end
		
		default: ;
	endcase
end

assign SH4_RDY_N = rdy_n_reg;
*/


// First few words of the Dreamcast mpr-21931.ic501 BIOS.
// This is the same BIOS used by default in MAME v0249b, with the command line:   mame dc -debug -window
// BYTESWAPPED! - Every 32-bit word of bytes are pre-swapped here. [7:0], [15:8], [23:16], [31:24] ...
/*
wire [31:0] word0    = 32'h4328E3FF;	// 0x00
wire [31:0] word1    = 32'h43186439;	// 0x04
wire [31:0] word2    = 32'h44094409;	// 0x08
wire [31:0] word3    = 32'h240A5039;	// 0x0c
wire [31:0] word4    = 32'h001A204E;	// 0x10
wire [31:0] word5    = 32'h8B772008;	// 0x14
wire [31:0] word6    = 32'hE1091304;	// 0x18
wire [31:0] word7    = 32'h71294118;	// 0x1c
wire [31:0] word8    = 32'h43211317;	// 0x20
wire [31:0] word9    = 32'h8132E001;	// 0x24
wire [31:0] word10   = 32'h4028E0C3;	// 0x28
wire [31:0] word11   = 32'h4018CBCD;	// 0x2c
wire [31:0] word12   = 32'h4001CBB0;	// 0x30
wire [31:0] word13   = 32'hE5011303;	// 0x34
wire [31:0] word14   = 32'h75604505;	// 0x38
wire [31:0] word15   = 32'h76206653;	// 0x3c
wire [31:0] word16   = 32'h0583C800;	// 0x40
wire [31:0] word17   = 32'h0009462B;	// 0x44
wire [31:0] word18   = 32'h00000000;	// 0x48
wire [31:0] word19   = 32'h00000000;	// 0x4c
wire [31:0] word20   = 32'h00000000;	// 0x50
wire [31:0] word21   = 32'h00000000;	// 0x54
wire [31:0] word22   = 32'h00000000;	// 0x58
wire [31:0] word23   = 32'h00000000;	// 0x5c
wire [31:0] word24   = 32'hA55EA504;	// 0x60
wire [31:0] word25   = 32'hA05F7480;	// 0x64
wire [31:0] word26   = 32'hA3020008;	// 0x68
wire [31:0] word27   = 32'h8C000100;	// 0x6c
wire [31:0] word28   = 32'h01110111;	// 0x70
wire [31:0] word29   = 32'h800A0E24;	// 0x74
wire [31:0] word30   = 32'hC00A0E24;	// 0x78
wire [31:0] word31   = 32'hFF940190;	// 0x7c
wire [31:0] word32   = 32'h13005052;	// 0x80
wire [31:0] word33   = 32'h13025054;	// 0x84
wire [31:0] word34   = 32'h50557310;	// 0x88
wire [31:0] word35   = 32'h52571301;	// 0x8c
wire [31:0] word36   = 32'hE0A42220;	// 0x90
wire [31:0] word37   = 32'h813C4018;	// 0x94
wire [31:0] word38   = 32'h813A8550;	// 0x98
wire [31:0] word39   = 32'h8136700C;	// 0x9c
wire [31:0] word40   = 32'h853CE610;	// 0xa0
wire [31:0] word41   = 32'h8BFC3066;	// 0xa4
wire [31:0] word42   = 32'h813A8551;	// 0xa8
wire [31:0] word43   = 32'h13015056;	// 0xac
wire [31:0] word44   = 32'h51512220;	// 0xb0
wire [31:0] word45   = 32'h6008E004;	// 0xb4
wire [31:0] word46   = 32'h53532101;	// 0xb8
wire [31:0] word47   = 32'h4610C708;	// 0xbc
wire [31:0] word48   = 32'h23156105;	// 0xc0
wire [31:0] word49   = 32'h61328BFB;	// 0xc4
wire [31:0] word50   = 32'h7320432B;	// 0xc8
wire [31:0] word51   = 32'h00000000;	// 0xcc
wire [31:0] word52   = 32'h00000000;	// 0xd0
wire [31:0] word53   = 32'h00000000;	// 0xd4
wire [31:0] word54   = 32'h00000000;	// 0xd8
wire [31:0] word55   = 32'h00000000;	// 0xdc
wire [31:0] word56   = 32'h74E4A05F;	// 0xe0
wire [31:0] word57   = 32'hFFC00007;	// 0xe4
wire [31:0] word58   = 32'hFFFF001F;	// 0xe8
wire [31:0] word59   = 32'h8BFA8915;	// 0xec
wire [31:0] word60   = 32'h73044210;	// 0xf0
wire [31:0] word61   = 32'h61062312;	// 0xf4
wire [31:0] word62   = 32'h2122D204;	// 0xf8
wire [31:0] word63   = 32'hD204D106;	// 0xfc
wire [31:0] word64   = 32'hD09F2F06;	// 0x100
wire [31:0] word65   = 32'h5009A27F;	// 0x104
wire [31:0] word66   = 32'h3400904A;	// 0x108
wire [31:0] word67   = 32'hD1268B03;	// 0x10c
wire [31:0] word68   = 32'h410BD027;	// 0x110
wire [31:0] word69   = 32'h91440009;	// 0x114
wire [31:0] word70   = 32'h2012D022;	// 0x118
wire [31:0] word71   = 32'h0009AFFE;	// 0x11c
wire [31:0] word72   = 32'hD02244FA;	// 0x120
wire [31:0] word73   = 32'hE100400B;	// 0x124
wire [31:0] word74   = 32'hE140C767;	// 0x128
wire [31:0] word75   = 32'h4110222A;	// 0x12c
wire [31:0] word76   = 32'h20268FFD;	// 0x130
wire [31:0] word77   = 32'hD0220102;	// 0x134
wire [31:0] word78   = 32'h410E2109;	// 0x138
wire [31:0] word79   = 32'h401100FA;	// 0x13c
wire [31:0] word80   = 32'hD1208B14;	// 0x140
wire [31:0] word81   = 32'hE3FF41FA;	// 0x144
wire [31:0] word82   = 32'h62334318;	// 0x148
wire [31:0] word83   = 32'h503C4328;	// 0x14c
wire [31:0] word84   = 32'h8B0BC880;	// 0x150
wire [31:0] word85   = 32'h42284209;	// 0x154
wire [31:0] word86   = 32'h4018E0A5;	// 0x158
wire [31:0] word87   = 32'hCB078126;	// 0x15c
wire [31:0] word88   = 32'hE05A8126;	// 0x160
wire [31:0] word89   = 32'h81244018;	// 0x164
wire [31:0] word90   = 32'h2201200A;	// 0x168
wire [31:0] word91   = 32'h0009002B;	// 0x16c
wire [31:0] word92   = 32'hD01461F6;	// 0x170
wire [31:0] word93   = 32'h60F6402B;	// 0x174
wire [31:0] word94   = 32'h7203E107;	// 0x178
wire [31:0] word95   = 32'h8B003212;	// 0x17c
wire [31:0] word96   = 32'hC7036213;	// 0x180
wire [31:0] word97   = 32'h320C4200;	// 0x184
wire [31:0] word98   = 32'h302C6221;	// 0x188
wire [31:0] word99   = 32'h0009402B;	// 0x18c
wire [31:0] word100  = 32'h02780290;	// 0x190
wire [31:0] word101  = 32'h06900138;	// 0x194
wire [31:0] word102  = 32'h07EE0138;	// 0x198
wire [31:0] word103  = 32'hFF860138;	// 0x19c
wire [31:0] word104  = 32'h76110FDF;	// 0x1a0
wire [31:0] word105  = 32'hA05F6890;	// 0x1a4
wire [31:0] word106  = 32'h8C000018;	// 0x1a8
wire [31:0] word107  = 32'h8C00B500;	// 0x1ac
wire [31:0] word108  = 32'hAC004000;	// 0x1b0
wire [31:0] word109  = 32'h002B003B;	// 0x1b4
wire [31:0] word110  = 32'h402B9401;	// 0x1b8
wire [31:0] word111  = 32'h0100E501;	// 0x1bc
wire [31:0] word112  = 32'hDFFFFFFF;	// 0x1c0
wire [31:0] word113  = 32'h8C000010;	// 0x1c4
wire [31:0] word114  = 32'h00000000;	// 0x1c8
wire [31:0] word115  = 32'h00000000;	// 0x1cc
wire [31:0] word116  = 32'h00000000;	// 0x1d0
wire [31:0] word117  = 32'h00000000;	// 0x1d4
wire [31:0] word118  = 32'h00000000;	// 0x1d8
wire [31:0] word119  = 32'h00000000;	// 0x1dc

								// Ditching the TWO lower bits of sh4_addr here, to select each 32-bit word.
wire [31:0] bios_data = (sh4_addr[25:2]==32'd0)   ? word0  :
								(sh4_addr[25:2]==32'd1)   ? word1  :
								(sh4_addr[25:2]==32'd2)   ? word2  :
								(sh4_addr[25:2]==32'd3)   ? word3  :
								(sh4_addr[25:2]==32'd4)   ? word4  :
								(sh4_addr[25:2]==32'd5)   ? word5  :
								(sh4_addr[25:2]==32'd6)   ? word6  :
								(sh4_addr[25:2]==32'd7)   ? word7  :
								(sh4_addr[25:2]==32'd8)   ? word8  :
								(sh4_addr[25:2]==32'd9)   ? word9  :
								(sh4_addr[25:2]==32'd10)  ? word10 :
								(sh4_addr[25:2]==32'd11)  ? word11 :
								(sh4_addr[25:2]==32'd12)  ? word12 :
								(sh4_addr[25:2]==32'd13)  ? word13 :
								(sh4_addr[25:2]==32'd14)  ? word14 :
								(sh4_addr[25:2]==32'd15)  ? word15 :
								(sh4_addr[25:2]==32'd16)  ? word16 :
								(sh4_addr[25:2]==32'd17)  ? word17 :
								(sh4_addr[25:2]==32'd18)  ? word18 :
								(sh4_addr[25:2]==32'd19)  ? word19 :
								(sh4_addr[25:2]==32'd20)  ? word20 :
								(sh4_addr[25:2]==32'd21)  ? word21 :
								(sh4_addr[25:2]==32'd22)  ? word22 :
								(sh4_addr[25:2]==32'd23)  ? word23 :
								(sh4_addr[25:2]==32'd24)  ? word24 :
								(sh4_addr[25:2]==32'd25)  ? word25 :
								(sh4_addr[25:2]==32'd26)  ? word26 :
								(sh4_addr[25:2]==32'd27)  ? word27 :
								(sh4_addr[25:2]==32'd28)  ? word28 :
								(sh4_addr[25:2]==32'd29)  ? word29 :
								(sh4_addr[25:2]==32'd30)  ? word30 :
								(sh4_addr[25:2]==32'd31)  ? word31 :
								(sh4_addr[25:2]==32'd32)  ? word32 :
								(sh4_addr[25:2]==32'd33)  ? word33 :
								(sh4_addr[25:2]==32'd34)  ? word34 :
								(sh4_addr[25:2]==32'd35)  ? word35 :
								(sh4_addr[25:2]==32'd36)  ? word36 :
								(sh4_addr[25:2]==32'd37)  ? word37 :
								(sh4_addr[25:2]==32'd38)  ? word38 :
								(sh4_addr[25:2]==32'd39)  ? word39 :
								(sh4_addr[25:2]==32'd40)  ? word40 :
								(sh4_addr[25:2]==32'd41)  ? word41 :
								(sh4_addr[25:2]==32'd42)  ? word42 :
								(sh4_addr[25:2]==32'd43)  ? word43 :
								(sh4_addr[25:2]==32'd44)  ? word44 :
								(sh4_addr[25:2]==32'd45)  ? word45 :
								(sh4_addr[25:2]==32'd46)  ? word46 :
								(sh4_addr[25:2]==32'd47)  ? word47 :
								(sh4_addr[25:2]==32'd48)  ? word48 :
								(sh4_addr[25:2]==32'd49)  ? word49 :
								(sh4_addr[25:2]==32'd50)  ? word50 :
								(sh4_addr[25:2]==32'd51)  ? word51 :
								(sh4_addr[25:2]==32'd52)  ? word52 :
								(sh4_addr[25:2]==32'd53)  ? word53 :
								(sh4_addr[25:2]==32'd54)  ? word54 :
								(sh4_addr[25:2]==32'd55)  ? word55 :
								(sh4_addr[25:2]==32'd56)  ? word56 :
								(sh4_addr[25:2]==32'd57)  ? word57 :
								(sh4_addr[25:2]==32'd58)  ? word58 :
								(sh4_addr[25:2]==32'd59)  ? word59 :
								(sh4_addr[25:2]==32'd60)  ? word60 :
								(sh4_addr[25:2]==32'd61)  ? word61 :
								(sh4_addr[25:2]==32'd62)  ? word62 :
								(sh4_addr[25:2]==32'd63)  ? word63 :
								(sh4_addr[25:2]==32'd64)  ? word64 :
								(sh4_addr[25:2]==32'd65)  ? word65 :
								(sh4_addr[25:2]==32'd66)  ? word66 :
								(sh4_addr[25:2]==32'd67)  ? word67 :
								(sh4_addr[25:2]==32'd68)  ? word68 :
								(sh4_addr[25:2]==32'd69)  ? word69 :
								(sh4_addr[25:2]==32'd70)  ? word70 :
								(sh4_addr[25:2]==32'd71)  ? word71 :
								(sh4_addr[25:2]==32'd72)  ? word72 :
								(sh4_addr[25:2]==32'd73)  ? word73 :
								(sh4_addr[25:2]==32'd74)  ? word74 :
								(sh4_addr[25:2]==32'd75)  ? word75 :
								(sh4_addr[25:2]==32'd76)  ? word76 :
								(sh4_addr[25:2]==32'd77)  ? word77 :
								(sh4_addr[25:2]==32'd78)  ? word78 :
								(sh4_addr[25:2]==32'd79)  ? word79 :
								(sh4_addr[25:2]==32'd80)  ? word80 :
								(sh4_addr[25:2]==32'd81)  ? word81 :
								(sh4_addr[25:2]==32'd82)  ? word82 :
								(sh4_addr[25:2]==32'd83)  ? word83 :
								(sh4_addr[25:2]==32'd84)  ? word84 :
								(sh4_addr[25:2]==32'd85)  ? word85 :
								(sh4_addr[25:2]==32'd86)  ? word86 :
								(sh4_addr[25:2]==32'd87)  ? word87 :
								(sh4_addr[25:2]==32'd88)  ? word88 :
								(sh4_addr[25:2]==32'd89)  ? word89 :
								(sh4_addr[25:2]==32'd90)  ? word90 :
								(sh4_addr[25:2]==32'd91)  ? word91 :
								(sh4_addr[25:2]==32'd92)  ? word92 :
								(sh4_addr[25:2]==32'd93)  ? word93 :
								(sh4_addr[25:2]==32'd94)  ? word94 :
								(sh4_addr[25:2]==32'd95)  ? word95 :
								(sh4_addr[25:2]==32'd96)  ? word96 :
								(sh4_addr[25:2]==32'd97)  ? word97 :
								(sh4_addr[25:2]==32'd98)  ? word98 :
								(sh4_addr[25:2]==32'd99)  ? word99 :
								(sh4_addr[25:2]==32'd100) ? word100 :
								(sh4_addr[25:2]==32'd101) ? word101 :
								(sh4_addr[25:2]==32'd102) ? word102 :
								(sh4_addr[25:2]==32'd103) ? word103 :
								(sh4_addr[25:2]==32'd104) ? word104 :
								(sh4_addr[25:2]==32'd105) ? word105 :
								(sh4_addr[25:2]==32'd106) ? word106 :
								(sh4_addr[25:2]==32'd107) ? word107 :
								(sh4_addr[25:2]==32'd108) ? word108 :
								(sh4_addr[25:2]==32'd109) ? word109 :
								(sh4_addr[25:2]==32'd110) ? word110 :
								(sh4_addr[25:2]==32'd111) ? word111 :
								(sh4_addr[25:2]==32'd112) ? word112 :
								(sh4_addr[25:2]==32'd113) ? word113 :
								(sh4_addr[25:2]==32'd114) ? word114 :
								(sh4_addr[25:2]==32'd115) ? word115 :
								(sh4_addr[25:2]==32'd116) ? word116 :
								(sh4_addr[25:2]==32'd117) ? word117 :
								(sh4_addr[25:2]==32'd118) ? word118 :
																	 word119;
*/

wire clk_sys;
wire clk_ram;
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	//.reconfig_to_pll(reconfig_to_pll),
	//.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

/*
wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;
	reg pal_r;

	pald <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 == pald && pald2 != pal_r) begin
		state <= 1;
		pal_r <= pald2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 7;
					cfg_data <= pal_r ? 2201376125 : 2537930535;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end
*/

wire reset = /*RESET |*/ status[0] | boot1_loading | vram_dump_loading;


(*keep*)wire boot0_loading = ioctl_index=={2'd0, 6'd0} && ioctl_download;	// PVR regs loaded at core-load.
(*keep*)wire pvr_dump_loading = ioctl_index[5:0]==2 && ioctl_download;		// File index 2 "Load PVR Regs".
(*noprune*)reg [31:00] rom_word32;
reg pvr_wr = 1'b0;

reg [31:0] pvr_ptr [0:80];	// 0x140/4 words. Enough to load up to TA_ALLOC_CTRL.

//always @(posedge SH4_CKIO2) begin
always @(posedge clk_sys) begin
	if (ioctl_download && ioctl_wr) begin
		case (ioctl_addr[1:0])
			0: rom_word32[15:00] <= ioctl_data;
			2: begin rom_word32[31:16] <= ioctl_data; if (boot0_loading |  pvr_dump_loading) pvr_wr <= 1'b1; end
			default: ;
		endcase
	end
	
	if (pvr_wr) begin
		pvr_ptr[ ioctl_addr[24:2] ] <= rom_word32;
		pvr_wr <= 1'b0;
	end
end


(*keep*)wire boot1_loading = ioctl_index=={2'd1, 6'd0} && ioctl_download;	// VRAM dump loaded at core-load.
(*keep*)wire vram_dump_loading = ioctl_index[5:0]==3 && ioctl_download;		// File index 3 "Load VRAM Dump".
(*noprune*)reg [63:00] rom_word64;
reg ddr_wr = 1'b0;

always @(posedge clk_sys) begin
	if (ioctl_download && ioctl_wr) begin
		case (ioctl_addr[2:0])
			0: rom_word64[15:00] <= ioctl_data;
			2: rom_word64[31:16] <= ioctl_data;
			4: rom_word64[47:32] <= ioctl_data;
			6: begin rom_word64[63:48] <= ioctl_data; if (boot1_loading | vram_dump_loading) ddr_wr <= 1'b1; end
			default: ;
		endcase
	end
	
	if (ddr_wr) begin
		if (DDRAM_BUSY) ioctl_wait <= 1'b1;
		else begin
			ioctl_wait <= 1'b0;
			ddr_wr <= 1'b0;
		end
	end
end

/*
//wire [28:0] DDRAM_BASE = 29'h04000000;	// 512MB >> 3.
//wire [28:0] DDRAM_BASE = 29'h06000000;	// 768MB >> 3.
wire [28:0] DDRAM_BASE = 29'h06400000;	// 800MB >> 3.

assign DDRAM_CLK      = SH4_CKIO2;
assign DDRAM_BURSTCNT = ioctl_download ? 8'd1 : burstcnt;
assign DDRAM_ADDR     = ioctl_download ? DDRAM_BASE+ioctl_addr[24:3] : DDRAM_BASE+sh4_addr[24:3];
assign DDRAM_DIN      = ioctl_download ? rom_word64 : SH4_AD;
assign DDRAM_WE       = ioctl_download ? ddram_wr_rising : write 1'b0;
assign DDRAM_BE       = 8'b11111111;
assign DDRAM_RD       = ioctl_download ? 1'b0 : read;
*/

// HOLLY Address Decoding.
// CS0...
/*
(*keep*)wire bios_cs     = sh4_addr[25:0]>=21'h00000000 && sh4_addr[25:0]<=21'h001fffff;
(*keep*)wire flash_cs    = sh4_addr[25:0]>=29'h00200000 && sh4_addr[25:0]<=29'h0021ffff;

(*keep*)wire reg_cs = system_cs | maple_cs | gdrom_cs | g1_reg_cs | g2_reg_cs | pvr_reg_cs |
							 ta_reg_cs | modem_cs | aica_reg_cs | aica_rtc_cs | aica_ram_cs | g2_ext_cs;

(*keep*)wire system_cs   = sh4_addr[25:0]>=29'h005f6800 && sh4_addr[25:0]<=29'h005f69ff;
(*keep*)wire maple_cs    = sh4_addr[25:0]>=29'h005f6c00 && sh4_addr[25:0]<=29'h005f6cff;
(*keep*)wire gdrom_cs    = sh4_addr[25:0]>=29'h005f7000 && sh4_addr[25:0]<=29'h005f70ff;
(*keep*)wire g1_reg_cs   = sh4_addr[25:0]>=29'h005f7400 && sh4_addr[25:0]<=29'h005f74ff;
(*keep*)wire g2_reg_cs   = sh4_addr[25:0]>=29'h005f7800 && sh4_addr[25:0]<=29'h005f78ff;
(*keep*)wire pvr_reg_cs  = sh4_addr[25:0]>=29'h005f7c00 && sh4_addr[25:0]<=29'h005f7cff;
(*keep*)wire ta_reg_cs   = sh4_addr[25:0]>=29'h005f8000 && sh4_addr[25:0]<=29'h005f9fff;
(*keep*)wire modem_cs    = sh4_addr[25:0]>=29'h00600000 && sh4_addr[25:0]<=29'h006007ff;
(*keep*)wire aica_reg_cs = sh4_addr[25:0]>=29'h00700000 && sh4_addr[25:0]<=29'h00707fff;
(*keep*)wire aica_rtc_cs = sh4_addr[25:0]>=29'h00710000 && sh4_addr[25:0]<=29'h00710007;
(*keep*)wire aica_ram_cs = sh4_addr[25:0]>=29'h00800000 && sh4_addr[25:0]<=29'h009fffff;
(*keep*)wire g2_ext_cs   = sh4_addr[25:0]>=29'h01000000 && sh4_addr[25:0]<=29'h01ffffff;

/// CS1...
(*keep*)wire vram_64_cs       = req_addr>=29'h04000000 && req_addr<=29'h047fffff;	// 8MB (64-bit access).
(*keep*)wire vram_32_cs       = req_addr>=29'h05000000 && req_addr<=29'h057fffff;	// 8MB (32-bit access).
(*keep*)wire vram_64_mirr_cs  = req_addr>=29'h06000000 && req_addr<=29'h067fffff;	// 8MB (Mirror. 64-bit access).
(*keep*)wire vram_32_mirr_cs  = req_addr>=29'h07000000 && req_addr<=29'h077fffff;	// 8MB (Mirror. 32-bit access).

// CS3...
(*keep*)wire sdram_cs	 = req_addr>=29'h08000000 && req_addr<=29'h0bffffff;

// CS4...
(*keep*)wire ta_fifo_cs  = req_addr>=29'h10000000 && req_addr<=29'h107fffff;
(*keep*)wire ta_yuv_cs   = req_addr>=29'h10800000 && req_addr<=29'h10ffffff;
(*keep*)wire ta_tex_cs   = req_addr>=29'h11000000 && req_addr<=29'h117fffff;
*/

wire pvr_reg_cs = (boot0_loading | pvr_dump_loading);	// BYTE Address!
wire [15:0] pvr_addr = ioctl_addr;
wire [31:0] pvr_din = rom_word32;
//wire pvr_wr = pvr_wr_rising;
wire pvr_rd = 1'b0;
wire [31:0] pvr_dout;

wire vram_wait = DDRAM_BUSY;
wire [23:0] vram_addr;
wire vram_rd;
wire vram_wr;

wire [63:0] vram_dout;
wire [63:0] vram_din = DDRAM_DOUT;
wire vram_valid = DDRAM_DOUT_READY;

wire [28:0] DDRAM_BASE = 29'h06400000;	// 800MB >> 3. (DDRAM_BASE is the 64-bit WORD address!)

assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = ioctl_download ? 8'd1 : 8'd1;
assign DDRAM_ADDR     = ioctl_download ? DDRAM_BASE+ioctl_addr[24:3] : DDRAM_BASE+vram_addr[23:3];
assign DDRAM_DIN      = ioctl_download ? {ioctl_data, rom_word64[47:00]} : vram_dout;
assign DDRAM_WE       = ioctl_download ? ddr_wr : /*vram_wr*/ 1'b0;
assign DDRAM_BE       = ioctl_download ? 8'b11111111 : 8'b11111111;
assign DDRAM_RD       = ioctl_download ? 1'b0 : vram_rd;

wire [22:0] fb_addr;
wire [31:0] fb_writedata;
wire fb_we;

pvr pvr (
	.clock( clk_sys ),			// input  clock
	.reset_n( !reset ),			// input  reset_n
	
	//.ta_fifo_cs( ta_fifo_cs ),	// input  ta_fifo_cs
	//.ta_yuv_cs( ta_yuv_cs ),		// input  ta_yuv_cs
	//.ta_tex_cs( ta_tex_cs ),		// input  ta_tex_cs
	
	// CPU<->PVR interface...
	.pvr_reg_cs( pvr_reg_cs ),	// input  pvr_reg_cs
	.pvr_addr( pvr_addr ),		// input [15:0]  pvr_addr  BYTE Address!
	.pvr_din( pvr_din ),			// input [31:0]  pvr_din
	.pvr_wr( pvr_wr ),			// input  pvr_wr
	.pvr_rd( pvr_rd ),			// input  pvr_rd
	.pvr_dout( pvr_dout ),		// output [31:0]  pvr_dout
	
	.PARAM_BASE( pvr_ptr[    'h20>>2 ] ),
	.REGION_BASE( pvr_ptr[   'h2c>>2 ] ),
	.FPU_PARAM_CFG( pvr_ptr[ 'h7c>>2 ] ),
	.TEXT_CONTROL( pvr_ptr[  'hE4>>2 ] ),
	.PAL_RAM_CTRL( pvr_ptr[  'h108>>2 ] ),
	.TA_ALLOC_CTRL( pvr_ptr[ 'h140>>2 ] ),
	
	// VRAM (vertex/texture access) interface...
	.vram_wait( vram_wait ),	// input  vram_wait
	.vram_rd( vram_rd ),			// output  vram_rd
	.vram_wr( vram_wr ),			// output  vram_wr
	.vram_addr( vram_addr ),	// input [23:0]  vram_addr
	.vram_din( vram_din ),		// input [63:0]  vram_din
	.vram_valid( vram_valid ),	// input  vram_valid
	.vram_dout( vram_dout ),	// output [63:0]  vram_dout,
	
	// Framebuffer (Display) output...
	.fb_addr( fb_addr ),					// output [22:0]  fb_addr
	.fb_writedata( fb_writedata ),	// output [31:0]  fb_writedata
	.fb_we( fb_we )						// output  fb_we
);

wire [15:0] fb_dout;
wire rd_rdy;
wire we_ack;

sdram_old  sdram_old_inst(
	.SDRAM_CLK( SDRAM_CLK ),
	.SDRAM_CKE( SDRAM_CKE ),
	.SDRAM_A( SDRAM_A ),
	.SDRAM_BA( SDRAM_BA ),
	.SDRAM_DQ( SDRAM_DQ ),
	.SDRAM_nCS( SDRAM_nCS ),
	.SDRAM_nWE( SDRAM_nWE ),
	.SDRAM_nRAS( SDRAM_nRAS ),
	.SDRAM_nCAS( SDRAM_nCAS ),

	.init( !locked ),
	
	.clk( clk_ram ),
	.clkref( clk_sys ),
	
	.raddr( hc + (vc * 640) ),		// 25 bit byte address
	.rd( ce_pix ),					// Display requests read
	.rd_rdy( rd_rdy ),
	.dout( fb_dout ),
	
	.waddr( fb_addr ),
	.din( {fb_writedata[23:19],fb_writedata[15:10], fb_writedata[7:3]} ),	// Use 565 format, for now.
	.we( fb_we ),
	.we_ack( we_ack )
);


wire [2:0] scale = status[3:1];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign CLK_VIDEO = clk_sys;
assign VGA_SL = 1'b0;

wire forced_scandoubler = 1'b0;
reg ce_pix;

reg HBlank;
reg VBlank;
reg HSync;
reg VSync;

reg [9:0] hc;
reg [8:0] vc;

always @(posedge CLK_VIDEO) begin
	ce_pix <= ~ce_pix;

	if (ce_pix) begin
		if (hc==767) begin
			hc <= 0;
			vc <= vc + 1;
		end
		else hc <= hc + 1;
		
		HBlank <= (hc>=640 && hc<767);
		VBlank <= (vc>=480 && vc<511);
		
		HSync <= (hc>=680 &&  hc<680+16);
		VSync <= (vc>=500 &&  vc<500+4);
	end
end

wire [7:0] core_r = (HBlank | VBlank) ? 8'h00 : {fb_dout[15:11], 3'b000};	// 565 format.
wire [7:0] core_g = (HBlank | VBlank) ? 8'h00 : {fb_dout[10:05], 2'b00};
wire [7:0] core_b = (HBlank | VBlank) ? 8'h00 : {fb_dout[04:00], 3'b000};

/*
assign SDRAM_CKE = 1'b1;

wire sdr_busy[4];
wire [15:0] sdr_do[4];
sdram sdram
(
	.init(~locked),
	//.clk( clk_ram ),
	.clk( clk_sys ),

	.SDRAM_CLK( SDRAM_CLK ),
	.SDRAM_A( SDRAM_A ),
	.SDRAM_BA( SDRAM_BA ),
	.SDRAM_DQ( SDRAM_DQ ),
	.SDRAM_nCS( SDRAM_nCS ),
	.SDRAM_nWE( SDRAM_nWE ),
	.SDRAM_nRAS( SDRAM_nRAS ),
	.SDRAM_nCAS( SDRAM_nCAS ),
	
	// Framebuffer write.
	.addr0( fb_addr ),
	.din0( {fb_writedata[23:19],fb_writedata[15:10], fb_writedata[7:3]} ),	// Use 565 format, for now.
	//.dout0( sdr_do[0] ),
	.rd0( 1'b0 ),
	.wr0( fb_we ),
	.busy0( sdr_busy[0] ),
	
	// Framebuffer read.
	.addr1( hc + (vc * 640) ),
	.din1( 16'h0000 ),
	.dout1( fb_dout ),
	.rd1( !fb_we ),
	.wr1( 1'b0 ),
	.busy1( sdr_busy[1] )
);
*/

/*
wire [31:0] ddr_dout;
wire [31:0] ddr_din = (!sh4_addr[2]) ? SH4_AD[63:32] : SH4_AD[31:0];

wire [31:0] rom_data = {rom_upper, ioctl_data};
wire rom_wr = {4{ioctl_addr[1]}};

ddram ddram
(
	.*,

	.clk( ioctl_download ? clk_sys : SH4_CKIO2 ),

	.mem_addr( ioctl_download ? {2'b00,ioctl_addr[24:2]} : sh4_addr[25:2] ),
	.mem_din( ioctl_download ? rom_data : ddr_din ),
	
	.mem_dout( ddr_dout ),
	
	.mem_rd( ioctl_download ? 1'b0   : read ),
	.mem_wr( ioctl_download ? rom_wr : {4{write}} ),
	.mem_chan(0),
	.mem_16b(0),
	.mem_busy( ddr_busy )
);
*/

/*
wire cofi_enable = 1'b0;
assign hblank_c = HBlank;
assign vblank_c = VBlank;
assign hs_c = HSync;
assign vs_c = VSync;

cofi coffee (
	.clk(clk_sys),
	.pix_ce(ce_pix),
	.enable(cofi_enable),

	.hblank(HBlank),
	.vblank(VBlank),
	.hs(HSync),
	.vs(VSync),
	.red(core_r),
	.green(core_g),
	.blue(core_b),

	.hblank_out(hblank_c),
	.vblank_out(vblank_c),
	.hs_out(hs_c),
	.vs_out(vs_c),
	.red_out(red),
	.green_out(green),
	.blue_out(blue)
);
*/

wire [7:0] red = core_r;
wire [7:0] green = core_g;
wire [7:0] blue = core_b;
assign hs_c = HSync;
assign vs_c = VSync;
assign hblank_c = HBlank;
assign vblank_c = VBlank;

wire hs_c, vs_c, hblank_c, vblank_c;

video_mixer #(.LINE_LENGTH(640), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.*,
	.ce_pix( ce_pix ),
	.scandoubler( (scale || forced_scandoubler) ),
	.hq2x( scale==1 ),
	.freeze_sync(),

	.R( red ),
	.G( green ),
	.B( blue ),

	// Positive pulses.
	.HSync( hs_c ),
	.VSync( vs_c ),
	.HBlank( hblank_c ),
	.VBlank( vblank_c ),
	
	.VGA_DE( vga_de )
);


/*
wire [2:0] lg_target;
wire       lg_sensor;
wire       lg_a;
wire       lg_b;
wire       lg_c;
wire       lg_start;

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&gun_mode),

	.JOY_X(gun_mode[0] ? joy0_x : joy1_x),
	.JOY_Y(gun_mode[0] ? joy0_y : joy1_y),
	.JOY(gun_mode[0] ? joystick_0 : joystick_1),

	.RELOAD(gun_type),

	.HDE(~hblank_c),
	.VDE(~vblank_c),
	.CE_PIX(ce_pix),
	.H40( 1'b0 ),

	.BTN_MODE(gun_btn_mode),
	.SIZE(status[44:43]),
	.SENSOR_DELAY(gun_sensor_delay),

	.TARGET(lg_target),
	.SENSOR(lg_sensor),
	.BTN_A(lg_a),
	.BTN_B(lg_b),
	.BTN_C(lg_c),
	.BTN_START(lg_start)
);
*/

/*
/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////
wire downloading = rom_download;
wire bk_change  = CART_SRAM_WR;
wire autosave   = status[13];
wire bk_load    = status[16];
wire bk_save    = status[17];

reg bk_ena = 0;
reg sav_pending = 0;
always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_change = 0;

	old_downloading <= downloading;
	if(~old_downloading & downloading) bk_ena <= 0;

	//Save file always mounted in the end of downloading state.
	if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

	old_change <= bk_change;
	if (~old_change & bk_change) sav_pending <= 1;
	else if (bk_state) sav_pending <= 0;
end

wire bk_save_a  = autosave & OSD_STATUS;
reg  bk_loading = 0;
reg  bk_state   = 0;
//reg  bk_reload  = 0;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_load = 0, old_save = 0, old_save_a = 0, old_ack;
	reg [1:0] state;

	old_downloading <= downloading;

	old_load   <= bk_load;
	old_save   <= bk_save;
	old_save_a <= bk_save_a;
	old_ack    <= sd_ack;

	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

	if (!bk_state) begin
		tmpram_tx_start <= 0;
		state <= 0;
		sd_lba <= 0;
//		bk_reload <= 0;
		bk_loading <= 0;
		if (bk_ena & ((~old_load & bk_load) | (~old_save & bk_save) | (~old_save_a & bk_save_a & sav_pending))) begin
			bk_state <= 1;
			bk_loading <= bk_load;
//			bk_reload <= bk_load;
			sd_rd <=  bk_load;
			sd_wr <= 0;
		end
		if (old_downloading & ~rom_download & bk_ena) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end
	else begin
		if (bk_loading) begin
			case(state)
				0: begin
						sd_rd <= 1;
						state <= 1;
					end
				1: if(old_ack & ~sd_ack) begin
						tmpram_tx_start <= 1;
						state <= 2;
					end
				2: if(tmpram_tx_finish) begin
						tmpram_tx_start <= 0;
						state <= 0;
						sd_lba <= sd_lba + 1'd1;
						if(sd_lba[6:0] == 7'h7F) bk_state <= 0;
					end
			endcase
		end
		else begin
			case(state)
				0: begin
						tmpram_tx_start <= 1;
						state <= 1;
					end
				1: if(tmpram_tx_finish) begin
						tmpram_tx_start <= 0;
						sd_wr <= 1;
						state <= 2;
					end
				2: if(old_ack & ~sd_ack) begin
						state <= 0;
						sd_lba <= sd_lba + 1'd1;
						if(sd_lba[6:0] == 7'h7F) bk_state <= 0;
					end
			endcase
		end
	end
end

wire [15:0] tmpram_dout;
wire [15:0] tmpram_din = {sdr_do[3][7:0],sdr_do[3][15:8]};
wire        tmpram_busy = sdr_busy[3];

wire [15:0] tmpram_sd_buff_q;
dpram_dif #(8,16,8,16) tmpram
(
	.clock(clk_sys),

	.address_a(tmpram_addr),
	.wren_a(~bk_loading & tmpram_busy_d & ~tmpram_busy),
	.data_a(tmpram_din),
	.q_a(tmpram_dout),

	.address_b(sd_buff_addr),
	.wren_b(sd_buff_wr & sd_ack),
	.data_b(sd_buff_dout),
	.q_b(tmpram_sd_buff_q)
);

//reg [10:0] tmpram_lba;
reg  [8:1] tmpram_addr;
reg tmpram_tx_start;
reg tmpram_tx_finish;
reg tmpram_req;
reg tmpram_busy_d;
always @(posedge clk_sys) begin
	reg state;

//	tmpram_lba <= sd_lba[10:0] - 11'h10;
	
	tmpram_busy_d <= tmpram_busy;
	if (~tmpram_busy_d & tmpram_busy) tmpram_req <= 0;

	if (~tmpram_tx_start) {tmpram_addr, state, tmpram_tx_finish} <= '0;
	else if(~tmpram_tx_finish) begin
		if(!state) begin
			tmpram_req <= 1;
			state <= 1;
		end
		else if(tmpram_busy_d & ~tmpram_busy) begin
			state <= 0;
			if(~&tmpram_addr) tmpram_addr <= tmpram_addr + 1'd1;
			else tmpram_tx_finish <= 1;
		end
	end
end

assign sd_buff_din = tmpram_sd_buff_q;


wire [7:0] SERJOYSTICK_IN;
wire [7:0] SERJOYSTICK_OUT;
wire [1:0] SER_OPT;

always @(posedge clk_sys) begin
	if (status[45]) begin
		SERJOYSTICK_IN[0] <= USER_IN[1];//up
		SERJOYSTICK_IN[1] <= USER_IN[0];//down	
		SERJOYSTICK_IN[2] <= USER_IN[5];//left	
		SERJOYSTICK_IN[3] <= USER_IN[3];//right
		SERJOYSTICK_IN[4] <= USER_IN[2];//b TL		
		SERJOYSTICK_IN[5] <= USER_IN[6];//c TR GPIO7			
		SERJOYSTICK_IN[6] <= USER_IN[4];//  TH
		SERJOYSTICK_IN[7] <= 0;
		SER_OPT[0] <= status[4];
		SER_OPT[1] <= ~status[4];
		USER_OUT[1] <= SERJOYSTICK_OUT[0];
		USER_OUT[0] <= SERJOYSTICK_OUT[1];
		USER_OUT[5] <= SERJOYSTICK_OUT[2];
		USER_OUT[3] <= SERJOYSTICK_OUT[3];
		USER_OUT[2] <= SERJOYSTICK_OUT[4];
		USER_OUT[6] <= SERJOYSTICK_OUT[5];
		USER_OUT[4] <= SERJOYSTICK_OUT[6];
	end else begin
		SER_OPT  <= 0;
		USER_OUT <= '1;
	end
end
*/

endmodule
