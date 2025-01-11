`timescale 1ns / 1ps
`default_nettype none

localparam ENTRIES = 1024;

module param_buffer (
	input clock,
	input reset_n,
	
	input [11:0] prim_tag,
	
	input pcache_write,
	
	input [31:0] isp_inst_in,
	input [31:0] tsp_inst_in,
	input [31:0] tcw_word_in,

	input [31:0] vert_a_x_in,
	input [31:0] vert_a_y_in,
	input [31:0] vert_a_z_in,
	input [31:0] vert_a_u0_in,
	input [31:0] vert_a_v0_in,
	input [31:0] vert_a_base_col_0_in,
	input [31:0] vert_a_off_col_in,

	input [31:0] vert_b_x_in,
	input [31:0] vert_b_y_in,
	input [31:0] vert_b_z_in,
	input [31:0] vert_b_u0_in,
	input [31:0] vert_b_v0_in,
	input [31:0] vert_b_base_col_0_in,
	input [31:0] vert_b_off_col_in,

	input [31:0] vert_c_x_in,
	input [31:0] vert_c_y_in,
	input [31:0] vert_c_z_in,
	input [31:0] vert_c_u0_in,
	input [31:0] vert_c_v0_in,
	input [31:0] vert_c_base_col_0_in,
	input [31:0] vert_c_off_col_in,
	
	output reg [31:0] isp_inst_out,
	output reg [31:0] tsp_inst_out,
	output reg [31:0] tcw_word_out,

	output reg [31:0] vert_a_x_out,
	output reg [31:0] vert_a_y_out,
	output reg [31:0] vert_a_z_out,
	output reg [31:0] vert_a_u0_out,
	output reg [31:0] vert_a_v0_out,
	output reg [31:0] vert_a_base_col_0_out,
	output reg [31:0] vert_a_off_col_out,

	output reg [31:0] vert_b_x_out,
	output reg [31:0] vert_b_y_out,
	output reg [31:0] vert_b_z_out,
	output reg [31:0] vert_b_u0_out,
	output reg [31:0] vert_b_v0_out,
	output reg [31:0] vert_b_base_col_0_out,
	output reg [31:0] vert_b_off_col_out,

	output reg [31:0] vert_c_x_out,
	output reg [31:0] vert_c_y_out,
	output reg [31:0] vert_c_z_out,
	output reg [31:0] vert_c_u0_out,
	output reg [31:0] vert_c_v0_out,
	output reg [31:0] vert_c_base_col_0_out,
	output reg [31:0] vert_c_off_col_out	
);

// Quartus version, using BRAMs...
`ifndef VERILATOR
pcache_mem	pcache_mem_isp               (prim_tag, clock, isp_inst_in,          pcache_write, isp_inst_out);
pcache_mem	pcache_mem_tsp               (prim_tag, clock, tsp_inst_in,          pcache_write, tsp_inst_out);
pcache_mem	pcache_mem_tcw               (prim_tag, clock, tcw_word_in,          pcache_write, tcw_word_out);

pcache_mem	pcache_mem_vert_a_x          (prim_tag, clock, vert_a_x_in,          pcache_write, vert_a_x_out);
pcache_mem	pcache_mem_vert_a_y          (prim_tag, clock, vert_a_y_in,          pcache_write, vert_a_y_out);
pcache_mem	pcache_mem_vert_a_z          (prim_tag, clock, vert_a_z_in,          pcache_write, vert_a_z_out);
pcache_mem	pcache_mem_vert_a_u0         (prim_tag, clock, vert_a_u0_in,         pcache_write, vert_a_u0_out);
pcache_mem	pcache_mem_vert_a_v0         (prim_tag, clock, vert_a_v0_in,         pcache_write, vert_a_v0_out);
pcache_mem	pcache_mem_vert_a_base_col_0 (prim_tag, clock, vert_a_base_col_0_in, pcache_write, vert_a_base_col_0_out);
pcache_mem	pcache_mem_vert_a_off_col    (prim_tag, clock, vert_a_off_col_in,    pcache_write, vert_a_off_col_out);

pcache_mem	pcache_mem_vert_b_x          (prim_tag, clock, vert_b_x_in,          pcache_write, vert_b_x_out);
pcache_mem	pcache_mem_vert_b_y          (prim_tag, clock, vert_b_y_in,          pcache_write, vert_b_y_out);
pcache_mem	pcache_mem_vert_b_z          (prim_tag, clock, vert_b_z_in,          pcache_write, vert_b_z_out);
pcache_mem	pcache_mem_vert_b_u0         (prim_tag, clock, vert_b_u0_in,         pcache_write, vert_b_u0_out);
pcache_mem	pcache_mem_vert_b_v0         (prim_tag, clock, vert_b_v0_in,         pcache_write, vert_b_v0_out);
pcache_mem	pcache_mem_vert_b_base_col_0 (prim_tag, clock, vert_b_base_col_0_in, pcache_write, vert_b_base_col_0_out);
pcache_mem	pcache_mem_vert_b_off_col    (prim_tag, clock, vert_b_off_col_in,    pcache_write, vert_b_off_col_out);

pcache_mem	pcache_mem_vert_c_x          (prim_tag, clock, vert_c_x_in,          pcache_write, vert_c_x_out);
pcache_mem	pcache_mem_vert_c_y          (prim_tag, clock, vert_c_y_in,          pcache_write, vert_c_y_out);
pcache_mem	pcache_mem_vert_c_z          (prim_tag, clock, vert_c_z_in,          pcache_write, vert_c_z_out);
pcache_mem	pcache_mem_vert_c_u0         (prim_tag, clock, vert_c_u0_in,         pcache_write, vert_c_u0_out);
pcache_mem	pcache_mem_vert_c_v0         (prim_tag, clock, vert_c_v0_in,         pcache_write, vert_c_v0_out);
pcache_mem	pcache_mem_vert_c_base_col_0 (prim_tag, clock, vert_c_base_col_0_in, pcache_write, vert_c_base_col_0_out);
pcache_mem	pcache_mem_vert_c_off_col    (prim_tag, clock, vert_c_off_col_in,    pcache_write, vert_c_off_col_out);
`else
// Sim version, using registers...
reg [31:0] pcache_isp_inst [0:ENTRIES-1];
reg [31:0] pcache_tsp_inst [0:ENTRIES-1];
reg [31:0] pcache_tcw_word [0:ENTRIES-1];

