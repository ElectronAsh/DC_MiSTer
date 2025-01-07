`timescale 1ns / 1ps
`default_nettype none

module float_to_fixed (
    input wire [31:0] float_in,
    input wire [7:0] FRAC_BITS,
    
    output wire signed [47:0] fixed
);

wire float_sign = float_in[31];
wire [7:0]  exp = float_in[30:23];         // Sign bit not included here.
wire [23:0] man = {1'b1, float_in[22:0]};  // Prepend the implied 1.

wire [63:0] float_shifted = (exp >= 8'd127) ? ((man<<FRAC_BITS) << (exp - 8'd127))  :	// Exponent is pos.
															 ((man<<FRAC_BITS) >> (8'd127 - exp));		// Exponent is neg.
										 
// Intermediate wire for the converted value
assign fixed = float_sign ? $signed({1'b1, (~(float_shifted>>6'd23))+1'd1}) :
									 $signed({1'b0, (  float_shifted>>6'd23)});


endmodule
