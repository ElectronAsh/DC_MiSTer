`timescale 1ns / 1ps
`default_nettype none

module z_buff #(
	parameter ENABLE_DEPTH_COMPARE = 1'b1
) (
	input clock,
	input reset_n,
	input debug_bank,
	
	input clear_z,				// clear_z && !ra_cont_zclear_n  New tile started AND ra_cont_zclear_n is asserted (Low).
	input clear_tags_only,
	output reg z_clear_busy,
	
	input z_write_disable,
	input z_force_row_write,
	
	input [4:0] col_sel,		// x_ps[4:0]
	input [4:0] row_sel,		// y_ps[4:0]
	
	input [31:0] inTri,
	input trig_z_row_write,
	
	input [2:0] depth_comp_in,	// Depth compare MODE.
	
	input [11:0] tag_in,	// prim_tag
	
	// IP_Z[] 2D array bus.
	input signed [47:0] z_in_cols [0:31],
	
	output signed [47:0] z_out,		// Single "pixel" Z value read.
	output [11:0] prim_tag_out,		// Single "pixel" prim_tag read.
	output wire [59:0] z_row_out [0:31],
	
	output wire [31:0] depth_allow
);

wire signed [47:0] z_in_col [0:31];

generate
begin : g_array_z_in
	genvar z_idx;
	for (z_idx = 0; z_idx < 32; z_idx = z_idx + 1) begin : g_array_z_in_map
		assign z_in_col[z_idx] = z_in_cols[z_idx];
	end
end
endgenerate

