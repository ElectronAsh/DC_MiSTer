`timescale 1ns / 1ps
`default_nettype none

module z_buff (
	input clock,
	input reset_n,
	
	input clear_z,				// clear_z && !ra_cont_zclear_n  New tile started AND ra_cont_zclear_n is asserted (Low).
	output reg z_clear_busy,
	
	input [4:0] col_sel,		// x_ps[4:0]
	input [4:0] row_sel,		// y_ps[4:0]
	
	input [31:0] inTri,
	input trig_z_row_write,
	
	input [2:0] depth_comp_in,	// Depth compare MODE.
	
	input [9:0] prim_tag_in,	// prim_tag
	
	input [31:0] z_in_col_0,	// IP_Z[0]
	input [31:0] z_in_col_1,
	input [31:0] z_in_col_2,
	input [31:0] z_in_col_3,
	input [31:0] z_in_col_4,
	input [31:0] z_in_col_5,
	input [31:0] z_in_col_6,
	input [31:0] z_in_col_7,
	input [31:0] z_in_col_8,
	input [31:0] z_in_col_9,
	input [31:0] z_in_col_10,
	input [31:0] z_in_col_11,
	input [31:0] z_in_col_12,
	input [31:0] z_in_col_13,
	input [31:0] z_in_col_14,
	input [31:0] z_in_col_15,
	input [31:0] z_in_col_16,
	input [31:0] z_in_col_17,
	input [31:0] z_in_col_18,
	input [31:0] z_in_col_19,
	input [31:0] z_in_col_20,
	input [31:0] z_in_col_21,
	input [31:0] z_in_col_22,
	input [31:0] z_in_col_23,
	input [31:0] z_in_col_24,
	input [31:0] z_in_col_25,
	input [31:0] z_in_col_26,
	input [31:0] z_in_col_27,
	input [31:0] z_in_col_28,
	input [31:0] z_in_col_29,
	input [31:0] z_in_col_30,
	input [31:0] z_in_col_31,
	
	output [31:0] z_out,			// Single "pixel" Z value read.
	output [9:0] prim_tag_out	// Single "pixel" prim_tag read.
);


/*
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : depth_compare_32x
		depth_compare depth_compare_inst0 (
			.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
			.old_z( z_col[i] [ row_sel ] ),		// input [47:0]  old_z
			.IP_Z( IP_Z[i] ),					// input [47:0]  IP_Z
			.depth_allow( depth_allow[i] )		// output depth_allow
		);
	end
endgenerate
*/

(*keep*)wire [31:0] depth_allow;

depth_compare depth_compare_inst0 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_0[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_0 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[0] )	// output depth_allow
);
depth_compare depth_compare_inst1 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_1[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_1 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[1] )	// output depth_allow
);
depth_compare depth_compare_inst2 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_2[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_2 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[2] )	// output depth_allow
);
depth_compare depth_compare_inst3 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_3[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_3 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[3] )	// output depth_allow
);
depth_compare depth_compare_inst4 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_4[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_4 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[4] )	// output depth_allow
);
depth_compare depth_compare_inst5 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_5[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_5 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[5] )	// output depth_allow
);
depth_compare depth_compare_inst6 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_6[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_6 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[6] )	// output depth_allow
);
depth_compare depth_compare_inst7 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_7[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_7 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[7] )	// output depth_allow
);
depth_compare depth_compare_inst8 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_8[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_8 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[8] )	// output depth_allow
);
depth_compare depth_compare_inst9 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_9[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_9 ),					// input [47:0]  IP_Z
	.depth_allow( depth_allow[9] )	// output depth_allow
);
depth_compare depth_compare_inst10 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_10[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_10 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[10] )	// output depth_allow
);
depth_compare depth_compare_inst11 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_11[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_11 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[11] )	// output depth_allow
);
depth_compare depth_compare_inst12 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_12[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_12 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[12] )	// output depth_allow
);
depth_compare depth_compare_inst13 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_13[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_13 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[13] )	// output depth_allow
);
depth_compare depth_compare_inst14 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_14[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_14 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[14] )	// output depth_allow
);
depth_compare depth_compare_inst15 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_15[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_15 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[15] )	// output depth_allow
);
depth_compare depth_compare_inst16 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_16[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_16 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[16] )	// output depth_allow
);
depth_compare depth_compare_inst17 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_17[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_17 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[17] )	// output depth_allow
);
depth_compare depth_compare_inst18 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_18[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_18 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[18] )	// output depth_allow
);
depth_compare depth_compare_inst19 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_19[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_19 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[19] )	// output depth_allow
);
depth_compare depth_compare_inst20 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_20[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_20 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[20] )	// output depth_allow
);
depth_compare depth_compare_inst21 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_21[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_21 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[21] )	// output depth_allow
);
depth_compare depth_compare_inst22 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_22[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_22 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[22] )	// output depth_allow
);
depth_compare depth_compare_inst23 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_23[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_23 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[23] )	// output depth_allow
);
depth_compare depth_compare_inst24 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_24[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_24 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[24] )	// output depth_allow
);
depth_compare depth_compare_inst25 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_25[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_25 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[25] )	// output depth_allow
);
depth_compare depth_compare_inst26 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_26[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_26 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[26] )	// output depth_allow
);
depth_compare depth_compare_inst27 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_27[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_27 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[27] )	// output depth_allow
);
depth_compare depth_compare_inst28 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_28[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_28 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[28] )	// output depth_allow
);
depth_compare depth_compare_inst29 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_29[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_29 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[29] )	// output depth_allow
);
depth_compare depth_compare_inst30 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_30[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_30 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[30] )	// output depth_allow
);
depth_compare depth_compare_inst31 (
	.depth_comp( depth_comp_in ),		// input [2:0]  depth_comp
	.old_z( z_col_31[31:0] ),					// input [47:0]  old_z
	.IP_Z( z_in_col_31 ),				// input [47:0]  IP_Z
	.depth_allow( depth_allow[31] )	// output depth_allow
);

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


