`timescale 1ns / 1ps
`default_nettype none

module inTri_calc #(
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter FRAC_BITS = 8'd12,
	parameter Z_FRAC_BITS = 8'd17,
	parameter INTRI_PIXELS_PER_CYCLE = 32
) (
	input signed [47:0] FX1_FIXED,
	input signed [47:0] FY1_FIXED,
	input signed [47:0] FX2_FIXED,
	input signed [47:0] FY2_FIXED,
	input signed [47:0] FX3_FIXED,
	input signed [47:0] FY3_FIXED,
	input signed [47:0] FX4_FIXED,
	input signed [47:0] FY4_FIXED,

	input is_quad,

	input [10:0] x_ps,
	input [10:0] y_ps,
	input [1:0] pixel_group,

	output wire [31:0] inTri
);

// Lite edge mode assumes screen-space coordinates fit comfortably in signed
// Q19.12. This cuts the edge multipliers from 48-bit input terms to 32-bit
// input terms in the FPGA build.
`ifdef PVR_LITE_INTRI_SIMPLE_EDGE
localparam EDGE_COORD_W = 32;
localparam EDGE_W = 56;
`else
localparam EDGE_COORD_W = 48;
localparam EDGE_W = 64;
`endif

function automatic signed [EDGE_COORD_W-1:0] edge_coord;
	input signed [47:0] v;
begin
	edge_coord = v[EDGE_COORD_W-1:0];
end
endfunction

function automatic signed [EDGE_W-1:0] edge_mul;
	input signed [EDGE_COORD_W-1:0] a;
	input signed [EDGE_COORD_W-1:0] b;
	reg signed [(EDGE_COORD_W*2)-1:0] p;
begin
	p = a * b;
	edge_mul = p[EDGE_W-1:0];
end
endfunction

function automatic signed [EDGE_W-1:0] edge_at_group;
	input signed [EDGE_W-1:0] edge_base;
	input signed [EDGE_W-1:0] edge_step;
	input [1:0] group;
begin
	case (group)
		2'd0: edge_at_group = edge_base;
		2'd1: edge_at_group = edge_base - (edge_step <<< 3);
		2'd2: edge_at_group = edge_base - (edge_step <<< 4);
		default: edge_at_group = edge_base - ((edge_step <<< 4) + (edge_step <<< 3));
	endcase
end
endfunction

function automatic edge_inside;
	input signed [EDGE_W-1:0] edge_val;
	input include_edge;
	input positive_winding;
begin
	edge_inside = positive_winding ? (include_edge ? (edge_val >= 0) : (edge_val > 0)) :
	                               (include_edge ? (edge_val <= 0) : (edge_val < 0));
end
endfunction

wire signed [EDGE_COORD_W-1:0] pixel_sample_offset = (PIXEL_CENTER_SAMPLE && (FRAC_BITS != 8'd0)) ?
	(edge_coord(48'sd1) <<< (FRAC_BITS - 8'd1)) : {EDGE_COORD_W{1'b0}};
wire signed [EDGE_COORD_W-1:0] y_ps_fixed = ($signed({{(EDGE_COORD_W-11){1'b0}}, y_ps}) <<< FRAC_BITS) + pixel_sample_offset;
wire signed [EDGE_COORD_W-1:0] x_base_fixed = ($signed({{(EDGE_COORD_W-11){1'b0}}, {x_ps[10:5],5'd0}}) <<< FRAC_BITS) + pixel_sample_offset;

wire signed [EDGE_COORD_W-1:0] fx1 = edge_coord(FX1_FIXED);
wire signed [EDGE_COORD_W-1:0] fy1 = edge_coord(FY1_FIXED);
wire signed [EDGE_COORD_W-1:0] fx2 = edge_coord(FX2_FIXED);
wire signed [EDGE_COORD_W-1:0] fy2 = edge_coord(FY2_FIXED);
wire signed [EDGE_COORD_W-1:0] fx3 = edge_coord(FX3_FIXED);
wire signed [EDGE_COORD_W-1:0] fy3 = edge_coord(FY3_FIXED);
`ifndef PVR_LITE_INTRI_TRI_ONLY
wire signed [EDGE_COORD_W-1:0] fx4 = edge_coord(FX4_FIXED);
wire signed [EDGE_COORD_W-1:0] fy4 = edge_coord(FY4_FIXED);
wire is_quad_eff = is_quad;
`else
wire is_quad_eff = 1'b0;
`endif

