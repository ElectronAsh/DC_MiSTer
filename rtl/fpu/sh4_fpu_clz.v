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

module sh4_fpu_clz #(
    parameter WIDTH = 32,
    localparam SWIDTH = $clog2(WIDTH)
) (
    input wire [WIDTH-1:0] data,
    output reg [SWIDTH-1:0] count
);

    // Reverse the number for calculating trailing zeros
    reg [WIDTH-1:0] reversed;
    integer i;
    always @(*) begin
        for (i = 0; i < WIDTH; i = i + 1) reversed[WIDTH-1-i] = data[i];
    end

    // Extract only the lowest set bit of data reversed
    wire [WIDTH-1:0] reversed_lsb = reversed & (-reversed);

    // Given only one bit would be high, it's possible to now get the index in
    // a loop in parallel
    /* verilator lint_off WIDTH */
    always @(*) begin
        count = 0;
        for (i = 0; i < WIDTH; i = i + 1) count |= reversed_lsb[i] ? i : 0;
    end
    /* verilator lint_on WIDTH */

endmodule
