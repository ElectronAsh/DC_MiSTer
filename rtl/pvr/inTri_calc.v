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
    
    output wire [31:0] inTri,
    
    // Debug outputs for multiplication overflow checks
    output wire y1_mult_overflow,
    output wire y2_mult_overflow,
    output wire y3_mult_overflow,
    
    // Debug outputs for edge evaluations
    output wire [31:0] edge_eval0_overflow,
    output wire [31:0] edge_eval1_overflow,
    output wire [31:0] edge_eval2_overflow,
    
    // Debug outputs for final comparisons
    output wire [31:0] cross_term_overflow
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


// verilator lint_off UNOPTFLAT
wire signed [31:0] y_ps_fixed = (y_ps<<<FRAC_BITS);

// Multiplication results with overflow detection
wire signed [47:0] y1_mult_fx2 = (y_ps_fixed-FY1) * (FX2-FX1);
wire signed [47:0] y2_mult_fx3 = (y_ps_fixed-FY2) * (FX3-FX2);
wire signed [47:0] y3_mult_fx1 = (y_ps_fixed-FY3) * (FX1-FX3);

// Overflow detection for multiplications
assign y1_mult_overflow = ((y_ps_fixed-FY1) != 0 && (FX2-FX1) != 0) && 
                         (y1_mult_fx2/((y_ps_fixed-FY1)) != (FX2-FX1));
assign y2_mult_overflow = ((y_ps_fixed-FY2) != 0 && (FX3-FX2) != 0) && 
                         (y2_mult_fx3/((y_ps_fixed-FY2)) != (FX3-FX2));
assign y3_mult_overflow = ((y_ps_fixed-FY3) != 0 && (FX1-FX3) != 0) && 
                         (y3_mult_fx1/((y_ps_fixed-FY3)) != (FX1-FX3));

wire signed [63:0] cross_term2_p0 = y1_mult_fx2 >>>FRAC_BITS;
wire signed [63:0] cross_term2_p1 = y2_mult_fx3 >>>FRAC_BITS;
wire signed [63:0] cross_term2_p2 = y3_mult_fx1 >>>FRAC_BITS;

// Calculate edge vectors
wire signed [31:0] edge0_y = FY2-FY1;
wire signed [31:0] edge1_y = FY3-FY2;
wire signed [31:0] edge2_y = FY1-FY3;

wire signed [31:0] base_x = {x_ps[10:5],5'd0}<<<FRAC_BITS;

wire signed [63:0] edge_eval0 [0:32];
wire signed [63:0] edge_eval1 [0:32];
wire signed [63:0] edge_eval2 [0:32];

// Initial edge evaluations with overflow detection
assign edge_eval0[0] = ((base_x-FX1) * edge0_y) >>>FRAC_BITS;
assign edge_eval1[0] = ((base_x-FX2) * edge1_y) >>>FRAC_BITS;
assign edge_eval2[0] = ((base_x-FX3) * edge2_y) >>>FRAC_BITS;

genvar i;
generate
    for (i=0; i<32; i=i+1) begin : pixel_test
        assign edge_eval0[i+1] = edge_eval0[i] + edge0_y;
        assign edge_eval1[i+1] = edge_eval1[i] + edge1_y;
        assign edge_eval2[i+1] = edge_eval2[i] + edge2_y;
        
        // Overflow detection for edge evaluations
        assign edge_eval0_overflow[i] = (edge_eval0[i+1] < edge_eval0[i] && edge0_y > 0) || 
										(edge_eval0[i+1] > edge_eval0[i] && edge0_y < 0);
        assign edge_eval1_overflow[i] = (edge_eval1[i+1] < edge_eval1[i] && edge1_y > 0) || 
										(edge_eval1[i+1] > edge_eval1[i] && edge1_y < 0);
        assign edge_eval2_overflow[i] = (edge_eval2[i+1] < edge_eval2[i] && edge2_y > 0) || 
										(edge_eval2[i+1] > edge_eval2[i] && edge2_y < 0);
        
        // Overflow detection for cross terms
        assign cross_term_overflow[i] = ((edge_eval0[i] < cross_term2_p0 && edge_eval0[i] >= 0 && cross_term2_p0 < 0) ||
                                         (edge_eval1[i] < cross_term2_p1 && edge_eval1[i] >= 0 && cross_term2_p1 < 0) ||
                                         (edge_eval2[i] < cross_term2_p2 && edge_eval2[i] >= 0 && cross_term2_p2 < 0));
        
        assign inTri[i] = ((edge_eval0[i]-cross_term2_p0)>=0) && 
                          ((edge_eval1[i]-cross_term2_p1)>=0) && 
                          ((edge_eval2[i]-cross_term2_p2)>=0);
    end
endgenerate

// verilator lint_on UNOPTFLAT

endmodule
