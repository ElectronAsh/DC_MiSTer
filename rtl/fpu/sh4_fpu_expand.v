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

// Expand to internal format where exponent is 2s complement
module sh4_fpu_expand (
    input wire [31:0] i,
    output reg o_sign,
    output reg [8:0] o_exp,
    output reg [22:0] o_frac,
    output reg o_is_zero,
    output reg o_is_inf,
    output reg o_is_nan
);
    wire [7:0] i_exp = i[30:23];
    assign o_sign = i[31];
    assign o_exp = i_exp - 8'd127;
    assign o_frac = i[22:0];
    wire is_frac_zero = (o_frac == 23'd0);
    wire is_exp_zero = (i_exp == 8'd0);
    wire is_exp_max = (i_exp == 8'hff);
    assign o_is_zero = (is_exp_zero) && (is_frac_zero);
    assign o_is_inf = (is_exp_max) && (is_frac_zero);
    assign o_is_nan = (is_exp_max) && (!is_frac_zero);

endmodule
