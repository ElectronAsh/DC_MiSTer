`timescale 1ns / 1ps
`default_nettype none

module shared_plane (
    input [7:0] FRAC_BITS, 	// Number of fractional bits for fixed-point calculations
    input wire signed [47:0] FX1, FX2, FX3,  // Fixed-point X coordinates
    input wire signed [47:0] FY1, FY2, FY3,  // Fixed-point Y coordinates
    output wire signed [31:0] FDDX,          // Plane slope in X direction
    output wire signed [31:0] FDDY           // Plane slope in Y direction
);

    // Differences in X and Y
    wire signed [47:0] DX12 = FX2 - FX1;
    wire signed [47:0] DY12 = FY2 - FY1;
    wire signed [47:0] DX13 = FX3 - FX1;
    wire signed [47:0] DY13 = FY3 - FY1;

    // Compute FDDX and FDDY using only the geometry
    assign FDDX = ((DX12 * DY13) >>>FRAC_BITS) - ((DY12 * DX13) >>>FRAC_BITS);
    assign FDDY = ((DY13 * DX12) >>>FRAC_BITS) - ((DX13 * DY12) >>>FRAC_BITS);

endmodule
