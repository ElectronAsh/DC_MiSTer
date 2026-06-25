`timescale 1ns / 1ps
`default_nettype none

module interp_params #(
    parameter [7:0] FRAC_BITS   = 8'd12,
    parameter [7:0] Z_FRAC_BITS = 8'd17,
    parameter [7:0] FRAC_DIFF   = Z_FRAC_BITS - FRAC_BITS
)(
	input reset_n,
    input clock,
	
    input  wire [3:0] interp_sel_in,
    input start_interp,

    input signed [47:0] FY2_sub_FY1,
    input signed [47:0] FY3_sub_FY1,
    input signed [47:0] FX2_sub_FX1,
    input signed [47:0] FX3_sub_FX1,

    input signed [47:0] FX1,
    input signed [47:0] FY1,

    input signed [63:0] BIG_C,

    input signed [47:0] FZ1,
    input signed [47:0] FZ2,
    input signed [47:0] FZ3,

    output reg signed [47:0] FDDX,
    output reg signed [47:0] FDDY,
    output reg signed [47:0] small_c,
	
    output reg  [3:0] interp_sel_out,
    output reg interp_valid
);

//
// ------------------------------------------------------------------------
// Stage 0 : Input capture
// ------------------------------------------------------------------------
//
reg signed [47:0] FY2_sub_FY1_cap;
reg signed [47:0] FY3_sub_FY1_cap;
reg signed [47:0] FX2_sub_FX1_cap;
reg signed [47:0] FX3_sub_FX1_cap;

reg signed [47:0] FX1_cap;
reg signed [47:0] FY1_cap;

reg signed [63:0] BIG_C_cap;

reg signed [47:0] FZ1_cap;
reg signed [47:0] FZ2_cap;
reg signed [47:0] FZ3_cap;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
        FY2_sub_FY1_cap <= 48'sd0;
        FY3_sub_FY1_cap <= 48'sd0;
        FX2_sub_FX1_cap <= 48'sd0;
        FX3_sub_FX1_cap <= 48'sd0;
        FX1_cap <= 48'sd0;
        FY1_cap <= 48'sd0;
        BIG_C_cap <= 64'sd0;
        FZ1_cap <= 48'sd0;
        FZ2_cap <= 48'sd0;
        FZ3_cap <= 48'sd0;
end
else begin
    if (start_interp) begin
        FY2_sub_FY1_cap <= FY2_sub_FY1;
        FY3_sub_FY1_cap <= FY3_sub_FY1;

        FX2_sub_FX1_cap <= FX2_sub_FX1;
        FX3_sub_FX1_cap <= FX3_sub_FX1;

        FX1_cap <= FX1;
        FY1_cap <= FY1;

        BIG_C_cap <= BIG_C;

        FZ1_cap <= FZ1;
        FZ2_cap <= FZ2;
        FZ3_cap <= FZ3;
    end
end

//
// ------------------------------------------------------------------------
// Stage 1 : Z deltas
// ------------------------------------------------------------------------
//
reg signed [47:0] FZ2_sub_FZ1_r;
reg signed [47:0] FZ3_sub_FZ1_r;

reg signed [47:0] FX1_s1;
reg signed [47:0] FY1_s1;
reg signed [47:0] FZ1_s1;
reg signed [47:0] FY2_sub_FY1_s1;
reg signed [47:0] FY3_sub_FY1_s1;
reg signed [47:0] FX2_sub_FX1_s1;
reg signed [47:0] FX3_sub_FX1_s1;
reg signed [63:0] BIG_C_s1;

always @(posedge clock) begin
    FZ2_sub_FZ1_r <= FZ2_cap - FZ1_cap;
    FZ3_sub_FZ1_r <= FZ3_cap - FZ1_cap;
    FX1_s1 <= FX1_cap;
    FY1_s1 <= FY1_cap;
    FZ1_s1 <= FZ1_cap;
    FY2_sub_FY1_s1 <= FY2_sub_FY1_cap;
    FY3_sub_FY1_s1 <= FY3_sub_FY1_cap;
    FX2_sub_FX1_s1 <= FX2_sub_FX1_cap;
    FX3_sub_FX1_s1 <= FX3_sub_FX1_cap;
    BIG_C_s1 <= BIG_C_cap;
end

//
// ------------------------------------------------------------------------
// Stage 2 : Aa / Ba multipliers
// ------------------------------------------------------------------------
//
reg signed [63:0] Aa_mult_1_r;
reg signed [63:0] Aa_mult_2_r;

reg signed [63:0] Ba_mult_1_r;
reg signed [63:0] Ba_mult_2_r;

reg signed [47:0] FX1_s2;
reg signed [47:0] FY1_s2;
reg signed [47:0] FZ1_s2;
reg signed [63:0] BIG_C_s2;

always @(posedge clock) begin
    Aa_mult_1_r <= FZ3_sub_FZ1_r * (FY2_sub_FY1_s1 <<< FRAC_DIFF);
    Aa_mult_2_r <= FZ2_sub_FZ1_r * (FY3_sub_FY1_s1 <<< FRAC_DIFF);
    Ba_mult_1_r <= (FX3_sub_FX1_s1 <<< FRAC_DIFF) * FZ2_sub_FZ1_r;
    Ba_mult_2_r <= (FX2_sub_FX1_s1 <<< FRAC_DIFF) * FZ3_sub_FZ1_r;
    FX1_s2 <= FX1_s1;
    FY1_s2 <= FY1_s1;
    FZ1_s2 <= FZ1_s1;
    BIG_C_s2 <= BIG_C_s1;
