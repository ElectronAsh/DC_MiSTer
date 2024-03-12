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

module sh4_lsu (
    input wire clk,
    input wire rst,
    // Flush
    input wire e1_flush,
    // Input modes
    input wire fpscr_sz,
    // Input instruction
    input wire in_valid,
    input wire [31:0] in_csr_rdata,
    input wire [31:0] in_r0,
    input wire [31:0] in_fpr,
    input wire [15:0] in_raw,
    input wire [31:0] in_opl,
    input wire [31:0] in_oph,
    // Result output
    output reg e1_alt_wen,
    output reg [3:0] e1_alt_wdst,
    output reg [31:0] e1_alt_wdata,
    output reg e1_fpul_wen,
    output reg e1_wpending,
    output reg e1_wfp,
    output reg e1_wen,
    output reg [3:0] e1_wdst,
    output reg [31:0] e1_wdata,
    output reg e2_csr_wen,
    output reg [31:0] e2_csr_wdata,
    output reg e2_csr_tonly,
    output reg e2_nack,
    output reg e2_fpul_wen,
    output reg e2_waltbank,
    output reg e2_wfp,
    output reg e2_wen,
    output reg [3:0] e2_wdst,
    output reg [31:0] e2_wdata,
    // Dmem interface
    output reg [31:0] dm_req_addr,
    output reg [63:0] dm_req_wdata,
    output reg [7:0] dm_req_wmask,
    output reg dm_req_wen,
    output reg dm_req_valid,
    input wire [63:0] dm_resp_rdata,
    input wire dm_resp_valid,
    output reg dm_req_flush,
    output reg dm_req_invalidate,
    output reg dm_req_writeback,
    output reg dm_req_prefetch,
    output reg dm_req_nofill
);

    reg [1:0] rwsize;
    localparam SZ_BYTE = 2'd0;  // 8
    localparam SZ_WORD = 2'd1;  // 16
    localparam SZ_LONG = 2'd2;  // 32
    localparam SZ_DOUBLE = 2'd3;  // 64
    reg [63:0] wdata;

    wire [3:0] imm4 = in_raw[3:0];
    wire [5:0] imm4_zext_shifted = (rwsize == SZ_BYTE) ?
        ({2'd0, imm4}) : (rwsize == SZ_WORD) ? ({1'd0, imm4, 1'd0}) : (rwsize == SZ_LONG) ? ({imm4, 2'b0}) : 6'bx;

    wire [31:0] addr_gen = in_opl + in_oph;
    wire [31:0] addr_gen_imm4 = in_opl + imm4_zext_shifted;
    wire [31:0] addr_gen_imm4h = in_oph + {imm4, 2'b0};  // Uses OPH
    wire [31:0] addr_gen_r0 = in_oph + in_r0;
    wire [31:0] addr_gen_gbr = in_opl + in_csr_rdata;  // Imm8 is handled in DU
    wire [31:0] addr_gen_r0_gbr = in_r0 + in_csr_rdata;

    wire [3:0] rh = in_raw[11:8];
    wire [3:0] rl = in_raw[7:4];
    // opl - rl (typ Rm)
    // oph - rh (typ Rn)
    // For LSU, all R0 should come in as oph

    wire [31:0] rwsize_bytes = (rwsize == SZ_BYTE) ? 32'd1 : (rwsize == SZ_WORD) ? 32'd2 : (rwsize == SZ_LONG) ? 32'd4 : 32'd8;
    wire [31:0] rn_dec = in_oph - rwsize_bytes;
    wire [31:0] rl_inc = in_opl + rwsize_bytes;  // Used in LD @Rm+, Rn
    wire [31:0] rh_inc = in_oph + rwsize_bytes;  // Used in LD @Rm+, CSR

    reg is_load;
    reg is_gprw;  // Non-memory GPR write
    reg is_store;
    reg is_amo;  // AMO flag is not exclusive

    reg use_passthrough;  // For REG to REG copy in CSR ops or FP ops
    reg use_passthrough_csr;
    reg [31:0] passthrough_val;
    reg write_csr;
    reg waltbank;
    reg amo_write_t;

    // States for atomic operations
    localparam AMO_READ = 1'b0;
    localparam AMO_WRITE = 1'b1;
    reg amo_state;
    reg [7:0] amo_oldval;

    // E1 stage logic
    always @(*) begin
        // Set default values
        dm_req_addr = addr_gen;
        wdata = 64'bx;
        dm_req_valid = 1'b0;
        dm_req_flush = 1'b0;
        dm_req_invalidate = 1'b0;
        dm_req_writeback = 1'b0;
        dm_req_prefetch = 1'b0;
        dm_req_nofill = 1'b0;
        // E1 register write is for hazard detection and forwarding
        // wen && wpending: the data is not ready, could be a hazard
        // wen && !wpending: the data is ready to be forwarded
        // !wen: the register is not used
        e1_wdata = 32'bx;
        e1_wdst = rh;
        // E1 alt register write allows using write port for another pipeline
        // This is only available if the decode unit marks this instruction as
        // "complex" so another pipeline is not used.
        e1_alt_wen = 1'b0;
        e1_alt_wdst = 4'bx;
        e1_alt_wdata = 32'bx;
        // For CSR use only
        use_passthrough = 1'b0;
        use_passthrough_csr = 1'b0;
        passthrough_val = 32'bx;
        waltbank = 1'b0;
        write_csr = 1'b0;
        // For FP use only
        e1_fpul_wen = 1'b0;
        e1_wfp = 1'b0;
        // For AMO use only
        amo_write_t = 1'bx;

        // Set default based on access type
        if (is_load || is_gprw) begin
            e1_wen = 1'b1;
            e1_wpending = 1'b1;
            dm_req_wen = 1'b0;
        end else if (is_store) begin
            e1_wen = 1'b0;
            e1_wpending = 1'b0;
            dm_req_wen = 1'b1;
        end else begin
            e1_wen = 1'b0;
            e1_wpending = 1'b0;
            dm_req_wen = 1'b0;
        end

        // Execute
        if (in_valid) begin
            if (is_load || is_store) begin
                dm_req_valid = 1'b1;
            end
            casez (in_raw)
                16'b1001????????????,  // MOV.W @(disp,PC),Rn
                16'b1101????????????,  // MOV.L @(disp,PC),Rn
                16'b0000????????1100,  // MOV.B @(R0,Rm),Rn
                16'b0000????????1101,  // MOV.W @(R0,Rm),Rn
                16'b0000????????1110:  // MOV.L @(R0,Rm),Rn
                    begin
                    // Nothing to be done here
                end
                16'b0010????????0000,  // MOV.B Rm,@Rn
                16'b0010????????0001,  // MOV.W Rm,@Rn
                16'b0010????????0010:  // MOV.L Rm,@Rn
                    begin
                    dm_req_addr = in_oph;
                    wdata = {32'b0, in_opl};
                end
                16'b0110????????0000,  // MOV.B @Rm,Rn
                16'b0110????????0001,  // MOV.W @Rm,Rn
                16'b0110????????0010:  // MOV.L @Rm,Rn
                    begin
                    dm_req_addr = in_opl;
                end
                16'b0010????????0100,  // MOV.B Rm,@-Rn
                16'b0010????????0101,  // MOV.W Rm,@-Rn
                16'b0010????????0110:  // MOV.L Rm,@-Rn
                    begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rn_dec;
                    e1_wpending = 1'b0;
                    dm_req_addr = rn_dec;
                    wdata = {32'b0, in_opl};
                end
                16'b0110????????0100,  // MOV.B @Rm+,Rn
                16'b0110????????0101,  // MOV.W @Rm+,Rn
                16'b0110????????0110:  // MOV.L @Rm+,Rn
                    begin
                    e1_alt_wen = (rl != rh);  // Move result take precedence
                    e1_alt_wdst = rl;
                    e1_alt_wdata = rl_inc;
                    dm_req_addr = in_opl;
                end
                16'b10000000????????,  // MOV.B R0,@(disp,Rn)
                16'b10000001????????:  // MOV.W R0,@(disp,Rn)
                    begin
                    dm_req_addr = addr_gen_imm4;
                    wdata = {32'b0, in_r0};
                end
                16'b0001????????????:  // MOV.L Rm,@(disp,Rn)
                    begin
                    dm_req_addr = addr_gen_imm4h;
                    wdata = {32'b0, in_opl};
                end
                16'b10000100????????:  // MOV.B @(disp,Rm),R0
                    begin
                    e1_wdst = 4'd0;
                    dm_req_addr = addr_gen_imm4;
                end
                16'b0101????????????:  // MOV.L @(disp,Rm),Rn
                    begin
                    dm_req_addr = addr_gen_imm4;
                end
                16'b0000????????0100,  // MOV.B Rm,@(R0,Rn)
                16'b0000????????0101,  // MOV.W Rm,@(R0,Rn)
                16'b0000????????0110:  // MOV.L Rm,@(R0,Rn)
                    begin
                    dm_req_addr = addr_gen_r0;
                    wdata = {32'b0, in_opl};
                end
                16'b11000000????????,  // MOV.B R0,@(disp,GBR)
                16'b11000001????????,  // MOV.W R0,@(disp,GBR)
                16'b11000010????????:  // MOV.L R0,@(disp,GBR)
                    begin
                    dm_req_addr = addr_gen_gbr;
                    wdata = {32'b0, in_r0};
                end
                16'b11000100????????,  // MOV.B @(disp,GBR),R0
                16'b11000101????????,  // MOV.W @(disp,GBR),R0
                16'b11000110????????:  // MOV.L @(disp,GBR),R0
                    begin
                    dm_req_addr = addr_gen_gbr;
                    e1_wdst = 4'd0;
                end
                16'b0000????11000011:  // MOVCA.L R0,@Rn
                    begin
                    dm_req_addr = in_oph;
                    wdata = {32'b0, in_r0};
                    dm_req_nofill = 1'b1;
                end
                16'b0000????10010011:  // OCBI @Rn
                    begin
                    dm_req_addr = in_oph;
                    dm_req_invalidate = 1'b1;
                end
                16'b0000????10100011:  // OCBP @Rn
                    begin
                    dm_req_addr = in_oph;
                    dm_req_flush = 1'b1;
                end
                16'b0000????10110011:  // OCBWB @Rn
                    begin
                    dm_req_addr = in_oph;
                    dm_req_writeback = 1'b1;
                end
                16'b0000????10000011:  // PREF @Rn
                    begin
                    dm_req_addr = in_oph;
                    dm_req_prefetch = 1'b1;
                    // TODO: HANDLE PREFETCH TO STORE QUEUE
                end
                // CSR related instructions
                16'b0100????00001110,  // LDC Rm,SR
                16'b0100????00011110,  // LDC Rm,GBR
                16'b0100????00101110,  // LDC Rm,VBR
                16'b0100????00111110,  // LDC Rm,SSR
                16'b0100????01001110,  // LDC Rm,SPC
                16'b0100????11111010,  // LDC Rm,DBR
                16'b0100????00001010,  // LDS Rm,MACH
                16'b0100????00011010,  // LDS Rm,MACL
                16'b0100????00101010,  // LDS Rm,PR
                16'b0100????01101010:  // LDS Rm,FPSCR
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_oph;
                    write_csr = 1'b1;
                end
                16'b0100????1???1110:  // LDC Rm,Rn_BANK
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_oph;
                    waltbank = 1'b1;
                end
                16'b0100????00000111,  // LDC.L @Rm+,SR
                16'b0100????00010111,  // LDC.L @Rm+,GBR
                16'b0100????00100111,  // LDC.L @Rm+,VBR
                16'b0100????00110111,  // LDC.L @Rm+,SSR
                16'b0100????01000111,  // LDC.L @Rm+,SPC
                16'b0100????11110110,  // LDC.L @Rm+,DBR
                16'b0100????00000110,  // LDS.L @Rm+,MACH
                16'b0100????00010110,  // LDS.L @Rm+,MACL
                16'b0100????00100110,  // LDS.L @Rm+,PR
                16'b0100????01100110,  // LDS.L @Rm+,FPSCR
                16'b0100????01010110:  // LDS.L @Rm+,FPUL
                    begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rh_inc;
                    e1_wpending = 1'b0;
                    dm_req_addr = in_oph;
                    write_csr = 1'b1;
                end
                16'b0100????1???0111:  // LDC.L @Rm+,Rn_BANK
                    begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rh_inc;
                    e1_wpending = 1'b0;
                    dm_req_addr = in_oph;
                    waltbank = 1'b1;
                end
                16'b0000????00000010,  // STC SR,Rn
                16'b0000????00010010,  // STC GBR,Rn
                16'b0000????00100010,  // STC VBR,Rn
                16'b0000????00110010,  // STC SSR,Rn
                16'b0000????01000010,  // STC SPC,Rn
                16'b0000????00111010,  // STC SGR,Rn
                16'b0000????11111010,  // STC DBR,Rn
                16'b0000????00001010,  // STS MACH,Rn
                16'b0000????00011010,  // STS MACL,Rn
                16'b0000????00101010,  // STS PR,Rn
                16'b0000????01101010:  // STS FPSCR,Rn
                    begin
                    use_passthrough = 1'b1;
                    use_passthrough_csr = 1'b1;
                end
                16'b0000????1???0010:  // STC Rm_BANK,Rn
                    begin
                    // This is basically reg to reg move...
                    // Alt bank handling is outside of this module
                    use_passthrough = 1'b1;
                    passthrough_val = in_oph;
                end
                16'b0100????00000011,  // STC.L SR,@-Rn
                16'b0100????00010011,  // STC.L GBR,@-Rn
                16'b0100????00100011,  // STC.L VBR,@-Rn
                16'b0100????00110011,  // STC.L SSR,@-Rn
                16'b0100????01000011,  // STC.L SPC,@-Rn
                16'b0100????00110010,  // STC.L SGR,@-Rn
                16'b0100????11110010,  // STC.L DBR,@-Rn
                16'b0100????00000010,  // STS.L MACH,@-Rn
                16'b0100????00010010,  // STS.L MACL,@-Rn
                16'b0100????00100010,  // STS.L PR,@-Rn
                16'b0100????01100010,  // STS.L FPSCR,@-Rn
                16'b0100????01010010:  // STS.L FPUL,@-Rn
                    begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rn_dec;
                    e1_wpending = 1'b0;
                    dm_req_addr = rn_dec;
                    wdata = {32'b0, in_csr_rdata};
                end
                16'b0100????1???0011:  // STC.L Rm_BANK,@-Rn
                    begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rn_dec;
                    e1_wpending = 1'b0;
                    dm_req_addr = rn_dec;
                    wdata = {32'b0, in_opl};
                end
                // FP related instructions
                16'b1111????10001101:  // FLDI0 FRn
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = 32'h0;
                    e1_wfp = 1'b1;
                end
                16'b1111????10011101:  // FLDI1 FRn
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = 32'h3f800000;
                    e1_wfp = 1'b1;
                end
                16'b1111????????1100:  // FMOV FRm,FRn
                    //16'b1111???0???01100, // FMOV DRm,DRn
                    //16'b1111???1???01100, // FMOV DRm,XDn
                    //16'b1111???0???11100, // FMOV XDm,DRn
                    //16'b1111???1???11100, // FMOV XDm,XDn
                begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_fpr;
                    e1_wfp = 1'b1;
                end
                16'b1111????????1000:  // FMOV.S @Rm,FRn
                    //16'b1111???0????1000, // FMOV @Rm,DRn
                    //16'b1111???1????1000, // FMOV @Rm,XDn
                begin
                    dm_req_addr = in_opl;
                    e1_wfp = 1'b1;
                end
                16'b1111????????0110:  // FMOV.S @(R0,Rm),FRn
                    //16'b1111???0????0110, // FMOV @(R0,Rm),DRn
                    //16'b1111???1????0110, // FMOV @(R0,Rm),XDn
                begin
                    e1_wfp = 1'b1;
                end
                16'b1111????????1001:  // FMOV.S @Rm+,FRn
                    //16'b1111???0????1001, // FMOV @Rm+,DRn
                    //16'b1111???1????1001, // FMOV @Rm+,XDn
                begin
                    e1_alt_wen = 1'b1;
                    e1_alt_wdst = rl;
                    e1_alt_wdata = rl_inc;
                    dm_req_addr = in_opl;
                    e1_wfp = 1'b1;
                end
                16'b1111????????1010:  // FMOV.S FRm,@Rn
                    //16'b1111???????01010, // FMOV DRm,@Rn
                    //16'b1111???????11010, // FMOV XDm,@Rn
                begin
                    dm_req_addr = in_oph;
                    wdata = {32'b0, in_fpr};
                end
                16'b1111????????1011:  // FMOV.S FRm,@-Rn
                    //16'b1111???????01011, // FMOV DRm,@-Rn
                    //16'b1111???????11011, // FMOV XDm,@-Rn
                begin
                    e1_wen = 1'b1;
                    e1_wdst = rh;
                    e1_wdata = rn_dec;
                    e1_wpending = 1'b0;
                    dm_req_addr = rn_dec;
                    wdata = {32'b0, in_fpr};
                end
                16'b1111????????0111:  // FMOV.S FRm,@(R0,Rn)
                    //16'b1111???????00111, // FMOV DRm,@(R0,Rn)
                    //16'b1111???????10111, // FMOV XDm,@(R0,Rn)
                begin
                    dm_req_addr = addr_gen_r0;
                    wdata = {32'b0, in_fpr};
                end
                16'b1111????00011101:  // FLDS FRm,FPUL
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_fpr;
                    e1_fpul_wen = 1'b1;
                end
                16'b1111????00001101:  // FSTS FPUL,FRn
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_csr_rdata;
                    e1_wfp = 1'b1;
                end
                16'b1111????01011101:  // FABS FRn
                    //16'b1111???001011101, // FABS DRn
                begin
                    use_passthrough = 1'b1;
                    passthrough_val = {1'b0, in_fpr[30:0]};
                    e1_wfp = 1'b1;
                end
                16'b1111????01001101:  // FNEG FRn
                    //16'b1111???001001101, // FNEG DRn
                begin
                    use_passthrough = 1'b1;
                    passthrough_val = {!in_fpr[31], in_fpr[30:0]};
                    e1_wfp = 1'b1;
                end
                16'b0100????01011010:  // LDS Rm,FPUL
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_oph;
                    e1_fpul_wen = 1'b1;
                end
                16'b0000????01011010:  // STS FPUL,Rn
                    begin
                    use_passthrough = 1'b1;
                    passthrough_val = in_csr_rdata;
                end
                16'b0100????00011011:  // TAS.B @Rn
                    begin
                    dm_req_addr = in_oph;
                    wdata = amo_oldval | 8'h80;
                    e1_wen = 1'b0;
                    use_passthrough_csr = 1'b0;
                    passthrough_val = 8'hff;
                    amo_write_t = 1'b1;
                end
                16'b11001101????????:  // AND.B #imm,@(R0,GBR)
                    begin
                    dm_req_addr = addr_gen_r0_gbr;
                    wdata = amo_oldval & in_opl;
                    e1_wen = 1'b0;
                    amo_write_t = 1'b0;
                end
                16'b11001111????????:  // OR.B #imm,@(R0,GBR)
                    begin
                    dm_req_addr = addr_gen_r0_gbr;
                    wdata = amo_oldval | in_opl;
                    e1_wen = 1'b0;
                    amo_write_t = 1'b0;
                end
                16'b11001100????????:  // TST.B #imm,@(R0,GBR)
                    begin
                    dm_req_addr = addr_gen_r0_gbr;
                    e1_wen = 1'b0;
                    use_passthrough_csr = 1'b0;
                    passthrough_val = in_opl;
                    amo_write_t = 1'b1;
                end
                16'b11001110????????:  // XOR.B #imm,@(R0,GBR)
                    begin
                    dm_req_addr = addr_gen_r0_gbr;
                    wdata = amo_oldval ^ in_opl;
                    e1_wen = 1'b0;
                    amo_write_t = 1'b0;
                end
                default: begin
                    // LSU activated but no instruction matched
                end
            endcase
        end

        if (e1_flush) dm_req_valid = 1'b0;
    end

    // RW decoder
    always @(*) begin
        is_load = 1'b0;
        is_gprw = 1'b0;
        is_store = 1'b0;
        is_amo = 1'b0;
        /* verilator lint_off CASEINCOMPLETE */
        casez (in_raw)
            16'b1001????????????,  // MOV.W @(disp,PC),Rn
            16'b1101????????????,  // MOV.L @(disp,PC),Rn
            16'b0110????????0000,  // MOV.B @Rm,Rn
            16'b0110????????0001,  // MOV.W @Rm,Rn
            16'b0110????????0010,  // MOV.L @Rm,Rn
            16'b0110????????0100,  // MOV.B @Rm+,Rn
            16'b0110????????0101,  // MOV.W @Rm+,Rn
            16'b0110????????0110,  // MOV.L @Rm+,Rn
            16'b10000100????????,  // MOV.B @(disp,Rm),R0
            16'b10000101????????,  // MOV.W @(disp,Rm),R0
            16'b0101????????????,  // MOV.L @(disp,Rm),Rn
            16'b0000????????1100,  // MOV.B @(R0,Rm),Rn
            16'b0000????????1101,  // MOV.W @(R0,Rm),Rn
            16'b0000????????1110,  // MOV.L @(R0,Rm),Rn
            16'b11000100????????,  // MOV.B @(disp,GBR),R0
            16'b11000101????????,  // MOV.W @(disp,GBR),R0
            16'b11000110????????,  // MOV.L @(disp,GBR),R0
            16'b0100????00000111,  // LDC.L @Rm+,SR
            16'b0100????00010111,  // LDC.L @Rm+,GBR
            16'b0100????00100111,  // LDC.L @Rm+,VBR
            16'b0100????00110111,  // LDC.L @Rm+,SSR
            16'b0100????01000111,  // LDC.L @Rm+,SPC
            16'b0100????11110110,  // LDC.L @Rm+,DBR
            16'b0100????00000110,  // LDS.L @Rm+,MACH
            16'b0100????00010110,  // LDS.L @Rm+,MACL
            16'b0100????00100110,  // LDS.L @Rm+,PR
            16'b0100????01100110,  // LDS.L @Rm+,FPSCR
            16'b0100????01010110,  // LDS.L @Rm+,FPUL
            16'b0100????1???0111,  // LDC.L @Rm+,Rn_BANK
            16'b1111????????1000,  // FMOV.S @Rm,FRn
            //16'b1111???0????1000, // FMOV @Rm,DRn
            //16'b1111???1????1000, // FMOV @Rm,XDn
            16'b1111????????0110,  // FMOV.S @(R0,Rm),FRn
            //16'b1111???0????0110, // FMOV @(R0,Rm),DRn
            //16'b1111???1????0110, // FMOV @(R0,Rm),XDn
            16'b1111????????1001:  // FMOV.S @Rm+,FRn
            //16'b1111???0????1001, // FMOV @Rm+,DRn
            //16'b1111???1????1001, // FMOV @Rm+,XDn
            is_load = 1'b1;
            16'b0010????????0000,  // MOV.B Rm,@Rn
            16'b0010????????0001,  // MOV.W Rm,@Rn
            16'b0010????????0010,  // MOV.L Rm,@Rn
            16'b0010????????0100,  // MOV.B Rm,@-Rn
            16'b0010????????0101,  // MOV.W Rm,@-Rn
            16'b0010????????0110,  // MOV.L Rm,@-Rn
            16'b10000000????????,  // MOV.B R0,@(disp,Rn)
            16'b10000001????????,  // MOV.W R0,@(disp,Rn)
            16'b0001????????????,  // MOV.L Rm,@(disp,Rn)
            16'b0000????????0100,  // MOV.B Rm,@(R0,Rn)
            16'b0000????????0101,  // MOV.W Rm,@(R0,Rn)
            16'b0000????????0110,  // MOV.L Rm,@(R0,Rn)
            16'b11000000????????,  // MOV.B R0,@(disp,GBR)
            16'b11000001????????,  // MOV.W R0,@(disp,GBR)
            16'b11000010????????,  // MOV.L R0,@(disp,GBR)
            16'b0000????11000011,  // MOVCA.L R0,@Rn
            16'b0000????10010011,  // OCBI @Rn
            16'b0000????10100011,  // OCBP @Rn
            16'b0000????10110011,  // OCBWB @Rn
            16'b0000????10000011,  // PREF @Rn
            16'b0100????00000011,  // STC.L SR,@-Rn
            16'b0100????00010011,  // STC.L GBR,@-Rn
            16'b0100????00100011,  // STC.L VBR,@-Rn
            16'b0100????00110011,  // STC.L SSR,@-Rn
            16'b0100????01000011,  // STC.L SPC,@-Rn
            16'b0100????00110010,  // STC.L SGR,@-Rn
            16'b0100????11110010,  // STC.L DBR,@-Rn
            16'b0100????00000010,  // STS.L MACH,@-Rn
            16'b0100????00010010,  // STS.L MACL,@-Rn
            16'b0100????00100010,  // STS.L PR,@-Rn
            16'b0100????01100010,  // STS.L FPSCR,@-Rn
            16'b0100????01010010,  // STS.L FPUL,@-Rn
            16'b0100????1???0011,  // STC.L Rm_BANK,@-Rn
            16'b1111????????1010,  // FMOV.S FRm,@Rn
            //16'b1111???????01010, // FMOV DRm,@Rn
            //16'b1111???????11010, // FMOV XDm,@Rn
            16'b1111????????1011,  // FMOV.S FRm,@-Rn
            //16'b1111???????01011, // FMOV DRm,@-Rn
            //16'b1111???????11011, // FMOV XDm,@-Rn
            16'b1111????????0111:  // FMOV.S FRm,@(R0,Rn)
            //16'b1111???????00111, // FMOV DRm,@(R0,Rn)
            //16'b1111???????10111, // FMOV XDm,@(R0,Rn)
            is_store = 1'b1;
            16'b0000????00000010,  // STC SR,Rn
            16'b0000????00010010,  // STC GBR,Rn
            16'b0000????00100010,  // STC VBR,Rn
            16'b0000????00110010,  // STC SSR,Rn
            16'b0000????01000010,  // STC SPC,Rn
            16'b0000????00111010,  // STC SGR,Rn
            16'b0000????11111010,  // STC DBR,Rn
            16'b0000????00001010,  // STS MACH,Rn
            16'b0000????00011010,  // STS MACL,Rn
            16'b0000????00101010,  // STS PR,Rn
            16'b0000????1???0010,  // STC Rm_BANK,Rn
            16'b0000????01011010,  // STS FPUL,Rn
            16'b0000????01101010:  // STS FPSCR,Rn
            is_gprw = 1'b1;
            16'b11001100????????:  // TST.B #imm,@(R0,GBR)
                begin
                if (amo_state == AMO_READ) is_load = 1'b1;
                is_amo = 1'b1;
            end
            16'b0100????00011011,  // TAS.B @Rn
            16'b11001101????????,  // AND.B #imm,@(R0,GBR)
            16'b11001111????????,  // OR.B #imm,@(R0,GBR)
            16'b11001110????????:  // XOR.B #imm,@(R0,GBR)
                begin
                if (amo_state == AMO_WRITE) is_store = 1'b1;
                else is_load = 1'b1;
                is_amo = 1'b1;
            end
            // Not listed instructions are not memory instructions
        endcase
        /* verilator lint_on CASEINCOMPLETE */
    end

    // Floating point access size
    wire [1:0] fpsize = fpscr_sz ? SZ_DOUBLE : SZ_LONG;

    // SIZE decoder
    always @(*) begin
        rwsize = 2'bx;
        /* verilator lint_off CASEINCOMPLETE */
        casez (in_raw)
            16'b0010????????0000,  // MOV.B Rm,@Rn
            16'b0110????????0000,  // MOV.B @Rm,Rn
            16'b0010????????0100,  // MOV.B Rm,@-Rn
            16'b0110????????0100,  // MOV.B @Rm+,Rn
            16'b10000000????????,  // MOV.B R0,@(disp,Rn)
            16'b10000100????????,  // MOV.B @(disp,Rm),R0
            16'b0000????????0100,  // MOV.B Rm,@(R0,Rn)
            16'b0000????????1100,  // MOV.B @(R0,Rm),Rn
            16'b11000000????????,  // MOV.B R0,@(disp,GBR)
            16'b11000100????????,  // MOV.B @(disp,GBR),R0
            16'b0100????00011011,  // TAS.B @Rn
            16'b11001101????????,  // AND.B #imm,@(R0,GBR)
            16'b11001111????????,  // OR.B #imm,@(R0,GBR)
            16'b11001100????????,  // TST.B #imm,@(R0,GBR)
            16'b11001110????????:  // XOR.B #imm,@(R0,GBR)
            rwsize = SZ_BYTE;
            16'b1001????????????,  // MOV.W @(disp,PC),Rn
            16'b0010????????0001,  // MOV.W Rm,@Rn
            16'b0110????????0001,  // MOV.W @Rm,Rn
            16'b0010????????0101,  // MOV.W Rm,@-Rn
            16'b0110????????0101,  // MOV.W @Rm+,Rn
            16'b10000001????????,  // MOV.W R0,@(disp,Rn)
            16'b10000101????????,  // MOV.W @(disp,Rm),R0 
            16'b0000????????0101,  // MOV.W Rm,@(R0,Rn)
            16'b0000????????1101,  // MOV.W @(R0,Rm),Rn
            16'b11000001????????,  // MOV.W R0,@(disp,GBR)
            16'b11000101????????:  // MOV.W @(disp,GBR),R0
            rwsize = SZ_WORD;
            16'b1101????????????,  // MOV.L @(disp,PC),Rn
            16'b0010????????0010,  // MOV.L Rm,@Rn
            16'b0110????????0010,  // MOV.L @Rm,Rn        
            16'b0010????????0110,  // MOV.L Rm,@-Rn
            16'b0110????????0110,  // MOV.L @Rm+,Rn
            16'b0001????????????,  // MOV.L Rm,@(disp,Rn)
            16'b0101????????????,  // MOV.L @(disp,Rm),Rn
            16'b0000????????0110,  // MOV.L Rm,@(R0,Rn)
            16'b0000????????1110,  // MOV.L @(R0,Rm),Rn
            16'b11000010????????,  // MOV.L R0,@(disp,GBR)
            16'b11000110????????,  // MOV.L @(disp,GBR),R0
            16'b0000????11000011,  // MOVCA.L R0,@Rn
            16'b0100????00000111,  // LDC.L @Rm+,SR
            16'b0100????00010111,  // LDC.L @Rm+,GBR
            16'b0100????00100111,  // LDC.L @Rm+,VBR
            16'b0100????00110111,  // LDC.L @Rm+,SSR
            16'b0100????01000111,  // LDC.L @Rm+,SPC
            16'b0100????11110110,  // LDC.L @Rm+,DBR
            16'b0100????00000110,  // LDS.L @Rm+,MACH
            16'b0100????00010110,  // LDS.L @Rm+,MACL
            16'b0100????00100110,  // LDS.L @Rm+,PR
            16'b0100????1???0111,  // LDC.L @Rm+,Rn_BANK
            16'b0100????00000011,  // STC.L SR,@-Rn
            16'b0100????00010011,  // STC.L GBR,@-Rn
            16'b0100????00100011,  // STC.L VBR,@-Rn
            16'b0100????00110011,  // STC.L SSR,@-Rn
            16'b0100????01000011,  // STC.L SPC,@-Rn
            16'b0100????00110010,  // STC.L SGR,@-Rn
            16'b0100????11110010,  // STC.L DBR,@-Rn
            16'b0100????00000010,  // STS.L MACH,@-Rn
            16'b0100????00010010,  // STS.L MACL,@-Rn
            16'b0100????00100010,  // STS.L PR,@-Rn
            16'b0100????1???0011:  // STC.L Rm_BANK,@-Rn
            rwsize = SZ_LONG;
            16'b1111????????1000,  // FMOV.S @Rm,FRn
            16'b1111????????0110,  // FMOV.S @(R0,Rm),FRn
            16'b1111????????1001,  // FMOV.S @Rm+,FRn
            16'b1111????????1010,  // FMOV.S FRm,@Rn
            16'b1111????????1011,  // FMOV.S FRm,@-Rn
            16'b1111????????0111:  // FMOV.S FRm,@(R0,Rn)
            rwsize = fpsize;
        endcase
        /* verilator lint_on CASEINCOMPLETE */
    end

    // WDATA and MASK generation
    wire [7:0] mem_wmask_byte;
    wire [7:0] mem_wmask_word;
    wire [7:0] mem_wmask_long;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin
            assign mem_wmask_byte[i] = (dm_req_addr[2:0] == i);
        end
        for (i = 0; i < 4; i = i + 1) begin
            assign mem_wmask_word[i*2+1:i*2] = {2{mem_wmask_byte[i*2]}};
        end
        for (i = 0; i < 2; i = i + 1) begin
            assign mem_wmask_long[i*4+3:i*4] = {4{mem_wmask_byte[i*4]}};
        end
    endgenerate

    always @(*) begin
        case (rwsize)
            SZ_BYTE: begin
                dm_req_wmask = mem_wmask_byte;
                dm_req_wdata = {8{wdata[7:0]}};
            end
            SZ_WORD: begin
                dm_req_wmask = mem_wmask_word;
                dm_req_wdata = {4{wdata[15:0]}};
            end
            SZ_LONG: begin
                dm_req_wmask = mem_wmask_long;
                dm_req_wdata = {2{wdata[31:0]}};
            end
            SZ_DOUBLE: begin
                dm_req_wmask = 8'hFF;
                dm_req_wdata = wdata;
            end
        endcase
    end

    // Readback
    reg [1:0] e2_reg_rwsize;
    reg e2_reg_valid;
    reg e2_reg_wen;
    reg [3:0] e2_reg_wdst;
    reg [2:0] e2_reg_byte_offset;
    reg [31:0] e2_reg_passthrough;
    reg e2_reg_use_passthrough;
    reg e2_reg_waltbank;
    reg e2_reg_write_csr;
    reg e2_reg_fpul_wen;
    reg e2_reg_wfp;
    reg e2_reg_amo;
    reg e2_reg_amo_write_t;
    always @(posedge clk) begin
        e2_reg_valid <= dm_req_valid && !e1_flush;
        e2_reg_wen <= dm_req_wen;
        e2_reg_rwsize <= rwsize;
        e2_reg_byte_offset <= dm_req_addr[2:0];
        e2_reg_wdst <= e1_wdst;
        e2_reg_use_passthrough <= use_passthrough;
        e2_reg_passthrough <= use_passthrough_csr ? in_csr_rdata : passthrough_val;
        e2_reg_waltbank <= waltbank;
        e2_reg_write_csr <= write_csr;
        e2_reg_fpul_wen <= e1_fpul_wen;
        e2_reg_wfp <= e1_wfp;
        e2_reg_amo <= is_amo;
        e2_reg_amo_write_t <= amo_write_t;
        if (rst) begin
            e2_reg_valid <= 1'b0;
        end
    end

    wire [63:0] mem_rd = dm_resp_rdata;

    wire [7:0] mem_rd_bl[0:7];
    wire [15:0] mem_rd_wl[0:3];
    wire [31:0] mem_rd_ll[0:1];
    generate
        for (i = 0; i < 8; i = i + 1) begin
            assign mem_rd_bl[i] = mem_rd[i*8+7:i*8];
        end
        for (i = 0; i < 4; i = i + 1) begin
            assign mem_rd_wl[i] = mem_rd[i*16+15:i*16];
        end
        for (i = 0; i < 2; i = i + 1) begin
            assign mem_rd_ll[i] = mem_rd[i*32+31:i*32];
        end
    endgenerate


    wire [7:0] mem_rd_b = mem_rd_bl[e2_reg_byte_offset];
    wire [15:0] mem_rd_w = mem_rd_wl[e2_reg_byte_offset[2:1]];
    wire [31:0] mem_rd_l = mem_rd_ll[e2_reg_byte_offset[2]];

    wire [31:0] mem_rd_bs = {{24{mem_rd_b[7]}}, mem_rd_b};
    wire [31:0] mem_rd_ws = {{16{mem_rd_w[15]}}, mem_rd_w};

    always @(*) begin
        e2_nack = 1'b0;
        e2_wen = 1'b0;
        e2_wdst = e2_reg_wdst;
        e2_waltbank = e2_reg_waltbank;
        if (e2_reg_use_passthrough) begin
            e2_wdata = e2_reg_passthrough;
            if (!e2_reg_fpul_wen && !e2_reg_wfp) begin
                e2_wen = 1'b1;
            end
        end else begin
            case (e2_reg_rwsize)
                SZ_BYTE: e2_wdata = mem_rd_bs;
                SZ_WORD: e2_wdata = mem_rd_ws;
                SZ_LONG: e2_wdata = mem_rd_l;
                SZ_DOUBLE: e2_wdata = 32'bx;  // Double result goes to FP write port
            endcase
            if (e2_reg_valid) begin
                if (!dm_resp_valid) e2_nack = 1'b1;
                else if (!e2_reg_wen) e2_wen = 1'b1;
            end
        end

        e2_csr_tonly = 1'b0;
        e2_csr_wdata = e2_wdata;
        e2_csr_wen = 1'b0;
        if (e2_reg_write_csr || e2_reg_fpul_wen) begin
            // Currently reg target and csr target is mutually exclusive
            e2_csr_wen = 1'b1;
            e2_wen = 1'b0;
        end

        if (e2_reg_amo && e2_reg_amo_write_t) begin
            e2_csr_tonly = 1'b1;
            e2_csr_wdata = (amo_oldval == 8'h00);
            e2_csr_wen = 1'b1;
        end

        if (e2_reg_amo) begin
            e2_wen = 1'b0;
        end

        if (e2_reg_amo && (amo_state == AMO_READ) && e2_reg_valid) begin
            e2_nack = 1'b1;  // Request replay
        end

        e2_fpul_wen = e2_reg_fpul_wen;
        e2_wfp = e2_reg_wfp;
    end

    always @(posedge clk) begin
        // Update AMO state
        if (e2_reg_valid && e2_reg_amo) begin
            if (dm_resp_valid) begin
                if (amo_state == AMO_READ) begin
                    amo_oldval <= mem_rd_b & e2_reg_passthrough[7:0];
                    amo_state <= AMO_WRITE;
                end else amo_state <= AMO_READ;
            end
        end

        if (rst) begin
            amo_state <= AMO_READ;
        end
    end

endmodule
