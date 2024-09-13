`timescale 1ns / 1ps
`default_nettype none

module inTri_calc (
	input signed [47:0] C1, C2, C3, C4,

	input signed [47:0] FDX12, FDY12,
	input signed [47:0] FDX23, FDY23,
	input signed [47:0] FDX31, FDY31,
	input signed [47:0] FDX41, FDY41,

	input [10:0] x_ps, y_ps,

	output reg inTriangle,
	
	output reg [31:0] inTri,
	
    output reg [4:0] leading_zeros,
    output reg [4:0] trailing_zeros
);

// No need to shift right after, since y_ps etc. are not fixed-point.
wire signed [47:0] mult9  = FDX12 * y_ps;
wire signed [47:0] mult11 = FDX23 * y_ps;
wire signed [47:0] mult13 = FDX31 * y_ps;
wire signed [47:0] mult15 = FDX41 * y_ps;

//wire signed [47:0] mult10 = FDY12 * x_ps;
//wire signed [47:0] mult12 = FDY23 * x_ps;
//wire signed [47:0] mult14 = FDY31 * x_ps;
//wire signed [47:0] mult16 = FDY41 * x_ps;

wire signed [47:0] c1_sum_mult9  = C1 + mult9;
wire signed [47:0] c2_sum_mult11 = C2 + mult11;
wire signed [47:0] c3_sum_mult13 = C3 + mult13;
wire signed [47:0] c4_sum_mult15 = C4 + mult15;


// Single pixel at a time...
wire signed [47:0] Xhs12 = c1_sum_mult9  - (FDY12 * x_ps);
wire signed [47:0] Xhs23 = c2_sum_mult11 - (FDY23 * x_ps);
wire signed [47:0] Xhs31 = c3_sum_mult13 - (FDY31 * x_ps);
wire signed [47:0] Xhs41 = c4_sum_mult15 - (FDY41 * x_ps);
assign inTriangle = !Xhs12[47] && !Xhs23[47] && !Xhs31[47] && !Xhs41[47];


