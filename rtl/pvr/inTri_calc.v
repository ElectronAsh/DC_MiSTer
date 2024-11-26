`timescale 1ns / 1ps
`default_nettype none

module inTri_calc (
	input signed [31:0] FX1, FY1,
	input signed [31:0] FX2, FY2,
	input signed [31:0] FX3, FY3,

	input [10:0] x_ps,
	input [10:0] y_ps,

	output wire inTriangle,
	
	output reg [31:0] inTri,
	
    output reg [4:0] leading_zeros,
    output reg [4:0] trailing_zeros
);

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

always @* begin	
		 if (inTri[30:00]==0) leading_zeros = 31;
	else if (inTri[29:00]==0) leading_zeros = 30;
	else if (inTri[28:00]==0) leading_zeros = 29;
	else if (inTri[27:00]==0) leading_zeros = 28;
	else if (inTri[26:00]==0) leading_zeros = 27;
	else if (inTri[25:00]==0) leading_zeros = 26;
	else if (inTri[24:00]==0) leading_zeros = 25;
	else if (inTri[23:00]==0) leading_zeros = 24;
	else if (inTri[22:00]==0) leading_zeros = 23;
	else if (inTri[21:00]==0) leading_zeros = 22;
	else if (inTri[20:00]==0) leading_zeros = 21;
	else if (inTri[19:00]==0) leading_zeros = 20;
	else if (inTri[18:00]==0) leading_zeros = 19;
	else if (inTri[17:00]==0) leading_zeros = 18;
	else if (inTri[16:00]==0) leading_zeros = 17;
	else if (inTri[15:00]==0) leading_zeros = 16;
	else if (inTri[14:00]==0) leading_zeros = 15;
	else if (inTri[13:00]==0) leading_zeros = 14;
	else if (inTri[12:00]==0) leading_zeros = 13;
	else if (inTri[11:00]==0) leading_zeros = 12;
	else if (inTri[10:00]==0) leading_zeros = 11;
	else if (inTri[09:00]==0) leading_zeros = 10;
	else if (inTri[08:00]==0) leading_zeros = 9;
	else if (inTri[07:00]==0) leading_zeros = 8;
	else if (inTri[06:00]==0) leading_zeros = 7;
	else if (inTri[05:00]==0) leading_zeros = 6;
	else if (inTri[04:00]==0) leading_zeros = 5;
	else if (inTri[03:00]==0) leading_zeros = 4;
	else if (inTri[02:00]==0) leading_zeros = 3;
	else if (inTri[01:00]==0) leading_zeros = 2;
	else if (inTri[00:00]==0) leading_zeros = 1;
	else leading_zeros = 0;
	
		 if (inTri[31:01]==0) trailing_zeros = 31;
	else if (inTri[31:02]==0) trailing_zeros = 30;
	else if (inTri[31:03]==0) trailing_zeros = 29;
	else if (inTri[31:04]==0) trailing_zeros = 28;
	else if (inTri[31:05]==0) trailing_zeros = 27;
	else if (inTri[31:06]==0) trailing_zeros = 26;
	else if (inTri[31:07]==0) trailing_zeros = 25;
	else if (inTri[31:08]==0) trailing_zeros = 24;
	else if (inTri[31:09]==0) trailing_zeros = 23;
	else if (inTri[31:10]==0) trailing_zeros = 22;
	else if (inTri[31:11]==0) trailing_zeros = 21;
	else if (inTri[31:12]==0) trailing_zeros = 20;
	else if (inTri[31:13]==0) trailing_zeros = 19;
	else if (inTri[31:14]==0) trailing_zeros = 18;
	else if (inTri[31:15]==0) trailing_zeros = 17;
	else if (inTri[31:16]==0) trailing_zeros = 16;
	else if (inTri[31:17]==0) trailing_zeros = 15;
	else if (inTri[31:18]==0) trailing_zeros = 14;
	else if (inTri[31:19]==0) trailing_zeros = 13;
	else if (inTri[31:20]==0) trailing_zeros = 12;
	else if (inTri[31:21]==0) trailing_zeros = 11;
	else if (inTri[31:22]==0) trailing_zeros = 10;
	else if (inTri[31:23]==0) trailing_zeros = 9;
	else if (inTri[31:24]==0) trailing_zeros = 8;
	else if (inTri[31:25]==0) trailing_zeros = 7;
	else if (inTri[31:26]==0) trailing_zeros = 6;
	else if (inTri[31:27]==0) trailing_zeros = 5;
	else if (inTri[31:28]==0) trailing_zeros = 4;
	else if (inTri[31:29]==0) trailing_zeros = 3;
	else if (inTri[31:30]==0) trailing_zeros = 2;
	else if (inTri[31:31]==0) trailing_zeros = 1;
	else trailing_zeros = 0;
end

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
wire signed [63:0] edge_eval0[32:0];
wire signed [63:0] edge_eval1[32:0];
wire signed [63:0] edge_eval2[32:0];

// Calculate first values
assign edge_eval0[0] = $signed(base_dx0) * $signed(edge0_y);
assign edge_eval1[0] = $signed(base_dx1) * $signed(edge1_y);
assign edge_eval2[0] = $signed(base_dx2) * $signed(edge2_y);

wire [31:0] inedge_a;
wire [31:0] inedge_b;
wire [31:0] inedge_c;

genvar i;
generate
    for (i = 1; i < 33; i = i + 1) begin : pixel_test
        // Ensure signed addition for each step
        assign edge_eval0[i] = $signed(edge_eval0[i-1]) + $signed(edge0_step);
        assign edge_eval1[i] = $signed(edge_eval1[i-1]) + $signed(edge1_step);
        assign edge_eval2[i] = $signed(edge_eval2[i-1]) + $signed(edge2_step);
        
        // Compare with cross terms using signed comparison
        assign inedge_a[i-1] = $signed(edge_eval0[i]) - $signed(cross_term2_p0) >= 0;
        assign inedge_b[i-1] = $signed(edge_eval1[i]) - $signed(cross_term2_p1) >= 0;
        assign inedge_c[i-1] = $signed(edge_eval2[i]) - $signed(cross_term2_p2) >= 0;
        
        assign inTri[i-1] = inedge_a[i-1] && inedge_b[i-1] && inedge_c[i-1];
    end
endgenerate

// verilator lint_on UNOPTFLAT

endmodule
