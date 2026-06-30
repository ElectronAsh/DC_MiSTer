`timescale 1ns / 1ps
`default_nettype none

module z_span_32
#(
    parameter [7:0] Z_FRAC_BITS = 8'd17
)
(
    input wire clock,
	input wire reset_n,

    input wire z_span_start,
    input wire signed [15:0] y_ps_in,
    input wire signed [39:0] FDDX,
    input wire signed [39:0] FDDY,
    input wire signed [47:0] small_c,

    output reg z_span_valid,
    output reg signed [15:0] y_ps_out,
    output reg signed [47:0] z_col [0:31]
);


// Stage 1 (was stage 1 after old stage 0 capture; stage 0 removed).
// Compute: base(y) = small_c + y*FDDY.
// FDDX/FDDY/small_c are stable throughout HSR so no capture gate needed.
reg signed [15:0] y_ps_s1;
reg signed [39:0] FDDX_s1;
reg signed [63:0] y_mul_ddy_s1;
reg signed [47:0] small_c_s1;
reg valid_s1;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	valid_s1 <= 1'b0;
end
else begin
    valid_s1 <= z_span_start;
    y_ps_s1  <= y_ps_in;
    FDDX_s1  <= FDDX;
    small_c_s1 <= small_c;
    y_mul_ddy_s1 <= y_ps_in * FDDY;
end


// Stage 2 (Generate bank bases).
reg signed [15:0] y_ps_s2;

reg signed [39:0] FDDX_s2;

reg signed [47:0] base0_s2;
reg signed [47:0] base8_s2;
reg signed [47:0] base16_s2;
reg signed [47:0] base24_s2;

reg valid_s2;

wire signed [47:0] row_base_s2 = small_c_s1 + y_mul_ddy_s1;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	valid_s2 <= 1'b0;
end
else begin
    valid_s2 <= valid_s1;

	y_ps_s2 <= y_ps_s1;
    FDDX_s2 <= FDDX_s1;

    base0_s2  <= row_base_s2;
    base8_s2  <= row_base_s2 + (FDDX_s1 <<< 3);
    base16_s2 <= row_base_s2 + (FDDX_s1 <<< 4);
    base24_s2 <= row_base_s2 + (FDDX_s1 <<< 4) + (FDDX_s1 <<< 3);
end


// Stage 3 (Generate first half of each bank).
reg signed [15:0] y_ps_s3;
reg signed [39:0] FDDX_s3;
reg signed [47:0] z_mid [0:31];

reg valid_s3;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	valid_s3 <= 1'b0;
end
else begin
    valid_s3 <= valid_s2;
    y_ps_s3 <= y_ps_s2;
    FDDX_s3 <= FDDX_s2;

    //
    // Bank 0
    //
    z_mid[0] <= base0_s2;
    z_mid[1] <= base0_s2 + FDDX_s2;
    z_mid[2] <= base0_s2 + (FDDX_s2 <<< 1);
    z_mid[3] <= base0_s2 + ((FDDX_s2 <<< 1) + FDDX_s2);

    //
    // Bank 1
    //
    z_mid[8]  <= base8_s2;
    z_mid[9]  <= base8_s2 + FDDX_s2;
    z_mid[10] <= base8_s2 + (FDDX_s2 <<< 1);
    z_mid[11] <= base8_s2 + ((FDDX_s2 <<< 1) + FDDX_s2);

    //
    // Bank 2
    //
    z_mid[16] <= base16_s2;
    z_mid[17] <= base16_s2 + FDDX_s2;
    z_mid[18] <= base16_s2 + (FDDX_s2 <<< 1);
    z_mid[19] <= base16_s2 + ((FDDX_s2 <<< 1) + FDDX_s2);

    //
    // Bank 3
    //
    z_mid[24] <= base24_s2;
    z_mid[25] <= base24_s2 + FDDX_s2;
    z_mid[26] <= base24_s2 + (FDDX_s2 <<< 1);
    z_mid[27] <= base24_s2 + ((FDDX_s2 <<< 1) + FDDX_s2);
end


// Stage 4 (Generate complete row and outputs).
always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	z_span_valid <= 1'b0;
end
else begin
    z_span_valid <= valid_s3;
    y_ps_out <= y_ps_s3;

    //
    // Bank 0
    //
    z_col[0] <= z_mid[0];
    z_col[1] <= z_mid[1];
    z_col[2] <= z_mid[2];
    z_col[3] <= z_mid[3];

    z_col[4] <= z_mid[3] + FDDX_s3;
    z_col[5] <= z_mid[3] + (FDDX_s3 <<< 1);
    z_col[6] <= z_mid[3] + ((FDDX_s3 <<< 1) + FDDX_s3);
    z_col[7] <= z_mid[3] + (FDDX_s3 <<< 2);

    //
    // Bank 1
    //
    z_col[8]  <= z_mid[8];
    z_col[9]  <= z_mid[9];
    z_col[10] <= z_mid[10];
    z_col[11] <= z_mid[11];

    z_col[12] <= z_mid[11] + FDDX_s3;
    z_col[13] <= z_mid[11] + (FDDX_s3 <<< 1);
    z_col[14] <= z_mid[11] + ((FDDX_s3 <<< 1) + FDDX_s3);
    z_col[15] <= z_mid[11] + (FDDX_s3 <<< 2);

    //
    // Bank 2
    //
    z_col[16] <= z_mid[16];
    z_col[17] <= z_mid[17];
    z_col[18] <= z_mid[18];
    z_col[19] <= z_mid[19];

    z_col[20] <= z_mid[19] + FDDX_s3;
    z_col[21] <= z_mid[19] + (FDDX_s3 <<< 1);
    z_col[22] <= z_mid[19] + ((FDDX_s3 <<< 1) + FDDX_s3);
    z_col[23] <= z_mid[19] + (FDDX_s3 <<< 2);

    //
    // Bank 3
    //
    z_col[24] <= z_mid[24];
    z_col[25] <= z_mid[25];
    z_col[26] <= z_mid[26];
    z_col[27] <= z_mid[27];

    z_col[28] <= z_mid[27] + FDDX_s3;
    z_col[29] <= z_mid[27] + (FDDX_s3 <<< 1);
    z_col[30] <= z_mid[27] + ((FDDX_s3 <<< 1) + FDDX_s3);
    z_col[31] <= z_mid[27] + (FDDX_s3 <<< 2);
end


endmodule