wire signed [EDGE_COORD_W-1:0] dx_ab = fx2 - fx1;
wire signed [EDGE_COORD_W-1:0] dy_ab = fy2 - fy1;
wire signed [EDGE_COORD_W-1:0] dx_bc = fx3 - fx2;
wire signed [EDGE_COORD_W-1:0] dy_bc = fy3 - fy2;
wire signed [EDGE_COORD_W-1:0] dx_ca = fx1 - fx3;
wire signed [EDGE_COORD_W-1:0] dy_ca = fy1 - fy3;

wire signed [EDGE_W-1:0] ab_const_term = edge_mul(dx_ab, y_ps_fixed - fy1);
wire signed [EDGE_W-1:0] bc_const_term = edge_mul(dx_bc, y_ps_fixed - fy2);
wire signed [EDGE_W-1:0] ca_const_term = edge_mul(dx_ca, y_ps_fixed - fy3);

wire signed [EDGE_W-1:0] dy_ab_step = {{(EDGE_W-EDGE_COORD_W){dy_ab[EDGE_COORD_W-1]}}, dy_ab} <<< FRAC_BITS;
wire signed [EDGE_W-1:0] dy_bc_step = {{(EDGE_W-EDGE_COORD_W){dy_bc[EDGE_COORD_W-1]}}, dy_bc} <<< FRAC_BITS;
wire signed [EDGE_W-1:0] dy_ca_step = {{(EDGE_W-EDGE_COORD_W){dy_ca[EDGE_COORD_W-1]}}, dy_ca} <<< FRAC_BITS;

wire signed [EDGE_W-1:0] edge_ab_base = ab_const_term - edge_mul(dy_ab, x_base_fixed - fx1);
wire signed [EDGE_W-1:0] edge_bc_base = bc_const_term - edge_mul(dy_bc, x_base_fixed - fx2);
wire signed [EDGE_W-1:0] edge_ca_base = ca_const_term - edge_mul(dy_ca, x_base_fixed - fx3);

`ifndef PVR_LITE_INTRI_TRI_ONLY
wire signed [EDGE_COORD_W-1:0] dx_cd = fx4 - fx3;
wire signed [EDGE_COORD_W-1:0] dy_cd = fy4 - fy3;
wire signed [EDGE_COORD_W-1:0] dx_da = fx1 - fx4;
wire signed [EDGE_COORD_W-1:0] dy_da = fy1 - fy4;
wire signed [EDGE_W-1:0] cd_const_term = edge_mul(dx_cd, y_ps_fixed - fy3);
wire signed [EDGE_W-1:0] da_const_term = edge_mul(dx_da, y_ps_fixed - fy4);
wire signed [EDGE_W-1:0] dy_cd_step = {{(EDGE_W-EDGE_COORD_W){dy_cd[EDGE_COORD_W-1]}}, dy_cd} <<< FRAC_BITS;
wire signed [EDGE_W-1:0] dy_da_step = {{(EDGE_W-EDGE_COORD_W){dy_da[EDGE_COORD_W-1]}}, dy_da} <<< FRAC_BITS;
wire signed [EDGE_W-1:0] edge_cd_base = cd_const_term - edge_mul(dy_cd, x_base_fixed - fx3);
wire signed [EDGE_W-1:0] edge_da_base = da_const_term - edge_mul(dy_da, x_base_fixed - fx4);
`endif

wire signed [EDGE_W-1:0] tri_area2 = edge_mul(dx_ab, fy3 - fy1) - edge_mul(dy_ab, fx3 - fx1);
wire sign_ref = tri_area2 >= 0;

