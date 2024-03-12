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

module sh4_fprf (
    input wire clk,
    /* verilator lint_off UNUSED */
    input wire rst,
    /* verilator lint_on UNUSED */
    input wire [3:0] rf_rsrc0,
    input wire rf_rbank0,
    output reg [31:0] rf_rdata0,
    input wire [3:0] rf_rsrc1,
    input wire rf_rbank1,
    output reg [31:0] rf_rdata1,
    input wire [3:0] rf_rsrc2,
    input wire rf_rbank2,
    output reg [31:0] rf_rdata2,
    input reg rf_r0bank,
    output reg [31:0] rf_r0data,
    input wire rf_wen0,
    input wire [3:0] rf_wdst0,
    input wire rf_wbank0,
    input wire [31:0] rf_wdata0,
    input wire rf_wen1,
    input wire [3:0] rf_wdst1,
    input wire rf_wbank1,
    input wire [31:0] rf_wdata1
);

    reg [31:0] rf_array_b0[15:0];
    reg [31:0] rf_array_b1[15:0];

    always @(posedge clk) begin
        if (rf_wen0) begin
            if (rf_wbank0) rf_array_b1[rf_wdst0] <= rf_wdata0;
            else rf_array_b0[rf_wdst0] <= rf_wdata0;
        end
        if (rf_wen1) begin
            if (rf_wbank1) rf_array_b1[rf_wdst1] <= rf_wdata1;
            else rf_array_b0[rf_wdst1] <= rf_wdata1;
        end

    end

    always @(*) begin
        if (rf_rbank0) rf_rdata0 = rf_array_b1[rf_rsrc0];
        else rf_rdata0 = rf_array_b0[rf_rsrc0];
        if (rf_rbank1) rf_rdata1 = rf_array_b1[rf_rsrc1];
        else rf_rdata1 = rf_array_b0[rf_rsrc1];
        if (rf_rbank2) rf_rdata2 = rf_array_b1[rf_rsrc2];
        else rf_rdata2 = rf_array_b0[rf_rsrc2];

        if (rf_r0bank) rf_r0data = rf_array_b1[0];
        else rf_r0data = rf_array_b0[0];
    end

endmodule