//(*keep*)wire [31:0] z_write_allow = (inTri & depth_allow & {32{trig_z_row_write | z_clear_busy}});		// inTri & depth_allow  Bitwise AND. (Old CRAPPY code).

// New code...
wire [31:0] z_write_allow = (z_clear_busy)   ? 32'hffffffff : 
                         (!trig_z_row_write) ? 32'h00000000 :
                                      (inTri & depth_allow);


reg [4:0] z_clear_row;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	z_clear_busy <= 1'b0;
	z_clear_row <= 5'd0;
end
else begin
	if (clear_z) begin
		z_clear_row <= 5'd0;
		z_clear_busy <= 1'b1;
	end
	if (z_clear_busy) begin
		if (z_clear_row==5'd31) z_clear_busy <= 1'b0;
		else z_clear_row <= z_clear_row + 5'd1;
	end
end

wire [4:0] row_sel_mux = (z_clear_busy) ? z_clear_row : row_sel;


wire [41:0] z_col_0;
wire [41:0] z_col_1;
wire [41:0] z_col_2;
wire [41:0] z_col_3;
wire [41:0] z_col_4;
wire [41:0] z_col_5;
wire [41:0] z_col_6;
wire [41:0] z_col_7;
wire [41:0] z_col_8;
wire [41:0] z_col_9;
wire [41:0] z_col_10;
wire [41:0] z_col_11;
wire [41:0] z_col_12;
wire [41:0] z_col_13;
wire [41:0] z_col_14;
wire [41:0] z_col_15;
wire [41:0] z_col_16;
wire [41:0] z_col_17;
wire [41:0] z_col_18;
wire [41:0] z_col_19;
wire [41:0] z_col_20;
wire [41:0] z_col_21;
wire [41:0] z_col_22;
wire [41:0] z_col_23;
wire [41:0] z_col_24;
wire [41:0] z_col_25;
wire [41:0] z_col_26;
wire [41:0] z_col_27;
wire [41:0] z_col_28;
wire [41:0] z_col_29;
wire [41:0] z_col_30;
wire [41:0] z_col_31;

wire [41:0] z_prim_out = (col_sel==5'd0)  ? z_col_0  :
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

assign prim_tag_out = z_prim_out[41:32];
assign z_out        = z_prim_out[31:0];


z_mem	z_mem_inst_0 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_0}  ), .address( row_sel_mux ), .wren( z_write_allow[0 ] ), .q( z_col_0  ) );
z_mem	z_mem_inst_1 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_1}  ), .address( row_sel_mux ), .wren( z_write_allow[1 ] ), .q( z_col_1  ) );
z_mem	z_mem_inst_2 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_2}  ), .address( row_sel_mux ), .wren( z_write_allow[2 ] ), .q( z_col_2  ) );
z_mem	z_mem_inst_3 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_3}  ), .address( row_sel_mux ), .wren( z_write_allow[3 ] ), .q( z_col_3  ) );
z_mem	z_mem_inst_4 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_4}  ), .address( row_sel_mux ), .wren( z_write_allow[4 ] ), .q( z_col_4  ) );
z_mem	z_mem_inst_5 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_5}  ), .address( row_sel_mux ), .wren( z_write_allow[5 ] ), .q( z_col_5  ) );
z_mem	z_mem_inst_6 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_6}  ), .address( row_sel_mux ), .wren( z_write_allow[6 ] ), .q( z_col_6  ) );
z_mem	z_mem_inst_7 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_7}  ), .address( row_sel_mux ), .wren( z_write_allow[7 ] ), .q( z_col_7  ) );
z_mem	z_mem_inst_8 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_8}  ), .address( row_sel_mux ), .wren( z_write_allow[8 ] ), .q( z_col_8  ) );
z_mem	z_mem_inst_9 ( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_9}  ), .address( row_sel_mux ), .wren( z_write_allow[9 ] ), .q( z_col_9  ) );
z_mem	z_mem_inst_10( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_10} ), .address( row_sel_mux ), .wren( z_write_allow[10] ), .q( z_col_10 ) );
z_mem	z_mem_inst_11( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_11} ), .address( row_sel_mux ), .wren( z_write_allow[11] ), .q( z_col_11 ) );
z_mem	z_mem_inst_12( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_12} ), .address( row_sel_mux ), .wren( z_write_allow[12] ), .q( z_col_12 ) );
z_mem	z_mem_inst_13( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_13} ), .address( row_sel_mux ), .wren( z_write_allow[13] ), .q( z_col_13 ) );
z_mem	z_mem_inst_14( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_14} ), .address( row_sel_mux ), .wren( z_write_allow[14] ), .q( z_col_14 ) );
z_mem	z_mem_inst_15( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_15} ), .address( row_sel_mux ), .wren( z_write_allow[15] ), .q( z_col_15 ) );
z_mem	z_mem_inst_16( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_16} ), .address( row_sel_mux ), .wren( z_write_allow[16] ), .q( z_col_16 ) );
z_mem	z_mem_inst_17( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_17} ), .address( row_sel_mux ), .wren( z_write_allow[17] ), .q( z_col_17 ) );
z_mem	z_mem_inst_18( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_18} ), .address( row_sel_mux ), .wren( z_write_allow[18] ), .q( z_col_18 ) );
z_mem	z_mem_inst_19( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_19} ), .address( row_sel_mux ), .wren( z_write_allow[19] ), .q( z_col_19 ) );
z_mem	z_mem_inst_20( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_20} ), .address( row_sel_mux ), .wren( z_write_allow[20] ), .q( z_col_20 ) );
z_mem	z_mem_inst_21( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_21} ), .address( row_sel_mux ), .wren( z_write_allow[21] ), .q( z_col_21 ) );
z_mem	z_mem_inst_22( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_22} ), .address( row_sel_mux ), .wren( z_write_allow[22] ), .q( z_col_22 ) );
z_mem	z_mem_inst_23( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_23} ), .address( row_sel_mux ), .wren( z_write_allow[23] ), .q( z_col_23 ) );
z_mem	z_mem_inst_24( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_24} ), .address( row_sel_mux ), .wren( z_write_allow[24] ), .q( z_col_24 ) );
z_mem	z_mem_inst_25( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_25} ), .address( row_sel_mux ), .wren( z_write_allow[25] ), .q( z_col_25 ) );
z_mem	z_mem_inst_26( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_26} ), .address( row_sel_mux ), .wren( z_write_allow[26] ), .q( z_col_26 ) );
z_mem	z_mem_inst_27( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_27} ), .address( row_sel_mux ), .wren( z_write_allow[27] ), .q( z_col_27 ) );
z_mem	z_mem_inst_28( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_28} ), .address( row_sel_mux ), .wren( z_write_allow[28] ), .q( z_col_28 ) );
z_mem	z_mem_inst_29( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_29} ), .address( row_sel_mux ), .wren( z_write_allow[29] ), .q( z_col_29 ) );
z_mem	z_mem_inst_30( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_30} ), .address( row_sel_mux ), .wren( z_write_allow[30] ), .q( z_col_30 ) );
z_mem	z_mem_inst_31( .clock( clock ), .data( (z_clear_busy) ? 42'd0 : {prim_tag_in,z_in_col_31} ), .address( row_sel_mux ), .wren( z_write_allow[31] ), .q( z_col_31 ) );


endmodule
