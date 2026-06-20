`timescale 1ns / 1ps
`default_nettype none

module uv_clamp_flip (
    input  [10:0] tex_u_size_full,
    input  [10:0] tex_v_size_full,
    
    input  signed [9:0] u_div_z,
    input  signed [9:0] v_div_z,
    
    input  tex_u_clamp,    
    input  tex_v_clamp,
    
    input  tex_u_flip,
    input  tex_v_flip,
    
    output wire [9:0] u_flipped,
    output wire [9:0] v_flipped
);

// ---------------- CLAMP ----------------
wire [9:0] u_clamped =
    (u_div_z < 0) ? 10'd0 :
    (u_div_z >= tex_u_size_full) ? tex_u_size_full[9:0] - 1 :
    u_div_z[9:0];

wire [9:0] v_clamped =
    (v_div_z < 0) ? 10'd0 :
    (v_div_z >= tex_v_size_full) ? tex_v_size_full[9:0] - 1 :
    v_div_z[9:0];

// ---------------- NORMALIZE ----------------
wire [9:0] u_norm = tex_u_clamp ? u_clamped : $unsigned(u_div_z);
wire [9:0] v_norm = tex_v_clamp ? v_clamped : $unsigned(v_div_z);

// ---------------- WRAP ----------------
wire [9:0] u_wrap = u_norm & (tex_u_size_full - 1);
wire [9:0] v_wrap = v_norm & (tex_v_size_full - 1);

// ---------------- MIRROR ----------------
wire [10:0] u_mirror_mask = (tex_u_size_full << 1) - 1;
wire [10:0] v_mirror_mask = (tex_v_size_full << 1) - 1;

wire [9:0] u_mirror = u_norm & u_mirror_mask[9:0];
wire [9:0] v_mirror = v_norm & v_mirror_mask[9:0];

// Detect upper half (the mirror half)
wire u_mirror_half = |(u_mirror & tex_u_size_full[9:0]);
wire v_mirror_half = |(v_mirror & tex_v_size_full[9:0]);

wire [9:0] u_flip_result =
    u_mirror_half ? (u_mirror ^ u_mirror_mask[9:0]) :
                    u_mirror;

wire [9:0] v_flip_result =
    v_mirror_half ? (v_mirror ^ v_mirror_mask[9:0]) :
                    v_mirror;

// ---------------- FINAL SELECT ----------------
assign u_flipped =
    tex_u_clamp ? u_clamped :
    tex_u_flip  ? u_flip_result :
                  u_wrap;

assign v_flipped =
    tex_v_clamp ? v_clamped :
    tex_v_flip  ? v_flip_result :
                  v_wrap;

endmodule
