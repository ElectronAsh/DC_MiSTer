`timescale 1ns / 1ps
`default_nettype none

// Tags are 12-bit in the Z/tag buffer. 512 entries aliases tags 512+ back
// onto earlier params, which shows up as wrong textures/shading on busy tiles.
localparam ENTRIES = 256;

module param_buffer #(
	parameter ENABLE_TEXTURE_PARAMS = 1'b1,
	parameter ENABLE_GOURAUD_PARAMS = 1'b1,
	parameter ENABLE_OFFSET_PARAMS = 1'b1
) (
	input clock,
	input reset_n,
	
	input [11:0] prim_tag,
	
	input pcache_write,
	
	input [31:0] isp_inst_in,
	input [31:0] tsp_inst_in,
	input [31:0] tcw_word_in,

	input signed [31:0] FDDX_BASE_A, FDDY_BASE_A, c_BASE_A,
	input signed [31:0] FDDX_BASE_R, FDDY_BASE_R, c_BASE_R,
	input signed [31:0] FDDX_BASE_G, FDDY_BASE_G, c_BASE_G,
	input signed [31:0] FDDX_BASE_B, FDDY_BASE_B, c_BASE_B,

	input signed [47:0] FDDX_U, FDDY_U, small_c_u,
	input signed [47:0] FDDX_V, FDDY_V, small_c_v,
	
	input signed [31:0] FDDX_OFFS_A, FDDY_OFFS_A, c_OFFS_A,
	input signed [31:0] FDDX_OFFS_R, FDDY_OFFS_R, c_OFFS_R,
	input signed [31:0] FDDX_OFFS_G, FDDY_OFFS_G, c_OFFS_G,
	input signed [31:0] FDDX_OFFS_B, FDDY_OFFS_B, c_OFFS_B,

	output wire [31:0] isp_inst_out,
	output wire [31:0] tsp_inst_out,
	output wire [31:0] tcw_word_out,

	output wire [31:0] FDDX_BASE_A_out, FDDY_BASE_A_out, c_BASE_A_out,
	output wire [31:0] FDDX_BASE_R_out, FDDY_BASE_R_out, c_BASE_R_out,
	output wire [31:0] FDDX_BASE_G_out, FDDY_BASE_G_out, c_BASE_G_out,
	output wire [31:0] FDDX_BASE_B_out, FDDY_BASE_B_out, c_BASE_B_out,

	output wire [47:0] FDDX_U_out, FDDY_U_out, small_c_u_out,
	output wire [47:0] FDDX_V_out, FDDY_V_out, small_c_v_out,
	
	output wire [31:0] FDDX_OFFS_A_out, FDDY_OFFS_A_out, c_OFFS_A_out,
	output wire [31:0] FDDX_OFFS_R_out, FDDY_OFFS_R_out, c_OFFS_R_out,
	output wire [31:0] FDDX_OFFS_G_out, FDDY_OFFS_G_out, c_OFFS_G_out,
	output wire [31:0] FDDX_OFFS_B_out, FDDY_OFFS_B_out, c_OFFS_B_out
);


// ---------------- Instruction words ----------------
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_isp (.addr(prim_tag), .clk(clock), .din(isp_inst_in), .we(pcache_write), .dout(isp_inst_out));
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_tsp (.addr(prim_tag), .clk(clock), .din(tsp_inst_in), .we(pcache_write), .dout(tsp_inst_out));
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_tcw (.addr(prim_tag), .clk(clock), .din(tcw_word_in), .we(pcache_write), .dout(tcw_word_out));

pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_BASE_A (.addr(prim_tag), .clk(clock), .din(c_BASE_A), .we(pcache_write), .dout(c_BASE_A_out));
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_BASE_R (.addr(prim_tag), .clk(clock), .din(c_BASE_R), .we(pcache_write), .dout(c_BASE_R_out));
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_BASE_G (.addr(prim_tag), .clk(clock), .din(c_BASE_G), .we(pcache_write), .dout(c_BASE_G_out));
pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_BASE_B (.addr(prim_tag), .clk(clock), .din(c_BASE_B), .we(pcache_write), .dout(c_BASE_B_out));

