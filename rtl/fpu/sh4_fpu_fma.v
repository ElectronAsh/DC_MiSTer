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

module sh4_fpu_fma (
    input wire clk,
    input wire rst,
    input wire ven,
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
    input wire c_sign,
    input wire [8:0] c_exp,
    input wire [22:0] c_frac,
    input wire c_is_zero,
    input wire c_is_inf,
    input wire c_is_nan,
    output reg o_valid,
    output reg [4:0] o_tag,
    output reg o_sign,
    output reg [10:0] o_exp,
    output reg [24:0] o_frac,
    output reg o_is_zero,
    output reg o_is_inf,
    output reg o_is_nan,
    output wire invalid
);
    // Multiply
    wire mul_invalid;
    wire mul_o_sign;
    wire [9:0] mul_o_exp;
    wire [46:0] mul_o_frac;
    wire mul_o_is_zero;
    wire mul_o_is_inf;
    wire mul_o_is_nan;

    wire mul_o_valid;
    wire [4:0] mul_o_tag;

    sh4_fpu_fmul fmul (
        .ven(ven),
        .i_valid(i_valid),
        .i_tag(i_tag),
        .a_sign(a_sign),
        .a_exp(a_exp),
        .a_frac(a_frac),
        .a_is_zero(a_is_zero),
        .a_is_inf(a_is_inf),
        .a_is_nan(a_is_nan),
        .b_sign(b_sign),
        .b_exp(b_exp),
        .b_frac(b_frac),
        .b_is_zero(b_is_zero),
        .b_is_inf(b_is_inf),
        .b_is_nan(b_is_nan),
        .o_valid(mul_o_valid),
        .o_tag(mul_o_tag),
        .o_sign(mul_o_sign),
        .o_exp(mul_o_exp),
        .o_frac(mul_o_frac),
        .o_is_zero(mul_o_is_zero),
        .o_is_inf(mul_o_is_inf),
        .o_is_nan(mul_o_is_nan),
        .invalid(mul_invalid)
    );

    // Convert value before continue
    reg adder_a_sign;
    reg [9:0] adder_a_exp;
    reg [24:0] adder_a_frac;
    reg adder_a_is_zero;
    reg adder_a_is_inf;
    reg adder_a_is_nan;

    reg adder_b_sign;
    reg [9:0] adder_b_exp;
    reg [24:0] adder_b_frac;
    reg adder_b_is_zero;
    reg adder_b_is_inf;
    reg adder_b_is_nan;

    reg adder_i_valid;
    reg [4:0] adder_i_tag;

    // Crude pipelining, relies on retiming to achieve good result
    always @(posedge clk) begin
        adder_i_valid <= mul_o_valid;
        if (mul_o_valid) begin
            adder_a_sign <= mul_o_sign;
            adder_a_exp <= mul_o_exp;
            adder_a_frac <= {mul_o_frac[46:23], |mul_o_frac[22:0]};
            adder_a_is_zero <= mul_o_is_zero;
            adder_a_is_inf <= mul_o_is_inf;
            adder_a_is_nan <= mul_o_is_nan;

            adder_b_sign <= c_sign;
            adder_b_exp <= {c_exp[8], c_exp};
            adder_b_frac <= {c_frac, 2'b0};
            adder_b_is_zero <= c_is_zero;
            adder_b_is_inf <= c_is_inf;
            adder_b_is_nan <= c_is_nan;

            adder_i_tag <= mul_o_tag;
        end
        if (rst) begin
            adder_i_valid <= 1'b0;
        end
    end

    // Add
    wire adder_o_valid;
    wire [4:0] adder_o_tag;
    wire adder_o_sign;
    wire [10:0] adder_o_exp;
    wire [24:0] adder_o_frac;
    wire adder_o_is_zero;
    wire adder_o_is_inf;
    wire adder_o_is_nan;

    wire adder_invalid;
    sh4_fpu_fadd fadd (
        .ven(ven),
        .i_valid(adder_i_valid),
        .i_tag(adder_i_tag),
        .a_sign(adder_a_sign),
        .a_exp(adder_a_exp),
        .a_frac(adder_a_frac),
        .a_is_zero(adder_a_is_zero),
        .a_is_inf(adder_a_is_inf),
        .a_is_nan(adder_a_is_nan),
        .b_sign(adder_b_sign),
        .b_exp(adder_b_exp),
        .b_frac(adder_b_frac),
        .b_is_zero(adder_b_is_zero),
        .b_is_inf(adder_b_is_inf),
        .b_is_nan(adder_b_is_nan),
        .o_valid(adder_o_valid),
        .o_tag(adder_o_tag),
        .o_sign(adder_o_sign),
        .o_exp(adder_o_exp),
        .o_frac(adder_o_frac),
        .o_is_zero(adder_o_is_zero),
        .o_is_inf(adder_o_is_inf),
        .o_is_nan(adder_o_is_nan),
        .invalid(adder_invalid)
    );

    always @(posedge clk) begin
        o_valid <= adder_o_valid;
        if (adder_o_valid) begin
            o_sign <= adder_o_sign;
            o_exp <= adder_o_exp;
            o_frac <= adder_o_frac;
            o_is_zero <= adder_o_is_zero;
            o_is_inf <= adder_o_is_inf;
            o_is_nan <= adder_o_is_nan;
            o_tag <= adder_o_tag;
        end
        if (rst) begin
            o_valid <= 1'b0;
        end
    end

    assign invalid = adder_invalid;  // TODO

endmodule
