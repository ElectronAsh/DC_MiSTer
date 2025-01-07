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


// Calculate signed area using cross product of two edges
wire signed [63:0] area = ((FX2_FIXED - FX1_FIXED) * (FY3_FIXED - FY1_FIXED)) - 
                          ((FY2_FIXED - FY1_FIXED) * (FX3_FIXED - FX1_FIXED));

wire sgn = area >= 0;

// Swap vertices if needed to ensure CW winding
wire signed [47:0] FX1 = FX1_FIXED;
wire signed [47:0] FY1 = FY1_FIXED;
wire signed [47:0] FX2 = sgn ? FX3_FIXED : FX2_FIXED;
wire signed [47:0] FY2 = sgn ? FY3_FIXED : FY2_FIXED;
wire signed [47:0] FX3 = sgn ? FX2_FIXED : FX3_FIXED;
wire signed [47:0] FY3 = sgn ? FY2_FIXED : FY3_FIXED;


// verilator lint_off UNOPTFLAT

// Precalcs...
//
// Triangle Vert input values are fixed, and should be stable one clock cycle before rendering.
//
// Similar for y_ps, since (screen pixel) Y stays the same for the current tile row,
// but we're calculating inTri for all 32 pixels in the tile row, so x_ps (screen pixel) X does change.
//
//wire signed [63:0] cross_term2_p0 = ((y_ps<<<FRAC_BITS) - FY1) * (FX2 - FX1);
//wire signed [63:0] cross_term2_p1 = ((y_ps<<<FRAC_BITS) - FY2) * (FX3 - FX2);
//wire signed [63:0] cross_term2_p2 = ((y_ps<<<FRAC_BITS) - FY3) * (FX1 - FX3);

wire signed [31:0] y_ps_fixed = (y_ps<<<FRAC_BITS);

wire signed [47:0] y1_mult_fx2 = (y_ps_fixed-FY1) * (FX2-FX1);
wire signed [47:0] y2_mult_fx3 = (y_ps_fixed-FY2) * (FX3-FX2);
wire signed [47:0] y3_mult_fx1 = (y_ps_fixed-FY3) * (FX1-FX3);

wire signed [31:0] cross_term2_p0 = y1_mult_fx2 >>>FRAC_BITS;
wire signed [31:0] cross_term2_p1 = y2_mult_fx3 >>>FRAC_BITS;
wire signed [31:0] cross_term2_p2 = y3_mult_fx1 >>>FRAC_BITS;

// Calculate edge vectors
wire signed [31:0] edge0_y = FY2-FY1;
wire signed [31:0] edge1_y = FY3-FY2;
wire signed [31:0] edge2_y = FY1-FY3;

wire signed [31:0] base_x = {x_ps[10:5],5'd0}<<<FRAC_BITS;

// Pre-calculate base values with explicit sign handling
wire signed [63:0] edge_eval0[0:32];
wire signed [63:0] edge_eval1[0:32];
wire signed [63:0] edge_eval2[0:32];

// Initial edge evaluations.
assign edge_eval0[0] = ((base_x-FX1) * edge0_y) >>>FRAC_BITS;
assign edge_eval1[0] = ((base_x-FX2) * edge1_y) >>>FRAC_BITS;
assign edge_eval2[0] = ((base_x-FX3) * edge2_y) >>>FRAC_BITS;

// Pre-calculate edge evaluations with cross terms included
wire signed [63:0] edge_eval0_adj[0:32];
wire signed [63:0] edge_eval1_adj[0:32];
wire signed [63:0] edge_eval2_adj[0:32];

// Initial values include cross terms
assign edge_eval0_adj[0] = edge_eval0[0] - cross_term2_p0;
assign edge_eval1_adj[0] = edge_eval1[0] - cross_term2_p1;
assign edge_eval2_adj[0] = edge_eval2[0] - cross_term2_p2;

genvar i;
generate
    for (i=0; i<32; i=i+1) begin : pixel_test
        // Simply add edge_y values - no subtractions needed per pixel
        assign edge_eval0_adj[i+1] = edge_eval0_adj[i] + edge0_y;
        assign edge_eval1_adj[i+1] = edge_eval1_adj[i] + edge1_y;
        assign edge_eval2_adj[i+1] = edge_eval2_adj[i] + edge2_y;
        
        // Direct comparison without subtractions
        assign inTri[i] = (edge_eval0_adj[i] >= 0) && 
                          (edge_eval1_adj[i] >= 0) && 
                          (edge_eval2_adj[i] >= 0);
    end
endgenerate

// verilator lint_on UNOPTFLAT

endmodule
