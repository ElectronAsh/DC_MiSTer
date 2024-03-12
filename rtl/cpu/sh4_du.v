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

module sh4_du (
    // Input instruction
    input wire in_valid,
    input wire [31:0] in_npc,
    input wire [15:0] in_raw,
    input wire [31:0] in_rl,
    input wire [31:0] in_rh,
    input wire [31:0] in_r0,
    // Partially decoded information to execution units
    output reg [31:0] out_opl,
    output reg [31:0] out_oph,
    output reg out_use_r0,
    output reg out_use_rl,
    output reg out_use_rh,
    output reg out_write_rn,
    output reg out_write_r0,
    output reg out_fp_use_rl,
    output reg out_fp_use_rh,
    output reg out_fp_use_r0,
    output reg out_fp_ls_use_freg,
    output reg out_fp_ls_use_altbank,
    output reg out_fp_ls_use_rh,
    output reg out_fp_write_rn,
    output reg out_fp_write_altbank,
    output reg [3:0] out_fp_op,
    output reg out_use_fpul,
    output reg out_write_fpul,
    output reg out_use_csr,
    output reg out_write_csr,
    output reg out_is_mt,
    output reg out_is_ex,
    output reg out_is_br,
    output reg out_is_ls,
    output reg out_is_fp,
    output reg [3:0] out_csr_id,
    output reg out_raltbank,
    output reg out_complex,
    output reg out_use_t,
    output reg out_write_t,
    output reg out_legal
);

    wire [11:0] imm = in_raw[11:0];
    wire [31:0] imm_sext = {{24{imm[7]}}, imm[7:0]};
    wire [31:0] imm_zext = {24'b0, imm[7:0]};
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] imm_sext12 = {{20{imm[11]}}, imm[11:0]};
    /* verilator lint_on UNUSEDSIGNAL */

    always @(*) begin
        // Set default values
        out_opl = in_rl;  // Rm or R0 (in some EXU ops)
        out_oph = in_rh;  // Rn
        out_use_rl = 1'b0;  // Typically Rm
        out_use_rh = 1'b0;  // Typically Rn
        out_use_r0 = 1'b0;
        out_write_rn = 1'b0;
        out_write_r0 = 1'b0;
        out_complex = 1'b0;
        out_fp_use_rl = 1'b0;
        out_fp_use_rh = 1'b0;
        out_fp_use_r0 = 1'b0;
        out_fp_ls_use_freg = 1'b0;
        out_fp_ls_use_altbank = 1'b0;
        out_fp_ls_use_rh = 1'b0;
        out_fp_write_rn = 1'b0;
        out_fp_write_altbank = 1'b0;
        out_fp_op = 4'bx;
        out_use_fpul = 1'b0;
        out_write_fpul = 1'b0;
        out_use_csr = 1'b0;
        out_write_csr = 1'b0;
        out_is_mt = 1'b0;
        out_is_ex = 1'b0;
        out_is_br = 1'b0;
        out_is_ls = 1'b0;
        out_is_fp = 1'b0;
        out_use_t = 1'b0;
        out_write_t = 1'b0;
        out_legal = 1'b1;

        // Decode
        if (in_valid) begin
            casez (in_raw)
                // ---- MT group ----
                16'b0000000000001001:  // NOP
                    begin
                    out_is_mt = 1'b1;
                end
                16'b0110????????0011:  // MOV Rm,Rn
                    begin
                    out_is_mt = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0011????????0000,  // CMP/EQ Rm,Rn
                16'b0011????????0010,  // CMP/HS Rm,Rn
                16'b0011????????0011,  // CMP/GE Rm,Rn
                16'b0011????????0110,  // CMP/HI Rm,Rn
                16'b0011????????0111,  // CMP/GT Rm,Rn
                16'b0010????????1100,  // CMP/STR Rm,Rn
                16'b0010????????1000:  // TST Rm,Rn
                    begin
                    out_is_mt = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0100????00010001,  // CMP/PZ Rn
                16'b0100????00010101:  // CMP/PL Rn
                    begin
                    out_is_mt = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0000000000001000,  // CLRT
                16'b0000000000011000:  // SETT
                    begin
                    out_is_mt = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b10001000????????:  // CMP/EQ #imm,R0
                    begin
                    out_is_mt = 1'b1;
                    out_opl = in_r0;
                    out_oph = imm_sext;
                    out_write_t = 1'b1;
                    out_use_r0 = 1'b1;
                end
                16'b11001000????????:  // TST #imm,R0
                    begin
                    out_is_mt = 1'b1;
                    out_opl = in_r0;
                    out_oph = imm_zext;
                    out_write_t = 1'b1;
                    out_use_r0 = 1'b1;
                end
                // ---- EX group ----
                16'b1110????????????,  // MOV #imm,Rn
                16'b0111????????????:  // ADD #imm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rh = 1'b1;
                    out_opl = imm_sext;
                    out_write_rn = 1'b1;
                end
                16'b11000111????????:  // MOVA @(disp,PC),R0
                    begin
                    out_is_ex = 1'b1;
                    out_opl = in_npc;
                    out_oph = {imm_zext[29:0], 2'b0};  // disp *4
                    out_write_r0 = 1'b1;
                end
                16'b0000????00101001:  // MOVT Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_t = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0011????????1110:  // ADDC Rm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_t = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0011????????1111,  // ADDV Rm,Rn
                16'b0011????????0100,  // DIV1 Rm,Rn
                16'b0010????????0111:  // DIV0S Rm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0000000000011001:  // DIV0U
                    begin
                    out_is_ex = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0100????00010000:  // DT Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0110????????1000,  // SWAP.B Rm,Rn
                16'b0110????????1001,  // SWAP.W Rm,Rn
                16'b0010????????1101,  // XTRCT Rm,Rn
                16'b0011????????1100,  // ADD Rm,Rn
                16'b0110????????1110,  // EXTS.B Rm,Rn
                16'b0110????????1111,  // EXTS.W Rm,Rn
                16'b0110????????1100,  // EXTU.B Rm,Rn
                16'b0110????????1101,  // EXTU.W Rm,Rn
                16'b0110????????1011,  // NEG Rm,Rn
                16'b0011????????1000,  // SUB Rm,Rn
                16'b0010????????1001,  // AND Rm,Rn
                16'b0110????????0111,  // NOT Rm,Rn
                16'b0010????????1011,  // OR Rm,Rn
                16'b0010????????1010,  // XOR Rm,Rn
                16'b0100????????1100,  // SHAD Rm,Rn
                16'b0100????????1101:  // SHLD Rm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0110????????1010,  // NEGC Rm,Rn
                16'b0011????????1010:  // SUBC Rm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_t = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0011????????1011:  // SUBV Rm,Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b11001001????????,  // AND #imm,R0
                16'b11001011????????,  // OR #imm,R0
                16'b11001010????????:  // XOR #imm,R0
                    begin
                    out_is_ex = 1'b1;
                    out_opl = in_r0;
                    out_oph = imm_zext;
                    out_use_r0 = 1'b1;
                    out_write_r0 = 1'b1;
                end
                16'b0100????00100100,  // ROTCL Rn
                16'b0100????00100101:  // ROTCR Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_t = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0100????00000100,  // ROTL Rn
                16'b0100????00000101,  // ROTR Rn
                16'b0100????00100000,  // SHAL Rn
                16'b0100????00100001,  // SHAR Rn
                16'b0100????00000000,  // SHLL Rn
                16'b0100????00000001:  // SHLR Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                    out_write_t = 1'b1;
                end
                16'b0100????00001000,  // SHLL2 Rn
                16'b0100????00001001,  // SHLR2 Rn
                16'b0100????00011000,  // SHLL8 Rn
                16'b0100????00011001,  // SHLR8 Rn
                16'b0100????00101000,  // SHLL16 Rn
                16'b0100????00101001:  // SHLR16 Rn
                    begin
                    out_is_ex = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                end
                // ----  BR group ----
                16'b10001011????????,  // BF label
                16'b10001111????????,  // BF/S label
                16'b10001001????????,  // BT label
                16'b10001101????????:  // BT/S label
                    begin
                    out_is_br = 1'b1;
                    out_use_t = 1'b1;
                    out_oph = in_npc;
                    out_opl = {imm_sext[30:0], 1'b0};  // x2
                end
                16'b1010????????????,  // BRA label
                16'b1011????????????:  // BSR label
                    begin
                    out_is_br = 1'b1;
                    out_oph = in_npc;
                    out_opl = {imm_sext12[30:0], 1'b0};  // x2
                end
                // ---- LS group ----
                16'b1001????????????:  // MOV.W @(disp,PC),Rn
                    begin
                    out_is_ls = 1'b1;
                    out_oph = in_npc;
                    out_opl = {imm_zext[30:0], 1'b0};  // x2
                    out_write_rn = 1'b1;
                end
                16'b1101????????????:  // MOV.L @(disp,PC),Rn
                    begin
                    out_is_ls = 1'b1;
                    out_oph = {in_npc[31:2], 2'b0};  // aligned + 4
                    out_opl = {imm_zext[29:0], 2'b0};  // x4
                    out_write_rn = 1'b1;
                end
                16'b0010????????0000,  // MOV.B Rm,@Rn
                16'b0010????????0001,  // MOV.W Rm,@Rn
                16'b0010????????0010:  // MOV.L Rm,@Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                end
                16'b0110????????0000,  // MOV.B @Rm,Rn
                16'b0110????????0001,  // MOV.W @Rm,Rn
                16'b0110????????0010:  // MOV.L @Rm,Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0010????????0100,  // MOV.B Rm,@-Rn
                16'b0010????????0101,  // MOV.W Rm,@-Rn
                16'b0010????????0110:  // MOV.L Rm,@-Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0110????????0100,  // MOV.B @Rm+,Rn
                16'b0110????????0101,  // MOV.W @Rm+,Rn
                16'b0110????????0110:  // MOV.L @Rm+,Rn
                    begin
                    out_complex = 1'b1;
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b10000000????????,  // MOV.B R0,@(disp,Rn)
                16'b10000001????????:  // MOV.W R0,@(disp,Rn)
                    begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_r0 = 1'b1;
                    // Imm4 is directly used by LSU, not assigned here
                end
                16'b0001????????????:  // MOV.L Rm,@(disp,Rn)
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                end
                16'b10000100????????,  // MOV.B @(disp,Rm),R0
                16'b10000101????????:  // MOV.W @(disp,Rm),R0
                    begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_write_r0 = 1'b1;
                end
                16'b0101????????????:  // MOV.L @(disp,Rm),Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0000????????0100,  // MOV.B Rm,@(R0,Rn)
                16'b0000????????0101,  // MOV.W Rm,@(R0,Rn)
                16'b0000????????0110:  // MOV.L Rm,@(R0,Rn)
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_r0 = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0000????????1100,  // MOV.B @(R0,Rm),Rn
                16'b0000????????1101,  // MOV.W @(R0,Rm),Rn
                16'b0000????????1110:  // MOV.L @(R0,Rm),Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_use_r0 = 1'b1;
                    out_oph = in_r0;
                    out_write_rn = 1'b1;
                end
                16'b11000000????????:  // MOV.B R0,@(disp,GBR)
                    begin
                    out_is_ls = 1'b1;
                    out_opl = imm_zext;
                    out_use_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b11000001????????:  // MOV.W R0,@(disp,GBR)
                    begin
                    out_is_ls = 1'b1;
                    out_opl = {imm_zext[30:0], 1'b0};  // x2
                    out_use_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b11000010????????:  // MOV.L R0,@(disp,GBR)
                    begin
                    out_is_ls = 1'b1;
                    out_opl = {imm_zext[29:0], 2'b0};  // x4
                    out_use_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b11000100????????:  // MOV.B @(disp,GBR),R0
                    begin
                    out_is_ls = 1'b1;
                    out_opl = imm_zext;
                    out_write_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b11000101????????:  // MOV.W @(disp,GBR),R0
                    begin
                    out_is_ls = 1'b1;
                    out_opl = {imm_zext[30:0], 1'b0};  // x2
                    out_write_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b11000110????????:  // MOV.L @(disp,GBR),R0
                    begin
                    out_is_ls = 1'b1;
                    out_opl = {imm_zext[29:0], 2'b0};  // x4
                    out_write_r0 = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b0000????11000011:  // MOVCA.L R0,@Rn
                    begin
                    out_is_ls = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b0000????10010011,  // OCBI @Rn
                16'b0000????10100011,  // OCBP @Rn
                16'b0000????10110011,  // OCBWB @Rn
                16'b0000????10000011:  // PREF @Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                end
                16'b1111????10001101,  // FLDI0 FRn
                16'b1111????10011101:  // FLDI1 FRn
                    begin
                    out_is_ls = 1'b1;
                    out_fp_write_rn = 1'b1;
                end
                16'b1111????????1100:  // FMOV FRm,FRn
                    //16'b1111???0???01100, // FMOV DRm,DRn
                    //16'b1111???1???01100, // FMOV DRm,XDn
                    //16'b1111???0???11100, // FMOV XDm,DRn
                    //16'b1111???1???11100, // FMOV XDm,XDn
                begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_fp_write_rn = 1'b1;
                end
                16'b1111????????1000:  // FMOV.S @Rm,FRn
                    //16'b1111???0????1000, // FMOV @Rm,DRn
                    //16'b1111???1????1000, // FMOV @Rm,XDn
                begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_fp_write_rn = 1'b1;
                end
                16'b1111????????0110:  // FMOV.S @(R0,Rm),FRn
                    //16'b1111???0????0110, // FMOV @(R0,Rm),DRn
                    //16'b1111???1????0110, // FMOV @(R0,Rm),XDn
                begin
                    out_is_ls = 1'b1;
                    out_use_r0 = 1'b1;
                    out_use_rl = 1'b1;
                    out_fp_write_rn = 1'b1;
                end
                16'b1111????????1001:  // FMOV.S @Rm+,FRn
                    //16'b1111???0????1001, // FMOV @Rm+,DRn
                    //16'b1111???1????1001, // FMOV @Rm+,XDn
                begin
                    out_is_ls = 1'b1;
                    out_use_rl = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_complex = 1'b1;
                end
                16'b1111????????1010:  // FMOV.S FRm,@Rn
                    //16'b1111???????01010, // FMOV DRm,@Rn
                    //16'b1111???????11010, // FMOV XDm,@Rn
                begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_use_rh = 1'b1;
                end
                16'b1111????????1011:  // FMOV.S FRm,@-Rn
                    //16'b1111???????01011, // FMOV DRm,@-Rn
                    //16'b1111???????11011, // FMOV XDm,@-Rn
                begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_rn = 1'b1;
                end
                16'b1111????????0111:  // FMOV.S FRm,@(R0,Rn)
                    //16'b1111???????00111, // FMOV DRm,@(R0,Rn)
                    //16'b1111???????10111, // FMOV XDm,@(R0,Rn)
                begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_use_r0 = 1'b1;
                    out_use_rh = 1'b1;
                end
                16'b1111????00011101:  // FLDS FRm,FPUL
                    begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_fp_ls_use_rh = 1'b1;
                    out_write_fpul = 1'b1;
                end
                16'b1111????00001101:  // FSTS FPUL,FRn
                    begin
                    out_is_ls = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_use_fpul = 1'b1;
                end
                16'b1111????01011101,  // FABS FRn
                //16'b1111???001011101, // FABS DRn
                16'b1111????01001101:  // FNEG FRn
                    //16'b1111???001001101, // FNEG DRn
                begin
                    out_is_ls = 1'b1;
                    out_fp_ls_use_freg = 1'b1;
                    out_fp_ls_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                end
                16'b0100????01011010:  // LDS Rm,FPUL
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_fpul = 1'b1;
                end
                16'b0000????01011010:  // STS FPUL,Rn
                    begin
                    out_is_ls = 1'b1;
                    out_write_rn = 1'b1;
                    out_use_fpul = 1'b1;
                end
                // ---- FE group ----
                16'b1111????????0000:  // FADD FRm,FRn
                    //16'b1111???0???00000, // FADD DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FADD;
                end
                16'b1111????????0100:  // FCMP/EQ FRm,FRn
                    //16'b1111???0???00100, // FCMP/EQ DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_write_t = 1'b1;
                    out_fp_op = `FOP_CMPEQ;
                end
                16'b1111????????0101:  // FCMP/GT FRm,FRn
                    //16'b1111???0???00101, // FCMP/GT DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_write_t = 1'b1;
                    out_fp_op = `FOP_CMPGT;
                end
                16'b1111????????0011:  // FDIV FRm,FRn
                    //16'b1111???0???00011, // FDIV DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FDIV;
                end
                16'b1111????00101101:  // FLOAT FPUL,FRn
                    //16'b1111???000101101, // FLOAT FPUL,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FLOAT;
                    out_use_fpul = 1'b1;
                end
                16'b1111????????1110:  // FMAC FR0,FRm,FRn
                    begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_fp_use_r0 = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FMAC;
                end
                16'b1111????????0010:  // FMUL FRm,FRn
                    //16'b1111???0???00010, // FMUL DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FMUL;
                end
                16'b1111????01101101:  // FSQRT FRn
                    //16'b1111???001101101, // FSQRT DRn
                begin
                    out_fp_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FSQRT;
                end
                16'b1111????????0001:  // FSUB FRm,FRn
                    //16'b1111???0???00001, // FSUB DRm,DRn
                begin
                    out_is_fp = 1'b1;
                    out_fp_use_rl = 1'b1;
                    out_fp_use_rh = 1'b1;
                    out_fp_write_rn = 1'b1;
                    out_fp_op = `FOP_FSUB;
                end
                16'b1111????00111101:  // FTRC FRm,FPUL
                    //16'b1111???000111101, // FTRC DRm,FPUL
                begin
                    out_fp_use_rh = 1'b1;
                    out_fp_op = `FOP_FSQRT;
                    out_write_fpul = 1'b1;
                end
                16'b1111???010111101:  // FCNVDS DRm,FPUL
                    begin
                    out_fp_use_rh = 1'b1;
                    out_fp_op = `FOP_FCNVDS;
                    out_write_fpul = 1'b1;
                end
                16'b1111???010101101:  // FCNVSD FPUL,DRn
                    begin
                    out_fp_use_rh = 1'b1;
                    out_fp_op = `FOP_FCNVSD;
                    out_use_fpul = 1'b1;
                end
                16'b0100????00011011:  // TAS.B @Rn
                    begin
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_csr = 1'b1;  // Touches status register
                end
                16'b11001101????????,  // AND.B #imm,@(R0,GBR)
                16'b11001111????????,  // OR.B #imm,@(R0,GBR)
                16'b11001100????????,  // TST.B #imm,@(R0,GBR)
                16'b11001110????????:  // XOR.B #imm,@(R0,GBR)
                    begin
                    out_is_ls = 1'b1;
                    out_use_r0 = 1'b1;
                    out_opl = imm_zext;
                    out_use_csr = 1'b1;
                    out_write_csr = 1'b1;
                end
                16'b1111????11101101,  // FIPR FVm,FVn
                16'b1111??0111111101,  // FTRV XMTRX,FVn
                16'b1111101111111101,  // FRCHG
                16'b1111001111111101,  // FSCHG
                // CO group
                16'b0000000000101000,  // CLRMAC
                16'b0011????????1101,  // DMULS.L Rm,Rn
                16'b0011????????0101,  // DMULU.L Rm,Rn
                16'b0000????????1111,  // MAC.L @Rm+,@Rn+
                16'b0100????????1111,  // MAC.W @Rm+,@Rn+
                16'b0000????????0111,  // MUL.L Rm,Rn
                16'b0010????????1111,  // MULS.W Rm,Rn
                16'b0010????????1110:  // MULU.W Rm,Rn
                    begin
                    // UNIMP
                end
                16'b0000????00100011,  // BRAF Rn
                16'b0000????00000011,  // BSRF Rn
                16'b0100????00101011,  // JMP @Rn
                16'b0100????00001011:  // JSR @Rn
                    begin
                    out_complex = 1'b1;
                    out_use_rh = 1'b1;
                    out_is_br = 1'b1;
                    out_opl = in_npc;
                end
                16'b0000000000001011,  // RTS
                16'b0000000000101011:  // RTE
                    begin
                    out_complex = 1'b1;
                    out_is_br = 1'b1;
                    out_opl = in_npc;
                    out_use_csr = 1'b1;
                end
                16'b0000000001001000,  // CLRS
                16'b0000000001011000:  // SETS 
                    begin
                    out_complex = 1'b1;
                    out_is_ex = 1'b1;
                end
                16'b0100????00001110,  // LDC Rm,SR
                16'b0100????00011110,  // LDC Rm,GBR
                16'b0100????00101110,  // LDC Rm,VBR
                16'b0100????00111110,  // LDC Rm,SSR
                16'b0100????01001110,  // LDC Rm,SPC
                16'b0100????11111010,  // LDC Rm,DBR
                16'b0100????1???1110,  // LDC Rm,Rn_BANK
                16'b0100????00000111,  // LDC.L @Rm+,SR
                16'b0100????00010111,  // LDC.L @Rm+,GBR
                16'b0100????00100111,  // LDC.L @Rm+,VBR
                16'b0100????00110111,  // LDC.L @Rm+,SSR
                16'b0100????01000111,  // LDC.L @Rm+,SPC
                16'b0100????11110110,  // LDC.L @Rm+,DBR
                16'b0100????1???0111,  // LDC.L @Rm+,Rn_BANK
                16'b0100????00001010,  // LDS Rm,MACH
                16'b0100????00011010,  // LDS Rm,MACL
                16'b0100????00101010,  // LDS Rm,PR
                16'b0100????01101010,  // LDS Rm,FPSCR
                16'b0100????00000110,  // LDS.L @Rm+,MACH
                16'b0100????00010110,  // LDS.L @Rm+,MACL
                16'b0100????00100110,  // LDS.L @Rm+,PR
                16'b0100????01100110,  // LDS.L @Rm+,FPSCR
                16'b0100????01010110:  // LDS.L @Rm+,FPUL
                    begin
                    out_complex = 1'b1;
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_write_csr = 1'b1;
                end
                16'b0100????00000011,  // STC.L SR,@-Rn
                16'b0100????00010011,  // STC.L GBR,@-Rn
                16'b0100????00100011,  // STC.L VBR,@-Rn
                16'b0100????00110011,  // STC.L SSR,@-Rn
                16'b0100????01000011,  // STC.L SPC,@-Rn
                16'b0100????00110010,  // STC.L SGR,@-Rn
                16'b0100????11110010,  // STC.L DBR,@-Rn
                16'b0100????1???0011,  // STC.L Rm_BANK,@-Rn
                16'b0100????00000010,  // STS.L MACH,@-Rn
                16'b0100????00010010,  // STS.L MACL,@-Rn
                16'b0100????00100010,  // STS.L PR,@-Rn
                16'b0100????01100010,  // STS.L FPSCR,@-Rn
                16'b0100????01010010:  // STS.L FPUL,@-Rn
                    begin
                    out_complex = 1'b1;
                    out_is_ls = 1'b1;
                    out_use_rh = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b0000????00000010,  // STC SR,Rn
                16'b0000????00010010,  // STC GBR,Rn
                16'b0000????00100010,  // STC VBR,Rn
                16'b0000????00110010,  // STC SSR,Rn
                16'b0000????01000010,  // STC SPC,Rn
                16'b0000????00111010,  // STC SGR,Rn
                16'b0000????11111010,  // STC DBR,Rn
                16'b0000????1???0010,  // STC Rm_BANK,Rn
                16'b0000????00001010,  // STS MACH,Rn
                16'b0000????00011010,  // STS MACL,Rn
                16'b0000????00101010,  // STS PR,Rn
                16'b0000????01101010:  // STS FPSCR,Rn
                    begin
                    // Write fields doesn't apply to complex instructions
                    out_complex = 1'b1;
                    out_is_ls = 1'b1;
                    out_use_csr = 1'b1;
                end
                16'b0000000000111000,  // LDTLB 
                16'b0000000000011011,  // SLEEP 
                16'b11000011????????:  // TRAPA #imm
                    begin
                    // Assertion here is triggered regardless of in_valid signal 
                    //$error("Unsupported opcode"); 
                end
                default: begin
                    out_legal = 1'b0;
                end
            endcase
        end
    end

    // CSR ID decoder
    always @(*) begin
        casez (in_raw)
            16'b0100????00001110,  // LDC Rm,SR
            16'b0100????00000111,  // LDC.L @Rm+,SR
            16'b0000????00000010,  // STC SR,Rn
            16'b0100????00000011:  // STC.L SR,@-Rn
            out_csr_id = `CSR_SR;
            16'b11000000????????,  // MOV.B R0,@(disp,GBR)
            16'b11000001????????,  // MOV.W R0,@(disp,GBR)
            16'b11000010????????,  // MOV.L R0,@(disp,GBR)
            16'b11000100????????,  // MOV.B @(disp,GBR),R0
            16'b11000101????????,  // MOV.W @(disp,GBR),R0
            16'b11000110????????,  // MOV.L @(disp,GBR),R0
            16'b11001101????????,  // AND.B #imm,@(R0,GBR)
            16'b11001111????????,  // OR.B #imm,@(R0,GBR)
            16'b11001100????????,  // TST.B #imm,@(R0,GBR)
            16'b11001110????????,  // XOR.B #imm,@(R0,GBR)
            16'b0100????00011110,  // LDC Rm,GBR
            16'b0100????00010111,  // LDC.L @Rm+,GBR
            16'b0000????00010010,  // STC GBR,Rn
            16'b0100????00010011:  // STC.L GBR,@-Rn
            out_csr_id = `CSR_GBR;
            16'b0100????00101110,  // LDC Rm,VBR
            16'b0100????00100111,  // LDC.L @Rm+,VBR
            16'b0000????00100010,  // STC VBR,Rn
            16'b0100????00100011:  // STC.L VBR,@-Rn
            out_csr_id = `CSR_VBR;
            16'b0100????00111110,  // LDC Rm,SSR
            16'b0100????00110111,  // LDC.L @Rm+,SSR
            16'b0000????00110010,  // STC SSR,Rn
            16'b0100????00110011:  // STC.L SSR,@-Rn
            out_csr_id = `CSR_SSR;
            16'b0100????01001110,  // LDC Rm,SPC
            16'b0100????01000111,  // LDC.L @Rm+,SPC
            16'b0000????01000010,  // STC SPC,Rn
            16'b0100????01000011:  // STC.L SPC,@-Rn
            out_csr_id = `CSR_SPC;
            16'b0100????11111010,  // LDC Rm,DBR
            16'b0100????11110110,  // LDC.L @Rm+,DBR
            16'b0000????11111010,  // STC DBR,Rn
            16'b0100????11110010:  // STC.L DBR,@-Rn
            out_csr_id = `CSR_DBR;
            16'b0000????00111010,  // STC SGR,Rn
            16'b0100????00110010:  // STC.L SGR,@-Rn
            out_csr_id = `CSR_SGR;
            16'b0100????00001010,  // LDS Rm,MACH
            16'b0100????00000110,  // LDS.L @Rm+,MACH
            16'b0000????00001010,  // STS MACH,Rn
            16'b0100????00000010:  // STS.L MACH,@-Rn
            out_csr_id = `CSR_MACH;
            16'b0100????00011010,  // LDS Rm,MACL
            16'b0100????00010110,  // LDS.L @Rm+,MACL
            16'b0000????00011010,  // STS MACL,Rn
            16'b0100????00010010:  // STS.L MACL,@-Rn
            out_csr_id = `CSR_MACL;
            16'b0100????00101010,  // LDS Rm,PR
            16'b0100????00100110,  // LDS.L @Rm+,PR
            16'b0000????00101010,  // STS PR,Rn
            16'b0100????00100010:  // STS.L PR,@-Rn
            out_csr_id = `CSR_PR;
            16'b0100????01101010,  // LDS Rm,FPSCR
            16'b0100????01100110,  // LDS.L @Rm+,FPSCR
            16'b0000????01101010,  // STS FPSCR,Rn
            16'b0100????01100010:  // STS.L FPSCR,@-Rn
            out_csr_id = `CSR_FPSCR;
            16'b0100????01010110,  // LDS.L @Rm+,FPUL
            16'b0100????01010010,  // STS.L FPUL,@-Rn
            16'b1111????00011101,  // FLDS FRm,FPUL
            16'b1111????00001101,  // FSTS FPUL,FRn
            16'b0100????01011010,  // LDS Rm,FPUL
            16'b0000????01011010:  // STS FPUL,Rn
            out_csr_id = `CSR_FPUL;
            default: out_csr_id = 4'bx;
        endcase
    end

    // Alternative bank decoder
    always @(*) begin
        casez (in_raw)
            16'b0000????1???0010,  // STC Rm_BANK,Rn
            16'b0100????1???0011:  // STC.L Rm_BANK,@-Rn
            out_raltbank = 1'b1;
            default: out_raltbank = 1'b0;
        endcase
    end

endmodule