generate
	if (ENABLE_GOURAUD_PARAMS) begin : g_gouraud_params
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_BASE_A (.addr(prim_tag), .clk(clock), .din(FDDX_BASE_A), .we(pcache_write), .dout(FDDX_BASE_A_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_BASE_A (.addr(prim_tag), .clk(clock), .din(FDDY_BASE_A), .we(pcache_write), .dout(FDDY_BASE_A_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_BASE_R (.addr(prim_tag), .clk(clock), .din(FDDX_BASE_R), .we(pcache_write), .dout(FDDX_BASE_R_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_BASE_R (.addr(prim_tag), .clk(clock), .din(FDDY_BASE_R), .we(pcache_write), .dout(FDDY_BASE_R_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_BASE_G (.addr(prim_tag), .clk(clock), .din(FDDX_BASE_G), .we(pcache_write), .dout(FDDX_BASE_G_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_BASE_G (.addr(prim_tag), .clk(clock), .din(FDDY_BASE_G), .we(pcache_write), .dout(FDDY_BASE_G_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_BASE_B (.addr(prim_tag), .clk(clock), .din(FDDX_BASE_B), .we(pcache_write), .dout(FDDX_BASE_B_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_BASE_B (.addr(prim_tag), .clk(clock), .din(FDDY_BASE_B), .we(pcache_write), .dout(FDDY_BASE_B_out));
	end
	else begin : g_no_gouraud_params
		assign FDDX_BASE_A_out = 32'd0; assign FDDY_BASE_A_out = 32'd0;
		assign FDDX_BASE_R_out = 32'd0; assign FDDY_BASE_R_out = 32'd0;
		assign FDDX_BASE_G_out = 32'd0; assign FDDY_BASE_G_out = 32'd0;
		assign FDDX_BASE_B_out = 32'd0; assign FDDY_BASE_B_out = 32'd0;
	end

	if (ENABLE_TEXTURE_PARAMS) begin : g_texture_params
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_FDDX_U    (.addr(prim_tag), .clk(clock), .din(FDDX_U),    .we(pcache_write), .dout(FDDX_U_out));
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_FDDY_U    (.addr(prim_tag), .clk(clock), .din(FDDY_U),    .we(pcache_write), .dout(FDDY_U_out));
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_small_c_u (.addr(prim_tag), .clk(clock), .din(small_c_u), .we(pcache_write), .dout(small_c_u_out));
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_FDDX_V    (.addr(prim_tag), .clk(clock), .din(FDDX_V),    .we(pcache_write), .dout(FDDX_V_out));
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_FDDY_V    (.addr(prim_tag), .clk(clock), .din(FDDY_V),    .we(pcache_write), .dout(FDDY_V_out));
		pcache_mem #(.DATA_WIDTH(48), .DEPTH(ENTRIES)) pcache_mem_small_c_v (.addr(prim_tag), .clk(clock), .din(small_c_v), .we(pcache_write), .dout(small_c_v_out));
	end
	else begin : g_no_texture_params
		assign FDDX_U_out = 48'd0; assign FDDY_U_out = 48'd0; assign small_c_u_out = 48'd0;
		assign FDDX_V_out = 48'd0; assign FDDY_V_out = 48'd0; assign small_c_v_out = 48'd0;
	end

	if (ENABLE_OFFSET_PARAMS) begin : g_offset_params
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_OFFS_A (.addr(prim_tag), .clk(clock), .din(FDDX_OFFS_A), .we(pcache_write), .dout(FDDX_OFFS_A_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_OFFS_A (.addr(prim_tag), .clk(clock), .din(FDDY_OFFS_A), .we(pcache_write), .dout(FDDY_OFFS_A_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_OFFS_A    (.addr(prim_tag), .clk(clock), .din(c_OFFS_A),    .we(pcache_write), .dout(c_OFFS_A_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_OFFS_R (.addr(prim_tag), .clk(clock), .din(FDDX_OFFS_R), .we(pcache_write), .dout(FDDX_OFFS_R_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_OFFS_R (.addr(prim_tag), .clk(clock), .din(FDDY_OFFS_R), .we(pcache_write), .dout(FDDY_OFFS_R_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_OFFS_R    (.addr(prim_tag), .clk(clock), .din(c_OFFS_R),    .we(pcache_write), .dout(c_OFFS_R_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_OFFS_G (.addr(prim_tag), .clk(clock), .din(FDDX_OFFS_G), .we(pcache_write), .dout(FDDX_OFFS_G_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_OFFS_G (.addr(prim_tag), .clk(clock), .din(FDDY_OFFS_G), .we(pcache_write), .dout(FDDY_OFFS_G_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_OFFS_G    (.addr(prim_tag), .clk(clock), .din(c_OFFS_G),    .we(pcache_write), .dout(c_OFFS_G_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDX_OFFS_B (.addr(prim_tag), .clk(clock), .din(FDDX_OFFS_B), .we(pcache_write), .dout(FDDX_OFFS_B_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_FDDY_OFFS_B (.addr(prim_tag), .clk(clock), .din(FDDY_OFFS_B), .we(pcache_write), .dout(FDDY_OFFS_B_out));
		pcache_mem #(.DATA_WIDTH(32), .DEPTH(ENTRIES)) pcache_mem_c_OFFS_B    (.addr(prim_tag), .clk(clock), .din(c_OFFS_B),    .we(pcache_write), .dout(c_OFFS_B_out));
	end
	else begin : g_no_offset_params
		assign FDDX_OFFS_A_out = 32'd0; assign FDDY_OFFS_A_out = 32'd0; assign c_OFFS_A_out = 32'd0;
		assign FDDX_OFFS_R_out = 32'd0; assign FDDY_OFFS_R_out = 32'd0; assign c_OFFS_R_out = 32'd0;
		assign FDDX_OFFS_G_out = 32'd0; assign FDDY_OFFS_G_out = 32'd0; assign c_OFFS_G_out = 32'd0;
		assign FDDX_OFFS_B_out = 32'd0; assign FDDY_OFFS_B_out = 32'd0; assign c_OFFS_B_out = 32'd0;
	end
endgenerate


endmodule
