`timescale 1ns / 1ps
`default_nettype none

module vertex_clipper (
	input [7:0] FRAC_BITS,
    input signed [47:0] FX1, FY1,
    input signed [47:0] FX2, FY2,
    input signed [47:0] FX3, FY3,
    input [31:0] max_width,
    input [31:0] max_height,
    output reg signed [47:0] FX1_clipped, FY1_clipped,
    output reg signed [47:0] FX2_clipped, FY2_clipped,
    output reg signed [47:0] FX3_clipped, FY3_clipped,
    output reg triangle_visible
);

wire [46:0] FX1_MAG = (FX1[47]) ? ~FX1[46:0] : FX1[46:0];
wire [46:0] FY1_MAG = (FY1[47]) ? ~FY1[46:0] : FY1[46:0];

wire [46:0] FX2_MAG = (FX2[47]) ? ~FX2[46:0] : FX2[46:0];
wire [46:0] FY2_MAG = (FY2[47]) ? ~FY2[46:0] : FY2[46:0];

wire [46:0] FX3_MAG = (FX3[47]) ? ~FX3[46:0] : FX3[46:0];
wire [46:0] FY3_MAG = (FY3[47]) ? ~FY3[46:0] : FY3[46:0];

wire signed [47:0] max_width_fixed  = max_width  << FRAC_BITS;
wire signed [47:0] max_height_fixed = max_height << FRAC_BITS;

// Compute bounding box
wire [46:0] min_x = (FX1_MAG < FX2_MAG) ? ((FX1_MAG < FX3_MAG) ? FX1_MAG : FX3_MAG) : ((FX2_MAG < FX3_MAG) ? FX2_MAG : FX3_MAG);
wire [46:0] max_x = (FX1_MAG > FX2_MAG) ? ((FX1_MAG > FX3_MAG) ? FX1_MAG : FX3_MAG) : ((FX2_MAG > FX3_MAG) ? FX2_MAG : FX3_MAG);
wire [46:0] min_y = (FY1_MAG < FY2_MAG) ? ((FY1_MAG < FY3_MAG) ? FY1_MAG : FY3_MAG) : ((FY2_MAG < FY3_MAG) ? FY2_MAG : FY3_MAG);
wire [46:0] max_y = (FY1_MAG > FY2_MAG) ? ((FY1_MAG > FY3_MAG) ? FY1_MAG : FY3_MAG) : ((FY2_MAG > FY3_MAG) ? FY2_MAG : FY3_MAG);

// Check if triangle is completely outside screen
always @* begin
    triangle_visible = (min_x > 0 && max_x < max_width_fixed && min_y > 0 && max_y < max_height_fixed);
                        
    // Clamp vertices to screen bounds
    FX1_clipped = (FX1 < 0) ? 0 : ((FX1 > max_width_fixed)  ? max_width_fixed  : FX1);
    FY1_clipped = (FY1 < 0) ? 0 : ((FY1 > max_height_fixed) ? max_height_fixed : FY1);
    
    FX2_clipped = (FX2 < 0) ? 0 : ((FX2 > max_width_fixed)  ? max_width_fixed  : FX2);
    FY2_clipped = (FY2 < 0) ? 0 : ((FY2 > max_height_fixed) ? max_height_fixed : FY2);
    
    FX3_clipped = (FX3 < 0) ? 0 : ((FX3 > max_width_fixed)  ? max_width_fixed  : FX3);
    FY3_clipped = (FY3 < 0) ? 0 : ((FY3 > max_height_fixed) ? max_height_fixed : FY3);
end

endmodule
