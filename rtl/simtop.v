`timescale 1ns / 1ps
`include "defines.v"
`default_nettype none

//
// VerilogDC
// Copyright 2023 Wenting Zhang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

module simtop (
    input clk,
    input rst,
	
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
	
	/*
	input ddram_waitrequest,
	output [21:0] ddram_addr,
	output ddram_read_burst,
	input [31:0] ddram_readdata,
	input ddram_readdata_valid
	*/
);

// Reset synchronizer
reg rst_reg;
always @(posedge clk) begin
	rst_reg <= rst;
end


/* verilator lint_off PINCONNECTEMPTY */
/*
core core (
	.clk(clk),
	.rst(rst_reg),
	
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
wire bios_cs     = im_req_addr>=21'h000000 && im_req_addr<=21'h1fffff;

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

pvr pvr (
	.clock( clk ),			// input  clock
	.reset_n( !rst_reg ),	// input  reset_n
	
	.pvr_reg_cs( pvr_reg_cs ),	// input  pvr_reg_cs
	.ta_fifo_cs( ta_fifo_cs ),	// input  ta_fifo_cs
	.ta_yuv_cs( ta_yuv_cs ),	// input  ta_yuv_cs
	.ta_tex_cs( ta_tex_cs ),	// input  ta_tex_cs
	
	.pvr_addr( dm_req_addr[15:0] ),	// input [15:0]  pvr_addr  BYTE Address!
	.pvr_din( dm_req_wdata ),		// input [31:0]  pvr_din
	.pvr_rd( pvr_rd ),			// input  pvr_rd
	.pvr_wr( pvr_wr ),			// input  pvr_wr
	.pvr_dout( pvr_dout ),		// output [31:0]  pvr_dout

	.vram_wait( vram_wait ),	// input  vram_wait
	.vram_rd( vram_rd ),		// output  vram_rd
	.vram_wr( vram_wr ),		// output  vram_wr
	.vram_addr( vram_addr ),	// input [23:0]  vram_addr
	.vram_din( vram_din ),		// input [63:0]  vram_din
	.vram_valid( vram_valid ),	// input  vram_valid
	.vram_dout( vram_dout ),	// output [63:0]  vram_dout,
	
	.fb_addr( fb_addr ),			// output [22:0]  fb_addr
	.fb_writedata( fb_writedata ),	// output [31:0]  fb_writedata
	.fb_we( fb_we )					// output  fb_we
);


endmodule