reg [31:0] pcache_vert_a_x [0:ENTRIES-1];
reg [31:0] pcache_vert_a_y [0:ENTRIES-1];
reg [31:0] pcache_vert_a_z [0:ENTRIES-1];
reg [31:0] pcache_vert_a_u0 [0:ENTRIES-1];
reg [31:0] pcache_vert_a_v0 [0:ENTRIES-1];
reg [31:0] pcache_vert_a_base_col_0 [0:ENTRIES-1];
reg [31:0] pcache_vert_a_off_col [0:ENTRIES-1];

reg [31:0] pcache_vert_b_x [0:ENTRIES-1];
reg [31:0] pcache_vert_b_y [0:ENTRIES-1];
reg [31:0] pcache_vert_b_z [0:ENTRIES-1];
reg [31:0] pcache_vert_b_u0 [0:ENTRIES-1];
reg [31:0] pcache_vert_b_v0 [0:ENTRIES-1];
reg [31:0] pcache_vert_b_base_col_0 [0:ENTRIES-1];
reg [31:0] pcache_vert_b_off_col [0:ENTRIES-1];

reg [31:0] pcache_vert_c_x [0:ENTRIES-1];
reg [31:0] pcache_vert_c_y [0:ENTRIES-1];
reg [31:0] pcache_vert_c_z [0:ENTRIES-1];
reg [31:0] pcache_vert_c_u0 [0:ENTRIES-1];
reg [31:0] pcache_vert_c_v0 [0:ENTRIES-1];
reg [31:0] pcache_vert_c_base_col_0 [0:ENTRIES-1];
reg [31:0] pcache_vert_c_off_col [0:ENTRIES-1];

