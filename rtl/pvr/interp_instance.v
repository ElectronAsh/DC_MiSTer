`timescale 1ns / 1ps
`default_nettype none

module interp_instance (
    input [7:0] FRAC_BITS,  // Number of fractional bits for fixed-point calculations
    input wire signed [31:0] FDDX,  // Plane slope in X direction
    input wire signed [31:0] FDDY,  // Plane slope in Y direction
    input wire signed [47:0] FX1,   // Fixed-point X1 coordinate of the triangle
    input wire signed [47:0] FY1,   // Fixed-point Y1 coordinate of the triangle
    input wire signed [47:0] FZ1,   // Fixed-point Z1 value at vertex 1
    input wire signed [47:0] FZ2,   // Fixed-point Z2 value at vertex 2
    input wire signed [47:0] FZ3,   // Fixed-point Z3 value at vertex 3
    input wire signed [10:0] x_ps,  // Pixel's X coordinate
    input wire signed [10:0] y_ps,  // Pixel's Y coordinate

    output reg signed [31:0] interp, // Interpolated value at (x_ps, y_ps)

    output reg signed [31:0] interp0, interp1, interp2, interp3, interp4, interp5, interp6, interp7,
    output reg signed [31:0] interp8, interp9, interp10, interp11, interp12, interp13, interp14, interp15,
    output reg signed [31:0] interp16, interp17, interp18, interp19, interp20, interp21, interp22, interp23,
    output reg signed [31:0] interp24, interp25, interp26, interp27, interp28, interp29, interp30, interp31
);

// Intermediate signals
reg signed [47:0] FDDX_mult_FX1, FDDY_mult_FY1, c_term;
reg signed [47:0] FZ_combined;  // Weighted combination of FZ1, FZ2, FZ3
reg signed [47:0] y_mult_FDDY_plus_c;

always @(*) begin
	// Compute weighted FZ using barycentric coordinates or similar
	FZ_combined = (FZ1 + FZ2 + FZ3) / 3;

	// Compute c = (FZ_combined) - (FDDX * FX1 + FDDY * FY1)
	FDDX_mult_FX1 = (FDDX * FX1) >>> FRAC_BITS;
	FDDY_mult_FY1 = (FDDY * FY1) >>> FRAC_BITS;
	c_term = FZ_combined - FDDX_mult_FX1 - FDDY_mult_FY1;

	// Compute row-wise value (y_ps * FDDY + c)
	y_mult_FDDY_plus_c = (y_ps * FDDY) + c_term;

	// Compute interpolation for pixel (x_ps * FDDX + y_mult_FDDY_plus_c)
	interp = (x_ps * FDDX) + y_mult_FDDY_plus_c;

	// Interpolate for all 32 columns
	interp0 = ({x_ps[10:5], 5'd0} * FDDX) + y_mult_FDDY_plus_c;
	interp1 = interp0 + FDDX;
	interp2 = interp1 + FDDX;
	interp3 = interp2 + FDDX;
	interp4 = interp3 + FDDX;
	interp5 = interp4 + FDDX;
	interp6 = interp5 + FDDX;
	interp7 = interp6 + FDDX;
	interp8 = interp7 + FDDX;
	interp9 = interp8 + FDDX;
	interp10 = interp9 + FDDX;
	interp11 = interp10 + FDDX;
	interp12 = interp11 + FDDX;
	interp13 = interp12 + FDDX;
	interp14 = interp13 + FDDX;
	interp15 = interp14 + FDDX;

	interp16 = ({x_ps[10:5], 5'd16} * FDDX) + y_mult_FDDY_plus_c;
	interp17 = interp16 + FDDX;
	interp18 = interp17 + FDDX;
	interp19 = interp18 + FDDX;
	interp20 = interp19 + FDDX;
	interp21 = interp20 + FDDX;
	interp22 = interp21 + FDDX;
	interp23 = interp22 + FDDX;
	interp24 = interp23 + FDDX;
	interp25 = interp24 + FDDX;
	interp26 = interp25 + FDDX;
	interp27 = interp26 + FDDX;
	interp28 = interp27 + FDDX;
	interp29 = interp28 + FDDX;
	interp30 = interp29 + FDDX;
	interp31 = interp30 + FDDX;
end

endmodule
