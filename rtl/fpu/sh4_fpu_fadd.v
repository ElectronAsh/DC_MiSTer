`timescale 1ns / 1ps
`include "defines.v"
`default_nettype none

//
// VerilogDC
// Copyright 2023 Wenting Zhang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

module sh4_fpu_fadd (
    input wire ven,  // 1 - generate exception for sNAN 
    input wire i_valid,
    input wire [4:0] i_tag,
    input wire a_sign,
    input wire [9:0] a_exp,
    input wire [24:0] a_frac,
    input wire a_is_zero,
    input wire a_is_inf,
    input wire a_is_nan,
    input wire b_sign,
    input wire [9:0] b_exp,
    input wire [24:0] b_frac,
    input wire b_is_zero,
    input wire b_is_inf,
    input wire b_is_nan,
    output wire o_valid,
    output wire [4:0] o_tag,
    output wire o_sign,
    output wire [10:0] o_exp,
    output wire [24:0] o_frac,
    output wire o_is_zero,
    output wire o_is_inf,
    output wire o_is_nan,
    output wire invalid
);

    // Swap and normalize input
    wire signed [10:0] exp_diff = $signed(a_exp) - $signed(b_exp);
    wire signed [10:0] neg_exp_diff = -exp_diff;

    // Use residual collecting shifter for inexact flag
    wire [25:0] a_frac_ext = {1'b1, a_frac};
    wire [25:0] b_frac_ext = {1'b1, b_frac};
    wire [25:0] a_frac_shifted;
    wire [25:0] b_frac_shifted;
    sh4_fpu_rsh #(
        .WIDTH(26),
        .SWIDTH(11)
    ) rsh_a (  // Used when exp_diff <= 0
        .data(a_frac_ext),
        .shamt(neg_exp_diff),
        .shifted(a_frac_shifted)
    );
    sh4_fpu_rsh #(
        .WIDTH(26),
        .SWIDTH(11)
    ) rsh_b (  // Used when exp_diff >= 0
        .data(b_frac_ext),
        .shamt(exp_diff),
        .shifted(b_frac_shifted)
    );

    wire swap_operand = (exp_diff < 0) || ((exp_diff == 0) && (a_frac < b_frac));
    wire [25:0] aa_frac_norm = swap_operand ? b_frac_ext : a_frac_ext;
    wire [25:0] bb_frac_norm = swap_operand ? a_frac_shifted : b_frac_shifted;

    // Add
    wire same_sign = a_sign == b_sign;
    wire [26:0] frac_sum = same_sign ? (aa_frac_norm + bb_frac_norm) : (aa_frac_norm - bb_frac_norm);
    wire [25:0] frac_sum_truncate = {frac_sum[26:2], frac_sum[1] | frac_sum[0]};

    // Normalize result
    wire [4:0] frac_shamt;
    sh4_fpu_clz #(
        .WIDTH(26)
    ) clz (
        .data(frac_sum_truncate),
        .count(frac_shamt)
    );
    wire [25:0] frac_norm = frac_sum_truncate << frac_shamt;
    wire frac_norm_is_zero = frac_norm == 0;
    wire [10:0] exp_norm = (swap_operand ? b_exp : a_exp) + 1 - frac_shamt;

    // Error check
    wire a_is_snan = a_is_nan && a_frac[22];
    wire b_is_snan = b_is_nan && b_frac[22];

    wire invalid_int = a_is_snan || b_is_snan || (a_is_inf && b_is_inf && !same_sign);
    assign invalid = invalid_int && ven;

    // Output
    assign o_valid = i_valid;
    assign o_tag = i_tag;
    assign o_sign = a_is_zero ? b_sign : b_is_zero ? a_sign : frac_norm_is_zero ? 1'b0 : swap_operand ? b_sign : a_sign;
    assign o_exp = a_is_zero ? b_exp : b_is_zero ? a_exp : exp_norm;
    assign o_frac = a_is_zero ? b_frac : b_is_zero ? a_frac : frac_norm[24:0];  // Drop leading 1
    assign o_is_zero = !o_is_nan && ((a_is_zero && b_is_zero) || (frac_norm_is_zero));
    assign o_is_inf = a_is_inf || b_is_inf;  // TODO: INF is not handled correctly
    assign o_is_nan = a_is_nan || b_is_nan;

endmodule