end

//
// ------------------------------------------------------------------------
// Stage 3 : Aa / Ba formation
// ------------------------------------------------------------------------
//
reg signed [47:0] Aa_r;
reg signed [47:0] Ba_r;

reg signed [47:0] FX1_s3;
reg signed [47:0] FY1_s3;
reg signed [47:0] FZ1_s3;
reg signed [63:0] BIG_C_s3;

always @(posedge clock) begin
    Aa_r <= (Aa_mult_1_r - Aa_mult_2_r) >>> Z_FRAC_BITS;
    Ba_r <= (Ba_mult_1_r - Ba_mult_2_r) >>> Z_FRAC_BITS;
    FX1_s3 <= FX1_s2;
    FY1_s3 <= FY1_s2;
    FZ1_s3 <= FZ1_s2;
    BIG_C_s3 <= BIG_C_s2;
end

//
// ------------------------------------------------------------------------
// Stage 4 : Divide
// ------------------------------------------------------------------------
//
reg signed [47:0] FDDX_r;
reg signed [47:0] FDDY_r;

reg signed [47:0] FX1_s4;
reg signed [47:0] FY1_s4;
reg signed [47:0] FZ1_s4;

wire signed [63:0] Aa_num = $signed({{17{Aa_r[47]}}, Aa_r}) <<< Z_FRAC_BITS;
wire signed [63:0] Ba_num = $signed({{17{Ba_r[47]}}, Ba_r}) <<< Z_FRAC_BITS;

always @(posedge clock) begin
    FDDX_r <= (BIG_C_s3 == 0) ? 48'sd0 : (Aa_num / BIG_C_s3);
    FDDY_r <= (BIG_C_s3 == 0) ? 48'sd0 : (Ba_num / BIG_C_s3);
    FX1_s4 <= FX1_s3;
    FY1_s4 <= FY1_s3;
    FZ1_s4 <= FZ1_s3;
end

//
// ------------------------------------------------------------------------
// Stage 5 : ddx*fx1 and ddy*fy1
// ------------------------------------------------------------------------
//
wire signed [47:0] FX1_z = FX1_s4 <<< FRAC_DIFF;
wire signed [47:0] FY1_z = FY1_s4 <<< FRAC_DIFF;

reg signed [63:0] ddx_fx1_mult_r;
reg signed [63:0] ddy_fy1_mult_r;

reg signed [47:0] ddx_fx1_r;
reg signed [47:0] ddy_fy1_r;

reg signed [47:0] FDDX_s5;
reg signed [47:0] FDDY_s5;
reg signed [47:0] FZ1_s5;

always @(posedge clock) begin
    ddx_fx1_mult_r <= FDDX_r * FX1_z;
    ddy_fy1_mult_r <= FDDY_r * FY1_z;
    FDDX_s5 <= FDDX_r;
    FDDY_s5 <= FDDY_r;
    FZ1_s5 <= FZ1_s4;
end

reg signed [47:0] FDDX_s6;
reg signed [47:0] FDDY_s6;
reg signed [47:0] FZ1_s6;

always @(posedge clock) begin
    ddx_fx1_r <= ddx_fx1_mult_r >>> Z_FRAC_BITS;
    ddy_fy1_r <= ddy_fy1_mult_r >>> Z_FRAC_BITS;
    FDDX_s6 <= FDDX_s5;
    FDDY_s6 <= FDDY_s5;
    FZ1_s6 <= FZ1_s5;
end

//
// ------------------------------------------------------------------------
// Stage 6 : Output
// ------------------------------------------------------------------------
//
always @(posedge clock) begin
    FDDX <= FDDX_s6;
    FDDY <= FDDY_s6;

    small_c <= FZ1_s6 - ddx_fx1_r - ddy_fy1_r;
end

//
// ------------------------------------------------------------------------
// Valid pipeline
// ------------------------------------------------------------------------
//
reg [6:0] valid_pipe;

reg [3:0] interp_sel_s0;
reg [3:0] interp_sel_s1;
reg [3:0] interp_sel_s2;
reg [3:0] interp_sel_s3;
reg [3:0] interp_sel_s4;
reg [3:0] interp_sel_s5;
reg [3:0] interp_sel_s6;

always @(posedge clock) begin
    if (start_interp) interp_sel_s0 <= interp_sel_in;
end

always @(posedge clock) begin
    interp_sel_s1 <= interp_sel_s0;
    interp_sel_s2 <= interp_sel_s1;
    interp_sel_s3 <= interp_sel_s2;
    interp_sel_s4 <= interp_sel_s3;
    interp_sel_s5 <= interp_sel_s4;
    interp_sel_s6 <= interp_sel_s5;

    interp_sel_out <= interp_sel_s6;
end


always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	valid_pipe <= 7'd0;
	interp_valid <= 1'b0;
end
else begin
    valid_pipe <= {valid_pipe[5:0], start_interp};
    interp_valid <= valid_pipe[6];
end


endmodule
