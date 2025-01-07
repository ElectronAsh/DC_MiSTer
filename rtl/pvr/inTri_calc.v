`timescale 1ns / 1ps
`default_nettype none

module inTri_calc (
    input signed [47:0] FX1_FIXED,
    input signed [47:0] FY1_FIXED,
    
    input signed [47:0] FX2_FIXED,
    input signed [47:0] FY2_FIXED,
    
    input signed [47:0] FX3_FIXED,
    input signed [47:0] FY3_FIXED,
    input [10:0] x_ps,
    input [10:0] y_ps,
	 
    output wire inTriangle,
    
    output wire [31:0] inTri
);

// Vertex deltas...
/*
wire signed [47:0] FDX12_FIXED = (sgn) ? (FX1_FIXED - FX2_FIXED) : (FX2_FIXED - FX1_FIXED);
wire signed [47:0] FDX23_FIXED = (sgn) ? (FX2_FIXED - FX3_FIXED) : (FX3_FIXED - FX2_FIXED);
wire signed [47:0] FDX31_FIXED = (is_quad_array) ? sgn ? (FX3_FIXED - FX4_FIXED) : (FX4_FIXED - FX3_FIXED) : sgn ? (FX3_FIXED - FX1_FIXED) : (FX1_FIXED - FX3_FIXED);
wire signed [47:0] FDX41_FIXED = (is_quad_array) ? sgn ? (FX4_FIXED - FX1_FIXED) : (FX1_FIXED - FX4_FIXED) : 0;

wire signed [47:0] FDY12_FIXED = sgn ? (FY1_FIXED - FY2_FIXED) : (FY2_FIXED - FY1_FIXED);
wire signed [47:0] FDY23_FIXED = sgn ? (FY2_FIXED - FY3_FIXED) : (FY3_FIXED - FY2_FIXED);
wire signed [47:0] FDY31_FIXED = (is_quad_array) ? sgn ? (FY3_FIXED - FY4_FIXED) : (FY4_FIXED - FY3_FIXED) : sgn ? (FY3_FIXED - FY1_FIXED) : (FY1_FIXED - FY3_FIXED);
wire signed [47:0] FDY41_FIXED = (is_quad_array) ? sgn ? (FY4_FIXED - FY1_FIXED) : (FY1_FIXED - FY4_FIXED) : 0;
*/

wire signed [47:0] f_area = ((FX1_FIXED-FX3_FIXED) * (FY2_FIXED-FY3_FIXED)) - ((FY1_FIXED-FY3_FIXED) * (FX2_FIXED-FX3_FIXED));
wire sgn = (f_area<=0);

wire signed [47:0] FX1 = sgn ? FX1_FIXED : FX3_FIXED;
wire signed [47:0] FY1 = sgn ? FY1_FIXED : FY3_FIXED;

wire signed [47:0] FX2 = sgn ? FX2_FIXED : FX2_FIXED;	// Seems to (mostly) work for the new inTri calc for now, but needs investigating.
wire signed [47:0] FY2 = sgn ? FY2_FIXED : FY2_FIXED;	// ?

//wire signed [31:0] FX3_SWAP = is_quad_array ? sgn ? FX3_FIXED : FX4_FIXED : sgn ? FX3_FIXED : FX1_FIXED;
//wire signed [31:0] FY3_SWAP = is_quad_array ? sgn ? FY3_FIXED : FY4_FIXED : sgn ? FY3_FIXED : FY1_FIXED;
wire signed [47:0] FX3 = sgn ? FX3_FIXED : FX1_FIXED;
wire signed [47:0] FY3 = sgn ? FY3_FIXED : FY1_FIXED;


tri_vis  tri_vis_inst (
	// Screen-space pixel coordinates (integer values)
	.x_ps( x_ps ), 		// input [10:0] X coord
	.y_ps( y_ps ), 		// input [10:0] Y coord
	
	// Fixed point format: 16.16 (16 bits integer, 16 bits fractional)
	.FX1( FX1 ),	// input [31:0]  Triangle vertex 0
	.FY1( FY1 ), 		
	
	.FX2( FX2 ),	// input [31:0]  Triangle vertex 1
	.FY2( FY2 ), 		

	.FX3( FX3 ),	// input [31:0]  Triangle vertex 2
	.FY3( FY3 ), 		
	
	.inTri( inTri )	// output [31:0]  inTri (one bit per each pixel in a span).
);