wire include_ab = sign_ref ? ((dy_ab < 0) || ((dy_ab == 0) && (dx_ab > 0))) :
                            ((dy_ab > 0) || ((dy_ab == 0) && (dx_ab < 0)));
wire include_bc = sign_ref ? ((dy_bc < 0) || ((dy_bc == 0) && (dx_bc > 0))) :
                            ((dy_bc > 0) || ((dy_bc == 0) && (dx_bc < 0)));
wire include_ca = sign_ref ? ((dy_ca < 0) || ((dy_ca == 0) && (dx_ca > 0))) :
                            ((dy_ca > 0) || ((dy_ca == 0) && (dx_ca < 0)));
`ifndef PVR_LITE_INTRI_TRI_ONLY
wire include_cd = sign_ref ? ((dy_cd < 0) || ((dy_cd == 0) && (dx_cd > 0))) :
                            ((dy_cd > 0) || ((dy_cd == 0) && (dx_cd < 0)));
wire include_da = sign_ref ? ((dy_da < 0) || ((dy_da == 0) && (dx_da > 0))) :
                            ((dy_da > 0) || ((dy_da == 0) && (dx_da < 0)));
`endif

localparam INTRI_LANES = (INTRI_PIXELS_PER_CYCLE <= 8) ? 8 : 32;
wire [4:0] pixel_base = (INTRI_LANES == 8) ? {pixel_group, 3'b000} : 5'd0;
wire [31:0] inTri_full;
wire [7:0] inTri_lanes;
wire [31:0] inTri_internal = (INTRI_LANES == 8) ? ({24'd0, inTri_lanes} << pixel_base) : inTri_full;

assign inTri = (tri_area2 == 0) ? 32'd0 : inTri_internal;

genvar i;
generate
	if (INTRI_LANES == 8) begin : g_8_lane
		wire signed [EDGE_W-1:0] edge_ab_0 = edge_at_group(edge_ab_base, dy_ab_step, pixel_group);
		wire signed [EDGE_W-1:0] edge_bc_0 = edge_at_group(edge_bc_base, dy_bc_step, pixel_group);
		wire signed [EDGE_W-1:0] edge_ca_0 = edge_at_group(edge_ca_base, dy_ca_step, pixel_group);
`ifndef PVR_LITE_INTRI_TRI_ONLY
		wire signed [EDGE_W-1:0] edge_cd_0 = edge_at_group(edge_cd_base, dy_cd_step, pixel_group);
		wire signed [EDGE_W-1:0] edge_da_0 = edge_at_group(edge_da_base, dy_da_step, pixel_group);
`endif

		wire signed [EDGE_W-1:0] edge_ab_1 = edge_ab_0 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_1 = edge_bc_0 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_1 = edge_ca_0 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_2 = edge_ab_1 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_2 = edge_bc_1 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_2 = edge_ca_1 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_3 = edge_ab_2 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_3 = edge_bc_2 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_3 = edge_ca_2 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_4 = edge_ab_3 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_4 = edge_bc_3 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_4 = edge_ca_3 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_5 = edge_ab_4 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_5 = edge_bc_4 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_5 = edge_ca_4 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_6 = edge_ab_5 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_6 = edge_bc_5 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_6 = edge_ca_5 - dy_ca_step;
		wire signed [EDGE_W-1:0] edge_ab_7 = edge_ab_6 - dy_ab_step;
		wire signed [EDGE_W-1:0] edge_bc_7 = edge_bc_6 - dy_bc_step;
		wire signed [EDGE_W-1:0] edge_ca_7 = edge_ca_6 - dy_ca_step;

`ifndef PVR_LITE_INTRI_TRI_ONLY
		wire signed [EDGE_W-1:0] edge_cd_1 = edge_cd_0 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_1 = edge_da_0 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_2 = edge_cd_1 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_2 = edge_da_1 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_3 = edge_cd_2 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_3 = edge_da_2 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_4 = edge_cd_3 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_4 = edge_da_3 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_5 = edge_cd_4 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_5 = edge_da_4 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_6 = edge_cd_5 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_6 = edge_da_5 - dy_da_step;
		wire signed [EDGE_W-1:0] edge_cd_7 = edge_cd_6 - dy_cd_step;
		wire signed [EDGE_W-1:0] edge_da_7 = edge_da_6 - dy_da_step;
`endif

`ifdef PVR_LITE_INTRI_TRI_ONLY
		assign inTri_lanes[0] = edge_inside(edge_ab_0, include_ab, sign_ref) && edge_inside(edge_bc_0, include_bc, sign_ref) && edge_inside(edge_ca_0, include_ca, sign_ref);
		assign inTri_lanes[1] = edge_inside(edge_ab_1, include_ab, sign_ref) && edge_inside(edge_bc_1, include_bc, sign_ref) && edge_inside(edge_ca_1, include_ca, sign_ref);
		assign inTri_lanes[2] = edge_inside(edge_ab_2, include_ab, sign_ref) && edge_inside(edge_bc_2, include_bc, sign_ref) && edge_inside(edge_ca_2, include_ca, sign_ref);
		assign inTri_lanes[3] = edge_inside(edge_ab_3, include_ab, sign_ref) && edge_inside(edge_bc_3, include_bc, sign_ref) && edge_inside(edge_ca_3, include_ca, sign_ref);
		assign inTri_lanes[4] = edge_inside(edge_ab_4, include_ab, sign_ref) && edge_inside(edge_bc_4, include_bc, sign_ref) && edge_inside(edge_ca_4, include_ca, sign_ref);
		assign inTri_lanes[5] = edge_inside(edge_ab_5, include_ab, sign_ref) && edge_inside(edge_bc_5, include_bc, sign_ref) && edge_inside(edge_ca_5, include_ca, sign_ref);
		assign inTri_lanes[6] = edge_inside(edge_ab_6, include_ab, sign_ref) && edge_inside(edge_bc_6, include_bc, sign_ref) && edge_inside(edge_ca_6, include_ca, sign_ref);
		assign inTri_lanes[7] = edge_inside(edge_ab_7, include_ab, sign_ref) && edge_inside(edge_bc_7, include_bc, sign_ref) && edge_inside(edge_ca_7, include_ca, sign_ref);
`else
		assign inTri_lanes[0] = is_quad_eff ? (edge_inside(edge_ab_0, include_ab, sign_ref) && edge_inside(edge_bc_0, include_bc, sign_ref) && edge_inside(edge_cd_0, include_cd, sign_ref) && edge_inside(edge_da_0, include_da, sign_ref)) : (edge_inside(edge_ab_0, include_ab, sign_ref) && edge_inside(edge_bc_0, include_bc, sign_ref) && edge_inside(edge_ca_0, include_ca, sign_ref));
		assign inTri_lanes[1] = is_quad_eff ? (edge_inside(edge_ab_1, include_ab, sign_ref) && edge_inside(edge_bc_1, include_bc, sign_ref) && edge_inside(edge_cd_1, include_cd, sign_ref) && edge_inside(edge_da_1, include_da, sign_ref)) : (edge_inside(edge_ab_1, include_ab, sign_ref) && edge_inside(edge_bc_1, include_bc, sign_ref) && edge_inside(edge_ca_1, include_ca, sign_ref));
		assign inTri_lanes[2] = is_quad_eff ? (edge_inside(edge_ab_2, include_ab, sign_ref) && edge_inside(edge_bc_2, include_bc, sign_ref) && edge_inside(edge_cd_2, include_cd, sign_ref) && edge_inside(edge_da_2, include_da, sign_ref)) : (edge_inside(edge_ab_2, include_ab, sign_ref) && edge_inside(edge_bc_2, include_bc, sign_ref) && edge_inside(edge_ca_2, include_ca, sign_ref));
		assign inTri_lanes[3] = is_quad_eff ? (edge_inside(edge_ab_3, include_ab, sign_ref) && edge_inside(edge_bc_3, include_bc, sign_ref) && edge_inside(edge_cd_3, include_cd, sign_ref) && edge_inside(edge_da_3, include_da, sign_ref)) : (edge_inside(edge_ab_3, include_ab, sign_ref) && edge_inside(edge_bc_3, include_bc, sign_ref) && edge_inside(edge_ca_3, include_ca, sign_ref));
		assign inTri_lanes[4] = is_quad_eff ? (edge_inside(edge_ab_4, include_ab, sign_ref) && edge_inside(edge_bc_4, include_bc, sign_ref) && edge_inside(edge_cd_4, include_cd, sign_ref) && edge_inside(edge_da_4, include_da, sign_ref)) : (edge_inside(edge_ab_4, include_ab, sign_ref) && edge_inside(edge_bc_4, include_bc, sign_ref) && edge_inside(edge_ca_4, include_ca, sign_ref));
		assign inTri_lanes[5] = is_quad_eff ? (edge_inside(edge_ab_5, include_ab, sign_ref) && edge_inside(edge_bc_5, include_bc, sign_ref) && edge_inside(edge_cd_5, include_cd, sign_ref) && edge_inside(edge_da_5, include_da, sign_ref)) : (edge_inside(edge_ab_5, include_ab, sign_ref) && edge_inside(edge_bc_5, include_bc, sign_ref) && edge_inside(edge_ca_5, include_ca, sign_ref));
		assign inTri_lanes[6] = is_quad_eff ? (edge_inside(edge_ab_6, include_ab, sign_ref) && edge_inside(edge_bc_6, include_bc, sign_ref) && edge_inside(edge_cd_6, include_cd, sign_ref) && edge_inside(edge_da_6, include_da, sign_ref)) : (edge_inside(edge_ab_6, include_ab, sign_ref) && edge_inside(edge_bc_6, include_bc, sign_ref) && edge_inside(edge_ca_6, include_ca, sign_ref));
		assign inTri_lanes[7] = is_quad_eff ? (edge_inside(edge_ab_7, include_ab, sign_ref) && edge_inside(edge_bc_7, include_bc, sign_ref) && edge_inside(edge_cd_7, include_cd, sign_ref) && edge_inside(edge_da_7, include_da, sign_ref)) : (edge_inside(edge_ab_7, include_ab, sign_ref) && edge_inside(edge_bc_7, include_bc, sign_ref) && edge_inside(edge_ca_7, include_ca, sign_ref));
`endif
		assign inTri_full = 32'd0;
	end
	else begin : g_32_lane
		for (i = 0; i < 32; i = i + 1) begin : pixel_test
			localparam [5:0] PIXEL_INDEX = i[5:0];
			wire signed [EDGE_W-1:0] edge_ab_i = edge_ab_base - (dy_ab_step * PIXEL_INDEX);
			wire signed [EDGE_W-1:0] edge_bc_i = edge_bc_base - (dy_bc_step * PIXEL_INDEX);
			wire signed [EDGE_W-1:0] edge_ca_i = edge_ca_base - (dy_ca_step * PIXEL_INDEX);
`ifndef PVR_LITE_INTRI_TRI_ONLY
			wire signed [EDGE_W-1:0] edge_cd_i = edge_cd_base - (dy_cd_step * PIXEL_INDEX);
			wire signed [EDGE_W-1:0] edge_da_i = edge_da_base - (dy_da_step * PIXEL_INDEX);
			wire inside_pixel_quad = edge_inside(edge_ab_i, include_ab, sign_ref) && edge_inside(edge_bc_i, include_bc, sign_ref) && edge_inside(edge_cd_i, include_cd, sign_ref) && edge_inside(edge_da_i, include_da, sign_ref);
`endif
			wire inside_pixel_tri = edge_inside(edge_ab_i, include_ab, sign_ref) && edge_inside(edge_bc_i, include_bc, sign_ref) && edge_inside(edge_ca_i, include_ca, sign_ref);
`ifdef PVR_LITE_INTRI_TRI_ONLY
			assign inTri_full[i] = inside_pixel_tri;
`else
			assign inTri_full[i] = is_quad_eff ? inside_pixel_quad : inside_pixel_tri;
`endif
		end
		assign inTri_lanes = 8'd0;
	end
endgenerate
endmodule
