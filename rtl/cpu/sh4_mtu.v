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

module sh4_mtu (
    // Input instruction
    input wire in_valid,
    input wire [15:0] in_raw,
    input wire [31:0] in_opl,
    input wire [31:0] in_oph,
    // Result output
    output reg out_t,
    output reg out_wen,
    output reg [3:0] out_wdst,
    output reg [31:0] out_wdata
);

    // Op1: Rm or R0
    // Op2: Rn

    reg cmpz;
    wire [31:0] cmp_opl = cmpz ? 32'd0 : in_opl;

    // subs = Rm - Rn
    /* verilator lint_off UNUSEDSIGNAL */
    wire [32:0] subs = {1'b0, cmp_opl} + {1'b1, ~in_oph} + 33'b1;
    /* verilator lint_on UNUSEDSIGNAL */
    // LT: Rm < Rn signed
    wire lt = (cmp_opl[31] ^ in_oph[31]) ? cmp_opl[31] : subs[32];
    // LTU: Rm < Rn unsigned
    wire ltu = subs[32];
    wire eq = cmp_opl == in_oph;

    always @(*) begin
        // Set default values
        out_t = 1'b0;
        out_wen = 1'b0;
        out_wdst = in_raw[11:8];
        out_wdata = in_opl;

        // Execute
        if (in_valid) begin
            casez (in_raw)
                16'b0000000000001001:  // NOP
                    begin
                    // NOP
                end
                16'b0110????????0011:  // MOV Rm,Rn
                    begin
                    out_wen = 1'b1;
                end
                16'b10001000????????,  // CMP/EQ #imm,R0
                16'b0011????????0000:  // CMP/EQ Rm,Rn
                    begin
                    out_t = eq;
                end
                16'b0100????00010001,  // CMP/PZ Rn
                16'b0011????????0010:  // CMP/HS Rm,Rn
                    begin
                    // Rn >= Rm unsigned
                    out_t = ltu || eq;
                end
                16'b0011????????0011:  // CMP/GE Rm,Rn
                    begin
                    // Rn >= Rm signed
                    out_t = lt || eq;
                end
                16'b0100????00010101,  // CMP/PL Rn
                16'b0011????????0110:  // CMP/HI Rm,Rn
                    begin
                    // Rn > Rm, unsigned
                    out_t = ltu;
                end
                16'b0011????????0111:  // CMP/GT Rm,Rn
                    begin
                    // Rn > Rm, signed
                    out_t = lt;
                end
                16'b0010????????1100:  // CMP/STR Rm,Rn
                    begin
                    out_t = (in_opl[31:24] == in_oph[31:24]) || (in_opl[23:16] == in_oph[23:16]) ||
                        (in_opl[15:8] == in_oph[15:8]) || (in_opl[7:0] == in_oph[7:0]);
                end
                16'b11001000????????,  // TST #imm,R0
                16'b0010????????1000:  // TST Rm,Rn
                    begin
                    out_t = (in_opl & in_oph) == 32'd0;
                end
                16'b0000000000001000:  // CLRT
                    begin
                    out_t = 1'b0;
                end
                16'b0000000000011000:  // SETT
                    begin
                    out_t = 1'b1;
                end
                default: begin
                    // MTU activated but no instruction matched?
                end
            endcase
        end
    end

    // Separate block to avoid UNOPTFLAT
    always @(*) begin
        casez (in_raw)
            16'b0100????00010001,  // CMP/PZ Rn
            16'b0100????00010101:  // CMP/PL Rn
                begin
                cmpz = 1'b1;
            end
            default: begin
                cmpz = 1'b0;
            end
        endcase
    end

endmodule