endmodule


module tri_vis (
	// Screen-space pixel coordinates (integer values)
	input wire signed [10:0] x_ps, 	// X coord
	input wire signed [10:0] y_ps, 	// Y coord
	
	// Fixed point format: 16.16 (16 bits integer, 16 bits fractional)
	input wire signed [31:0] FX1, FY1, // Triangle vertex 0
	input wire signed [31:0] FX2, FY2, // Triangle vertex 1
	input wire signed [31:0] FX3, FY3, // Triangle vertex 2
	
	// 1 bit per pixel indicating if it's inside triangle
	output wire [31:0] inTri
);

// verilator lint_off UNOPTFLAT

// Precalcs...
//
// Triangle Vert input values are fixed, and should be stable one clock cycle before rendering.
//
// Similar for y_ps, since (screen pixel) Y stays the same for the current tile row,
// but we're calculating inTri for all 32 pixels in the tile row, so x_ps (screen pixel) X does change.
//
wire signed [63:0] cross_term2_p0 = ((y_ps<<<FRAC_BITS) - FY1) * (FX2 - FX1);
wire signed [63:0] cross_term2_p1 = ((y_ps<<<FRAC_BITS) - FY2) * (FX3 - FX2);
wire signed [63:0] cross_term2_p2 = ((y_ps<<<FRAC_BITS) - FY3) * (FX1 - FX3);

// Calculate edge vectors
// (deltas of triangle Y verts.)
wire signed [31:0] edge0_y = FY2 - FY1;
wire signed [31:0] edge1_y = FY3 - FY2;
wire signed [31:0] edge2_y = FY1 - FY3;

// Ensure step values are properly sign extended when shifted 
wire signed [47:0] edge0_step = $signed(edge0_y) <<< FRAC_BITS;
wire signed [47:0] edge1_step = $signed(edge1_y) <<< FRAC_BITS;
wire signed [47:0] edge2_step = $signed(edge2_y) <<< FRAC_BITS;

// Generate 32 parallel edge function evaluators
// Pre-calculate base values outside generate block
wire signed [31:0] base_dx0 = ({x_ps[10:5],5'd0} <<< FRAC_BITS) - FX1;
wire signed [31:0] base_dx1 = ({x_ps[10:5],5'd0} <<< FRAC_BITS) - FX2;
wire signed [31:0] base_dx2 = ({x_ps[10:5],5'd0} <<< FRAC_BITS) - FX3;

// Pre-calculate base values with explicit sign handling
wire signed [63:0] edge_eval0[0:32];
wire signed [63:0] edge_eval1[0:32];
wire signed [63:0] edge_eval2[0:32];

// Calculate first values
assign edge_eval0[0] = $signed(base_dx0) * $signed(edge0_y);
assign edge_eval1[0] = $signed(base_dx1) * $signed(edge1_y);
assign edge_eval2[0] = $signed(base_dx2) * $signed(edge2_y);

wire [31:0] inedge_a;
wire [31:0] inedge_b;
wire [31:0] inedge_c;

genvar i;
generate
    for (i=0; i<32; i=i+1) begin : pixel_test
        // Ensure signed addition for each step
        assign edge_eval0[i+1] = $signed(edge_eval0[i]) + $signed(edge0_step);
        assign edge_eval1[i+1] = $signed(edge_eval1[i]) + $signed(edge1_step);
        assign edge_eval2[i+1] = $signed(edge_eval2[i]) + $signed(edge2_step);
        
        // Compare with cross terms using signed comparison
        assign inedge_a[i] = $signed(edge_eval0[i]) - $signed(cross_term2_p0) >= 0;
        assign inedge_b[i] = $signed(edge_eval1[i]) - $signed(cross_term2_p1) >= 0;
        assign inedge_c[i] = $signed(edge_eval2[i]) - $signed(cross_term2_p2) >= 0;
        
        assign inTri[i] = inedge_a[i] && inedge_b[i] && inedge_c[i];
    end
endgenerate

// verilator lint_on UNOPTFLAT

endmodule