generate
if (ENABLE_DEPTH_COMPARE) begin : g_depth_compare
depth_compare depth_compare_inst0 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_0            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[0] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[0] )	// output depth_allow
);
depth_compare depth_compare_inst1 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_1            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[1] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[1] )	// output depth_allow
);
depth_compare depth_compare_inst2 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_2            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[2] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[2] )	// output depth_allow
);
depth_compare depth_compare_inst3 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_3            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[3] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[3] )	// output depth_allow
);
depth_compare depth_compare_inst4 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_4            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[4] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[4] )	// output depth_allow
);
depth_compare depth_compare_inst5 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_5            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[5] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[5] )	// output depth_allow
);
depth_compare depth_compare_inst6 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_6            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[6] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[6] )	// output depth_allow
);
depth_compare depth_compare_inst7 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_7            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[7] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[7] )	// output depth_allow
);
depth_compare depth_compare_inst8 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_8            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[8] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[8] )	// output depth_allow
);
depth_compare depth_compare_inst9 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_9            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[9] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[9] )	// output depth_allow
);
depth_compare depth_compare_inst10 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_10            ),		// input [47:0]  old_z
	.IP_Z( z_in_col[10] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[10] )		// output depth_allow
);
depth_compare depth_compare_inst11 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_11           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[11] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[11] )		// output depth_allow
);
depth_compare depth_compare_inst12 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_12           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[12] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[12] )		// output depth_allow
);
depth_compare depth_compare_inst13 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_13           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[13] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[13] )		// output depth_allow
);
depth_compare depth_compare_inst14 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_14           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[14] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[14] )	// output depth_allow
);
depth_compare depth_compare_inst15 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_15           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[15] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[15] )		// output depth_allow
);
depth_compare depth_compare_inst16 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_16           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[16] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[16] )		// output depth_allow
);
depth_compare depth_compare_inst17 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_17           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[17] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[17] )		// output depth_allow
);
depth_compare depth_compare_inst18 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_18           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[18] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[18] )		// output depth_allow
);
depth_compare depth_compare_inst19 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_19           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[19] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[19] )		// output depth_allow
);
depth_compare depth_compare_inst20 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_20           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[20] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[20] )		// output depth_allow
);
depth_compare depth_compare_inst21 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_21           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[21] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[21] )		// output depth_allow
);
depth_compare depth_compare_inst22 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_22           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[22] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[22] )		// output depth_allow
);
depth_compare depth_compare_inst23 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_23           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[23] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[23] )		// output depth_allow
);
depth_compare depth_compare_inst24 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_24           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[24] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[24] )		// output depth_allow
);
depth_compare depth_compare_inst25 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_25           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[25] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[25] )		// output depth_allow
);
depth_compare depth_compare_inst26 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_26           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[26] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[26] )		// output depth_allow
);
depth_compare depth_compare_inst27 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_27           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[27] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[27] )		// output depth_allow
);
depth_compare depth_compare_inst28 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_28           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[28] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[28] )		// output depth_allow
);
depth_compare depth_compare_inst29 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_29           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[29] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[29] )		// output depth_allow
);
depth_compare depth_compare_inst30 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_30           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[30] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[30] )		// output depth_allow
);
depth_compare depth_compare_inst31 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_31           ),		// input [47:0]  old_z
	.IP_Z( z_in_col[31] ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[31] )		// output depth_allow
);
end
else begin : g_no_depth_compare
	assign depth_allow = {32{depth_comp_in != 3'd0}};
end
endgenerate

// The registers below make up our 32x32 internal Z buffer.
//
// It's a bit hard to describe how the regs below relate to the mapping of the tile pixels, but here goes...
// 
// z_col[0][0] is the Z value for the top-left tile pixel.
// z_col[0][1] is the Z value for the tile pixel just below the top-left pixel, and so-on.
//
// z_col[1][0] is the top pixel for the next COLUMN along the tile.
//
// Z value for current tile pixel = z_col [x_ps[4:0]] [y_ps[4:0]]. 
//
//reg [40:0] z_col  [0:31] [0:31];

// Pipeline row write so we can read row N while writing row N-1 (dual-port RAMs).
reg [31:0] inTri_d;
reg [4:0]  row_sel_d;
reg        z_write_disable_d;
reg        z_force_row_write_d;
reg        trig_z_row_write_d;

always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		inTri_d <= 32'd0;
		row_sel_d <= 5'd0;
		z_write_disable_d <= 1'b0;
		z_force_row_write_d <= 1'b0;
		trig_z_row_write_d <= 1'b0;
	end
	else begin
		inTri_d <= inTri;
		row_sel_d <= row_sel;
		z_write_disable_d <= z_write_disable;
		z_force_row_write_d <= z_force_row_write;
		trig_z_row_write_d <= trig_z_row_write;
	end
end

// Keep write-enable generation on registered row data. Using the live current
// inTri here creates a long inTri_calc/float_to_fixed -> RAM WE timing path.
wire [31:0] z_write_allow = trig_z_row_write_d ? (inTri_d & (depth_allow | {32{z_force_row_write_d}})) :	// inTri & depth_allow  Bitwise AND.
										 32'h00000000;

reg [4:0] z_clear_row;
reg       z_clear_tags_only_active;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	z_clear_busy <= 1'b0;
	z_clear_row <= 5'd0;
	z_clear_tags_only_active <= 1'b0;
end
else begin
	if (clear_z) begin
		z_clear_row <= 5'd0;
		z_clear_busy <= 1'b1;
		z_clear_tags_only_active <= clear_tags_only;
	end
	if (z_clear_busy) begin
		if (z_clear_row==5'd31) begin
			z_clear_busy <= 1'b0;
			z_clear_tags_only_active <= 1'b0;
		end
		else z_clear_row <= z_clear_row + 5'd1;
	end
end


wire [59:0] z_col_0;
wire [59:0] z_col_1;
wire [59:0] z_col_2;
wire [59:0] z_col_3;
wire [59:0] z_col_4;
wire [59:0] z_col_5;
wire [59:0] z_col_6;
wire [59:0] z_col_7;
wire [59:0] z_col_8;
wire [59:0] z_col_9;
wire [59:0] z_col_10;
wire [59:0] z_col_11;
wire [59:0] z_col_12;
wire [59:0] z_col_13;
wire [59:0] z_col_14;
wire [59:0] z_col_15;
wire [59:0] z_col_16;
wire [59:0] z_col_17;
wire [59:0] z_col_18;
wire [59:0] z_col_19;
wire [59:0] z_col_20;
wire [59:0] z_col_21;
wire [59:0] z_col_22;
wire [59:0] z_col_23;
wire [59:0] z_col_24;
wire [59:0] z_col_25;
wire [59:0] z_col_26;
wire [59:0] z_col_27;
wire [59:0] z_col_28;
wire [59:0] z_col_29;
wire [59:0] z_col_30;
wire [59:0] z_col_31;

wire [59:0] z_prim_out = (col_sel==5'd0)  ? z_col_0  :
						 (col_sel==5'd1)  ? z_col_1  :
						 (col_sel==5'd2)  ? z_col_2  :
						 (col_sel==5'd3)  ? z_col_3  :
						 (col_sel==5'd4)  ? z_col_4  :
						 (col_sel==5'd5)  ? z_col_5  :
						 (col_sel==5'd6)  ? z_col_6  :
						 (col_sel==5'd7)  ? z_col_7  :
						 (col_sel==5'd8)  ? z_col_8  :
						 (col_sel==5'd9)  ? z_col_9  :
						 (col_sel==5'd10) ? z_col_10 :
						 (col_sel==5'd11) ? z_col_11 :
						 (col_sel==5'd12) ? z_col_12 :
						 (col_sel==5'd13) ? z_col_13 :
						 (col_sel==5'd14) ? z_col_14 :
						 (col_sel==5'd15) ? z_col_15 :
						 (col_sel==5'd16) ? z_col_16 :
						 (col_sel==5'd17) ? z_col_17 :
						 (col_sel==5'd18) ? z_col_18 :
						 (col_sel==5'd19) ? z_col_19 :
						 (col_sel==5'd20) ? z_col_20 :
						 (col_sel==5'd21) ? z_col_21 :
						 (col_sel==5'd22) ? z_col_22 :
						 (col_sel==5'd23) ? z_col_23 :
						 (col_sel==5'd24) ? z_col_24 :
						 (col_sel==5'd25) ? z_col_25 :
						 (col_sel==5'd26) ? z_col_26 :
						 (col_sel==5'd27) ? z_col_27 :
						 (col_sel==5'd28) ? z_col_28 :
						 (col_sel==5'd29) ? z_col_29 :
						 (col_sel==5'd30) ? z_col_30 :
											z_col_31;

assign prim_tag_out = z_prim_out[59:48];
assign z_out        = z_prim_out[47:0];

assign z_row_out[0]  = z_col_0;
assign z_row_out[1]  = z_col_1;
assign z_row_out[2]  = z_col_2;
assign z_row_out[3]  = z_col_3;
assign z_row_out[4]  = z_col_4;
assign z_row_out[5]  = z_col_5;
assign z_row_out[6]  = z_col_6;
assign z_row_out[7]  = z_col_7;
assign z_row_out[8]  = z_col_8;
assign z_row_out[9]  = z_col_9;
assign z_row_out[10] = z_col_10;
assign z_row_out[11] = z_col_11;
assign z_row_out[12] = z_col_12;
assign z_row_out[13] = z_col_13;
assign z_row_out[14] = z_col_14;
assign z_row_out[15] = z_col_15;
assign z_row_out[16] = z_col_16;
assign z_row_out[17] = z_col_17;
assign z_row_out[18] = z_col_18;
assign z_row_out[19] = z_col_19;
assign z_row_out[20] = z_col_20;
assign z_row_out[21] = z_col_21;
assign z_row_out[22] = z_col_22;
assign z_row_out[23] = z_col_23;
assign z_row_out[24] = z_col_24;
assign z_row_out[25] = z_col_25;
assign z_row_out[26] = z_col_26;
assign z_row_out[27] = z_col_27;
assign z_row_out[28] = z_col_28;
assign z_row_out[29] = z_col_29;
assign z_row_out[30] = z_col_30;
assign z_row_out[31] = z_col_31;

wire [4:0] row_sel_mux = (z_clear_busy) ? z_clear_row : row_sel;
wire [4:0] row_sel_wr  = (z_clear_busy) ? z_clear_row : row_sel_d;

`ifdef VERILATOR
`ifdef PVR_ZROW_TRACE_PRINTS
always @(posedge clock) begin
	if (reset_n && (z_clear || z_clear_busy || (z_write_allow != 32'd0))) begin
		$strobe("[ZBUF] bank=%0d clear=%0b tags_only=%0b clear_busy=%0b clear_row=%0d row_rd=%0d row_wr=%0d trig_d=%0b write_mask=%08x tag=%03x z_disable=%0b",
			debug_bank, z_clear, z_clear_tags_only_active, z_clear_busy, z_clear_row,
			row_sel_mux, row_sel_wr, trig_z_row_write_d, z_write_allow, tag_in, z_write_disable_d);
	end
end
`endif
`endif

z_mem_dual  z_mem_inst_0 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[0]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[0 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_0  ) );
z_mem_dual  z_mem_inst_1 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[1]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[1 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_1  ) );
z_mem_dual  z_mem_inst_2 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[2]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[2 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_2  ) );
z_mem_dual  z_mem_inst_3 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[3]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[3 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_3  ) );
z_mem_dual  z_mem_inst_4 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[4]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[4 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_4  ) );
z_mem_dual  z_mem_inst_5 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[5]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[5 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_5  ) );
z_mem_dual  z_mem_inst_6 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[6]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[6 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_6  ) );
z_mem_dual  z_mem_inst_7 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[7]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[7 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_7  ) );
z_mem_dual  z_mem_inst_8 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[8]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[8 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_8  ) );
z_mem_dual  z_mem_inst_9 ( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[9]  ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[9 ]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_9  ) );
z_mem_dual  z_mem_inst_10( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[10] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[10]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_10 ) );
z_mem_dual  z_mem_inst_11( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[11] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[11]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_11 ) );
z_mem_dual  z_mem_inst_12( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[12] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[12]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_12 ) );
z_mem_dual  z_mem_inst_13( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[13] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[13]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_13 ) );
z_mem_dual  z_mem_inst_14( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[14] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[14]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_14 ) );
z_mem_dual  z_mem_inst_15( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[15] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[15]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_15 ) );
z_mem_dual  z_mem_inst_16( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[16] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[16]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_16 ) );
z_mem_dual  z_mem_inst_17( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[17] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[17]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_17 ) );
z_mem_dual  z_mem_inst_18( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[18] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[18]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_18 ) );
z_mem_dual  z_mem_inst_19( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[19] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[19]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_19 ) );
z_mem_dual  z_mem_inst_20( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[20] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[20]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_20 ) );
z_mem_dual  z_mem_inst_21( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[21] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[21]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_21 ) );
z_mem_dual  z_mem_inst_22( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[22] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[22]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_22 ) );
z_mem_dual  z_mem_inst_23( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[23] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[23]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_23 ) );
z_mem_dual  z_mem_inst_24( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[24] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[24]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_24 ) );
z_mem_dual  z_mem_inst_25( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[25] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[25]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_25 ) );
z_mem_dual  z_mem_inst_26( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[26] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[26]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_26 ) );
z_mem_dual  z_mem_inst_27( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[27] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[27]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_27 ) );
z_mem_dual  z_mem_inst_28( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[28] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[28]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_28 ) );
z_mem_dual  z_mem_inst_29( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[29] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[29]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_29 ) );
z_mem_dual  z_mem_inst_30( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[30] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[30]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_30 ) );
z_mem_dual  z_mem_inst_31( .clock( clock ), .tag_in( tag_in ), .z_in( z_in_col[31] ), .addr_wr( row_sel_wr  ), .addr_rd( row_sel_mux ), .z_write_allow( z_clear_busy ? 1'b1 : z_write_allow[31]), .z_write_disable( z_write_disable_d ), .z_clear( z_clear_busy ), .clear_tags_only( z_clear_tags_only_active ), .q( z_col_31 ) );


endmodule

module z_mem_dual (
	input clock,
	
	input z_clear,
	input clear_tags_only,
	input z_write_allow,
	input z_write_disable,
	
	input [4:0] addr_wr,
	input [4:0] addr_rd,
	input [11:0] tag_in,
	input [47:0] z_in,

	output reg [59:0] q
);

reg [11:0] tag_mem [0:31];
reg [47:0] z_mem [0:31];

always @(posedge clock) begin
	if (z_clear) begin
		tag_mem[ addr_wr ] <= 12'd0;
		if (!clear_tags_only) z_mem[ addr_wr ] <= 48'd0;
	end
	else if (z_write_allow) begin
		// z_buff has already registered the write controls, and isp_parser
		// delays z_in to the same token. Registering the data again here writes
		// row N-1 into row N, leaving the first tile row with stale/reset Z.
		tag_mem[ addr_wr ] <= tag_in;
		if (!z_write_disable) z_mem[ addr_wr ] <= z_in;
	end

	q <= {tag_mem[ addr_rd ], z_mem[ addr_rd ]};
end

endmodule


`ifdef VERILATOR
module z_mem (
	input clock,
	
	input z_clear,
	input z_write_allow,
	input z_write_disable,
	
	input [4:0] addr,
	input [11:0] tag_in,
	input [47:0] z_in,

	output reg [59:0] q
);

reg [11:0] tag_mem [0:31];
reg [47:0] z_mem [0:31];

always @(posedge clock) begin
	if (z_clear || z_write_allow)                       tag_mem[ addr ] <= z_clear ? 0 : tag_in;
	if (z_clear || (z_write_allow && !z_write_disable))   z_mem[ addr ] <= z_clear ? 0 : z_in;
  
	q <= {tag_mem[ addr ], z_mem[ addr ]};
end

endmodule
`endif


// Version with Dual-ported RAMs.
// For some reason, made barely any difference to the speed,
// when doing the Z-buffer updates all within isp_state 50 ??
//
// Using the Dual-ported RAMs should save around 32 clock cycles per PRIM.
//
// Since it can read the first row, increment to the next, and Write back to the *previous* row, using row_sel-1.
//
/*
z_mem_dual  z_mem_inst_0 ( .clock( clock ), .data_a( {tag_in,z_in_col[0]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[0 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_0  ) );
z_mem_dual  z_mem_inst_1 ( .clock( clock ), .data_a( {tag_in,z_in_col[1]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[1 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_1  ) );
z_mem_dual  z_mem_inst_2 ( .clock( clock ), .data_a( {tag_in,z_in_col[2]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[2 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_2  ) );
z_mem_dual  z_mem_inst_3 ( .clock( clock ), .data_a( {tag_in,z_in_col[3]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[3 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_3  ) );
z_mem_dual  z_mem_inst_4 ( .clock( clock ), .data_a( {tag_in,z_in_col[4]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[4 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_4  ) );
z_mem_dual  z_mem_inst_5 ( .clock( clock ), .data_a( {tag_in,z_in_col[5]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[5 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_5  ) );
z_mem_dual  z_mem_inst_6 ( .clock( clock ), .data_a( {tag_in,z_in_col[6]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[6 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_6  ) );
z_mem_dual  z_mem_inst_7 ( .clock( clock ), .data_a( {tag_in,z_in_col[7]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[7 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_7  ) );
z_mem_dual  z_mem_inst_8 ( .clock( clock ), .data_a( {tag_in,z_in_col[8]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[8 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_8  ) );
z_mem_dual  z_mem_inst_9 ( .clock( clock ), .data_a( {tag_in,z_in_col[9]}  ), .address_a( row_sel-1 ), .wren_a( z_write_allow[9 ] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_9  ) );
z_mem_dual  z_mem_inst_10( .clock( clock ), .data_a( {tag_in,z_in_col[10]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[10] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_10 ) );
z_mem_dual  z_mem_inst_11( .clock( clock ), .data_a( {tag_in,z_in_col[11]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[11] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_11 ) );
z_mem_dual  z_mem_inst_12( .clock( clock ), .data_a( {tag_in,z_in_col[12]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[12] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_12 ) );
z_mem_dual  z_mem_inst_13( .clock( clock ), .data_a( {tag_in,z_in_col[13]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[13] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_13 ) );
z_mem_dual  z_mem_inst_14( .clock( clock ), .data_a( {tag_in,z_in_col[14]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[14] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_14 ) );
z_mem_dual  z_mem_inst_15( .clock( clock ), .data_a( {tag_in,z_in_col[15]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[15] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_15 ) );
z_mem_dual  z_mem_inst_16( .clock( clock ), .data_a( {tag_in,z_in_col[16]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[16] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_16 ) );
z_mem_dual  z_mem_inst_17( .clock( clock ), .data_a( {tag_in,z_in_col[17]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[17] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_17 ) );
z_mem_dual  z_mem_inst_18( .clock( clock ), .data_a( {tag_in,z_in_col[18]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[18] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_18 ) );
z_mem_dual  z_mem_inst_19( .clock( clock ), .data_a( {tag_in,z_in_col[19]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[19] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_19 ) );
z_mem_dual  z_mem_inst_20( .clock( clock ), .data_a( {tag_in,z_in_col[20]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[20] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_20 ) );
z_mem_dual  z_mem_inst_21( .clock( clock ), .data_a( {tag_in,z_in_col[21]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[21] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_21 ) );
z_mem_dual  z_mem_inst_22( .clock( clock ), .data_a( {tag_in,z_in_col[22]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[22] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_22 ) );
z_mem_dual  z_mem_inst_23( .clock( clock ), .data_a( {tag_in,z_in_col[23]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[23] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_23 ) );
z_mem_dual  z_mem_inst_24( .clock( clock ), .data_a( {tag_in,z_in_col[24]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[24] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_24 ) );
z_mem_dual  z_mem_inst_25( .clock( clock ), .data_a( {tag_in,z_in_col[25]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[25] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_25 ) );
z_mem_dual  z_mem_inst_26( .clock( clock ), .data_a( {tag_in,z_in_col[26]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[26] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_26 ) );
z_mem_dual  z_mem_inst_27( .clock( clock ), .data_a( {tag_in,z_in_col[27]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[27] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_27 ) );
z_mem_dual  z_mem_inst_28( .clock( clock ), .data_a( {tag_in,z_in_col[28]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[28] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_28 ) );
z_mem_dual  z_mem_inst_29( .clock( clock ), .data_a( {tag_in,z_in_col[29]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[29] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_29 ) );
z_mem_dual  z_mem_inst_30( .clock( clock ), .data_a( {tag_in,z_in_col[30]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[30] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_30 ) );
z_mem_dual  z_mem_inst_31( .clock( clock ), .data_a( {tag_in,z_in_col[31]} ), .address_a( row_sel-1 ), .wren_a( z_write_allow[31] ), .q_a(), .data_b( 44'd0 ), .address_b( row_sel_mux ), .wren_b( z_clear_busy ), .q_b( z_col_31 ) );

endmodule


`ifdef VERILATOR
module z_mem (
	input clock,

	input [43:0] data_a,
	input [4:0] address_a,
	input wren_a,

	input [43:0] data_b,
	input [4:0] address_b,
	input wren_b,

	output reg [43:0] q_a,
	output reg [43:0] q_b
);

reg [43:0] z_mem [0:31];

always @(posedge clock) begin
  if (wren_a) z_mem[ address_a ] <= data_a;
  if (wren_b) z_mem[ address_b ] <= data_b;
  
  q_a <= z_mem[ address_a ];
  q_b <= z_mem[ address_b ];
end

endmodule
`endif
*/
