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

// Right shifter, collects residual for rounding and inexact detection
module fpu_rsh #(
    parameter WIDTH = 32,
    parameter SWIDTH = 5
) (
    input wire [WIDTH-1:0] data,
    input wire [SWIDTH-1:0] shamt,
    output reg [WIDTH-1:0] shifted
);

    reg [WIDTH-1:0] residual;
    integer i;
    always @(*) begin
        residual[0] = data[0];
        for (i = 1; i < WIDTH; i = i + 1) begin
            residual[i] = residual[i-1] | data[i];
        end
    end

    localparam SWIDTH_BOUNDED = $clog2(WIDTH);
    wire [SWIDTH_BOUNDED-1:0] shamt_bounded = shamt[SWIDTH_BOUNDED-1:0];

    assign shifted = (shamt >= WIDTH) ?
        {{(WIDTH - 1) {1'b0}}, residual[WIDTH-1]} : {data[WIDTH-1:1] >> shamt_bounded, residual[shamt_bounded]};

endmodule
