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

module sh4_bru (
    // Input instruction
    input wire in_valid,
    input wire [31:0] in_pr,
    input wire in_t,
    input wire [15:0] in_raw,
    input wire [31:0] in_opl,
    input wire [31:0] in_oph,
    // Result output
    output reg out_taken,
    output reg [31:0] out_target,
    output reg out_delayslot,
    output reg out_write_pr
);

    always @(*) begin
        // Set default values
        out_taken = 1'b0;
        out_target = in_opl + in_oph;
        out_delayslot = 1'b0;
        out_write_pr = 1'b0;

        // Execute
        if (in_valid) begin
            casez (in_raw)
                16'b10001011????????:  // BF label
                    begin
                    out_taken = !in_t;
                end
                16'b10001111????????:  // BF/S label
                    begin
                    out_taken = !in_t;
                    out_delayslot = 1'b1;
                end
                16'b10001001????????:  // BT label
                    begin
                    out_taken = in_t;
                end
                16'b10001101????????:  // BT/S label
                    begin
                    out_taken = in_t;
                    out_delayslot = 1'b1;
                end
                16'b1010????????????:  // BRA label
                    begin
                    out_taken = 1'b1;
                    out_delayslot = 1'b1;
                end
                16'b1011????????????:  // BSR label
                    begin
                    out_taken = 1'b1;
                    out_delayslot = 1'b1;
                    out_write_pr = 1'b1;
                end
                16'b0100????00101011:  // JMP @Rn
                    begin
                    out_taken = 1'b1;
                    out_delayslot = 1'b1;
                    out_target = in_oph;
                end
                16'b0100????00001011:  // JSR @Rn
                    begin
                    out_taken = 1'b1;
                    out_delayslot = 1'b1;
                    out_target = in_oph;
                    out_write_pr = 1'b1;
                end
                16'b0000????00100011:  // BRAF Rn
                    begin
                    out_taken = 1'b1;
                end
                16'b0000????00000011:  // BSRF Rn
                    begin
                    out_taken = 1'b1;
                    out_delayslot = 1'b1;
                end
                16'b0000000000001011:  // RTS
                    begin
                    out_taken = 1'b1;
                    out_target = in_pr;
                    out_delayslot = 1'b1;
                end
                16'b0000000000101011:  // RTE
                    begin
                    out_taken = 1'b1;
                    out_target = in_pr;
                end
                default: begin
                    // BRU activated but no instruction matched?
                end
            endcase
        end
    end

endmodule
