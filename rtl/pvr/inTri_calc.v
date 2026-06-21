`timescale 1ns / 1ps
`default_nettype none

module inTri_calc #(
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter FRAC_BITS = 8'd12,			// Q format for XY coordinates (e.g., Q21.11)
	parameter Z_FRAC_BITS = 8'd17,
	parameter INTRI_PIXELS_PER_CYCLE = 32  		// Q format for Z values (e.g., Q20.12)
) (
	input signed [47:0] FX1_FIXED,  // Vertex A
	input signed [47:0] FY1_FIXED,
	input signed [47:0] FX2_FIXED,  // Vertex B
	input signed [47:0] FY2_FIXED,
	input signed [47:0] FX3_FIXED,  // Vertex C
	input signed [47:0] FY3_FIXED,
	input signed [47:0] FX4_FIXED,  // Vertex D
	input signed [47:0] FY4_FIXED,

	input is_quad,

	input [10:0] x_ps,
	input [10:0] y_ps,
	input [1:0] pixel_group,

	output wire [31:0] inTri
);


// Convert screen coordinates to fixed-point. Sampling at pixel centres avoids
// testing shared polygon edges exactly on integer pixel boundaries.
wire signed [47:0] pixel_sample_offset = (PIXEL_CENTER_SAMPLE && (FRAC_BITS != 8'd0)) ? (48'sd1 <<< (FRAC_BITS - 8'd1)) : 48'sd0;
wire signed [47:0] y_ps_fixed = ($signed({37'd0, y_ps}) <<< FRAC_BITS) + pixel_sample_offset;

// Precompute common terms that don't depend on x_pixel
wire signed [47:0] dx_ab = FX2_FIXED - FX1_FIXED;
wire signed [47:0] dy_ab = FY2_FIXED - FY1_FIXED;
wire signed [63:0] ab_const_term = dx_ab * (y_ps_fixed - FY1_FIXED);

wire signed [47:0] dx_bc = FX3_FIXED - FX2_FIXED;
wire signed [47:0] dy_bc = FY3_FIXED - FY2_FIXED;
wire signed [63:0] bc_const_term = dx_bc * (y_ps_fixed - FY2_FIXED);

wire signed [47:0] dx_ca = FX1_FIXED - FX3_FIXED;
wire signed [47:0] dy_ca = FY1_FIXED - FY3_FIXED;
wire signed [63:0] ca_const_term = dx_ca * (y_ps_fixed - FY3_FIXED);

wire signed [47:0] dx_cd = FX4_FIXED - FX3_FIXED;
wire signed [47:0] dy_cd = FY4_FIXED - FY3_FIXED;
wire signed [63:0] cd_const_term = dx_cd * (y_ps_fixed - FY3_FIXED);

wire signed [47:0] dx_da = FX1_FIXED - FX4_FIXED;
wire signed [47:0] dy_da = FY1_FIXED - FY4_FIXED;
wire signed [63:0] da_const_term = dx_da * (y_ps_fixed - FY4_FIXED);

// Base X for the tile row (pixel 0)
wire signed [47:0] x_base_fixed = ($signed({37'd0, {x_ps[10:5],5'd0}}) <<< FRAC_BITS) + pixel_sample_offset;

wire signed [63:0] dy_ab_step = dy_ab <<< FRAC_BITS;
wire signed [63:0] dy_bc_step = dy_bc <<< FRAC_BITS;
wire signed [63:0] dy_ca_step = dy_ca <<< FRAC_BITS;
wire signed [63:0] dy_cd_step = dy_cd <<< FRAC_BITS;
wire signed [63:0] dy_da_step = dy_da <<< FRAC_BITS;

wire signed [63:0] edge_ab [0:31];
wire signed [63:0] edge_bc [0:31];
wire signed [63:0] edge_ca [0:31];
wire signed [63:0] edge_cd [0:31];
wire signed [63:0] edge_da [0:31];

wire signed [63:0] edge_ab_base = ab_const_term - dy_ab * (x_base_fixed - FX1_FIXED);
wire signed [63:0] edge_bc_base = bc_const_term - dy_bc * (x_base_fixed - FX2_FIXED);
wire signed [63:0] edge_ca_base = ca_const_term - dy_ca * (x_base_fixed - FX3_FIXED);
wire signed [63:0] edge_cd_base = cd_const_term - dy_cd * (x_base_fixed - FX3_FIXED);
wire signed [63:0] edge_da_base = da_const_term - dy_da * (x_base_fixed - FX4_FIXED);

function automatic signed [63:0] edge_at_pixel;
    input signed [63:0] edge_base;
    input signed [63:0] edge_step;
    input [5:0] pixel_index;
    begin
        edge_at_pixel = edge_base - (edge_step * $signed({58'd0, pixel_index}));
    end
endfunction
wire signed [63:0] tri_area2 = dx_ab * (FY3_FIXED - FY1_FIXED) - dy_ab * (FX3_FIXED - FX1_FIXED);
wire sign_ref = tri_area2 >= 0;

wire include_ab = sign_ref ? ((dy_ab < 0) || ((dy_ab == 0) && (dx_ab > 0))) :
                            ((dy_ab > 0) || ((dy_ab == 0) && (dx_ab < 0)));
wire include_bc = sign_ref ? ((dy_bc < 0) || ((dy_bc == 0) && (dx_bc > 0))) :
                            ((dy_bc > 0) || ((dy_bc == 0) && (dx_bc < 0)));
wire include_ca = sign_ref ? ((dy_ca < 0) || ((dy_ca == 0) && (dx_ca > 0))) :
                            ((dy_ca > 0) || ((dy_ca == 0) && (dx_ca < 0)));
wire include_cd = sign_ref ? ((dy_cd < 0) || ((dy_cd == 0) && (dx_cd > 0))) :
                            ((dy_cd > 0) || ((dy_cd == 0) && (dx_cd < 0)));
wire include_da = sign_ref ? ((dy_da < 0) || ((dy_da == 0) && (dx_da > 0))) :
                            ((dy_da > 0) || ((dy_da == 0) && (dx_da < 0)));

function automatic edge_inside;
    input signed [63:0] edge_val;
    input include_edge;
    input positive_winding;
    begin
        edge_inside = positive_winding ? (include_edge ? (edge_val >= 0) : (edge_val > 0)) :
                                         (include_edge ? (edge_val <= 0) : (edge_val < 0));
    end
endfunction

localparam INTRI_LANES = (INTRI_PIXELS_PER_CYCLE <= 8) ? 8 : 32;
wire [4:0] pixel_base = (INTRI_LANES == 8) ? {pixel_group, 3'b000} : 5'd0;
wire [31:0] inTri_full;
wire [7:0] inTri_lanes;
wire [31:0] inTri_internal = (INTRI_LANES == 8) ? ({24'd0, inTri_lanes} << pixel_base) : inTri_full;

assign inTri = (tri_area2==0) ? 32'b0 : inTri_internal;

genvar i;
generate
    if (INTRI_LANES == 8) begin : g_8_lane
        wire signed [63:0] edge_ab_0 = edge_at_pixel(edge_ab_base, dy_ab_step, {1'b0, pixel_base});
        wire signed [63:0] edge_bc_0 = edge_at_pixel(edge_bc_base, dy_bc_step, {1'b0, pixel_base});
        wire signed [63:0] edge_ca_0 = edge_at_pixel(edge_ca_base, dy_ca_step, {1'b0, pixel_base});
        wire signed [63:0] edge_cd_0 = edge_at_pixel(edge_cd_base, dy_cd_step, {1'b0, pixel_base});
        wire signed [63:0] edge_da_0 = edge_at_pixel(edge_da_base, dy_da_step, {1'b0, pixel_base});

        wire signed [63:0] edge_ab_1 = edge_ab_0 - dy_ab_step;
        wire signed [63:0] edge_bc_1 = edge_bc_0 - dy_bc_step;
        wire signed [63:0] edge_ca_1 = edge_ca_0 - dy_ca_step;
        wire signed [63:0] edge_cd_1 = edge_cd_0 - dy_cd_step;
        wire signed [63:0] edge_da_1 = edge_da_0 - dy_da_step;

        wire signed [63:0] edge_ab_2 = edge_ab_1 - dy_ab_step;
        wire signed [63:0] edge_bc_2 = edge_bc_1 - dy_bc_step;
        wire signed [63:0] edge_ca_2 = edge_ca_1 - dy_ca_step;
        wire signed [63:0] edge_cd_2 = edge_cd_1 - dy_cd_step;
        wire signed [63:0] edge_da_2 = edge_da_1 - dy_da_step;

        wire signed [63:0] edge_ab_3 = edge_ab_2 - dy_ab_step;
        wire signed [63:0] edge_bc_3 = edge_bc_2 - dy_bc_step;
        wire signed [63:0] edge_ca_3 = edge_ca_2 - dy_ca_step;
        wire signed [63:0] edge_cd_3 = edge_cd_2 - dy_cd_step;
        wire signed [63:0] edge_da_3 = edge_da_2 - dy_da_step;

        wire signed [63:0] edge_ab_4 = edge_ab_3 - dy_ab_step;
        wire signed [63:0] edge_bc_4 = edge_bc_3 - dy_bc_step;
        wire signed [63:0] edge_ca_4 = edge_ca_3 - dy_ca_step;
        wire signed [63:0] edge_cd_4 = edge_cd_3 - dy_cd_step;
        wire signed [63:0] edge_da_4 = edge_da_3 - dy_da_step;

        wire signed [63:0] edge_ab_5 = edge_ab_4 - dy_ab_step;
        wire signed [63:0] edge_bc_5 = edge_bc_4 - dy_bc_step;
        wire signed [63:0] edge_ca_5 = edge_ca_4 - dy_ca_step;
        wire signed [63:0] edge_cd_5 = edge_cd_4 - dy_cd_step;
        wire signed [63:0] edge_da_5 = edge_da_4 - dy_da_step;

        wire signed [63:0] edge_ab_6 = edge_ab_5 - dy_ab_step;
        wire signed [63:0] edge_bc_6 = edge_bc_5 - dy_bc_step;
        wire signed [63:0] edge_ca_6 = edge_ca_5 - dy_ca_step;
        wire signed [63:0] edge_cd_6 = edge_cd_5 - dy_cd_step;
        wire signed [63:0] edge_da_6 = edge_da_5 - dy_da_step;

        wire signed [63:0] edge_ab_7 = edge_ab_6 - dy_ab_step;
        wire signed [63:0] edge_bc_7 = edge_bc_6 - dy_bc_step;
        wire signed [63:0] edge_ca_7 = edge_ca_6 - dy_ca_step;
        wire signed [63:0] edge_cd_7 = edge_cd_6 - dy_cd_step;
        wire signed [63:0] edge_da_7 = edge_da_6 - dy_da_step;

        assign edge_ab[0] = edge_ab_0; assign edge_bc[0] = edge_bc_0; assign edge_ca[0] = edge_ca_0; assign edge_cd[0] = edge_cd_0; assign edge_da[0] = edge_da_0;
        assign edge_ab[1] = edge_ab_1; assign edge_bc[1] = edge_bc_1; assign edge_ca[1] = edge_ca_1; assign edge_cd[1] = edge_cd_1; assign edge_da[1] = edge_da_1;
        assign edge_ab[2] = edge_ab_2; assign edge_bc[2] = edge_bc_2; assign edge_ca[2] = edge_ca_2; assign edge_cd[2] = edge_cd_2; assign edge_da[2] = edge_da_2;
        assign edge_ab[3] = edge_ab_3; assign edge_bc[3] = edge_bc_3; assign edge_ca[3] = edge_ca_3; assign edge_cd[3] = edge_cd_3; assign edge_da[3] = edge_da_3;
        assign edge_ab[4] = edge_ab_4; assign edge_bc[4] = edge_bc_4; assign edge_ca[4] = edge_ca_4; assign edge_cd[4] = edge_cd_4; assign edge_da[4] = edge_da_4;
        assign edge_ab[5] = edge_ab_5; assign edge_bc[5] = edge_bc_5; assign edge_ca[5] = edge_ca_5; assign edge_cd[5] = edge_cd_5; assign edge_da[5] = edge_da_5;
        assign edge_ab[6] = edge_ab_6; assign edge_bc[6] = edge_bc_6; assign edge_ca[6] = edge_ca_6; assign edge_cd[6] = edge_cd_6; assign edge_da[6] = edge_da_6;
        assign edge_ab[7] = edge_ab_7; assign edge_bc[7] = edge_bc_7; assign edge_ca[7] = edge_ca_7; assign edge_cd[7] = edge_cd_7; assign edge_da[7] = edge_da_7;

        assign inTri_lanes[0] = is_quad ? (edge_inside(edge_ab_0, include_ab, sign_ref) && edge_inside(edge_bc_0, include_bc, sign_ref) && edge_inside(edge_cd_0, include_cd, sign_ref) && edge_inside(edge_da_0, include_da, sign_ref)) : (edge_inside(edge_ab_0, include_ab, sign_ref) && edge_inside(edge_bc_0, include_bc, sign_ref) && edge_inside(edge_ca_0, include_ca, sign_ref));
        assign inTri_lanes[1] = is_quad ? (edge_inside(edge_ab_1, include_ab, sign_ref) && edge_inside(edge_bc_1, include_bc, sign_ref) && edge_inside(edge_cd_1, include_cd, sign_ref) && edge_inside(edge_da_1, include_da, sign_ref)) : (edge_inside(edge_ab_1, include_ab, sign_ref) && edge_inside(edge_bc_1, include_bc, sign_ref) && edge_inside(edge_ca_1, include_ca, sign_ref));
        assign inTri_lanes[2] = is_quad ? (edge_inside(edge_ab_2, include_ab, sign_ref) && edge_inside(edge_bc_2, include_bc, sign_ref) && edge_inside(edge_cd_2, include_cd, sign_ref) && edge_inside(edge_da_2, include_da, sign_ref)) : (edge_inside(edge_ab_2, include_ab, sign_ref) && edge_inside(edge_bc_2, include_bc, sign_ref) && edge_inside(edge_ca_2, include_ca, sign_ref));
        assign inTri_lanes[3] = is_quad ? (edge_inside(edge_ab_3, include_ab, sign_ref) && edge_inside(edge_bc_3, include_bc, sign_ref) && edge_inside(edge_cd_3, include_cd, sign_ref) && edge_inside(edge_da_3, include_da, sign_ref)) : (edge_inside(edge_ab_3, include_ab, sign_ref) && edge_inside(edge_bc_3, include_bc, sign_ref) && edge_inside(edge_ca_3, include_ca, sign_ref));
        assign inTri_lanes[4] = is_quad ? (edge_inside(edge_ab_4, include_ab, sign_ref) && edge_inside(edge_bc_4, include_bc, sign_ref) && edge_inside(edge_cd_4, include_cd, sign_ref) && edge_inside(edge_da_4, include_da, sign_ref)) : (edge_inside(edge_ab_4, include_ab, sign_ref) && edge_inside(edge_bc_4, include_bc, sign_ref) && edge_inside(edge_ca_4, include_ca, sign_ref));
        assign inTri_lanes[5] = is_quad ? (edge_inside(edge_ab_5, include_ab, sign_ref) && edge_inside(edge_bc_5, include_bc, sign_ref) && edge_inside(edge_cd_5, include_cd, sign_ref) && edge_inside(edge_da_5, include_da, sign_ref)) : (edge_inside(edge_ab_5, include_ab, sign_ref) && edge_inside(edge_bc_5, include_bc, sign_ref) && edge_inside(edge_ca_5, include_ca, sign_ref));
        assign inTri_lanes[6] = is_quad ? (edge_inside(edge_ab_6, include_ab, sign_ref) && edge_inside(edge_bc_6, include_bc, sign_ref) && edge_inside(edge_cd_6, include_cd, sign_ref) && edge_inside(edge_da_6, include_da, sign_ref)) : (edge_inside(edge_ab_6, include_ab, sign_ref) && edge_inside(edge_bc_6, include_bc, sign_ref) && edge_inside(edge_ca_6, include_ca, sign_ref));
        assign inTri_lanes[7] = is_quad ? (edge_inside(edge_ab_7, include_ab, sign_ref) && edge_inside(edge_bc_7, include_bc, sign_ref) && edge_inside(edge_cd_7, include_cd, sign_ref) && edge_inside(edge_da_7, include_da, sign_ref)) : (edge_inside(edge_ab_7, include_ab, sign_ref) && edge_inside(edge_bc_7, include_bc, sign_ref) && edge_inside(edge_ca_7, include_ca, sign_ref));

        for (i = 8; i < 32; i = i + 1) begin : inactive_lane
            assign edge_ab[i] = 64'sd0;
            assign edge_bc[i] = 64'sd0;
            assign edge_ca[i] = 64'sd0;
            assign edge_cd[i] = 64'sd0;
            assign edge_da[i] = 64'sd0;
        end
        assign inTri_full = 32'd0;
    end
    else begin : g_32_lane
        for (i = 0; i < 32; i = i + 1) begin : pixel_test
            localparam [5:0] PIXEL_INDEX = i[5:0];

            assign edge_ab[i] = edge_at_pixel(edge_ab_base, dy_ab_step, PIXEL_INDEX);
            assign edge_bc[i] = edge_at_pixel(edge_bc_base, dy_bc_step, PIXEL_INDEX);
            assign edge_ca[i] = edge_at_pixel(edge_ca_base, dy_ca_step, PIXEL_INDEX);
            assign edge_cd[i] = edge_at_pixel(edge_cd_base, dy_cd_step, PIXEL_INDEX);
            assign edge_da[i] = edge_at_pixel(edge_da_base, dy_da_step, PIXEL_INDEX);

            wire inside_pixel_tri =
                edge_inside(edge_ab[i], include_ab, sign_ref) &&
                edge_inside(edge_bc[i], include_bc, sign_ref) &&
                edge_inside(edge_ca[i], include_ca, sign_ref);

            wire inside_pixel_quad =
                edge_inside(edge_ab[i], include_ab, sign_ref) &&
                edge_inside(edge_bc[i], include_bc, sign_ref) &&
                edge_inside(edge_cd[i], include_cd, sign_ref) &&
                edge_inside(edge_da[i], include_da, sign_ref);

            assign inTri_full[i] = is_quad ? inside_pixel_quad : inside_pixel_tri;
        end
        assign inTri_lanes = 8'd0;
    end
endgenerate
endmodule
