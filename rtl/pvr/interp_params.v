`timescale 1ns / 1ps
`default_nettype none

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
module interp_params #(
    parameter [7:0] FRAC_BITS   = 8'd12,
    parameter [7:0] Z_FRAC_BITS = 8'd17,
    parameter [7:0] FRAC_DIFF   = Z_FRAC_BITS - FRAC_BITS
)(
	input reset_n,
    input clock,
	
    input  wire [5:0] param_id_in,
    input start_interp,

    input signed [47:0] FY2_sub_FY1,
    input signed [47:0] FY3_sub_FY1,
    input signed [47:0] FX2_sub_FX1,
    input signed [47:0] FX3_sub_FX1,

    input signed [47:0] FX1,
    input signed [47:0] FY1,

    input signed [47:0] BIG_C,

    input wire [31:0] param_a_z,
    input wire [31:0] param_b_z,
    input wire [31:0] param_c_z,

    input wire [31:0] param_a_u,
    input wire [31:0] param_b_u,
    input wire [31:0] param_c_u,

    input wire [31:0] param_a_v,
    input wire [31:0] param_b_v,
    input wire [31:0] param_c_v,

    input wire [31:0] param_a_base_argb,
    input wire [31:0] param_b_base_argb,
    input wire [31:0] param_c_base_argb,

    input wire [31:0] param_a_offs_argb,
    input wire [31:0] param_b_offs_argb,
    input wire [31:0] param_c_offs_argb,

    input wire [10:0] tex_u_size,
    input wire [10:0] tex_v_size,

    output reg signed [47:0] FDDX,
    output reg signed [47:0] FDDY,
    output reg signed [47:0] small_c,
	
    output reg  [5:0] param_id_out,
    output reg interp_valid
);

localparam PARAM_Z      = 6'd0;
localparam PARAM_U      = 6'd1;
localparam PARAM_V      = 6'd2;

localparam PARAM_BASE_A = 6'd3;
localparam PARAM_BASE_R = 6'd4;
localparam PARAM_BASE_G = 6'd5;
localparam PARAM_BASE_B = 6'd6;

localparam PARAM_OFFS_A = 6'd7;
localparam PARAM_OFFS_R = 6'd8;
localparam PARAM_OFFS_G = 6'd9;
localparam PARAM_OFFS_B = 6'd10;

wire [31:0] param_a_float = (param_id_in == PARAM_Z) ? param_a_z :
                            (param_id_in == PARAM_U) ? param_a_u :
                            (param_id_in == PARAM_V) ? param_a_v :
                                                        32'd0;
wire [31:0] param_b_float = (param_id_in == PARAM_Z) ? param_b_z :
                            (param_id_in == PARAM_U) ? param_b_u :
                            (param_id_in == PARAM_V) ? param_b_v :
                                                        32'd0;
wire [31:0] param_c_float = (param_id_in == PARAM_Z) ? param_c_z :
                            (param_id_in == PARAM_U) ? param_c_u :
                            (param_id_in == PARAM_V) ? param_c_v :
                                                        32'd0;

wire signed [47:0] param_a_float_fixed;
wire signed [47:0] param_b_float_fixed;
wire signed [47:0] param_c_float_fixed;

float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) param_a_float_to_fixed (
    .float_in(param_a_float),
    .fixed(param_a_float_fixed)
);

float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) param_b_float_to_fixed (
    .float_in(param_b_float),
    .fixed(param_b_float_fixed)
);

float_to_fixed #(.FRAC_BITS(Z_FRAC_BITS)) param_c_float_to_fixed (
    .float_in(param_c_float),
    .fixed(param_c_float_fixed)
);

reg signed [47:0] param_a_z_fixed_cap;
reg signed [47:0] param_b_z_fixed_cap;
reg signed [47:0] param_c_z_fixed_cap;

