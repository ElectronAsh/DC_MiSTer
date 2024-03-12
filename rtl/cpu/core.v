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

module core (
    input wire clk,
    input wire rst,
    // Runtime Configuration
    input wire [31:0] boot_vector,
    // Instruction memory
    output wire [31:0] im_req_addr,
    output wire im_req_valid,
    input wire [31:0] im_resp_rdata,
    input wire im_resp_valid,
    output wire im_invalidate_req,
    input wire im_invalidate_resp,
    // Data memory
    output wire [31:0] dm_req_addr,
    output wire [63:0] dm_req_wdata,
    output wire [7:0] dm_req_wmask,
    output wire dm_req_wen,
    output wire dm_req_valid,
    input wire [63:0] dm_resp_rdata,
    input wire dm_resp_valid,
    output wire dm_req_flush,
    output wire dm_req_invalidate,
    output wire dm_req_writeback,
    output wire dm_req_prefetch,
    output wire dm_req_nofill,
    // Trace
    output wire trace_valid0,
    output wire [31:0] trace_pc0,
    output wire [15:0] trace_instr0,
    output wire trace_wen0,
    output wire [3:0] trace_wdst0,
    output wire [31:0] trace_wdata0,
    output wire trace_valid1,
    output wire [31:0] trace_pc1,
    output wire [15:0] trace_instr1,
    output wire trace_wen1,
    output wire [3:0] trace_wdst1,
    output wire [31:0] trace_wdata1
);

    // ---- IF ----
    wire if_pc_redirect;
    wire [31:0] if_pc_redirect_target;
    reg [31:0] if_reg_pc;
    wire if_valid = !rst;
    wire [31:0] if_pc_plus4 = {if_reg_pc[31:2], 2'b00} + 32'd4;
    wire [31:0] if_pc_next = if_pc_redirect ? if_pc_redirect_target : if_pc_plus4;

    always @(posedge clk) begin
        if_reg_pc <= if_pc_next;
        if (rst) begin
            if_reg_pc <= boot_vector - 4;
        end
    end

    assign im_req_addr = if_pc_next;
    assign im_req_valid = if_valid;

    // CSR
    // This thing spans across multiple pipeline stages...
    // Use in both ID and E1, write back in both E1 and E2
    reg csr_sr_md;
    reg csr_sr_rb;
    reg csr_sr_bl;
    reg csr_sr_fd;
    reg [3:0] csr_sr_imask;
    reg [31:0] csr_ssr;
    reg [31:0] csr_spc;
    reg [31:0] csr_gbr;
    reg [31:0] csr_vbr;
    reg [31:0] csr_dbr;
    reg [31:0] csr_sgr;
    reg [31:0] csr_mach;
    reg [31:0] csr_macl;
    reg [31:0] csr_pr;
    reg [31:0] csr_fpscr;
    reg [31:0] csr_fpul;
    wire csr_fpscr_fr = csr_fpscr[21];
    wire csr_fpscr_sz = csr_fpscr[20];

    // ---- ID ----
    wire id_flush0;  // 🚽
    wire id_flush1;  // separate flush signal for delay slot handling
    wire id_is_delayslot;
    reg id_reg_valid;
    reg [31:0] id_reg_pc;
    wire [31:0] id_instr = im_resp_rdata;
    wire [15:0] id_instr0_raw = id_instr[15:0];
    wire [15:0] id_instr1_raw = id_instr[31:16];
    wire id_instr0_valid = id_reg_valid && !id_reg_pc[1] && !id_flush0;
    wire id_instr1_valid = id_reg_valid && !id_flush1;
    // Actual PC, only used for trace
    wire [31:0] id_instr0_pc = {id_reg_pc[31:2], 2'b00};
    wire [31:0] id_instr1_pc = {id_reg_pc[31:2], 2'b10};
    // Instructions uses PC+4
    wire [31:0] id_instr0_npc = {if_pc_plus4[31:2], 2'b00};
    wire [31:0] id_instr1_npc = {if_pc_plus4[31:2], 2'b10};
    wire [3:0] id_instr0_rsl = id_instr0_raw[7:4];
    wire [3:0] id_instr0_rsh = id_instr0_raw[11:8];
    wire [3:0] id_instr1_rsl = id_instr1_raw[7:4];
    wire [3:0] id_instr1_rsh = id_instr1_raw[11:8];

    always @(posedge clk) begin
        id_reg_valid <= if_valid;
        id_reg_pc <= if_pc_next;
        if (rst) begin
            id_reg_valid <= 1'b0;
        end
    end

    // Regfile
    wire [3:0] rf_rsrc[0:4];
    wire [31:0] rf_rdata[0:4];
    wire rf_wen0;
    wire [3:0] rf_wdst0;
    wire [31:0] rf_wdata0;
    wire rf_wen1;
    wire [3:0] rf_wdst1;
    wire [31:0] rf_wdata1;

    wire rf_rbank_p0;
    wire rf_rbank_p1;
    wire rf_wbank_p0;
    wire rf_wbank_p1;

    assign rf_rsrc[0] = id_instr0_rsl;
    assign rf_rsrc[1] = id_instr0_rsh;
    assign rf_rsrc[2] = id_instr1_rsl;
    assign rf_rsrc[3] = id_instr1_rsh;
    assign rf_rsrc[4] = 4'd0;

    rf rf (
        .clk(clk),
        .rst(rst),
        .rf_rsrc0(rf_rsrc[0]),
        .rf_rdata0(rf_rdata[0]),
        .rf_rbank0(rf_rbank_p0),
        .rf_rsrc1(rf_rsrc[1]),
        .rf_rdata1(rf_rdata[1]),
        .rf_rbank1(rf_rbank_p0),
        .rf_rsrc2(rf_rsrc[2]),
        .rf_rdata2(rf_rdata[2]),
        .rf_rbank2(rf_rbank_p1),
        .rf_rsrc3(rf_rsrc[3]),
        .rf_rdata3(rf_rdata[3]),
        .rf_rbank3(rf_rbank_p1),
        .rf_wen0(rf_wen0),
        .rf_wdst0(rf_wdst0),
        .rf_wdata0(rf_wdata0),
        .rf_wen1(rf_wen1),
        .rf_wdst1(rf_wdst1),
        .rf_wdata1(rf_wdata1),
        .rf_wbank0(rf_wbank_p0),
        .rf_wbank1(rf_wbank_p1),
        .rf_rd_r0(rf_rdata[4])
    );

    // Bypass network
    // TODO: If a previous CSR instruction writes into alternative bank, it might
    // get errornously forwarded here
    wire [31:0] id_instr_rs[0:4];
    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin
            assign id_instr_rs[i] = (e1_p1_wen && (e1_p1_wdst == rf_rsrc[i])) ?
                e1_p1_wdata : (e1_p0_wen && (e1_p0_wdst == rf_rsrc[i])) ? e1_p0_wdata : (e2_p1_wen && (e2_p1_wdst == rf_rsrc[i])) ?
                e2_p1_wdata : (e2_p0_wen && (e2_p0_wdst == rf_rsrc[i])) ? e2_p0_wdata : rf_rdata[i];
        end
    endgenerate

    // FP register file
    // No bypass, static allocation
    wire [3:0] fprf_rsrc0;
    wire fprf_rbank0;
    wire [31:0] fprf_rdata0;
    wire [3:0] fprf_rsrc1;
    wire fprf_rbank1;
    wire [31:0] fprf_rdata1;
    wire [3:0] fprf_rsrc2;
    wire fprf_rbank2;
    wire [31:0] fprf_rdata2;

    wire fprf_wen0;
    wire [3:0] fprf_wdst0;
    wire fprf_wbank0;
    wire [31:0] fprf_wdata0;
    wire fprf_wen1;
    wire [3:0] fprf_wdst1;
    wire fprf_wbank1;
    wire [31:0] fprf_wdata1;

    wire fprf_r0bank;
    wire [31:0] fprf_r0data;
    fprf fprf (
        .clk(clk),
        .rst(rst),
        .rf_rsrc0(fprf_rsrc0),
        .rf_rbank0(fprf_rbank0),
        .rf_rdata0(fprf_rdata0),
        .rf_rsrc1(fprf_rsrc1),
        .rf_rbank1(fprf_rbank1),
        .rf_rdata1(fprf_rdata1),
        .rf_rsrc2(fprf_rsrc2),
        .rf_rbank2(fprf_rbank2),
        .rf_rdata2(fprf_rdata2),
        .rf_r0bank(fprf_r0bank),
        .rf_r0data(fprf_r0data),
        .rf_wen0(fprf_wen0),
        .rf_wdst0(fprf_wdst0),
        .rf_wbank0(fprf_wbank0),
        .rf_wdata0(fprf_wdata0),
        .rf_wen1(fprf_wen1),
        .rf_wdst1(fprf_wdst1),
        .rf_wbank1(fprf_wbank1),
        .rf_wdata1(fprf_wdata1)
    );

    // Decode
    wire [31:0] id_dec0_opl;
    wire [31:0] id_dec0_oph;
    wire id_dec0_use_r0;
    wire id_dec0_use_rl;
    wire id_dec0_use_rh;
    wire id_dec0_write_rn;
    wire id_dec0_write_r0;
    wire id_dec0_fp_use_rl;
    wire id_dec0_fp_use_rh;
    wire id_dec0_fp_use_r0;
    wire id_dec0_fp_ls_use_freg;
    wire id_dec0_fp_ls_use_altbank;
    wire id_dec0_fp_ls_use_rh;
    wire id_dec0_fp_write_rn;
    wire id_dec0_fp_write_altbank;
    wire [3:0] id_dec0_fp_op;
    wire id_dec0_use_fpul;
    wire id_dec0_write_fpul;
    wire id_dec0_use_csr;
    wire id_dec0_write_csr;
    wire id_dec0_is_mt;
    wire id_dec0_is_ex;
    wire id_dec0_is_br;
    wire id_dec0_is_ls;
    wire id_dec0_is_fp;
    wire [3:0] id_dec0_csr_id;
    wire id_dec0_raltbank;
    wire id_dec0_complex;
    wire id_dec0_use_t;
    wire id_dec0_write_t;
    wire id_dec0_legal;

    wire [31:0] id_dec1_opl;
    wire [31:0] id_dec1_oph;
    wire id_dec1_use_r0;
    wire id_dec1_use_rl;
    wire id_dec1_use_rh;
    wire id_dec1_write_rn;
    wire id_dec1_write_r0;
    wire id_dec1_fp_use_rl;
    wire id_dec1_fp_use_rh;
    wire id_dec1_fp_use_r0;
    wire id_dec1_fp_ls_use_freg;
    wire id_dec1_fp_ls_use_altbank;
    wire id_dec1_fp_ls_use_rh;
    wire id_dec1_fp_write_rn;
    wire id_dec1_fp_write_altbank;
    wire [3:0] id_dec1_fp_op;
    wire id_dec1_use_fpul;
    wire id_dec1_write_fpul;
    wire id_dec1_use_csr;
    wire id_dec1_write_csr;
    wire id_dec1_is_mt;
    wire id_dec1_is_ex;
    wire id_dec1_is_br;
    wire id_dec1_is_ls;
    wire id_dec1_is_fp;
    wire [3:0] id_dec1_csr_id;
    wire id_dec1_raltbank;
    wire id_dec1_complex;
    wire id_dec1_use_t;
    wire id_dec1_write_t;
    wire id_dec1_legal;

    wire [31:0] id_instr0_rl = id_instr_rs[0];
    wire [31:0] id_instr0_rh = id_instr_rs[1];
    wire [31:0] id_instr0_r0 = id_instr_rs[4];
    wire [31:0] id_instr1_rl = id_instr_rs[2];
    wire [31:0] id_instr1_rh = id_instr_rs[3];
    wire [31:0] id_instr1_r0 = id_instr_rs[4];

    du du0 (
        .in_valid(id_instr0_valid),
        .in_npc(id_instr0_npc),
        .in_raw(id_instr0_raw),
        .in_rl(id_instr0_rl),
        .in_rh(id_instr0_rh),
        .in_r0(id_instr0_r0),
        .out_opl(id_dec0_opl),
        .out_oph(id_dec0_oph),
        .out_use_r0(id_dec0_use_r0),
        .out_use_rl(id_dec0_use_rl),
        .out_use_rh(id_dec0_use_rh),
        .out_write_rn(id_dec0_write_rn),
        .out_write_r0(id_dec0_write_r0),
        .out_fp_use_rl(id_dec0_fp_use_rl),
        .out_fp_use_rh(id_dec0_fp_use_rh),
        .out_fp_use_r0(id_dec0_fp_use_r0),
        .out_fp_ls_use_freg(id_dec0_fp_ls_use_freg),
        .out_fp_ls_use_altbank(id_dec0_fp_ls_use_altbank),
        .out_fp_ls_use_rh(id_dec0_fp_ls_use_rh),
        .out_fp_write_rn(id_dec0_fp_write_rn),
        .out_fp_write_altbank(id_dec0_fp_write_altbank),
        .out_fp_op(id_dec0_fp_op),
        .out_use_fpul(id_dec0_use_fpul),
        .out_write_fpul(id_dec0_write_fpul),
        .out_use_csr(id_dec0_use_csr),
        .out_write_csr(id_dec0_write_csr),
        .out_is_mt(id_dec0_is_mt),
        .out_is_ex(id_dec0_is_ex),
        .out_is_br(id_dec0_is_br),
        .out_is_ls(id_dec0_is_ls),
        .out_is_fp(id_dec0_is_fp),
        .out_csr_id(id_dec0_csr_id),
        .out_raltbank(id_dec0_raltbank),
        .out_complex(id_dec0_complex),
        .out_use_t(id_dec0_use_t),
        .out_write_t(id_dec0_write_t),
        .out_legal(id_dec0_legal)
    );

    du du1 (
        .in_valid(id_instr1_valid),
        .in_npc(id_instr1_npc),
        .in_raw(id_instr1_raw),
        .in_rl(id_instr1_rl),
        .in_rh(id_instr1_rh),
        .in_r0(id_instr1_r0),
        .out_opl(id_dec1_opl),
        .out_oph(id_dec1_oph),
        .out_use_r0(id_dec1_use_r0),
        .out_use_rl(id_dec1_use_rl),
        .out_use_rh(id_dec1_use_rh),
        .out_write_rn(id_dec1_write_rn),
        .out_write_r0(id_dec1_write_r0),
        .out_fp_use_rl(id_dec1_fp_use_rl),
        .out_fp_use_rh(id_dec1_fp_use_rh),
        .out_fp_use_r0(id_dec1_fp_use_r0),
        .out_fp_ls_use_freg(id_dec1_fp_ls_use_freg),
        .out_fp_ls_use_altbank(id_dec1_fp_ls_use_altbank),
        .out_fp_ls_use_rh(id_dec1_fp_ls_use_rh),
        .out_fp_write_rn(id_dec1_fp_write_rn),
        .out_fp_write_altbank(id_dec1_fp_write_altbank),
        .out_fp_op(id_dec1_fp_op),
        .out_use_fpul(id_dec1_use_fpul),
        .out_write_fpul(id_dec1_write_fpul),
        .out_use_csr(id_dec1_use_csr),
        .out_write_csr(id_dec1_write_csr),
        .out_is_mt(id_dec1_is_mt),
        .out_is_ex(id_dec1_is_ex),
        .out_is_br(id_dec1_is_br),
        .out_is_ls(id_dec1_is_ls),
        .out_is_fp(id_dec1_is_fp),
        .out_csr_id(id_dec1_csr_id),
        .out_raltbank(id_dec1_raltbank),
        .out_complex(id_dec1_complex),
        .out_use_t(id_dec1_use_t),
        .out_write_t(id_dec1_write_t),
        .out_legal(id_dec1_legal)
    );

    wire [31:0] id_instr0_opl = id_dec0_opl;
    wire [31:0] id_instr0_oph = id_dec0_oph;
    wire [31:0] id_instr1_opl = id_dec1_opl;
    wire [31:0] id_instr1_oph = id_dec1_oph;

    wire p0_int_hazard = (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == rf_rsrc[0]) && (id_dec0_use_rl)) ||
        (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == rf_rsrc[1]) && (id_dec0_use_rh)) ||
        (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == 4'd0) && (id_dec0_use_r0)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == rf_rsrc[0]) && (id_dec0_use_rl)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == rf_rsrc[1]) && (id_dec0_use_rh)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == 4'd0) && (id_dec0_use_r0));

    wire p1_int_hazard = (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == rf_rsrc[2]) && (id_dec1_use_rl)) ||
        (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == rf_rsrc[3]) && (id_dec1_use_rh)) ||
        (e1_p0_wen && e1_p0_wpending && (e1_p0_wdst == 4'd0) && (id_dec1_use_r0)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == rf_rsrc[2]) && (id_dec1_use_rl)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == rf_rsrc[3]) && (id_dec1_use_rh)) ||
        (e1_p1_wen && e1_p1_wpending && (e1_p1_wdst == 4'd0) && (id_dec1_use_r0));

    assign rf_rbank_p0 = csr_sr_md && (csr_sr_rb ^ id_dec0_raltbank);
    assign rf_rbank_p1 = csr_sr_md && (csr_sr_rb ^ id_dec1_raltbank);

    // FP scoreboard
    reg [31:0] fp_scoreboard;

    // In case of a FP LSU + FPU, up to 2 register might be allocated
    wire [4:0] fpsb_set_p0 = {csr_fpscr_fr ^ id_dec0_fp_write_altbank, id_instr0_rsh};
    wire [4:0] fpsb_set_p1 = {csr_fpscr_fr ^ id_dec1_fp_write_altbank, id_instr1_rsh};
    wire fpsb_set_en_p0 = id_dec0_fp_write_rn && instr0_issued;
    wire fpsb_set_en_p1 = id_dec1_fp_write_rn && instr1_issued;

    wire fp_rs0_busy = fp_scoreboard[{fprf_rbank0, fprf_rsrc0}];
    wire fp_rs1_busy = fp_scoreboard[{fprf_rbank1, fprf_rsrc1}];
    wire fp_rs2_busy = fp_scoreboard[{fprf_rbank1, fprf_rsrc2}];
    wire fp_r0_busy = fp_scoreboard[{fprf_r0bank, 4'd0}];
    wire fp_p0_waw_busy = fp_scoreboard[fpsb_set_p0];
    wire fp_p1_waw_busy = fp_scoreboard[fpsb_set_p1];

    always @(posedge clk) begin
        // Clear first
        if (fprf_wen0) fp_scoreboard[{fprf_wbank0, fprf_wdst0}] <= 1'b0;
        if (fprf_wen1) fp_scoreboard[{fprf_wbank1, fprf_wdst1}] <= 1'b0;

        // Set next
        if (fpsb_set_en_p0) fp_scoreboard[fpsb_set_p0] <= 1'b1;
        if (fpsb_set_en_p1) fp_scoreboard[fpsb_set_p1] <= 1'b1;

        // Finally reset
        if (rst) fp_scoreboard <= 32'b0;
    end

    wire p0_fp_hazard = (id_dec0_fp_ls_use_freg && fp_rs0_busy) || (id_dec0_fp_use_rl && fp_rs1_busy) ||
        (id_dec0_fp_use_rh && fp_rs2_busy) || (id_dec0_fp_use_r0 && fp_r0_busy) || (id_dec0_fp_write_rn && fp_p0_waw_busy);
    wire p1_fp_hazard = (id_dec1_fp_ls_use_freg && fp_rs0_busy) || (id_dec1_fp_use_rl && fp_rs1_busy) ||
        (id_dec1_fp_use_rh && fp_rs2_busy) || (id_dec1_fp_use_r0 && fp_r0_busy) || (id_dec1_fp_write_rn && fp_p1_waw_busy);

    // T flag FP busy
    // This only checks FPU because in all other places the T flag is either
    // written in E1 or a sync is forced (CSR)
    reg t_busy;
    wire p0_t_hazard = t_busy && (id_dec0_use_t || id_dec0_write_t);
    wire p1_t_hazard = t_busy && (id_dec1_use_t || id_dec1_write_t);

    always @(posedge clk) begin
        if (fpu_out_t_wen) t_busy <= 1'b0;
        if ((id_dec0_write_t && id_dec0_is_fp && instr0_issued) || (id_dec1_write_t && id_dec1_is_fp && instr1_issued))
            t_busy <= 1'b1;
        if (rst) t_busy <= 1'b0;
    end

    // FPUL register busy
    reg fpul_busy;
    wire p0_fpul_hazard = fpul_busy && (id_dec0_use_fpul || id_dec0_write_fpul);
    wire p1_fpul_hazard = fpul_busy && (id_dec1_use_fpul || id_dec1_write_fpul);

    always @(posedge clk) begin
        if (fpu_out_fpul_wen || e2_lsu_fpul_wen) fpul_busy <= 1'b0;
        if ((id_dec0_write_fpul && instr0_issued) || (id_dec1_write_fpul && instr1_issued)) fpul_busy <= 1'b1;
        if (rst) fpul_busy <= 1'b0;
    end

    // Other CSR register busy
    // If this turns to be a big performance hit, turn into scoreboard 
    // CSR busy also blocks FPUL access because FPUL memory operations are not
    // tracked by the fpul busy flag.
    reg csr_busy;
    wire p0_csr_hazard = csr_busy && (id_dec0_use_csr || id_dec0_write_csr || id_dec0_use_fpul || id_dec0_use_t);
    wire p1_csr_hazard = csr_busy && (id_dec1_use_csr || id_dec1_write_csr || id_dec1_use_fpul || id_dec1_use_t);

    always @(posedge clk) begin
        if (e2_lsu_csr_wen) csr_busy <= 1'b0;
        if ((id_dec0_write_csr && instr0_issued) || (id_dec1_write_csr && instr1_issued)) csr_busy <= 1'b1;
        if (rst) csr_busy <= 1'b0;
    end

    wire p0_hazard = p0_int_hazard || p0_fp_hazard || p0_t_hazard || p0_fpul_hazard || p0_csr_hazard;
    wire p1_hazard = p1_int_hazard || p1_fp_hazard || p1_t_hazard || p1_fpul_hazard || p1_csr_hazard;

    // Issue logic
    reg e1_reg_exu_valid;
    reg [15:0] e1_reg_exu_raw;
    reg [31:0] e1_reg_exu_opl;
    reg [31:0] e1_reg_exu_oph;

    reg e1_reg_bru_valid;
    reg [15:0] e1_reg_bru_raw;
    reg [31:0] e1_reg_bru_opl;
    reg [31:0] e1_reg_bru_oph;

    reg e1_reg_mtu0_valid;
    reg [15:0] e1_reg_mtu0_raw;
    reg [31:0] e1_reg_mtu0_opl;
    reg [31:0] e1_reg_mtu0_oph;

    reg e1_reg_mtu1_valid;
    reg [15:0] e1_reg_mtu1_raw;
    reg [31:0] e1_reg_mtu1_opl;
    reg [31:0] e1_reg_mtu1_oph;

    reg e1_reg_lsu_valid;
    reg [31:0] e1_reg_lsu_r0;
    reg [15:0] e1_reg_lsu_raw;
    reg [31:0] e1_reg_lsu_opl;
    reg [31:0] e1_reg_lsu_oph;

    reg [31:0] e1_reg_lsu_fpr;
    reg e1_reg_fpu_valid;
    reg [15:0] e1_reg_fpu_raw;
    reg [3:0] e1_reg_fpu_fop;
    reg [31:0] e1_reg_fpu_frl;
    reg [31:0] e1_reg_fpu_frh;
    reg [31:0] e1_reg_fpu_fr0;


    wire dual_issue_int_no_interdep = !(id_dec1_use_rl && id_dec0_write_rn && (id_instr1_rsl == id_instr0_rsh)) &&
        !(id_dec1_use_rh && id_dec0_write_rn && (id_instr1_rsh == id_instr0_rsh)) &&
        !(id_dec1_use_rl && id_dec0_write_r0 && (id_instr1_rsl == 4'd0)) &&
        !(id_dec1_use_rh && id_dec0_write_r0 && (id_instr1_rsh == 4'd0)) &&
        !(id_dec1_use_r0 && id_dec0_write_rn && (id_instr0_rsh == 4'd0)) && !(id_dec1_use_r0 && id_dec0_write_r0);

    wire dual_issue_fp_no_interdep = !(id_dec1_fp_ls_use_freg && ({fprf_rbank0, fprf_rsrc0} == fpsb_set_p0)) &&
        !(id_dec1_fp_use_rl && ({fprf_rbank1, fprf_rsrc1} == fpsb_set_p0)) &&
        !(id_dec1_fp_use_rh && ({fprf_rbank2, fprf_rsrc2} == fpsb_set_p0)) &&
        !(id_dec1_fp_use_r0 && ({fprf_rbank2, fprf_rsrc2} == fpsb_set_p0));

    wire dual_issue_no_res_conflict = !(id_dec0_write_fpul && id_dec1_use_fpul) && !(id_dec0_write_t && id_dec1_use_t) &&
        !(id_dec0_write_csr && (id_dec1_use_csr || id_dec1_write_csr || id_dec1_use_t || id_dec1_write_t)) &&
        !(id_dec0_is_ex && id_dec1_is_ex) && !(id_dec0_is_br && id_dec1_is_br) && !(id_dec0_is_ls && id_dec1_is_ls) &&
        !(id_dec0_is_fp && id_dec1_is_fp);

    wire dual_issue = !id_dec0_complex && !id_dec1_complex && dual_issue_int_no_interdep && dual_issue_fp_no_interdep &&
        dual_issue_no_res_conflict;
    // Either dual issuing allowed or 1st instruction is not masked out
    wire instr0_allow_issue = !p0_hazard;
    wire instr1_allow_issue = ((dual_issue && !p0_hazard) || !id_instr0_valid) && !p1_hazard;
    wire id_exu_sel = id_dec0_is_ex ? 1'b0 : 1'b1;
    wire id_bru_sel = id_dec0_is_br ? 1'b0 : 1'b1;
    wire id_lsu_sel = id_dec0_is_ls ? 1'b0 : 1'b1;
    wire id_fpu_sel = id_dec0_is_fp ? 1'b0 : 1'b1;
    reg e1_reg_exu_sel;
    reg e1_reg_bru_sel;
    reg e1_reg_lsu_sel;
    reg [3:0] e1_reg_lsu_csr_id;
    reg e1_reg_fpu_sel;
    wire instr0_issue = id_instr0_valid && instr0_allow_issue;
    wire instr1_issue = id_instr1_valid && instr1_allow_issue;
    always @(posedge clk) begin
        if (id_exu_sel == 1'b0) begin
            e1_reg_exu_valid <= id_dec0_is_ex && instr0_issue;
            e1_reg_exu_raw <= id_instr0_raw;
            e1_reg_exu_opl <= id_instr0_opl;
            e1_reg_exu_oph <= id_instr0_oph;
        end else begin
            e1_reg_exu_valid <= id_dec1_is_ex && instr1_issue;
            e1_reg_exu_raw <= id_instr1_raw;
            e1_reg_exu_opl <= id_instr1_opl;
            e1_reg_exu_oph <= id_instr1_oph;
        end
        e1_reg_exu_sel <= id_exu_sel;
        if (id_bru_sel == 1'b0) begin
            e1_reg_bru_valid <= id_dec0_is_br && instr0_issue;
            e1_reg_bru_raw <= id_instr0_raw;
            e1_reg_bru_opl <= id_instr0_opl;
            e1_reg_bru_oph <= id_instr0_oph;
        end else begin
            e1_reg_bru_valid <= id_dec1_is_br && instr1_issue;
            e1_reg_bru_raw <= id_instr1_raw;
            e1_reg_bru_opl <= id_instr1_opl;
            e1_reg_bru_oph <= id_instr1_oph;
        end
        e1_reg_bru_sel <= id_bru_sel;
        e1_reg_mtu0_valid <= id_dec0_is_mt && instr0_issue;
        e1_reg_mtu0_raw <= id_instr0_raw;
        e1_reg_mtu0_opl <= id_instr0_opl;
        e1_reg_mtu0_oph <= id_instr0_oph;
        e1_reg_mtu1_valid <= id_dec1_is_mt && instr1_issue;
        e1_reg_mtu1_raw <= id_instr1_raw;
        e1_reg_mtu1_opl <= id_instr1_opl;
        e1_reg_mtu1_oph <= id_instr1_oph;
        e1_reg_lsu_sel <= id_lsu_sel;
        e1_reg_lsu_r0 <= id_instr_rs[4];
        e1_reg_lsu_fpr <= fprf_rdata0;
        if (id_lsu_sel == 1'b0) begin
            e1_reg_lsu_valid <= id_dec0_is_ls && instr0_issue;
            e1_reg_lsu_raw <= id_instr0_raw;
            e1_reg_lsu_opl <= id_instr0_opl;
            e1_reg_lsu_oph <= id_instr0_oph;
            e1_reg_lsu_csr_id <= id_dec0_csr_id;
        end else begin
            e1_reg_lsu_valid <= id_dec1_is_ls && instr1_issue;
            e1_reg_lsu_raw <= id_instr1_raw;
            e1_reg_lsu_opl <= id_instr1_opl;
            e1_reg_lsu_oph <= id_instr1_oph;
            e1_reg_lsu_csr_id <= id_dec1_csr_id;
        end
        e1_reg_fpu_sel <= id_fpu_sel;
        if (id_fpu_sel == 1'b0) begin
            e1_reg_fpu_valid <= id_dec0_is_fp && instr0_issue;
            e1_reg_fpu_raw <= id_instr0_raw;
            e1_reg_fpu_fop <= id_dec0_fp_op;
        end else begin
            e1_reg_fpu_valid <= id_dec1_is_fp && instr1_issue;
            e1_reg_fpu_raw <= id_instr1_raw;
            e1_reg_fpu_fop <= id_dec1_fp_op;
        end
        e1_reg_fpu_frl <= fprf_rdata1;
        e1_reg_fpu_frh <= fprf_rdata2;
        e1_reg_fpu_fr0 <= fprf_r0data;
    end

    // RD port 0 is for LSU, RD port 1,2 and R0 port are for FPU
    assign fprf_rsrc0 = (id_lsu_sel == 1'b0) ?
        (id_dec0_fp_ls_use_rh ? id_instr0_rsh : id_instr0_rsl) : (id_dec1_fp_ls_use_rh ? id_instr1_rsh : id_instr1_rsl);
    assign fprf_rsrc1 = (id_fpu_sel == 1'b0) ? id_instr0_rsl : id_instr1_rsl;
    assign fprf_rsrc2 = (id_fpu_sel == 1'b0) ? id_instr0_rsh : id_instr1_rsh;
    assign fprf_rbank0 = csr_fpscr_fr ^ ((id_lsu_sel == 1'b0) ? id_dec0_fp_ls_use_altbank : id_dec1_fp_ls_use_altbank);
    assign fprf_rbank1 = csr_fpscr_fr;
    assign fprf_rbank2 = csr_fpscr_fr;
    assign fprf_r0bank = csr_fpscr_fr;

    wire instr0_issued = id_instr0_valid && instr0_allow_issue;
    wire instr1_issued = id_instr1_valid && instr1_allow_issue &&
        (((id_exu_sel == 1'b1) && id_dec1_is_ex) || ((id_bru_sel == 1'b1) && id_dec1_is_br) ||
         ((id_lsu_sel == 1'b1) && id_dec1_is_ls) || ((id_fpu_sel == 1'b1) && id_dec1_is_fp) ||
         id_dec1_is_mt);  //TODO: These checks seems redundant

    // REPLAY!
    // TODO: Corner case: control is being redirected but cache missed,
    // If delay slot is enabled, still need to ensure they get executed
    // In such case, the branch instruction should be replayed
    wire replay_icache_miss = id_reg_valid && !im_resp_valid;
    wire [31:0] replay_icache_miss_pc = id_reg_pc;
    wire replay_delayslot_miss = replay_icache_miss && id_is_delayslot;
    wire [31:0] replay_delayslot_miss_pc = e1_reg_bru_sel ? e1_reg_instr1_pc : e1_reg_instr0_pc;
    wire replay_stalled = id_instr0_valid && !instr0_issued;
    wire [31:0] replay_stalled_pc = id_instr0_pc;
    wire replay_nodi = id_instr1_valid && !instr1_issued;
    wire [31:0] replay_nodi_pc = id_instr1_pc;
    wire replay_mispredict;
    wire [31:0] replay_mispredict_pc;
    wire replay_dcache_miss;
    wire [31:0] replay_dcache_miss_pc;

    assign if_pc_redirect = replay_icache_miss || replay_delayslot_miss || replay_nodi || replay_mispredict;
    assign if_pc_redirect_target = (replay_dcache_miss) ? (replay_dcache_miss_pc) :  // E2
        (replay_delayslot_miss) ? (replay_delayslot_miss_pc) :  // E1
        (replay_mispredict) ? (replay_mispredict_pc) :  // E1
        (replay_icache_miss) ? (replay_icache_miss_pc) :  // ID
        (replay_stalled) ? (replay_stalled_pc) :  // ID
        (replay_nodi) ? (replay_nodi_pc) : 32'bx;  // ID

    // Store information about the instructions issued
    reg e1_reg_instr0_valid;
    reg [31:0] e1_reg_instr0_pc;
    reg [15:0] e1_reg_instr0_raw;
    reg [3:0] e1_reg_instr0_flags;

    reg e1_reg_instr1_valid;
    reg [31:0] e1_reg_instr1_pc;
    reg [15:0] e1_reg_instr1_raw;
    reg [3:0] e1_reg_instr1_flags;

    reg [31:0] e1_reg_instr0_npc;
    reg [31:0] e1_reg_instr1_npc;
    reg e1_reg_instr0_write_t;
    reg e1_reg_instr1_write_t;
    always @(posedge clk) begin
        e1_reg_instr0_valid <= instr0_issued;
        e1_reg_instr1_valid <= instr1_issued;
        e1_reg_instr0_pc <= id_instr0_pc;
        e1_reg_instr1_pc <= id_instr1_pc;
        e1_reg_instr0_npc <= id_instr0_npc;
        e1_reg_instr1_npc <= id_instr1_npc;
        e1_reg_instr0_raw <= id_instr0_raw;
        e1_reg_instr1_raw <= id_instr1_raw;
        e1_reg_instr0_flags <= 4'd0;
        e1_reg_instr1_flags <= 4'd0;
        e1_reg_instr0_write_t <= id_dec0_write_t;
        e1_reg_instr1_write_t <= id_dec1_write_t;
        if (rst) begin
            e1_reg_instr0_valid <= 1'b0;
            e1_reg_instr1_valid <= 1'b0;
        end
    end

    // ---- E1 ----

    reg [3:0] e1_reg_flags;  // Flags: M Q S T
    wire e1_flush;
    wire [3:0] e1_flags_restore;
    wire e1_flags_restore_en;

    wire [31:0] e1_csr_sr = {
        1'b0, csr_sr_md, csr_sr_rb, csr_sr_bl, 12'd0, csr_sr_fd, 5'd0, e1_reg_flags[3:2], csr_sr_imask, 2'b0, e1_reg_flags[1:0]
    };

    reg [31:0] csr_rdata;
    always @(*) begin
        case (e1_reg_lsu_csr_id)
            `CSR_SR: csr_rdata = e1_csr_sr;
            `CSR_GBR: csr_rdata = csr_gbr;
            `CSR_VBR: csr_rdata = csr_vbr;
            `CSR_SSR: csr_rdata = csr_ssr;
            `CSR_SPC: csr_rdata = csr_spc;
            `CSR_DBR: csr_rdata = csr_dbr;
            `CSR_SGR: csr_rdata = csr_sgr;
            `CSR_MACH: csr_rdata = csr_mach;
            `CSR_MACL: csr_rdata = csr_macl;
            `CSR_PR: csr_rdata = csr_pr;
            `CSR_FPSCR: csr_rdata = csr_fpscr;
            `CSR_FPUL: csr_rdata = csr_fpul;
            default: csr_rdata = 32'bx;
        endcase
    end

    // EXU
    wire [3:0] e1_reg_exu_flags = e1_reg_flags;
    wire [3:0] e1_exu_flags;
    wire e1_exu_wen;
    wire [3:0] e1_exu_wdst;
    wire [31:0] e1_exu_wdata;

    wire e1_exu_wpending = 1'b0;  // EXU always generate results immediately
    exu exu (
        .in_valid(e1_reg_exu_valid),
        .in_flags(e1_reg_exu_flags),
        .in_raw(e1_reg_exu_raw),
        .in_opl(e1_reg_exu_opl),
        .in_oph(e1_reg_exu_oph),
        .out_flags(e1_exu_flags),
        .out_wen(e1_exu_wen),
        .out_wdst(e1_exu_wdst),
        .out_wdata(e1_exu_wdata)
    );

    // BRU
    wire [31:0] e1_reg_bru_pr = csr_pr;
    wire e1_reg_bru_t = e1_reg_flags[0];
    wire e1_bru_taken;
    wire [31:0] e1_bru_target;
    wire e1_bru_delayslot;
    wire e1_bru_write_pr;

    bru bru (
        .in_valid(e1_reg_bru_valid),
        .in_pr(e1_reg_bru_pr),
        .in_t(e1_reg_bru_t),
        .in_raw(e1_reg_bru_raw),
        .in_opl(e1_reg_bru_opl),
        .in_oph(e1_reg_bru_oph),
        .out_taken(e1_bru_taken),
        .out_target(e1_bru_target),
        .out_delayslot(e1_bru_delayslot),
        .out_write_pr(e1_bru_write_pr)
    );
    // TODO: PR register
    assign replay_mispredict = e1_bru_taken;
    assign replay_mispredict_pc = e1_bru_target;
    // 0 is flushed if there is no delay slot, OR branch is issued in slot0
    assign id_flush0 = e1_bru_taken && ((!e1_bru_delayslot) || (e1_reg_bru_sel == 1'b0));
    // 1 is flushed if there is no delay slot, OR branch is issued in slot1,
    // OR branch is issued in slot0 and dual issued
    assign id_flush1 = e1_bru_taken &&
        ((!e1_bru_delayslot) || (e1_reg_bru_sel == 1'b1) || ((e1_reg_bru_sel == 1'b0) && e1_reg_instr1_valid));
    // Current ID contains a delay slot instruction, need to replay BR until
    // cache-line is reloaded.
    assign id_is_delayslot = e1_bru_taken && e1_bru_delayslot && !(id_flush0 || id_flush1);

    // MTU
    wire e1_mtu0_t;
    wire e1_mtu0_wen;
    wire [3:0] e1_mtu0_wdst;
    wire [31:0] e1_mtu0_wdata;

    wire e1_mtu0_wpending = 1'b0;
    mtu mtu0 (
        .in_valid(e1_reg_mtu0_valid),
        .in_raw(e1_reg_mtu0_raw),
        .in_opl(e1_reg_mtu0_opl),
        .in_oph(e1_reg_mtu0_oph),
        .out_t(e1_mtu0_t),
        .out_wen(e1_mtu0_wen),
        .out_wdst(e1_mtu0_wdst),
        .out_wdata(e1_mtu0_wdata)
    );

    wire e1_mtu1_t;
    wire e1_mtu1_wen;
    wire [3:0] e1_mtu1_wdst;
    wire [31:0] e1_mtu1_wdata;

    wire e1_mtu1_wpending = 1'b0;
    mtu mtu1 (
        .in_valid(e1_reg_mtu1_valid),
        .in_raw(e1_reg_mtu1_raw),
        .in_opl(e1_reg_mtu1_opl),
        .in_oph(e1_reg_mtu1_oph),
        .out_t(e1_mtu1_t),
        .out_wen(e1_mtu1_wen),
        .out_wdst(e1_mtu1_wdst),
        .out_wdata(e1_mtu1_wdata)
    );

    // LSU
    wire e1_lsu_alt_wen;
    wire [3:0] e1_lsu_alt_wdst;
    wire [31:0] e1_lsu_alt_wdata;
    wire e1_lsu_fpul_wen;
    wire e1_lsu_wpending;
    wire e1_lsu_wfp;
    wire e1_lsu_wen;
    wire [3:0] e1_lsu_wdst;
    wire [31:0] e1_lsu_wdata;

    wire e2_lsu_csr_wen;
    wire [31:0] e2_lsu_csr_wdata;
    wire e2_lsu_csr_tonly;
    wire e2_lsu_nack;
    wire e2_lsu_fpul_wen;
    wire e2_lsu_waltbank;
    wire e2_lsu_wfp;
    wire e2_lsu_wen;
    wire [3:0] e2_lsu_wdst;
    wire [31:0] e2_lsu_wdata;

    wire [31:0] e1_reg_lsu_csr_rdata = csr_rdata;
    wire [31:0] e1_reg_lsu_fpul = csr_fpul;
    lsu lsu (
        .clk(clk),
        .rst(rst),
        .e1_flush(e1_flush),
        .fpscr_sz(csr_fpscr_sz),
        .in_valid(e1_reg_lsu_valid),
        .in_csr_rdata(e1_reg_lsu_csr_rdata),
        .in_r0(e1_reg_lsu_r0),
        .in_fpr(e1_reg_lsu_fpr),
        .in_raw(e1_reg_lsu_raw),
        .in_opl(e1_reg_lsu_opl),
        .in_oph(e1_reg_lsu_oph),
        .e1_alt_wen(e1_lsu_alt_wen),
        .e1_alt_wdst(e1_lsu_alt_wdst),
        .e1_alt_wdata(e1_lsu_alt_wdata),
        .e1_fpul_wen(e1_lsu_fpul_wen),
        .e1_wpending(e1_lsu_wpending),
        .e1_wfp(e1_lsu_wfp),
        .e1_wen(e1_lsu_wen),
        .e1_wdst(e1_lsu_wdst),
        .e1_wdata(e1_lsu_wdata),
        .e2_csr_wen(e2_lsu_csr_wen),
        .e2_csr_wdata(e2_lsu_csr_wdata),
        .e2_csr_tonly(e2_lsu_csr_tonly),
        .e2_nack(e2_lsu_nack),
        .e2_fpul_wen(e2_lsu_fpul_wen),
        .e2_waltbank(e2_lsu_waltbank),
        .e2_wfp(e2_lsu_wfp),
        .e2_wen(e2_lsu_wen),
        .e2_wdst(e2_lsu_wdst),
        .e2_wdata(e2_lsu_wdata),
        .dm_req_addr(dm_req_addr),
        .dm_req_wdata(dm_req_wdata),
        .dm_req_wmask(dm_req_wmask),
        .dm_req_wen(dm_req_wen),
        .dm_req_valid(dm_req_valid),
        .dm_resp_rdata(dm_resp_rdata),
        .dm_resp_valid(dm_resp_valid),
        .dm_req_flush(dm_req_flush),
        .dm_req_invalidate(dm_req_invalidate),
        .dm_req_writeback(dm_req_writeback),
        .dm_req_prefetch(dm_req_prefetch),
        .dm_req_nofill(dm_req_nofill)
    );
    assign fprf_wen1 = e2_lsu_wfp;
    assign fprf_wdst1 = e2_lsu_wdst;
    assign fprf_wbank1 = csr_fpscr_fr;
    assign fprf_wdata1 = e2_lsu_wdata;

    // FPU
    wire fpu_out_valid;
    wire fpu_out_t;
    wire fpu_out_t_wen;
    wire [31:0] fpu_out_fpul;
    wire fpu_out_fpul_wen;
    wire fpu_out_wen;
    wire [3:0] fpu_out_wdst;
    wire fpu_out_wbank;
    wire [31:0] fpu_out_wdata;

    fpu fpu (
        .clk(clk),
        .rst(rst),
        .fpscr(csr_fpscr),
        .in_valid(e1_reg_fpu_valid),
        .in_raw(e1_reg_fpu_raw),
        .in_fop(e1_reg_fpu_fop),
        .in_frl(e1_reg_fpu_frl),
        .in_frh(e1_reg_fpu_frh),
        .in_fr0(e1_reg_fpu_fr0),
        .out_valid(fpu_out_valid),
        .out_t(fpu_out_t),
        .out_t_wen(fpu_out_t_wen),
        .out_fpul(fpu_out_fpul),
        .out_fpul_wen(fpu_out_fpul_wen),
        .out_wen(fpu_out_wen),
        .out_wdst(fpu_out_wdst),
        .out_wbank(fpu_out_wbank),
        .out_wdata(fpu_out_wdata)
    );
    assign fprf_wen0 = fpu_out_wen && fpu_out_valid;
    assign fprf_wdst0 = fpu_out_wdst;
    assign fprf_wbank0 = fpu_out_wbank;
    assign fprf_wdata0 = fpu_out_wdata;

    // Flag write back
    wire [3:0] e1_flags_wb;
    assign e1_flags_wb[3:1] = e1_exu_flags[3:1];
    assign e1_flags_wb[0] = (e1_reg_mtu1_valid && e1_reg_instr1_write_t) ? e1_mtu1_t :
        (e1_reg_mtu0_valid && e1_reg_instr0_write_t) ? e1_mtu0_t : (fpu_out_valid && fpu_out_t_wen) ? fpu_out_t : e1_exu_flags[0];
    wire [3:0] e2_flags_wb;
    wire e2_flags_wen;

    always @(posedge clk) begin
        if (e1_flags_restore_en) e1_reg_flags <= e1_flags_restore;
        else if (!e1_flush) e1_reg_flags <= e1_flags_wb;

        // If modified by CSR instructions...
        if (e2_flags_wen) e1_reg_flags <= e2_flags_wb;

        if (e2_lsu_csr_wen && e2_lsu_csr_tonly) e1_reg_flags[0] <= e2_csr_wdata[0];

        if (rst) begin
            e1_reg_flags <= 4'b0;  // Actually in DS this is not resetted
        end
    end

    // Completion pipe and forward source
    reg e1_p0_wpending;
    reg e1_p0_wen;
    reg [3:0] e1_p0_wdst;
    reg [31:0] e1_p0_wdata;

    reg e1_p1_wpending;
    reg e1_p1_wen;
    reg [3:0] e1_p1_wdst;
    reg [31:0] e1_p1_wdata;


    always @(*) begin
        // Set default values
        e1_p0_wdata = 32'bx;
        e1_p0_wdst = 4'bx;
        e1_p0_wen = 1'b0;
        e1_p0_wpending = 1'b0;
        e1_p1_wdata = 32'bx;
        e1_p1_wdst = 4'bx;
        e1_p1_wen = 1'b0;
        e1_p1_wpending = 1'b0;

        // Assign value based on FU enable
        if (e1_reg_exu_valid) begin
            if (e1_reg_exu_sel == 1'b0) begin
                e1_p0_wpending = e1_exu_wpending;
                e1_p0_wen = e1_exu_wen;
                e1_p0_wdst = e1_exu_wdst;
                e1_p0_wdata = e1_exu_wdata;
            end else begin
                e1_p1_wpending = e1_exu_wpending;
                e1_p1_wen = e1_exu_wen;
                e1_p1_wdst = e1_exu_wdst;
                e1_p1_wdata = e1_exu_wdata;
            end
        end
        if (e1_reg_mtu0_valid && e1_mtu0_wen) begin
            e1_p0_wpending = e1_mtu0_wpending;
            e1_p0_wen = e1_mtu0_wen;
            e1_p0_wdst = e1_mtu0_wdst;
            e1_p0_wdata = e1_mtu0_wdata;
        end
        if (e1_reg_mtu1_valid && e1_mtu1_wen) begin
            e1_p1_wpending = e1_mtu1_wpending;
            e1_p1_wen = e1_mtu1_wen;
            e1_p1_wdst = e1_mtu1_wdst;
            e1_p1_wdata = e1_mtu1_wdata;
        end
        if (e1_reg_lsu_valid && !e1_lsu_wfp) begin
            if ((e1_reg_lsu_sel == 1'b0) || e1_lsu_alt_wen) begin
                e1_p0_wpending = e1_lsu_wpending;
                e1_p0_wen = e1_lsu_wen;
                e1_p0_wdst = e1_lsu_wdst;
                e1_p0_wdata = e1_lsu_wdata;
            end else begin
                e1_p1_wpending = e1_lsu_wpending;
                e1_p1_wen = e1_lsu_wen;
                e1_p1_wdst = e1_lsu_wdst;
                e1_p1_wdata = e1_lsu_wdata;
            end
            if (e1_lsu_alt_wen) begin  // Requested to use another pipe's WR port
                e1_p1_wen = e1_lsu_alt_wen;
                e1_p1_wdst = e1_lsu_alt_wdst;
                e1_p1_wdata = e1_lsu_alt_wdata;
            end
        end
        // Mask off if flushed
        if (e1_flush) begin
            e1_p0_wen = 1'b0;
            e1_p1_wen = 1'b0;
        end
    end

    // Register output
    reg e2_reg_p0_wpending;
    reg e2_reg_p0_wen;
    reg [3:0] e2_reg_p0_wdst;
    reg [31:0] e2_reg_p0_wdata;

    reg e2_reg_p1_wpending;
    reg e2_reg_p1_wen;
    reg [3:0] e2_reg_p1_wdst;
    reg [31:0] e2_reg_p1_wdata;

    always @(posedge clk) begin
        e2_reg_p0_wpending <= e1_p0_wpending;
        e2_reg_p0_wen <= e1_p0_wen;
        e2_reg_p0_wdst <= e1_p0_wdst;
        e2_reg_p0_wdata <= e1_p0_wdata;
        e2_reg_p1_wpending <= e1_p1_wpending;
        e2_reg_p1_wen <= e1_p1_wen;
        e2_reg_p1_wdst <= e1_p1_wdst;
        e2_reg_p1_wdata <= e1_p1_wdata;
        if (rst) begin
            e2_reg_p0_wen <= 1'b0;
            e2_reg_p1_wen <= 1'b0;
        end
    end

    // Pipedown informations
    reg e2_reg_instr0_valid;
    reg [31:0] e2_reg_instr0_pc;
    reg [15:0] e2_reg_instr0_raw;
    reg [3:0] e2_reg_instr0_flags;

    reg e2_reg_instr1_valid;
    reg [31:0] e2_reg_instr1_pc;
    reg [15:0] e2_reg_instr1_raw;
    reg [3:0] e2_reg_instr1_flags;

    reg e2_reg_lsu_valid;
    reg e2_reg_lsu_sel;
    reg e2_reg_lsu_alt_wen;
    reg [3:0] e2_reg_lsu_csr_id;
    reg e2_reg_bru_write_pr;
    reg [31:0] e2_reg_bru_pr_target;
    always @(posedge clk) begin
        e2_reg_instr0_valid <= e1_reg_instr0_valid;
        e2_reg_instr0_pc <= e1_reg_instr0_pc;
        e2_reg_instr0_raw <= e1_reg_instr0_raw;
        e2_reg_instr0_flags <= e1_reg_instr0_flags;
        e2_reg_instr1_valid <= e1_reg_instr1_valid;
        e2_reg_instr1_pc <= e1_reg_instr1_pc;
        e2_reg_instr1_raw <= e1_reg_instr1_raw;
        e2_reg_instr1_flags <= e1_reg_instr1_flags;
        // Override default capture
        e2_reg_instr0_valid <= e1_reg_instr0_valid & !e1_flush;
        e2_reg_instr1_valid <= e1_reg_instr1_valid & !e1_flush;
        // this captures the flags status before instruction execution
        e2_reg_instr0_flags <= e1_reg_flags;
        e2_reg_instr1_flags <= (!e1_reg_instr0_write_t) ?
            e1_reg_flags : (e1_reg_mtu0_valid ? {e1_reg_flags[3:1], e1_mtu0_t} : e1_exu_flags);
        e2_reg_lsu_valid <= e1_reg_lsu_valid;
        e2_reg_lsu_sel <= e1_reg_lsu_sel;
        e2_reg_lsu_alt_wen <= e1_lsu_alt_wen;
        e2_reg_lsu_csr_id <= e1_reg_lsu_csr_id;
        e2_reg_bru_write_pr <= e1_bru_write_pr;
        e2_reg_bru_pr_target <= (e1_reg_bru_sel == 1'b0) ? e1_reg_instr0_npc : e1_reg_instr1_npc;
    end

    // ---- E2 ----

    wire e2_flush0;
    wire e2_flush1;

    reg e2_p0_wpending;
    reg e2_p0_wen;
    reg [3:0] e2_p0_wdst;
    reg [31:0] e2_p0_wdata;

    reg e2_p1_wpending;
    reg e2_p1_wen;
    reg [3:0] e2_p1_wdst;
    reg [31:0] e2_p1_wdata;

    reg e2_p0_waltbank;
    reg e2_p1_waltbank;
    always @(*) begin
        // Set default values
        e2_p0_wpending = e2_reg_p0_wpending;
        e2_p0_wen = e2_reg_p0_wen;
        e2_p0_wdst = e2_reg_p0_wdst;
        e2_p0_wdata = e2_reg_p0_wdata;
        e2_p1_wpending = e2_reg_p1_wpending;
        e2_p1_wen = e2_reg_p1_wen;
        e2_p1_wdst = e2_reg_p1_wdst;
        e2_p1_wdata = e2_reg_p1_wdata;
        e2_p0_waltbank = 1'b0;
        e2_p1_waltbank = 1'b0;
        // Take LSU output
        if (e2_reg_lsu_valid && e2_lsu_wen && !e2_lsu_wfp) begin
            // It's important not to overwrite E2 LSU output if WEN is low:
            // This could happen during LD @Rm+, CSR where incremented Rm is
            // only valid during E1
            if ((e2_reg_lsu_sel == 1'b0) || e2_reg_lsu_alt_wen) begin
                e2_p0_wen = e2_lsu_wen;
                e2_p0_wdst = e2_lsu_wdst;
                e2_p0_wdata = e2_lsu_wdata;
                e2_p0_waltbank = e2_lsu_waltbank;
            end else begin
                e2_p1_wen = e2_lsu_wen;
                e2_p1_wdst = e2_lsu_wdst;
                e2_p1_wdata = e2_lsu_wdata;
                e2_p1_waltbank = e2_lsu_waltbank;
            end
        end
        if (e2_flush0) e2_p0_wen = 1'b0;
        if (e2_flush1) e2_p1_wen = 1'b0;
    end
    assign rf_wbank_p0 = csr_sr_md && (csr_sr_rb ^ e2_p0_waltbank);
    assign rf_wbank_p1 = csr_sr_md && (csr_sr_rb ^ e2_p1_waltbank);

    // Handle NACK, need to flush current
    // ID instructions, E1 instructions, and E2 instructions if dual-issued
    // Should always flush itself
    assign e1_flush = e2_lsu_nack;
    assign e1_flags_restore_en = e2_lsu_nack;
    assign e1_flags_restore = (e2_reg_lsu_sel == 1'b0) ? e2_reg_instr0_flags : e2_reg_instr1_flags;
    assign e2_flush0 = e2_lsu_nack && ((e2_reg_lsu_sel == 1'b0) || e2_reg_lsu_alt_wen);
    assign e2_flush1 = e2_lsu_nack;
    assign replay_dcache_miss = e2_lsu_nack;
    assign replay_dcache_miss_pc = (e2_reg_lsu_sel == 1'b0) ? e2_reg_instr0_pc : e2_reg_instr1_pc;

    // Putting register RF here instead of in a separate WB stage
    // Add WB stage if running to actual timing issues later
    assign rf_wen0 = e2_p0_wen;
    assign rf_wdst0 = e2_p0_wdst;
    assign rf_wdata0 = e2_p0_wdata;

    assign rf_wen1 = e2_p1_wen;
    assign rf_wdst1 = e2_p1_wdst;
    assign rf_wdata1 = e2_p1_wdata;

    // CSR writeback
    wire [31:0] e2_csr_wdata = e2_lsu_csr_wdata;
    wire [3:0] e2_csr_wdst = e2_reg_lsu_csr_id;
    wire e2_csr_wen = e2_lsu_csr_wen && !e2_lsu_csr_tonly;
    assign e2_flags_wb = {e2_csr_wdata[9:8], e2_csr_wdata[1:0]};
    assign e2_flags_wen = e2_csr_wen && (e2_csr_wdst == `CSR_SR);

    always @(posedge clk) begin
        if (e2_csr_wen) begin
            case (e2_csr_wdst)
                `CSR_SR: begin
                    csr_sr_md <= e2_csr_wdata[30];
                    csr_sr_rb <= e2_csr_wdata[29];
                    csr_sr_bl <= e2_csr_wdata[28];
                    csr_sr_fd <= e2_csr_wdata[15];
                    csr_sr_imask <= e2_csr_wdata[7:4];
                end
                `CSR_GBR: csr_gbr <= e2_csr_wdata;
                `CSR_VBR: csr_vbr <= e2_csr_wdata;
                `CSR_SSR: csr_ssr <= e2_csr_wdata;
                `CSR_SPC: csr_spc <= e2_csr_wdata;
                `CSR_DBR: csr_dbr <= e2_csr_wdata;
                `CSR_SGR: csr_sgr <= e2_csr_wdata;
                `CSR_MACH: csr_mach <= e2_csr_wdata;
                `CSR_MACL: csr_macl <= e2_csr_wdata;
                `CSR_PR: csr_pr <= e2_csr_wdata;
                `CSR_FPSCR: csr_fpscr <= e2_csr_wdata;
                `CSR_FPUL: csr_fpul <= e2_csr_wdata;
                default: begin
                    $error("Writing to non-exist CSR %d", e2_csr_wdst);
                end
            endcase
        end
        if (e2_reg_bru_write_pr) csr_pr <= e2_reg_bru_pr_target;

        if (fpu_out_fpul_wen) csr_fpul <= fpu_out_fpul;

        if (rst) begin
            csr_sr_md <= 1'b1;
`ifdef DIRECT_BOOT
            csr_sr_rb <= 1'b0;
`else
            csr_sr_rb <= 1'b1;
`endif
            csr_sr_bl <= 1'b1;
            csr_sr_fd <= 1'b0;
            csr_sr_imask <= 4'b1111;
            csr_vbr <= 32'd0;
            csr_fpscr <= 32'h0040001;
`ifdef DIRECT_BOOT
            csr_pr <= 32'h8c000128;
            csr_gbr <= 32'h8c000000;
            csr_vbr <= 32'h8c000000;
            csr_ssr <= 32'h500000f0;
            csr_spc <= 32'hac000800;
`endif
        end
    end

    // Assign trace
    assign trace_valid0 = e2_reg_instr0_valid && !e2_flush0;
    assign trace_valid1 = e2_reg_instr1_valid && !e2_flush1;
    assign trace_pc0 = e2_reg_instr0_pc;
    assign trace_pc1 = e2_reg_instr1_pc;
    assign trace_instr0 = e2_reg_instr0_raw;
    assign trace_instr1 = e2_reg_instr1_raw;
    assign trace_wen0 = rf_wen0;
    assign trace_wdst0 = rf_wdst0;
    assign trace_wdata0 = rf_wdata0;
    assign trace_wen1 = rf_wen1;
    assign trace_wdst1 = rf_wdst1;
    assign trace_wdata1 = rf_wdata1;

    // Tieoff unused stuff for now
    assign im_invalidate_req = 0;

endmodule