// 32 pixels at a time (a whole tile row)...
/*
wire [9:0] x_ps_0  = {x_ps[9:5], 5'd0};
wire [9:0] x_ps_1  = {x_ps[9:5], 5'd1};
wire [9:0] x_ps_2  = {x_ps[9:5], 5'd2};
wire [9:0] x_ps_3  = {x_ps[9:5], 5'd3};
wire [9:0] x_ps_4  = {x_ps[9:5], 5'd4};
wire [9:0] x_ps_5  = {x_ps[9:5], 5'd5};
wire [9:0] x_ps_6  = {x_ps[9:5], 5'd6};
wire [9:0] x_ps_7  = {x_ps[9:5], 5'd7};
wire [9:0] x_ps_8  = {x_ps[9:5], 5'd8};
wire [9:0] x_ps_9  = {x_ps[9:5], 5'd9};
wire [9:0] x_ps_10 = {x_ps[9:5], 5'd10};
wire [9:0] x_ps_11 = {x_ps[9:5], 5'd11};
wire [9:0] x_ps_12 = {x_ps[9:5], 5'd12};
wire [9:0] x_ps_13 = {x_ps[9:5], 5'd13};
wire [9:0] x_ps_14 = {x_ps[9:5], 5'd14};
wire [9:0] x_ps_15 = {x_ps[9:5], 5'd15};
wire [9:0] x_ps_16 = {x_ps[9:5], 5'd16};
wire [9:0] x_ps_17 = {x_ps[9:5], 5'd17};
wire [9:0] x_ps_18 = {x_ps[9:5], 5'd18};
wire [9:0] x_ps_19 = {x_ps[9:5], 5'd19};
wire [9:0] x_ps_20 = {x_ps[9:5], 5'd20};
wire [9:0] x_ps_21 = {x_ps[9:5], 5'd21};
wire [9:0] x_ps_22 = {x_ps[9:5], 5'd22};
wire [9:0] x_ps_23 = {x_ps[9:5], 5'd23};
wire [9:0] x_ps_24 = {x_ps[9:5], 5'd24};
wire [9:0] x_ps_25 = {x_ps[9:5], 5'd25};
wire [9:0] x_ps_26 = {x_ps[9:5], 5'd26};
wire [9:0] x_ps_27 = {x_ps[9:5], 5'd27};
wire [9:0] x_ps_28 = {x_ps[9:5], 5'd28};
wire [9:0] x_ps_29 = {x_ps[9:5], 5'd29};
wire [9:0] x_ps_30 = {x_ps[9:5], 5'd30};
wire [9:0] x_ps_31 = {x_ps[9:5], 5'd31};

wire signed [47:0] Xhs12_0 = c1_sum_mult9   - (FDY12 * x_ps_0);
wire signed [47:0] Xhs23_0 = c2_sum_mult11  - (FDY23 * x_ps_0);
wire signed [47:0] Xhs31_0 = c3_sum_mult13  - (FDY31 * x_ps_0);
//wire signed [47:0] Xhs41_0 = c4_sum_mult15  - (FDY41 * x_ps_0);
                                                                         
wire signed [47:0] Xhs12_1 = c1_sum_mult9   - (FDY12 * x_ps_1);
wire signed [47:0] Xhs23_1 = c2_sum_mult11  - (FDY23 * x_ps_1);
wire signed [47:0] Xhs31_1 = c3_sum_mult13  - (FDY31 * x_ps_1);
//wire signed [47:0] Xhs41_1 = c4_sum_mult15  - (FDY41 * x_ps_1);
                                                                         
wire signed [47:0] Xhs12_2 = c1_sum_mult9   - (FDY12 * x_ps_2);
wire signed [47:0] Xhs23_2 = c2_sum_mult11  - (FDY23 * x_ps_2);
wire signed [47:0] Xhs31_2 = c3_sum_mult13  - (FDY31 * x_ps_2);
//wire signed [47:0] Xhs41_2 = c4_sum_mult15  - (FDY41 * x_ps_2);
                                                                         
wire signed [47:0] Xhs12_3 = c1_sum_mult9   - (FDY12 * x_ps_3);
wire signed [47:0] Xhs23_3 = c2_sum_mult11  - (FDY23 * x_ps_3);
wire signed [47:0] Xhs31_3 = c3_sum_mult13  - (FDY31 * x_ps_3);
//wire signed [47:0] Xhs41_3 = c4_sum_mult15  - (FDY41 * x_ps_3);
                                                                         
wire signed [47:0] Xhs12_4 = c1_sum_mult9   - (FDY12 * x_ps_4);
wire signed [47:0] Xhs23_4 = c2_sum_mult11  - (FDY23 * x_ps_4);
wire signed [47:0] Xhs31_4 = c3_sum_mult13  - (FDY31 * x_ps_4);
//wire signed [47:0] Xhs41_4 = c4_sum_mult15  - (FDY41 * x_ps_4);
                                                                         
wire signed [47:0] Xhs12_5 = c1_sum_mult9   - (FDY12 * x_ps_5);
wire signed [47:0] Xhs23_5 = c2_sum_mult11  - (FDY23 * x_ps_5);
wire signed [47:0] Xhs31_5 = c3_sum_mult13  - (FDY31 * x_ps_5);
//wire signed [47:0] Xhs41_5 = c4_sum_mult15  - (FDY41 * x_ps_5);
                                                                         
wire signed [47:0] Xhs12_6 = c1_sum_mult9   - (FDY12 * x_ps_6);
wire signed [47:0] Xhs23_6 = c2_sum_mult11  - (FDY23 * x_ps_6);
wire signed [47:0] Xhs31_6 = c3_sum_mult13  - (FDY31 * x_ps_6);
//wire signed [47:0] Xhs41_6 = c4_sum_mult15  - (FDY41 * x_ps_6);
                                                                         
wire signed [47:0] Xhs12_7 = c1_sum_mult9   - (FDY12 * x_ps_7);
wire signed [47:0] Xhs23_7 = c2_sum_mult11  - (FDY23 * x_ps_7);
wire signed [47:0] Xhs31_7 = c3_sum_mult13  - (FDY31 * x_ps_7);
//wire signed [47:0] Xhs41_7 = c4_sum_mult15  - (FDY41 * x_ps_7);
                                                                         
wire signed [47:0] Xhs12_8 = c1_sum_mult9   - (FDY12 * x_ps_8);
wire signed [47:0] Xhs23_8 = c2_sum_mult11  - (FDY23 * x_ps_8);
wire signed [47:0] Xhs31_8 = c3_sum_mult13  - (FDY31 * x_ps_8);
//wire signed [47:0] Xhs41_8 = c4_sum_mult15  - (FDY41 * x_ps_8);
                                                                         
wire signed [47:0] Xhs12_9 = c1_sum_mult9   - (FDY12 * x_ps_9);
wire signed [47:0] Xhs23_9 = c2_sum_mult11  - (FDY23 * x_ps_9);
wire signed [47:0] Xhs31_9 = c3_sum_mult13  - (FDY31 * x_ps_9);
//wire signed [47:0] Xhs41_9 = c4_sum_mult15  - (FDY41 * x_ps_9);

wire signed [47:0] Xhs12_10 = c1_sum_mult9  - (FDY12 * x_ps_10);
wire signed [47:0] Xhs23_10 = c2_sum_mult11 - (FDY23 * x_ps_10);
wire signed [47:0] Xhs31_10 = c3_sum_mult13 - (FDY31 * x_ps_10);
//wire signed [47:0] Xhs41_10 = c4_sum_mult15 - (FDY41 * x_ps_10);
                                                                          
wire signed [47:0] Xhs12_11 = c1_sum_mult9  - (FDY12 * x_ps_11);
wire signed [47:0] Xhs23_11 = c2_sum_mult11 - (FDY23 * x_ps_11);
wire signed [47:0] Xhs31_11 = c3_sum_mult13 - (FDY31 * x_ps_11);
//wire signed [47:0] Xhs41_11 = c4_sum_mult15 - (FDY41 * x_ps_11);
                                                                          
wire signed [47:0] Xhs12_12 = c1_sum_mult9  - (FDY12 * x_ps_12);
wire signed [47:0] Xhs23_12 = c2_sum_mult11 - (FDY23 * x_ps_12);
wire signed [47:0] Xhs31_12 = c3_sum_mult13 - (FDY31 * x_ps_12);
//wire signed [47:0] Xhs41_12 = c4_sum_mult15 - (FDY41 * x_ps_12);
                                                                          
wire signed [47:0] Xhs12_13 = c1_sum_mult9  - (FDY12 * x_ps_13);
wire signed [47:0] Xhs23_13 = c2_sum_mult11 - (FDY23 * x_ps_13);
wire signed [47:0] Xhs31_13 = c3_sum_mult13 - (FDY31 * x_ps_13);
//wire signed [47:0] Xhs41_13 = c4_sum_mult15 - (FDY41 * x_ps_13);
                                                                          
wire signed [47:0] Xhs12_14 = c1_sum_mult9  - (FDY12 * x_ps_14);
wire signed [47:0] Xhs23_14 = c2_sum_mult11 - (FDY23 * x_ps_14);
wire signed [47:0] Xhs31_14 = c3_sum_mult13 - (FDY31 * x_ps_14);
//wire signed [47:0] Xhs41_14 = c4_sum_mult15 - (FDY41 * x_ps_14);
                                                                          
wire signed [47:0] Xhs12_15 = c1_sum_mult9  - (FDY12 * x_ps_15);
wire signed [47:0] Xhs23_15 = c2_sum_mult11 - (FDY23 * x_ps_15);
wire signed [47:0] Xhs31_15 = c3_sum_mult13 - (FDY31 * x_ps_15);
//wire signed [47:0] Xhs41_15 = c4_sum_mult15 - (FDY41 * x_ps_15);
                                                                          
wire signed [47:0] Xhs12_16 = c1_sum_mult9  - (FDY12 * x_ps_16);
wire signed [47:0] Xhs23_16 = c2_sum_mult11 - (FDY23 * x_ps_16);
wire signed [47:0] Xhs31_16 = c3_sum_mult13 - (FDY31 * x_ps_16);
//wire signed [47:0] Xhs41_16 = c4_sum_mult15 - (FDY41 * x_ps_16);
                                                                          
wire signed [47:0] Xhs12_17 = c1_sum_mult9  - (FDY12 * x_ps_17);
wire signed [47:0] Xhs23_17 = c2_sum_mult11 - (FDY23 * x_ps_17);
wire signed [47:0] Xhs31_17 = c3_sum_mult13 - (FDY31 * x_ps_17);
//wire signed [47:0] Xhs41_17 = c4_sum_mult15 - (FDY41 * x_ps_17);
                                                                          
wire signed [47:0] Xhs12_18 = c1_sum_mult9  - (FDY12 * x_ps_18);
wire signed [47:0] Xhs23_18 = c2_sum_mult11 - (FDY23 * x_ps_18);
wire signed [47:0] Xhs31_18 = c3_sum_mult13 - (FDY31 * x_ps_18);
//wire signed [47:0] Xhs41_18 = c4_sum_mult15 - (FDY41 * x_ps_18);
                                                                          
wire signed [47:0] Xhs12_19 = c1_sum_mult9  - (FDY12 * x_ps_19);
wire signed [47:0] Xhs23_19 = c2_sum_mult11 - (FDY23 * x_ps_19);
wire signed [47:0] Xhs31_19 = c3_sum_mult13 - (FDY31 * x_ps_19);
//wire signed [47:0] Xhs41_19 = c4_sum_mult15 - (FDY41 * x_ps_19);
                                                                          
wire signed [47:0] Xhs12_20 = c1_sum_mult9  - (FDY12 * x_ps_20);
wire signed [47:0] Xhs23_20 = c2_sum_mult11 - (FDY23 * x_ps_20);
wire signed [47:0] Xhs31_20 = c3_sum_mult13 - (FDY31 * x_ps_20);
//wire signed [47:0] Xhs41_20 = c4_sum_mult15 - (FDY41 * x_ps_20);
                                                                          
wire signed [47:0] Xhs12_21 = c1_sum_mult9  - (FDY12 * x_ps_21);
wire signed [47:0] Xhs23_21 = c2_sum_mult11 - (FDY23 * x_ps_21);
wire signed [47:0] Xhs31_21 = c3_sum_mult13 - (FDY31 * x_ps_21);
//wire signed [47:0] Xhs41_21 = c4_sum_mult15 - (FDY41 * x_ps_21);
                                                                          
wire signed [47:0] Xhs12_22 = c1_sum_mult9  - (FDY12 * x_ps_22);
wire signed [47:0] Xhs23_22 = c2_sum_mult11 - (FDY23 * x_ps_22);
wire signed [47:0] Xhs31_22 = c3_sum_mult13 - (FDY31 * x_ps_22);
//wire signed [47:0] Xhs41_22 = c4_sum_mult15 - (FDY41 * x_ps_22);
                                                                          
wire signed [47:0] Xhs12_23 = c1_sum_mult9  - (FDY12 * x_ps_23);
wire signed [47:0] Xhs23_23 = c2_sum_mult11 - (FDY23 * x_ps_23);
wire signed [47:0] Xhs31_23 = c3_sum_mult13 - (FDY31 * x_ps_23);
//wire signed [47:0] Xhs41_23 = c4_sum_mult15 - (FDY41 * x_ps_23);
                                                                          
wire signed [47:0] Xhs12_24 = c1_sum_mult9  - (FDY12 * x_ps_24);
wire signed [47:0] Xhs23_24 = c2_sum_mult11 - (FDY23 * x_ps_24);
wire signed [47:0] Xhs31_24 = c3_sum_mult13 - (FDY31 * x_ps_24);
//wire signed [47:0] Xhs41_24 = c4_sum_mult15 - (FDY41 * x_ps_24);
                                                                          
wire signed [47:0] Xhs12_25 = c1_sum_mult9  - (FDY12 * x_ps_25);
wire signed [47:0] Xhs23_25 = c2_sum_mult11 - (FDY23 * x_ps_25);
wire signed [47:0] Xhs31_25 = c3_sum_mult13 - (FDY31 * x_ps_25);
//wire signed [47:0] Xhs41_25 = c4_sum_mult15 - (FDY41 * x_ps_25);
                                                                          
wire signed [47:0] Xhs12_26 = c1_sum_mult9  - (FDY12 * x_ps_26);
wire signed [47:0] Xhs23_26 = c2_sum_mult11 - (FDY23 * x_ps_26);
wire signed [47:0] Xhs31_26 = c3_sum_mult13 - (FDY31 * x_ps_26);
//wire signed [47:0] Xhs41_26 = c4_sum_mult15 - (FDY41 * x_ps_26);
                                                                          
wire signed [47:0] Xhs12_27 = c1_sum_mult9  - (FDY12 * x_ps_27);
wire signed [47:0] Xhs23_27 = c2_sum_mult11 - (FDY23 * x_ps_27);
wire signed [47:0] Xhs31_27 = c3_sum_mult13 - (FDY31 * x_ps_27);
//wire signed [47:0] Xhs41_27 = c4_sum_mult15 - (FDY41 * x_ps_27);
                                                                          
wire signed [47:0] Xhs12_28 = c1_sum_mult9  - (FDY12 * x_ps_28);
wire signed [47:0] Xhs23_28 = c2_sum_mult11 - (FDY23 * x_ps_28);
wire signed [47:0] Xhs31_28 = c3_sum_mult13 - (FDY31 * x_ps_28);
//wire signed [47:0] Xhs41_28 = c4_sum_mult15 - (FDY41 * x_ps_28);
                                                                          
wire signed [47:0] Xhs12_29 = c1_sum_mult9  - (FDY12 * x_ps_29);
wire signed [47:0] Xhs23_29 = c2_sum_mult11 - (FDY23 * x_ps_29);
wire signed [47:0] Xhs31_29 = c3_sum_mult13 - (FDY31 * x_ps_29);
//wire signed [47:0] Xhs41_29 = c4_sum_mult15 - (FDY41 * x_ps_29);
                                                                          
wire signed [47:0] Xhs12_30 = c1_sum_mult9  - (FDY12 * x_ps_30);
wire signed [47:0] Xhs23_30 = c2_sum_mult11 - (FDY23 * x_ps_30);
wire signed [47:0] Xhs31_30 = c3_sum_mult13 - (FDY31 * x_ps_30);
//wire signed [47:0] Xhs41_30 = c4_sum_mult15 - (FDY41 * x_ps_30);
                                                                          
wire signed [47:0] Xhs12_31 = c1_sum_mult9  - (FDY12 * x_ps_31);
wire signed [47:0] Xhs23_31 = c2_sum_mult11 - (FDY23 * x_ps_31);
wire signed [47:0] Xhs31_31 = c3_sum_mult13 - (FDY31 * x_ps_31);
//wire signed [47:0] Xhs41_31 = c4_sum_mult15 - (FDY41 * x_ps_31);

always @* begin
	inTri[0]  = !Xhs12_0[47]  && !Xhs23_0[47]  && !Xhs31_0[47] ;// && !Xhs41_0[47];
	inTri[1]  = !Xhs12_1[47]  && !Xhs23_1[47]  && !Xhs31_1[47] ;// && !Xhs41_1[47];
	inTri[2]  = !Xhs12_2[47]  && !Xhs23_2[47]  && !Xhs31_2[47] ;// && !Xhs41_2[47];
	inTri[3]  = !Xhs12_3[47]  && !Xhs23_3[47]  && !Xhs31_3[47] ;// && !Xhs41_3[47];
	inTri[4]  = !Xhs12_4[47]  && !Xhs23_4[47]  && !Xhs31_4[47] ;// && !Xhs41_4[47];
	inTri[5]  = !Xhs12_5[47]  && !Xhs23_5[47]  && !Xhs31_5[47] ;// && !Xhs41_5[47];
	inTri[6]  = !Xhs12_6[47]  && !Xhs23_6[47]  && !Xhs31_6[47] ;// && !Xhs41_6[47];
	inTri[7]  = !Xhs12_7[47]  && !Xhs23_7[47]  && !Xhs31_7[47] ;// && !Xhs41_7[47];
	inTri[8]  = !Xhs12_8[47]  && !Xhs23_8[47]  && !Xhs31_8[47] ;// && !Xhs41_8[47];
	inTri[9]  = !Xhs12_9[47]  && !Xhs23_9[47]  && !Xhs31_9[47] ;// && !Xhs41_9[47];
	inTri[10] = !Xhs12_1[47]  && !Xhs23_1[47]  && !Xhs31_1[47] ;// && !Xhs41_1[47];
	inTri[11] = !Xhs12_11[47] && !Xhs23_11[47] && !Xhs31_11[47];// && !Xhs41_11[47];
	inTri[12] = !Xhs12_12[47] && !Xhs23_12[47] && !Xhs31_12[47];// && !Xhs41_12[47];
	inTri[13] = !Xhs12_13[47] && !Xhs23_13[47] && !Xhs31_13[47];// && !Xhs41_13[47];
	inTri[14] = !Xhs12_14[47] && !Xhs23_14[47] && !Xhs31_14[47];// && !Xhs41_14[47];
	inTri[15] = !Xhs12_15[47] && !Xhs23_15[47] && !Xhs31_15[47];// && !Xhs41_15[47];
	inTri[16] = !Xhs12_16[47] && !Xhs23_16[47] && !Xhs31_16[47];// && !Xhs41_16[47];
	inTri[17] = !Xhs12_17[47] && !Xhs23_17[47] && !Xhs31_17[47];// && !Xhs41_17[47];
	inTri[18] = !Xhs12_18[47] && !Xhs23_18[47] && !Xhs31_18[47];// && !Xhs41_18[47];
	inTri[19] = !Xhs12_19[47] && !Xhs23_19[47] && !Xhs31_19[47];// && !Xhs41_19[47];
	inTri[20] = !Xhs12_20[47] && !Xhs23_20[47] && !Xhs31_20[47];// && !Xhs41_20[47];
	inTri[21] = !Xhs12_21[47] && !Xhs23_21[47] && !Xhs31_21[47];// && !Xhs41_21[47];
	inTri[22] = !Xhs12_22[47] && !Xhs23_22[47] && !Xhs31_22[47];// && !Xhs41_22[47];
	inTri[23] = !Xhs12_23[47] && !Xhs23_23[47] && !Xhs31_23[47];// && !Xhs41_23[47];
	inTri[24] = !Xhs12_24[47] && !Xhs23_24[47] && !Xhs31_24[47];// && !Xhs41_24[47];
	inTri[25] = !Xhs12_25[47] && !Xhs23_25[47] && !Xhs31_25[47];// && !Xhs41_25[47];
	inTri[26] = !Xhs12_26[47] && !Xhs23_26[47] && !Xhs31_26[47];// && !Xhs41_26[47];
	inTri[27] = !Xhs12_27[47] && !Xhs23_27[47] && !Xhs31_27[47];// && !Xhs41_27[47];
	inTri[28] = !Xhs12_28[47] && !Xhs23_28[47] && !Xhs31_28[47];// && !Xhs41_28[47];
	inTri[29] = !Xhs12_29[47] && !Xhs23_29[47] && !Xhs31_29[47];// && !Xhs41_29[47];
	inTri[30] = !Xhs12_30[47] && !Xhs23_30[47] && !Xhs31_30[47];// && !Xhs41_30[47];
	inTri[31] = !Xhs12_31[47] && !Xhs23_31[47] && !Xhs31_31[47];// && !Xhs41_31[47];
	
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
*/

endmodule