wire signed [63:0] param_a_tex = param_a_float_fixed * $signed({1'b0, (param_id_in == PARAM_U) ? tex_u_size : tex_v_size});
wire signed [63:0] param_b_tex = param_b_float_fixed * $signed({1'b0, (param_id_in == PARAM_U) ? tex_u_size : tex_v_size});
wire signed [63:0] param_c_tex = param_c_float_fixed * $signed({1'b0, (param_id_in == PARAM_U) ? tex_u_size : tex_v_size});

wire signed [111:0] param_a_uv_persp = param_a_tex * param_a_z_fixed_cap;
wire signed [111:0] param_b_uv_persp = param_b_tex * param_b_z_fixed_cap;
wire signed [111:0] param_c_uv_persp = param_c_tex * param_c_z_fixed_cap;

wire signed [47:0] param_a_uv_fixed = param_a_uv_persp >>> Z_FRAC_BITS;
wire signed [47:0] param_b_uv_fixed = param_b_uv_persp >>> Z_FRAC_BITS;
wire signed [47:0] param_c_uv_fixed = param_c_uv_persp >>> Z_FRAC_BITS;

function [7:0] argb_chan;
    input [31:0] argb;
    input [5:0] id;
    begin
        case (id)
            PARAM_BASE_A, PARAM_OFFS_A: argb_chan = argb[31:24];
            PARAM_BASE_R, PARAM_OFFS_R: argb_chan = argb[23:16];
            PARAM_BASE_G, PARAM_OFFS_G: argb_chan = argb[15:8];
            PARAM_BASE_B, PARAM_OFFS_B: argb_chan = argb[7:0];
            default: argb_chan = 8'd0;
        endcase
    end
endfunction

wire [31:0] param_a_argb_src = (param_id_in >= PARAM_OFFS_A) ? param_a_offs_argb : param_a_base_argb;
wire [31:0] param_b_argb_src = (param_id_in >= PARAM_OFFS_A) ? param_b_offs_argb : param_b_base_argb;
wire [31:0] param_c_argb_src = (param_id_in >= PARAM_OFFS_A) ? param_c_offs_argb : param_c_base_argb;

wire signed [47:0] param_a_color_fixed = $signed({1'b0, argb_chan(param_a_argb_src, param_id_in)}) <<< Z_FRAC_BITS;
wire signed [47:0] param_b_color_fixed = $signed({1'b0, argb_chan(param_b_argb_src, param_id_in)}) <<< Z_FRAC_BITS;
wire signed [47:0] param_c_color_fixed = $signed({1'b0, argb_chan(param_c_argb_src, param_id_in)}) <<< Z_FRAC_BITS;

wire signed [47:0] param_a_in = (param_id_in == PARAM_Z) ? param_a_float_fixed :
                                ((param_id_in == PARAM_U) || (param_id_in == PARAM_V)) ? param_a_uv_fixed :
                                                                                          param_a_color_fixed;
wire signed [47:0] param_b_in = (param_id_in == PARAM_Z) ? param_b_float_fixed :
                                ((param_id_in == PARAM_U) || (param_id_in == PARAM_V)) ? param_b_uv_fixed :
                                                                                          param_b_color_fixed;
wire signed [47:0] param_c_in = (param_id_in == PARAM_Z) ? param_c_float_fixed :
                                ((param_id_in == PARAM_U) || (param_id_in == PARAM_V)) ? param_c_uv_fixed :
                                                                                          param_c_color_fixed;

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

reg signed [47:0] BIG_C_cap;

reg signed [47:0] param_a_cap;
reg signed [47:0] param_b_cap;
reg signed [47:0] param_c_cap;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
        FY2_sub_FY1_cap <= 48'sd0;
        FY3_sub_FY1_cap <= 48'sd0;
        FX2_sub_FX1_cap <= 48'sd0;
        FX3_sub_FX1_cap <= 48'sd0;
        FX1_cap <= 48'sd0;
        FY1_cap <= 48'sd0;
        BIG_C_cap <= 48'sd0;
        param_a_cap <= 48'sd0;
        param_b_cap <= 48'sd0;
        param_c_cap <= 48'sd0;
        param_a_z_fixed_cap <= 48'sd0;
        param_b_z_fixed_cap <= 48'sd0;
        param_c_z_fixed_cap <= 48'sd0;
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

        param_a_cap <= param_a_in;
        param_b_cap <= param_b_in;
        param_c_cap <= param_c_in;

        if (param_id_in == PARAM_Z) begin
            param_a_z_fixed_cap <= param_a_float_fixed;
            param_b_z_fixed_cap <= param_b_float_fixed;
            param_c_z_fixed_cap <= param_c_float_fixed;
        end
    end
end

//
// ------------------------------------------------------------------------
// Stage 1 : Z deltas
// ------------------------------------------------------------------------
//
reg signed [47:0] param_b_sub_param_a_r;
reg signed [47:0] param_c_sub_param_a_r;

reg signed [47:0] FX1_s1;
reg signed [47:0] FY1_s1;
reg signed [47:0] param_a_s1;
reg signed [47:0] FY2_sub_FY1_s1;
reg signed [47:0] FY3_sub_FY1_s1;
reg signed [47:0] FX2_sub_FX1_s1;
reg signed [47:0] FX3_sub_FX1_s1;

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
reg signed [47:0] BIG_C_s1;

always @(posedge clock) begin
    param_b_sub_param_a_r <= param_b_cap - param_a_cap;
    param_c_sub_param_a_r <= param_c_cap - param_a_cap;
    FX1_s1 <= FX1_cap;
    FY1_s1 <= FY1_cap;
    param_a_s1 <= param_a_cap;
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
reg signed [63:0] A_num_mult_1_r;
reg signed [63:0] A_num_mult_2_r;

reg signed [63:0] B_num_mult_1_r;
reg signed [63:0] B_num_mult_2_r;

reg signed [47:0] FX1_s2;
reg signed [47:0] FY1_s2;
reg signed [47:0] param_a_s2;

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
reg signed [47:0] BIG_C_s2;

always @(posedge clock) begin
    A_num_mult_1_r <= param_c_sub_param_a_r * (FY2_sub_FY1_s1 <<< FRAC_DIFF);
    A_num_mult_2_r <= param_b_sub_param_a_r * (FY3_sub_FY1_s1 <<< FRAC_DIFF);
    B_num_mult_1_r <= (FX3_sub_FX1_s1 <<< FRAC_DIFF) * param_b_sub_param_a_r;
    B_num_mult_2_r <= (FX2_sub_FX1_s1 <<< FRAC_DIFF) * param_c_sub_param_a_r;
    FX1_s2 <= FX1_s1;
    FY1_s2 <= FY1_s1;
    param_a_s2 <= param_a_s1;
    BIG_C_s2 <= BIG_C_s1;
end

//
// ------------------------------------------------------------------------
// Stage 3 : Aa / Ba formation
// ------------------------------------------------------------------------
//
reg signed [47:0] A_num_r;
reg signed [47:0] B_num_r;

reg signed [47:0] FX1_s3;
reg signed [47:0] FY1_s3;
reg signed [47:0] param_a_s3;

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
reg signed [47:0] BIG_C_s3;

always @(posedge clock) begin
    A_num_r <= (A_num_mult_1_r - A_num_mult_2_r) >>> Z_FRAC_BITS;
    B_num_r <= (B_num_mult_1_r - B_num_mult_2_r) >>> Z_FRAC_BITS;
    FX1_s3 <= FX1_s2;
    FY1_s3 <= FY1_s2;
    param_a_s3 <= param_a_s2;
    BIG_C_s3 <= BIG_C_s2;
end

(* preserve, dont_merge *) reg signed [47:0] BIG_C_div;

always @(posedge clock) begin
    // A_num_r is produced from stage 2 on the same edge that BIG_C_s3 is
    // produced. Register stage 2 here so the divider sees matching tokens.
    BIG_C_div <= BIG_C_s2;
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
reg signed [47:0] param_a_s4;

// Ideally needs to be at least 56 bits here, else things go screwy, especially the extra large polys on Daytona Bhind.
wire signed [59:0] A_num_num = $signed({{17{A_num_r[47]}}, A_num_r}) <<< Z_FRAC_BITS;
wire signed [59:0] B_num_num = $signed({{17{B_num_r[47]}}, B_num_r}) <<< Z_FRAC_BITS;

always @(posedge clock) begin
    //FDDX_r <= (BIG_C_s3 == 0) ? 48'sd0 : (A_num_num / BIG_C_s3);
    //FDDY_r <= (BIG_C_s3 == 0) ? 48'sd0 : (B_num_num / BIG_C_s3);
    FDDX_r <= (BIG_C_div == 0) ? 48'sd0 : (A_num_num / BIG_C_div);
    FDDY_r <= (BIG_C_div == 0) ? 48'sd0 : (B_num_num / BIG_C_div);
    FX1_s4 <= FX1_s3;
    FY1_s4 <= FY1_s3;
    param_a_s4 <= param_a_s3;
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
reg signed [47:0] param_a_s5;

always @(posedge clock) begin
    ddx_fx1_mult_r <= FDDX_r * FX1_z;
    ddy_fy1_mult_r <= FDDY_r * FY1_z;
    FDDX_s5 <= FDDX_r;
    FDDY_s5 <= FDDY_r;
    param_a_s5 <= param_a_s4;
end

reg signed [47:0] FDDX_s6;
reg signed [47:0] FDDY_s6;
reg signed [47:0] param_a_s6;

always @(posedge clock) begin
    ddx_fx1_r <= ddx_fx1_mult_r >>> Z_FRAC_BITS;
    ddy_fy1_r <= ddy_fy1_mult_r >>> Z_FRAC_BITS;
    FDDX_s6 <= FDDX_s5;
    FDDY_s6 <= FDDY_s5;
    param_a_s6 <= param_a_s5;
end

//
// ------------------------------------------------------------------------
// Stage 6 : Output
// ------------------------------------------------------------------------
//
always @(posedge clock) begin
    FDDX <= FDDX_s6;
    FDDY <= FDDY_s6;
    small_c <= param_a_s6 - ddx_fx1_r - ddy_fy1_r;
end

//
// ------------------------------------------------------------------------
// Valid pipeline
// ------------------------------------------------------------------------
//
reg [6:0] valid_pipe;

reg [5:0] param_id_s0;
reg [5:0] param_id_s1;
reg [5:0] param_id_s2;
reg [5:0] param_id_s3;
reg [5:0] param_id_s4;
reg [5:0] param_id_s5;
reg [5:0] param_id_s6;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	valid_pipe <= 7'd0;
	interp_valid <= 1'b0;
	param_id_out <= 6'd0;
	param_id_s0 <= 6'd0;
	param_id_s1 <= 6'd0;
	param_id_s2 <= 6'd0;
	param_id_s3 <= 6'd0;
	param_id_s4 <= 6'd0;
	param_id_s5 <= 6'd0;
	param_id_s6 <= 6'd0;
end
else begin
    valid_pipe <= {valid_pipe[5:0], start_interp};
    interp_valid <= valid_pipe[6];
    if (start_interp) param_id_s0 <= param_id_in;
    param_id_s1 <= param_id_s0;
    param_id_s2 <= param_id_s1;
    param_id_s3 <= param_id_s2;
    param_id_s4 <= param_id_s3;
    param_id_s5 <= param_id_s4;
    param_id_s6 <= param_id_s5;
    param_id_out <= param_id_s6;
end


endmodule
