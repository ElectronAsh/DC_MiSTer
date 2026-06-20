`timescale 1ns / 1ps
`default_nettype none

module float_fixed_five #(
	parameter [7:0] FRAC_BITS = 8'd12,
	parameter [7:0] Z_FRAC_BITS = 8'd17
) (
	input wire signed [31:0]  float_1,
	output wire signed [47:0] fixed_1,

	input wire signed [31:0]  float_2,
	output wire signed [47:0] fixed_2,

	input wire signed [31:0]  float_3,	// 3 = Z input !
	output wire signed [47:0] fixed_3,

	input wire signed [31:0]  float_4,
	output wire signed [47:0] fixed_4,

	input wire signed [31:0]  float_5,
	output wire signed [47:0] fixed_5
);

float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_inst_1 (
	.float_in( float_1 ),	// input [31:0]  float_in
	.fixed( fixed_1 )		// output [47:0]  fixed
);

float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_inst_2 (
	.float_in( float_2 ),	// input [31:0]  float_in
	.fixed( fixed_2 )		// output [47:0]  fixed
);

// Uses Z_FRAC_BITS instead!...
float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) float_inst_3 (
	.float_in( float_3 ),	// input [31:0]  float_in
	.fixed( fixed_3 )		// output [47:0]  fixed
);

float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_inst_4 (
	.float_in( float_4 ),	// input [31:0]  float_in
	.fixed( fixed_4 )		// output [47:0]  fixed
);

float_to_fixed #(.FRAC_BITS(FRAC_BITS)) float_inst_5 (
	.float_in( float_5 ),	// input [31:0]  float_in
	.fixed( fixed_5 )		// output [47:0]  fixed
);

endmodule
