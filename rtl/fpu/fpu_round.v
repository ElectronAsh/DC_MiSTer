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

module fpu_round (
    input wire rm,
    input wire i_sign,
    input wire [10:0] i_exp,
    input wire [24:0] i_frac,
    input wire i_is_zero,
    input wire i_is_inf,
    input wire i_is_nan,
    output wire [31:0] o_val,
    output reg overflow,
    output reg underflow,
    output reg inexact
);

    wire signed [11:0] exp_biased = $signed(i_exp) + $signed(11'd127);
    reg o_sign;
    reg [7:0] o_exp;
    reg [22:0] o_frac;

    // TODO, currently only RTZ
    always @(*) begin
        overflow = 1'b0;
        underflow = 1'b0;
        inexact = 1'b0;

        o_sign = i_sign;
        o_exp = exp_biased[7:0];
        o_frac = i_frac[24:2];

        if (i_is_zero || i_is_inf) begin
            // No rounding needed
        end else if (i_is_nan) begin
            o_exp = 8'hff;
            o_frac = 23'h3fffff;
        end else if (exp_biased[11:8] != 0) begin
            // Overflow to infinity
            overflow = 1'b1;
            inexact = 1'b1;  // Should this be set?
            o_exp = 8'hff;
            o_frac = 23'd0;
        end else if ((o_frac == 23'd0) && (i_frac[1:0] != 0)) begin
            inexact = 1'b1;
            if (o_exp == 8'd127) begin
                // Underflow to zero
                underflow = 1'b1;
            end
        end
    end

    assign o_val = {o_sign, o_exp, o_frac};

endmodule
