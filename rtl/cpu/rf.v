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

module rf (
    input wire clk,
    input wire rst,
    input wire [3:0] rf_rsrc0,
    output reg [31:0] rf_rdata0,
    input wire rf_rbank0,
    input wire [3:0] rf_rsrc1,
    output reg [31:0] rf_rdata1,
    input wire rf_rbank1,
    input wire [3:0] rf_rsrc2,
    output reg [31:0] rf_rdata2,
    input wire rf_rbank2,
    input wire [3:0] rf_rsrc3,
    output reg [31:0] rf_rdata3,
    input wire rf_rbank3,
    input wire rf_wen0,
    input wire [3:0] rf_wdst0,
    input wire [31:0] rf_wdata0,
    input wire rf_wen1,
    input wire [3:0] rf_wdst1,
    input wire [31:0] rf_wdata1,
    input wire rf_wbank0,
    input wire rf_wbank1,
    output wire [31:0] rf_rd_r0
);

    reg [31:0] rf_array_b0[15:0];
    reg [31:0] rf_array_b1[7:0];

    always @(posedge clk) begin
        if (rf_wen0) begin
            if (!rf_wdst0[3] && rf_wbank0) rf_array_b1[rf_wdst0[2:0]] <= rf_wdata0;
            else rf_array_b0[rf_wdst0] <= rf_wdata0;
        end
        if (rf_wen1) begin
            if (!rf_wdst1[3] && rf_wbank1) rf_array_b1[rf_wdst1[2:0]] <= rf_wdata1;
            else rf_array_b0[rf_wdst1] <= rf_wdata1;
        end


        // Initialize registers for direct boot
`ifdef DIRECT_BOOT
        if (rst) begin
            rf_array_b0[0] <= 32'h00000000;
            rf_array_b0[1] <= 32'h00000000;
            rf_array_b0[2] <= 32'h00000000;
            rf_array_b0[3] <= 32'h00000000;
            rf_array_b0[4] <= 32'h00000000;
            rf_array_b0[5] <= 32'h00000000;
            rf_array_b0[6] <= 32'h00000000;
            rf_array_b0[7] <= 32'h00000000;
            rf_array_b0[8] <= 32'h00000000;
            rf_array_b0[9] <= 32'h00000000;
            rf_array_b0[10] <= 32'h00000000;
            rf_array_b0[11] <= 32'h00000000;
            rf_array_b0[12] <= 32'h00000000;
            rf_array_b0[13] <= 32'h00000000;
            rf_array_b0[14] <= 32'h00000000;
            rf_array_b0[15] <= 32'h8d000000;
            rf_array_b1[0] <= 32'h00000000;
            rf_array_b1[1] <= 32'h00000000;
            rf_array_b1[2] <= 32'h00000000;
            rf_array_b1[3] <= 32'h00000000;
            rf_array_b1[4] <= 32'h00000000;
            rf_array_b1[5] <= 32'h00000000;
            rf_array_b1[6] <= 32'h00000000;
            rf_array_b1[7] <= 32'h00000000;
        end
`endif
    end

    always @(*) begin
        if (!rf_rsrc0[3] && rf_rbank0) rf_rdata0 = rf_array_b1[rf_rsrc0[2:0]];
        else rf_rdata0 = rf_array_b0[rf_rsrc0];
        if (!rf_rsrc1[3] && rf_rbank1) rf_rdata1 = rf_array_b1[rf_rsrc1[2:0]];
        else rf_rdata1 = rf_array_b0[rf_rsrc1];
        if (!rf_rsrc2[3] && rf_rbank2) rf_rdata2 = rf_array_b1[rf_rsrc2[2:0]];
        else rf_rdata2 = rf_array_b0[rf_rsrc2];
        if (!rf_rsrc3[3] && rf_rbank3) rf_rdata3 = rf_array_b1[rf_rsrc3[2:0]];
        else rf_rdata3 = rf_array_b0[rf_rsrc3];

    end

    assign rf_rd_r0 = rf_rbank0 ? rf_array_b1[0] : rf_array_b0[0];

endmodule