always @(posedge clock) begin
	if (pcache_write) begin
		pcache_isp_inst[prim_tag]				<= isp_inst_in;
		pcache_tsp_inst[prim_tag]				<= tsp_inst_in;
		pcache_tcw_word[prim_tag]				<= tcw_word_in;
	
		pcache_vert_a_x[prim_tag]				<= vert_a_x_in;
		pcache_vert_a_y[prim_tag]				<= vert_a_y_in;
		pcache_vert_a_z[prim_tag]				<= vert_a_z_in;
		pcache_vert_a_u0[prim_tag]				<= vert_a_u0_in;
		pcache_vert_a_v0[prim_tag]				<= vert_a_v0_in;
		pcache_vert_a_base_col_0[prim_tag]	<= vert_a_base_col_0_in;
		pcache_vert_a_off_col[prim_tag]		<= vert_a_off_col_in;
		
		pcache_vert_b_x[prim_tag]				<= vert_b_x_in;
		pcache_vert_b_y[prim_tag]				<= vert_b_y_in;
		pcache_vert_b_z[prim_tag]				<= vert_b_z_in;
		pcache_vert_b_u0[prim_tag]				<= vert_b_u0_in;
		pcache_vert_b_v0[prim_tag]				<= vert_b_v0_in;
		pcache_vert_b_base_col_0[prim_tag]	<= vert_b_base_col_0_in;
		pcache_vert_b_off_col[prim_tag]		<= vert_b_off_col_in;

		pcache_vert_c_x[prim_tag] 				<= vert_c_x_in;
		pcache_vert_c_y[prim_tag] 				<= vert_c_y_in;
		pcache_vert_c_z[prim_tag] 				<= vert_c_z_in;
		pcache_vert_c_u0[prim_tag] 			<= vert_c_u0_in;
		pcache_vert_c_v0[prim_tag] 			<= vert_c_v0_in;
		pcache_vert_c_base_col_0[prim_tag]	<= vert_c_base_col_0_in;
		pcache_vert_c_off_col[prim_tag] 		<= vert_c_off_col_in;
	end

	/*
	isp_inst_out			<= pcache_isp_inst[prim_tag];
	tsp_inst_out			<= pcache_tsp_inst[prim_tag];
	tcw_word_out			<= pcache_tcw_word[prim_tag];

	vert_a_x_out			<= pcache_vert_a_x[prim_tag];
	vert_a_y_out			<= pcache_vert_a_y[prim_tag];
	vert_a_z_out			<= pcache_vert_a_z[prim_tag];
	vert_a_u0_out			<= pcache_vert_a_u0[prim_tag];
	vert_a_v0_out			<= pcache_vert_a_v0[prim_tag];
	vert_a_base_col_0_out	<= pcache_vert_a_base_col_0[prim_tag];
	vert_a_off_col_out		<= pcache_vert_a_off_col[prim_tag];
	
	vert_b_x_out			<= pcache_vert_b_x[prim_tag];
	vert_b_y_out			<= pcache_vert_b_y[prim_tag];
	vert_b_z_out			<= pcache_vert_b_z[prim_tag];
	vert_b_u0_out			<= pcache_vert_b_u0[prim_tag];
	vert_b_v0_out			<= pcache_vert_b_v0[prim_tag];
	vert_b_base_col_0_out	<= pcache_vert_b_base_col_0[prim_tag];
	vert_b_off_col_out		<= pcache_vert_b_off_col[prim_tag];
	
	vert_c_x_out			<= pcache_vert_c_x[prim_tag];
	vert_c_y_out			<= pcache_vert_c_y[prim_tag];
	vert_c_z_out			<= pcache_vert_c_z[prim_tag];
	vert_c_u0_out			<= pcache_vert_c_u0[prim_tag];
	vert_c_v0_out			<= pcache_vert_c_v0[prim_tag];
	vert_c_base_col_0_out	<= pcache_vert_c_base_col_0[prim_tag];
	vert_c_off_col_out		<= pcache_vert_c_off_col[prim_tag];
	*/
end

assign isp_inst_out				= pcache_isp_inst[prim_tag];
assign tsp_inst_out				= pcache_tsp_inst[prim_tag];
assign tcw_word_out				= pcache_tcw_word[prim_tag];

assign vert_a_x_out				= pcache_vert_a_x[prim_tag];
assign vert_a_y_out				= pcache_vert_a_y[prim_tag];
assign vert_a_z_out				= pcache_vert_a_z[prim_tag];
assign vert_a_u0_out				= pcache_vert_a_u0[prim_tag];
assign vert_a_v0_out				= pcache_vert_a_v0[prim_tag];
assign vert_a_base_col_0_out	= pcache_vert_a_base_col_0[prim_tag];
assign vert_a_off_col_out		= pcache_vert_a_off_col[prim_tag];

assign vert_b_x_out				= pcache_vert_b_x[prim_tag];
assign vert_b_y_out				= pcache_vert_b_y[prim_tag];
assign vert_b_z_out				= pcache_vert_b_z[prim_tag];
assign vert_b_u0_out				= pcache_vert_b_u0[prim_tag];
assign vert_b_v0_out				= pcache_vert_b_v0[prim_tag];
assign vert_b_base_col_0_out	= pcache_vert_b_base_col_0[prim_tag];
assign vert_b_off_col_out		= pcache_vert_b_off_col[prim_tag];

assign vert_c_x_out				= pcache_vert_c_x[prim_tag];
assign vert_c_y_out				= pcache_vert_c_y[prim_tag];
assign vert_c_z_out				= pcache_vert_c_z[prim_tag];
assign vert_c_u0_out				= pcache_vert_c_u0[prim_tag];
assign vert_c_v0_out				= pcache_vert_c_v0[prim_tag];
assign vert_c_base_col_0_out	= pcache_vert_c_base_col_0[prim_tag];
assign vert_c_off_col_out		= pcache_vert_c_off_col[prim_tag];
`endif


endmodule
