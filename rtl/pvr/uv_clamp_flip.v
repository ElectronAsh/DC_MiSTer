`timescale 1ns / 1ps
`default_nettype none

module uv_clamp_flip (
	input [10:0] tex_u_size_full,
	input [10:0] tex_v_size_full,
	
	input signed [47:0] IP_U_INTERP,
	input signed [47:0] IP_V_INTERP,
	
	input signed [47:0] z_out,
	
	input tex_u_clamp,	
	input tex_v_clamp,
	
	input tex_u_flip,
	input tex_v_flip,
	
	output wire [9:0] u_flipped,
	output wire [9:0] v_flipped
);

wire signed [10:0] u_div_z = (IP_U_INTERP <<<FRAC_DIFF) / z_out;
wire signed [10:0] v_div_z = (IP_V_INTERP <<<FRAC_DIFF) / z_out;

wire [9:0] u_clamped = (tex_u_clamp && u_div_z>=tex_u_size_full) ? tex_u_size_full-1 :	// Clamp, if U > texture width.
											   (tex_u_clamp && u_div_z[10]) ? 10'd0 :	// Zero U coord if u_div_z is negative.
													           u_div_z;					// Else, don't clamp nor zero.

wire [9:0] v_clamped = (tex_v_clamp && v_div_z>=tex_v_size_full) ? tex_v_size_full-1 :	// Clamp, if V > texture height.
											   (tex_v_clamp && v_div_z[10]) ? 10'd0 :	// Zero U coord if u_div_z is negative.
													           v_div_z;					// Else, don't clamp nor zero.

wire [9:0] u_masked  = u_clamped&((tex_u_size_full<<1)-1);	// Mask with TWICE the texture width?
wire [9:0] v_masked  = v_clamped&((tex_v_size_full<<1)-1);	// Mask with TWICE the texture height?

wire [9:0] u_mask_flip = (u_masked&tex_u_size_full) ? u_div_z^((tex_u_size_full<<1)-1) : u_div_z;
wire [9:0] v_mask_flip = (v_masked&tex_v_size_full) ? v_div_z^((tex_v_size_full<<1)-1) : v_div_z;

assign u_flipped = (tex_u_clamp) ? u_clamped : (tex_u_flip) ? u_mask_flip : u_div_z&(tex_u_size_full-1);
assign v_flipped = (tex_v_clamp) ? v_clamped : (tex_v_flip) ? v_mask_flip : v_div_z&(tex_v_size_full-1);

endmodule
