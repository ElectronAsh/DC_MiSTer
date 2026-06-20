`timescale 1ns / 1ps
`default_nettype none

module edge_engine #(
    parameter FP_BITS = 16   // fractional bits for screen space
)(
    input  wire         clock,
    input  wire         reset_n,

    // Triangle setup
    input  wire         tri_setup,

    input  wire signed [47:0] x1,
    input  wire signed [47:0] y1,
    input  wire signed [47:0] x2,
    input  wire signed [47:0] y2,
    input  wire signed [47:0] x3,
    input  wire signed [47:0] y3,

    // Pixel position (absolute, fixed-point)
    input  wire signed [47:0] px,
    input  wire signed [47:0] py,

    // Barycentric edge values
    output reg  signed [63:0] E1,
    output reg  signed [63:0] E2,
    output reg  signed [63:0] E3,

    // Triangle area (constant)
    output reg  signed [63:0] area
);

// Edge deltas
reg signed [31:0] E1_dx, E1_dy;
reg signed [31:0] E2_dx, E2_dy;
reg signed [31:0] E3_dx, E3_dy;

// Edge constants
reg signed [63:0] E1_c, E2_c, E3_c;

always @(posedge clock) begin
	if (!reset_n) begin
		E1_dx <= 0; E1_dy <= 0; E1_c <= 0;
		E2_dx <= 0; E2_dy <= 0; E2_c <= 0;
		E3_dx <= 0; E3_dy <= 0; E3_c <= 0;
		area  <= 0;
	end
	else if (tri_setup) begin
		// Edge equations
		E1_dx <=  y2 - y3;
		E1_dy <=  x3 - x2;
		E1_c  <=  x2*y3 - x3*y2;

		E2_dx <=  y3 - y1;
		E2_dy <=  x1 - x3;
		E2_c  <=  x3*y1 - x1*y3;

		E3_dx <=  y1 - y2;
		E3_dy <=  x2 - x1;
		E3_c  <=  x1*y2 - x2*y1;
		
		// Top-left rule bias
		//if (E1_dy > 0 || (E1_dy == 0 && E1_dx < 0)) E1_c <= E1_c + 1;
		//if (E2_dy > 0 || (E2_dy == 0 && E2_dx < 0)) E2_c <= E2_c + 1;
		//if (E3_dy > 0 || (E3_dy == 0 && E3_dx < 0)) E3_c <= E3_c + 1;

		// Signed triangle area (twice actual area)
		area <= (x2 - x1)*(y3 - y1) - (y2 - y1)*(x3 - x1);
	end
end

always @(posedge clock) begin
	if (!reset_n) begin
		E1 <= 0;
		E2 <= 0;
		E3 <= 0;
	end else begin
		E1 <= E1_dx * px + E1_dy * py + E1_c;
		E2 <= E2_dx * px + E2_dy * py + E2_c;
		E3 <= E3_dx * px + E3_dy * py + E3_c;
	end
end

endmodule
