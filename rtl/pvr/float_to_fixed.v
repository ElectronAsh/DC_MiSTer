`timescale 1ns / 1ps
`default_nettype none

module float_to_fixed (
	input wire signed [31:0] float_in,
	input wire [7:0] FRAC_BITS,
	
	output wire signed [47:0] fixed
);
wire float_sign = float_in[31];
wire [7:0]  exp = float_in[30:23];	// Sign bit not included here.
wire [23:0] man = {1'b1, float_in[22:00]};	// Prepend the implied 1.

wire [47:0] float_shifted = (exp>127) ? man<<(exp-127) :	// Exponent is positive.
										man>>(127-exp);		// Exponent is negative.
										 
wire [47:0] new_fixed = float_shifted>>(23-FRAC_BITS);	// Sign bit not included here.

assign fixed = float_sign ? {1'b1,~new_fixed[46:0]} : {1'b0,new_fixed[46:0]};	// Invert the lower bits when the Sign bit is set.
																				// (tip from SKMP, because float values are essentially sign-magnitude.)
endmodule
