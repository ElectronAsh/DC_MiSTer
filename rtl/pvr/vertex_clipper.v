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

// Convert screen dimensions to fixed-point format
wire signed [47:0] max_width_fixed  = max_width  <<FRAC_BITS;
wire signed [47:0] max_height_fixed = max_height <<FRAC_BITS;
wire signed [47:0] zero = 0;

// Compute proper bounding box using signed comparisons
wire signed [47:0] min_x = (FX1 < FX2) ? ((FX1 < FX3) ? FX1 : FX3) : ((FX2 < FX3) ? FX2 : FX3);
wire signed [47:0] max_x = (FX1 > FX2) ? ((FX1 > FX3) ? FX1 : FX3) : ((FX2 > FX3) ? FX2 : FX3);
wire signed [47:0] min_y = (FY1 < FY2) ? ((FY1 < FY3) ? FY1 : FY3) : ((FY2 < FY3) ? FY2 : FY3);
wire signed [47:0] max_y = (FY1 > FY2) ? ((FY1 > FY3) ? FY1 : FY3) : ((FY2 > FY3) ? FY2 : FY3);

// Check if triangle is completely outside screen
// Triangle is visible if it overlaps with the screen [0, max_width_fixed] x [0, max_height_fixed]
always @* begin
    triangle_visible = !((max_x < zero) || (min_x > max_width_fixed) || 
                        (max_y < zero) || (min_y > max_height_fixed));
    
    // Clamp vertices to screen bounds
    FX1_clipped = (FX1 < zero) ? zero : ((FX1 > max_width_fixed)  ? max_width_fixed  : FX1);
    FY1_clipped = (FY1 < zero) ? zero : ((FY1 > max_height_fixed) ? max_height_fixed : FY1);
    
    FX2_clipped = (FX2 < zero) ? zero : ((FX2 > max_width_fixed)  ? max_width_fixed  : FX2);
    FY2_clipped = (FY2 < zero) ? zero : ((FY2 > max_height_fixed) ? max_height_fixed : FY2);
    
    FX3_clipped = (FX3 < zero) ? zero : ((FX3 > max_width_fixed)  ? max_width_fixed  : FX3);
    FY3_clipped = (FY3 < zero) ? zero : ((FY3 > max_height_fixed) ? max_height_fixed : FY3);
end

endmodule
