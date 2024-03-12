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

module fpu_fcmp (
    input wire ven,
    input wire i_valid,
    input wire a_sign,
    input wire [7:0] a_exp,
    input wire [22:0] a_frac,
    input wire a_is_zero,
    input wire a_is_inf,
    input wire a_is_nan,
    input wire b_sign,
    input wire [7:0] b_exp,
    input wire [22:0] b_frac,
    input wire b_is_zero,
    input wire b_is_inf,
    input wire b_is_nan,
    output wire eq,
    output wire gt,
    output wire invalid,
    output wire unordered
);

    wire exp_eq = a_exp == b_exp;
    wire exp_gt = a_exp > b_exp;
    wire frac_eq = a_frac == b_frac;
    wire frac_gt = a_frac > b_frac;
    wire exp_frac_eq = exp_eq && frac_eq;
    wire exp_frac_gt = exp_gt && frac_gt;

    reg cmp_eq;
    reg cmp_gt;

    always @(*) begin
        cmp_eq = 1'b0;
        cmp_gt = 1'b0;
        if (a_is_zero && b_is_zero) begin
            cmp_eq = 1'b1;
        end else if (a_is_zero) begin
            cmp_gt = b_sign;
        end else if (b_is_zero) begin
            cmp_gt = !a_sign;
        end else if (a_sign != b_sign) begin
            cmp_gt = b_sign;
        end else if (a_is_inf && b_is_inf) begin
            cmp_eq = a_sign == b_sign;
            cmp_gt = a_sign && !b_sign;
        end else if (a_is_inf) begin
            cmp_gt = !a_sign;
        end else if (b_is_inf) begin
            cmp_gt = b_sign;
        end else if (exp_frac_eq) begin
            cmp_eq = 1'b1;
        end else begin
            cmp_gt = exp_frac_gt ^ b_sign;
        end
    end

    // Error check and output
    wire a_is_snan = a_is_nan && a_frac[22];
    wire b_is_snan = b_is_nan && b_frac[22];

    assign invalid = (a_is_snan || b_is_snan) && ven & i_valid;
    assign unordered = (a_is_nan || b_is_nan) & i_valid;

    assign eq = cmp_eq & i_valid;
    assign gt = cmp_gt & i_valid;

endmodule
