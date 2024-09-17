`timescale 1ns / 1ps
`default_nettype none

module inTri_calc (
	input signed [31:0] FX1, FX2, FX3, FX4,
	input signed [31:0] FY1, FY2, FY3, FY4,
	
	input is_quad_array,

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
//int C1 = FDY12 * FX1 - FDX12 * FY1;
wire signed [63:0] c1 = ((FDY12*FX1)>>FRAC_BITS) - ((FDX12*FY1)>>FRAC_BITS);
wire signed [63:0] c2 = ((FDY23*FX2)>>FRAC_BITS) - ((FDX23*FY2)>>FRAC_BITS);
wire signed [63:0] c3 = ((FDY31*FX3)>>FRAC_BITS) - ((FDX31*FY3)>>FRAC_BITS);
wire signed [63:0] c4 = ((FDY41*FX4)>>FRAC_BITS) - ((FDX41*FY4)>>FRAC_BITS);

wire signed [47:0] c1_plus_dx12_mult_yps =                     c1 + (FDX12 * y_ps);
wire signed [47:0] c2_plus_dx23_mult_yps =                     c2 + (FDX23 * y_ps);
wire signed [47:0] c3_plus_dx31_mult_yps =                     c3 + (FDX31 * y_ps);
wire signed [47:0] c4_plus_dx41_mult_yps = is_quad_array ? 0 : c4 + (FDX41 * y_ps);


// Single pixel at a time...
wire signed [47:0] Xhs12 = c1_plus_dx12_mult_yps - (FDY12 * x_ps);
wire signed [47:0] Xhs23 = c2_plus_dx23_mult_yps - (FDY23 * x_ps);
wire signed [47:0] Xhs31 = c3_plus_dx31_mult_yps - (FDY31 * x_ps);
wire signed [47:0] Xhs41 = c4_plus_dx41_mult_yps - (FDY41 * x_ps);
assign inTriangle = !Xhs12[47] && !Xhs23[47] && !Xhs31[47] && !Xhs41[47];



// 32 pixels at a time (a whole tile row)...
/*
wire signed [11:0] x_ps_0  = {1'b0, x_ps[10:5], 5'd0};
wire signed [11:0] x_ps_1  = {1'b0, x_ps[10:5], 5'd1};
wire signed [11:0] x_ps_2  = {1'b0, x_ps[10:5], 5'd2};
wire signed [11:0] x_ps_3  = {1'b0, x_ps[10:5], 5'd3};
wire signed [11:0] x_ps_4  = {1'b0, x_ps[10:5], 5'd4};
wire signed [11:0] x_ps_5  = {1'b0, x_ps[10:5], 5'd5};
wire signed [11:0] x_ps_6  = {1'b0, x_ps[10:5], 5'd6};
wire signed [11:0] x_ps_7  = {1'b0, x_ps[10:5], 5'd7};
wire signed [11:0] x_ps_8  = {1'b0, x_ps[10:5], 5'd8};
wire signed [11:0] x_ps_9  = {1'b0, x_ps[10:5], 5'd9};
wire signed [11:0] x_ps_10 = {1'b0, x_ps[10:5], 5'd10};
wire signed [11:0] x_ps_11 = {1'b0, x_ps[10:5], 5'd11};
wire signed [11:0] x_ps_12 = {1'b0, x_ps[10:5], 5'd12};
wire signed [11:0] x_ps_13 = {1'b0, x_ps[10:5], 5'd13};
wire signed [11:0] x_ps_14 = {1'b0, x_ps[10:5], 5'd14};
wire signed [11:0] x_ps_15 = {1'b0, x_ps[10:5], 5'd15};
wire signed [11:0] x_ps_16 = {1'b0, x_ps[10:5], 5'd16};
wire signed [11:0] x_ps_17 = {1'b0, x_ps[10:5], 5'd17};
wire signed [11:0] x_ps_18 = {1'b0, x_ps[10:5], 5'd18};
wire signed [11:0] x_ps_19 = {1'b0, x_ps[10:5], 5'd19};
wire signed [11:0] x_ps_20 = {1'b0, x_ps[10:5], 5'd20};
wire signed [11:0] x_ps_21 = {1'b0, x_ps[10:5], 5'd21};
wire signed [11:0] x_ps_22 = {1'b0, x_ps[10:5], 5'd22};
wire signed [11:0] x_ps_23 = {1'b0, x_ps[10:5], 5'd23};
wire signed [11:0] x_ps_24 = {1'b0, x_ps[10:5], 5'd24};
wire signed [11:0] x_ps_25 = {1'b0, x_ps[10:5], 5'd25};
wire signed [11:0] x_ps_26 = {1'b0, x_ps[10:5], 5'd26};
wire signed [11:0] x_ps_27 = {1'b0, x_ps[10:5], 5'd27};
wire signed [11:0] x_ps_28 = {1'b0, x_ps[10:5], 5'd28};
wire signed [11:0] x_ps_29 = {1'b0, x_ps[10:5], 5'd29};
wire signed [11:0] x_ps_30 = {1'b0, x_ps[10:5], 5'd30};
wire signed [11:0] x_ps_31 = {1'b0, x_ps[10:5], 5'd31};

always @(*) begin
	inTri[0]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_0) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_0) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_0) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_0))>=0;
	inTri[1]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_1) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_1) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_1) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_1))>=0;
	inTri[2]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_2) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_2) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_2) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_2))>=0;
	inTri[3]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_3) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_3) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_3) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_3))>=0;
	inTri[4]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_4) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_4) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_4) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_4))>=0;
	inTri[5]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_5) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_5) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_5) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_5))>=0;
	inTri[6]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_6) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_6) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_6) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_6))>=0;
	inTri[7]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_7) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_7) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_7) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_7))>=0;
	inTri[8]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_8) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_8) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_8) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_8))>=0;
	inTri[9]  = (c1_plus_dx12_mult_yps-(FDY12*x_ps_9) )>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_9) )>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_9) )>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_9))>=0;
	inTri[10] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_10))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_10))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_10))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_10))>=0;
	inTri[11] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_11))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_11))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_11))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_11))>=0;
	inTri[12] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_12))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_12))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_12))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_12))>=0;
	inTri[13] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_13))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_13))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_13))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_13))>=0;
	inTri[14] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_14))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_14))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_14))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_14))>=0;
	inTri[15] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_15))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_15))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_15))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_15))>=0;
	inTri[16] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_16))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_16))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_16))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_16))>=0;
	inTri[17] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_17))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_17))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_17))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_17))>=0;
	inTri[18] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_18))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_18))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_18))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_18))>=0;
	inTri[19] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_19))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_19))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_19))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_19))>=0;
	inTri[20] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_20))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_20))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_20))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_20))>=0;
	inTri[21] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_21))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_21))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_21))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_21))>=0;
	inTri[22] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_22))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_22))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_22))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_22))>=0;
	inTri[23] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_23))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_23))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_23))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_23))>=0;
	inTri[24] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_24))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_24))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_24))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_24))>=0;
	inTri[25] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_25))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_25))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_25))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_25))>=0;
	inTri[26] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_26))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_26))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_26))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_26))>=0;
	inTri[27] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_27))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_27))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_27))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_27))>=0;
	inTri[28] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_28))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_28))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_28))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_28))>=0;
	inTri[29] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_29))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_29))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_29))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_29))>=0;
	inTri[30] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_30))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_30))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_30))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_30))>=0;
	inTri[31] = (c1_plus_dx12_mult_yps-(FDY12*x_ps_31))>=0 && (c2_plus_dx23_mult_yps-(FDY23*x_ps_31))>=0 && (c3_plus_dx31_mult_yps-(FDY31*x_ps_31))>=0 && (c4_plus_dx41_mult_yps-(FDY41*x_ps_31))>=0;

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
