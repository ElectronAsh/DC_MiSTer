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

module exu (
    // Input instruction
    input wire in_valid,
    input wire [3:0] in_flags,
    input wire [15:0] in_raw,
    input wire [31:0] in_opl,
    input wire [31:0] in_oph,
    // Result output
    output reg [3:0] out_flags,
    output reg out_wen,
    output reg [3:0] out_wdst,
    output reg [31:0] out_wdata
);

    wire in_m = in_flags[3];
    wire in_q = in_flags[2];
    wire in_s = in_flags[1];
    wire in_t = in_flags[0];

    reg out_m, out_q, out_s, out_t;

    wire [3:0] rn = in_raw[11:8];

    // Ideally this should be in the always_comb but this causes verilator to generate UNOPTFLAT
    wire use_carry = ((in_raw[15:12] == 4'b0011) && (in_raw[3:0] == 4'b1110)) ||  // ADDC Rm,Rn
    ((in_raw[15:12] == 4'b0110) && (in_raw[3:0] == 4'b1010)) ||  // NEGC Rm,Rn
    ((in_raw[15:12] == 4'b0011) && (in_raw[3:0] == 4'b1010));  // SUBC Rm,Rn
    wire [32:0] carry = use_carry ? {32'd0, in_t} : 33'd0;
    wire [32:0] adder = {1'b0, in_opl} + {1'b0, in_oph} + carry;
    wire is_neg =  // negate
    ((in_raw[15:12] == 4'b0110) && (in_raw[3:0] == 4'b1011)) ||  // NEG Rm,Rn
    ((in_raw[15:12] == 4'b0110) && (in_raw[3:0] == 4'b1010));  // NEGC Rm,Rn
    wire [32:0] sub = (is_neg ? 33'd0 : {1'b0, in_oph}) + ~({1'b0, in_opl} + carry) + 33'd1;

    // Op1: Rm or R0
    // Op2: Rn

    // For division...
    wire [31:0] rn_shift = {in_oph[30:0], in_t};

    // Barrel shifter
    wire [4:0] shamt_left = in_opl[4:0];
    wire [4:0] shamt_right = (~in_opl[4:0]) + 1;

    wire [31:0] lshifter_1 = shamt_left[0] ? {in_oph[30:0], 1'b0} : in_oph;
    wire [31:0] lshifter_2 = shamt_left[1] ? {lshifter_1[29:0], 2'b0} : lshifter_1;
    wire [31:0] lshifter_4 = shamt_left[2] ? {lshifter_2[27:0], 4'b0} : lshifter_2;
    wire [31:0] lshifter_8 = shamt_left[3] ? {lshifter_4[23:0], 8'b0} : lshifter_4;
    wire [31:0] lshifter = shamt_left[4] ? {lshifter_8[15:0], 16'b0} : lshifter_8;

    // Ideally this should be in the always_comb, similar reason as above
    wire rsh_arith = (in_raw[15:12] == 4'b0100) && (in_raw[3:0] == 4'b1100);
    wire rsh_sign = rsh_arith && in_oph[31];
    wire [31:0] rshifter_1 = shamt_right[0] ? {rsh_sign, in_oph[31:1]} : in_oph;
    wire [31:0] rshifter_2 = shamt_right[1] ? {{2{rsh_sign}}, rshifter_1[31:2]} : rshifter_1;
    wire [31:0] rshifter_4 = shamt_right[2] ? {{4{rsh_sign}}, rshifter_2[31:4]} : rshifter_2;
    wire [31:0] rshifter_8 = shamt_right[3] ? {{8{rsh_sign}}, rshifter_4[31:8]} : rshifter_4;
    wire [31:0] rshifter = shamt_right[4] ? {{16{rsh_sign}}, rshifter_8[31:16]} : rshifter_8;

    always @(*) begin
        // Set default values
        out_t = in_t;
        out_m = in_m;
        out_s = in_s;
        out_q = in_q;
        out_wdata = 32'bx;
        out_wdst = rn;
        out_wen = 1'b1;

        // Execute
        if (in_valid) begin
            casez (in_raw)
                // ---- EX group ----
                16'b1110????????????:  // MOV #imm,Rn
                    begin
                    out_wdata = in_opl;
                end
                16'b0011????????1100,  // ADD Rm,Rn
                16'b0111????????????:  // ADD #imm,Rn
                    begin
                    out_wdata = adder[31:0];
                end
                16'b11000111????????:  // MOVA @(disp,PC),R0
                    begin
                    out_wdst = 4'd0;
                    out_wdata = adder[31:0];
                end
                16'b0000????00101001:  // MOVT Rn
                    begin
                    out_wdata = {31'd0, in_t};
                end
                16'b0011????????1110:  // ADDC Rm,Rn
                    begin
                    out_wdata = adder[31:0];
                    out_t = adder[32];
                end
                16'b0011????????1111:  // ADDV Rm,Rn
                    begin
                    out_wdata = adder[31:0];
                    out_t = (!in_opl[31] && !in_oph[31] && adder[31]) || (in_opl[31] && in_oph[31] && !adder[31]);
                end
                16'b0011????????0100:  // DIV1 Rm,Rn
                    begin
                    if (in_q == 0) begin
                        if (in_m == 0) begin
                            out_wdata = rn_shift - in_opl;
                            out_q = in_oph[31] ? (out_wdata <= rn_shift) : (out_wdata > rn_shift);
                        end else begin
                            out_wdata = rn_shift + in_opl;
                            out_q = in_oph[31] ? (out_wdata < rn_shift) : (out_wdata >= rn_shift);
                        end
                    end else begin
                        if (in_m == 0) begin
                            out_wdata = rn_shift + in_opl;
                            out_q = in_oph[31] ? (out_wdata >= rn_shift) : (out_wdata < rn_shift);
                        end else begin
                            out_wdata = rn_shift - in_opl;
                            out_q = in_oph[31] ? (out_wdata > rn_shift) : (out_wdata <= rn_shift);
                        end
                    end
                    out_t = (out_m == out_q);
                end
                16'b0010????????0111:  // DIV0S Rm,Rn
                    begin
                    out_m = in_opl[31];
                    out_q = in_oph[31];
                    out_t = !(out_m == out_q);
                    out_wen = 1'b0;
                end
                16'b0000000000011001:  // DIV0U
                    begin
                    out_m = 1'b0;
                    out_q = 1'b0;
                    out_t = 1'b0;
                    out_wen = 1'b0;
                end
                16'b0100????00010000:  // DT Rn
                    begin
                    out_wdata = in_oph - 32'd1;
                    out_t = (out_wdata == 32'd0);
                end
                16'b0110????????1000:  // SWAP.B Rm,Rn
                    begin
                    out_wdata = {in_opl[31:16], in_opl[7:0], in_opl[15:8]};
                end
                16'b0110????????1001:  // SWAP.W Rm,Rn
                    begin
                    out_wdata = {in_opl[15:0], in_opl[31:16]};
                end
                16'b0010????????1101:  // XTRCT Rm,Rn
                    begin
                    out_wdata = {in_opl[15:0], in_oph[31:16]};
                end
                16'b0110????????1110:  // EXTS.B Rm,Rn
                    begin
                    out_wdata = {{24{in_opl[7]}}, in_opl[7:0]};
                end
                16'b0110????????1111:  // EXTS.W Rm,Rn
                    begin
                    out_wdata = {{16{in_opl[15]}}, in_opl[15:0]};
                end
                16'b0110????????1100:  // EXTU.B Rm,Rn
                    begin
                    out_wdata = {24'd0, in_opl[7:0]};
                end
                16'b0110????????1101:  // EXTU.W Rm,Rn
                    begin
                    out_wdata = {16'd0, in_opl[15:0]};
                end
                16'b0110????????1011:  // NEG Rm,Rn
                    begin
                    out_wdata = sub[31:0];
                end
                16'b0011????????1000:  // SUB Rm,Rn
                    begin
                    out_wdata = sub[31:0];
                end
                16'b0110????????1010:  // NEGC Rm,Rn
                    begin
                    out_wdata = sub[31:0];
                    out_t = sub[32];
                end
                16'b0011????????1010:  // SUBC Rm,Rn
                    begin
                    out_wdata = sub[31:0];
                    out_t = sub[32];
                end
                16'b0011????????1011:  // SUBV Rm,Rn
                    begin
                    out_wdata = sub[31:0];
                    out_t = (in_opl[31] ^ in_oph[31]) &&  // input different sign
                    (sub[31] ^ in_oph[31]);  // result and minuend different sign
                end
                16'b11001001????????:  // AND #imm,R0
                    begin
                    out_wdata = in_opl & in_oph;
                    out_wdst = 4'd0;
                end
                16'b0010????????1001:  // AND Rm,Rn
                    begin
                    out_wdata = in_opl & in_oph;
                end
                16'b0110????????0111:  // NOT Rm,Rn
                    begin
                    out_wdata = ~in_opl;
                end
                16'b0010????????1011:  // OR Rm,Rn
                    begin
                    out_wdata = in_opl | in_oph;
                end
                16'b11001011????????:  // OR #imm,R0
                    begin
                    out_wdata = in_opl | in_oph;
                    out_wdst = 4'd0;
                end
                16'b0010????????1010:  // XOR Rm,Rn
                    begin
                    out_wdata = in_opl ^ in_oph;
                end
                16'b11001010????????:  // XOR #imm,R0
                    begin
                    out_wdata = in_opl ^ in_oph;
                    out_wdst = 4'd0;
                end
                16'b0100????????1100:  // SHAD Rm,Rn
                    begin
                    out_wdata = in_opl[31] ? rshifter : lshifter;
                end
                16'b0100????????1101:  // SHLD Rm,Rn
                    begin
                    out_wdata = in_opl[31] ? rshifter : lshifter;
                end
                16'b0100????00100100:  // ROTCL Rn
                    begin
                    out_t = in_oph[31];
                    out_wdata = {in_oph[30:0], in_t};
                end
                16'b0100????00100101:  // ROTCR Rn
                    begin
                    out_t = in_oph[0];
                    out_wdata = {in_t, in_oph[31:1]};
                end
                16'b0100????00000100:  // ROTL Rn
                    begin
                    out_t = in_oph[31];
                    out_wdata = {in_oph[30:0], in_oph[31]};
                end
                16'b0100????00000101:  // ROTR Rn
                    begin
                    out_t = in_oph[0];
                    out_wdata = {in_oph[0], in_oph[31:1]};
                end
                16'b0100????00000000,  // SHLL Rn
                16'b0100????00100000:  // SHAL Rn
                    begin
                    out_t = in_oph[31];
                    out_wdata = {in_oph[30:0], 1'b0};
                end
                16'b0100????00100001:  // SHAR Rn
                    begin
                    out_t = in_oph[0];
                    out_wdata = {in_oph[31], in_oph[31:1]};
                end
                16'b0100????00000001:  // SHLR Rn
                    begin
                    out_t = in_oph[0];
                    out_wdata = {1'b0, in_oph[31:1]};
                end
                16'b0100????00001000:  // SHLL2 Rn
                    begin
                    out_wdata = {in_oph[29:0], 2'b0};
                end
                16'b0100????00001001:  // SHLR2 Rn
                    begin
                    out_wdata = {2'b0, in_oph[31:2]};
                end
                16'b0100????00011000:  // SHLL8 Rn
                    begin
                    out_wdata = {in_oph[23:0], 8'b0};
                end
                16'b0100????00011001:  // SHLR8 Rn
                    begin
                    out_wdata = {8'b0, in_oph[31:8]};
                end
                16'b0100????00101000:  // SHLL16 Rn
                    begin
                    out_wdata = {in_oph[15:0], 16'b0};
                end
                16'b0100????00101001:  // SHLR16 Rn
                    begin
                    out_wdata = {16'b0, in_oph[31:16]};
                end
                default: begin
                    // Do something about this, probably
                end
            endcase
        end else begin
            out_wen = 1'b0;
        end
        out_flags = {out_m, out_q, out_s, out_t};
    end

endmodule
