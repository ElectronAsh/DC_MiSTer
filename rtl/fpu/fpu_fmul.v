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

module fpu_fmul (
    input wire ven,  // 1 - generate exception for sNAN 
    input wire i_valid,
    input wire [4:0] i_tag,
    input wire a_sign,
    input wire [8:0] a_exp,
    input wire [22:0] a_frac,
    input wire a_is_zero,
    input wire a_is_inf,
    input wire a_is_nan,
    input wire b_sign,
    input wire [8:0] b_exp,
    input wire [22:0] b_frac,
    input wire b_is_zero,
    input wire b_is_inf,
    input wire b_is_nan,
    output wire o_valid,
    output wire [4:0] o_tag,
    output wire o_sign,
    output wire [9:0] o_exp,
    output wire [46:0] o_frac,
    output wire o_is_zero,
    output wire o_is_inf,
    output wire o_is_nan,
    output wire invalid
);
    // Multiply    
    wire signed [9:0] x_exp = $signed(a_exp) + $signed(b_exp);
    wire [47:0] x_frac = {1'b1, a_frac} * {1'b1, b_frac};

    // Normalize
    wire [9:0] x_exp_norm = x_exp + (x_frac[47] ? 10'd1 : 10'd0);
    wire [46:0] x_frac_norm = x_frac[47] ? x_frac[46:0] : {x_frac[45:0], 1'b0};

    // Error check
    wire a_is_snan = a_is_nan && a_frac[22];
    wire b_is_snan = b_is_nan && b_frac[22];

    wire invalid_int = a_is_snan || b_is_snan || ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero));
    assign invalid = invalid_int && ven;

    // Output
    assign o_valid = i_valid;
    assign o_tag = i_tag;
    assign o_is_nan = a_is_nan || b_is_nan || invalid_int;
    assign o_is_inf = !o_is_nan && (a_is_inf || b_is_inf);
    assign o_is_zero = !o_is_nan && (a_is_zero || b_is_zero);
    assign o_sign = a_sign ^ b_sign;
    assign o_exp = x_exp_norm;  // NaN value is handled at final rounding
    assign o_frac = x_frac_norm;

endmodule
