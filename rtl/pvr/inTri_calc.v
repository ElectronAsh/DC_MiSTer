`timescale 1ns / 1ps
`default_nettype none

module inTri_calc #(
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter FRAC_BITS = 8'd12,			// Q format for XY coordinates (e.g., Q21.11)
	parameter Z_FRAC_BITS = 8'd17 		// Q format for Z values (e.g., Q20.12)
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

logic signed [63:0] edge_ab [0:31];
logic signed [63:0] edge_bc [0:31];
logic signed [63:0] edge_ca [0:31];
logic signed [63:0] edge_cd [0:31];
logic signed [63:0] edge_da [0:31];

always_comb begin edge_ab[0] = ab_const_term - dy_ab * (x_base_fixed - FX1_FIXED); for (int j=1; j<32; j++) edge_ab[j] = edge_ab[j-1] - dy_ab_step; end
always_comb begin edge_bc[0] = bc_const_term - dy_bc * (x_base_fixed - FX2_FIXED); for (int j=1; j<32; j++) edge_bc[j] = edge_bc[j-1] - dy_bc_step; end
always_comb begin edge_ca[0] = ca_const_term - dy_ca * (x_base_fixed - FX3_FIXED); for (int j=1; j<32; j++) edge_ca[j] = edge_ca[j-1] - dy_ca_step; end
always_comb begin edge_cd[0] = cd_const_term - dy_cd * (x_base_fixed - FX3_FIXED); for (int j=1; j<32; j++) edge_cd[j] = edge_cd[j-1] - dy_cd_step; end
always_comb begin edge_da[0] = da_const_term - dy_da * (x_base_fixed - FX4_FIXED); for (int j=1; j<32; j++) edge_da[j] = edge_da[j-1] - dy_da_step; end

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

wire [31:0] inTri_internal;

assign inTri = (tri_area2==0) ? 32'b0 : inTri_internal;

genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : pixel_test
        //wire sign_ref = edge_ab[i] >= 0;

        // Triangle test
        wire inside_pixel_tri =
            edge_inside(edge_ab[i], include_ab, sign_ref) &&
            edge_inside(edge_bc[i], include_bc, sign_ref) &&
            edge_inside(edge_ca[i], include_ca, sign_ref);

        // Quad test (do NOT simplify; quads are tricky)
        wire inside_pixel_quad =
            edge_inside(edge_ab[i], include_ab, sign_ref) &&
            edge_inside(edge_bc[i], include_bc, sign_ref) &&
            edge_inside(edge_cd[i], include_cd, sign_ref) &&
            edge_inside(edge_da[i], include_da, sign_ref);

        assign inTri_internal[i] = is_quad ? inside_pixel_quad : inside_pixel_tri;
    end
endgenerate

endmodule
