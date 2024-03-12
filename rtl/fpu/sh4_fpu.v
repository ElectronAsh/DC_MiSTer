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

module sh4_fpu (
    input wire clk,
    input wire rst,
    input wire [31:0] fpscr,
    input wire in_valid,
    input wire [15:0] in_raw,
    input wire [3:0] in_fop,
    input wire [31:0] in_frl,
    input wire [31:0] in_frh,
    input wire [31:0] in_fr0,
    output reg out_valid,
    output reg out_t,
    output reg out_t_wen,
    output reg [31:0] out_fpul,
    output reg out_fpul_wen,
    output reg out_wen,
    output reg [3:0] out_wdst,
    output reg out_wbank,
    output reg [31:0] out_wdata
);

    // Settings
    wire fpscr_fr = fpscr[21];
    wire fpscr_v_en = fpscr[11];
    wire fpscr_rm = fpscr[0];

    wire [3:0] rn = in_raw[11:8];

    // Expand input
    wire in_l_sign;
    wire [8:0] in_l_exp;
    wire [22:0] in_l_frac;
    wire in_l_is_zero;
    wire in_l_is_inf;
    wire in_l_is_nan;

    wire in_h_sign;
    wire [8:0] in_h_exp;
    wire [22:0] in_h_frac;
    wire in_h_is_zero;
    wire in_h_is_inf;
    wire in_h_is_nan;

    wire in_0_sign;
    wire [8:0] in_0_exp;
    wire [22:0] in_0_frac;
    wire in_0_is_zero;
    wire in_0_is_inf;
    wire in_0_is_nan;

    sh4_fpu_expand expand_l (
        .i(in_frl),
        .o_sign(in_l_sign),
        .o_exp(in_l_exp),
        .o_frac(in_l_frac),
        .o_is_zero(in_l_is_zero),
        .o_is_inf(in_l_is_inf),
        .o_is_nan(in_l_is_nan)
    );
    sh4_fpu_expand expand_h (
        .i(in_frh),
        .o_sign(in_h_sign),
        .o_exp(in_h_exp),
        .o_frac(in_h_frac),
        .o_is_zero(in_h_is_zero),
        .o_is_inf(in_h_is_inf),
        .o_is_nan(in_h_is_nan)
    );
    sh4_fpu_expand expand_0 (
        .i(in_fr0),
        .o_sign(in_0_sign),
        .o_exp(in_0_exp),
        .o_frac(in_0_frac),
        .o_is_zero(in_0_is_zero),
        .o_is_inf(in_0_is_inf),
        .o_is_nan(in_0_is_nan)
    );

    // Consts
    wire const_zero_sign;
    wire [8:0] const_zero_exp;
    wire [22:0] const_zero_frac;
    wire const_zero_is_zero;
    wire const_zero_is_inf;
    wire const_zero_is_nan;

    wire const_one_sign;
    wire [8:0] const_one_exp;
    wire [22:0] const_one_frac;
    wire const_one_is_zero;
    wire const_one_is_inf;
    wire const_one_is_nan;

    sh4_fpu_expand const_zero_expand (
        .i(32'h00000000),
        .o_sign(const_zero_sign),
        .o_exp(const_zero_exp),
        .o_frac(const_zero_frac),
        .o_is_zero(const_zero_is_zero),
        .o_is_inf(const_zero_is_inf),
        .o_is_nan(const_zero_is_nan)
    );
    sh4_fpu_expand const_one_expand (
        .i(32'h3f800000),
        .o_sign(const_one_sign),
        .o_exp(const_one_exp),
        .o_frac(const_one_frac),
        .o_is_zero(const_one_is_zero),
        .o_is_inf(const_one_is_inf),
        .o_is_nan(const_one_is_nan)
    );

    // FMA unit, a * b + c
    reg fma_i_valid;
    reg [4:0] fma_i_tag;
    reg fma_a_sign;
    reg [8:0] fma_a_exp;
    reg [22:0] fma_a_frac;
    reg fma_a_is_zero;
    reg fma_a_is_inf;
    reg fma_a_is_nan;

    reg fma_b_sign;
    reg [8:0] fma_b_exp;
    reg [22:0] fma_b_frac;
    reg fma_b_is_zero;
    reg fma_b_is_inf;
    reg fma_b_is_nan;

    reg fma_c_sign;
    reg [8:0] fma_c_exp;
    reg [22:0] fma_c_frac;
    reg fma_c_is_zero;
    reg fma_c_is_inf;
    reg fma_c_is_nan;

    wire fma_o_valid;
    wire [4:0] fma_o_tag;
    wire fma_o_sign;
    wire [10:0] fma_o_exp;
    wire [24:0] fma_o_frac;
    wire fma_o_is_zero;
    wire fma_o_is_inf;
    wire fma_o_is_nan;

    wire fma_invalid;
    sh4_fpu_fma fpu_fma (
        .clk(clk),
        .rst(rst),
        .ven(fpscr_v_en),
        .i_valid(fma_i_valid),
        .i_tag(fma_i_tag),
        .a_sign(fma_a_sign),
        .a_exp(fma_a_exp),
        .a_frac(fma_a_frac),
        .a_is_zero(fma_a_is_zero),
        .a_is_inf(fma_a_is_inf),
        .a_is_nan(fma_a_is_nan),
        .b_sign(fma_b_sign),
        .b_exp(fma_b_exp),
        .b_frac(fma_b_frac),
        .b_is_zero(fma_b_is_zero),
        .b_is_inf(fma_b_is_inf),
        .b_is_nan(fma_b_is_nan),
        .c_sign(fma_c_sign),
        .c_exp(fma_c_exp),
        .c_frac(fma_c_frac),
        .c_is_zero(fma_c_is_zero),
        .c_is_inf(fma_c_is_inf),
        .c_is_nan(fma_c_is_nan),
        .o_valid(fma_o_valid),
        .o_tag(fma_o_tag),
        .o_sign(fma_o_sign),
        .o_exp(fma_o_exp),
        .o_frac(fma_o_frac),
        .o_is_zero(fma_o_is_zero),
        .o_is_inf(fma_o_is_inf),
        .o_is_nan(fma_o_is_nan),
        .invalid(fma_invalid)
    );

    wire fma_overflow;
    wire fma_underflow;
    wire fma_inexact;
    wire [31:0] fma_rounded;
    sh4_fpu_round fma_round (
        .rm(fpscr_rm),
        .i_sign(fma_o_sign),
        .i_exp(fma_o_exp),
        .i_frac(fma_o_frac),
        .i_is_zero(fma_o_is_zero),
        .i_is_inf(fma_o_is_inf),
        .i_is_nan(fma_o_is_nan),
        .o_val(fma_rounded),
        .overflow(fma_overflow),
        .underflow(fma_underflow),
        .inexact(fma_inexact)
    );

    reg fcmp_i_valid;
    wire fcmp_eq;
    wire fcmp_gt;
    wire fcmp_invalid;
    wire fcmp_unordered;
    sh4_fpu_fcmp fpu_fcmp (
        .ven(fpscr_v_en),
        .i_valid(fcmp_i_valid),
        .a_sign(in_h_sign),
        .a_exp(in_h_exp),
        .a_frac(in_h_frac),
        .a_is_zero(in_h_is_zero),
        .a_is_inf(in_h_is_inf),
        .a_is_nan(in_h_is_nan),
        .b_sign(in_l_sign),
        .b_exp(in_l_exp),
        .b_frac(in_l_frac),
        .b_is_zero(in_l_is_zero),
        .b_is_inf(in_l_is_inf),
        .b_is_nan(in_l_is_nan),
        .eq(fcmp_eq),
        .gt(fcmp_gt),
        .invalid(fcmp_invalid),
        .unordered(fcmp_unordered)
    );

    always @(*) begin
        fma_i_valid = 1'b0;
        fma_i_tag = {fpscr_fr, rn};
        fma_a_sign = const_zero_sign;
        fma_a_exp = const_zero_exp;
        fma_a_frac = const_zero_frac;
        fma_a_is_zero = const_zero_is_zero;
        fma_a_is_inf = const_zero_is_inf;
        fma_a_is_nan = const_zero_is_nan;
        fma_b_sign = const_one_sign;
        fma_b_exp = const_one_exp;
        fma_b_frac = const_one_frac;
        fma_b_is_zero = const_one_is_zero;
        fma_b_is_inf = const_one_is_inf;
        fma_b_is_nan = const_one_is_nan;
        fma_c_sign = const_zero_sign;
        fma_c_exp = const_zero_exp;
        fma_c_frac = const_zero_frac;
        fma_c_is_zero = const_zero_is_zero;
        fma_c_is_inf = const_zero_is_inf;
        fma_c_is_nan = const_zero_is_nan;
        out_t = 1'bx;
        out_t_wen = 1'b0;
        fcmp_i_valid = 1'b0;

        if (in_valid) begin
            case (in_fop)
                `FOP_FADD: begin
                    fma_i_valid = 1'b1;
                    fma_a_sign = in_h_sign;
                    fma_a_exp = in_h_exp;
                    fma_a_frac = in_h_frac;
                    fma_a_is_zero = in_h_is_zero;
                    fma_a_is_inf = in_h_is_inf;
                    fma_a_is_nan = in_h_is_nan;
                    fma_c_sign = in_l_sign;
                    fma_c_exp = in_l_exp;
                    fma_c_frac = in_l_frac;
                    fma_c_is_zero = in_l_is_zero;
                    fma_c_is_inf = in_l_is_inf;
                    fma_c_is_nan = in_l_is_nan;
                end
                `FOP_CMPEQ: begin
                    fcmp_i_valid = 1'b1;
                    out_t = fcmp_eq;
                    out_t_wen = 1'b1;
                end
                `FOP_CMPGT: begin
                    fcmp_i_valid = 1'b1;
                    out_t = fcmp_gt;
                    out_t_wen = 1'b1;
                end
                `FOP_FDIV: begin

                end
                `FOP_FLOAT: begin

                end
                `FOP_FMAC: begin
                    fma_i_valid = 1'b1;
                    fma_a_sign = in_0_sign;
                    fma_a_exp = in_0_exp;
                    fma_a_frac = in_0_frac;
                    fma_a_is_zero = in_0_is_zero;
                    fma_a_is_inf = in_0_is_inf;
                    fma_a_is_nan = in_0_is_nan;
                    fma_b_sign = in_l_sign;
                    fma_b_exp = in_l_exp;
                    fma_b_frac = in_l_frac;
                    fma_b_is_zero = in_l_is_zero;
                    fma_b_is_inf = in_l_is_inf;
                    fma_b_is_nan = in_l_is_nan;
                    fma_c_sign = in_h_sign;
                    fma_c_exp = in_h_exp;
                    fma_c_frac = in_h_frac;
                    fma_c_is_zero = in_h_is_zero;
                    fma_c_is_inf = in_h_is_inf;
                    fma_c_is_nan = in_h_is_nan;
                end
                `FOP_FMUL: begin
                    fma_i_valid = 1'b1;
                    fma_a_sign = in_h_sign;
                    fma_a_exp = in_h_exp;
                    fma_a_frac = in_h_frac;
                    fma_a_is_zero = in_h_is_zero;
                    fma_a_is_inf = in_h_is_inf;
                    fma_a_is_nan = in_h_is_nan;
                    fma_b_sign = in_l_sign;
                    fma_b_exp = in_l_exp;
                    fma_b_frac = in_l_frac;
                    fma_b_is_zero = in_l_is_zero;
                    fma_b_is_inf = in_l_is_inf;
                    fma_b_is_nan = in_l_is_nan;
                    fma_c_sign = fma_a_sign ^ fma_b_sign;  // Use same sign as product
                end
                `FOP_FSQRT: begin

                end
                `FOP_FSUB: begin
                    fma_i_valid = 1'b1;
                    fma_a_sign = in_h_sign;
                    fma_a_exp = in_h_exp;
                    fma_a_frac = in_h_frac;
                    fma_a_is_zero = in_h_is_zero;
                    fma_a_is_inf = in_h_is_inf;
                    fma_a_is_nan = in_h_is_nan;
                    fma_c_sign = in_l_sign;
                    fma_c_exp = in_l_exp;
                    fma_c_frac = in_l_frac;
                    fma_c_is_zero = in_l_is_zero;
                    fma_c_is_inf = in_l_is_inf;
                    fma_c_is_nan = in_l_is_nan;
                    fma_c_sign = !fma_c_sign;  // Reverse flag of C
                end
                `FOP_FTRC: begin

                end
                `FOP_FCNVDS: begin

                end
                `FOP_FCNVSD: begin

                end
                `FOP_FIPR: begin

                end
                `FOP_FTRV: begin

                end
                default: begin
                    // FPU activated but invalid fop
                end
            endcase
        end
    end

    always @(*) begin
        // Output
        // For now, only FMA unit is present
        out_fpul_wen = 1'b0;
        out_fpul = 32'b0;

        out_valid = fma_o_valid;
        out_wen = 1'b1;
        out_wdst = fma_o_tag[3:0];
        out_wbank = fma_o_tag[4];
        out_wdata = fma_rounded;
    end

endmodule
