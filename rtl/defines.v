
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

`define REG_RD_PORTS 4
`define REG_WR_PORTS 2
`define FPREG_RD_PORTS 3
`define FPREG_WR_PORTS 2


// Control registers
`define CSR_SR 4'd0
`define CSR_GBR 4'd1
`define CSR_VBR 4'd2
`define CSR_SSR 4'd3
`define CSR_SPC 4'd4
`define CSR_DBR 4'd5
`define CSR_SGR 4'd6
// System registers
`define CSR_MACH 4'd8
`define CSR_MACL 4'd9
`define CSR_PR 4'd10
`define CSR_FPSCR 4'd11
`define CSR_FPUL 4'd12

`include "fpu/fpu_defines.v"

`define FOP_FADD 4'd0
`define FOP_CMPEQ 4'd1
`define FOP_CMPGT 4'd2
`define FOP_FDIV 4'd3
`define FOP_FLOAT 4'd4    // int to float
`define FOP_FMAC 4'd5
`define FOP_FMUL 4'd6
`define FOP_FSQRT 4'd7
`define FOP_FSUB 4'd8
`define FOP_FTRC 4'd9    // float to int
`define FOP_FCNVDS 4'd10   // double to single
`define FOP_FCNVSD 4'd11   // single to double
`define FOP_FIPR 4'd12
`define FOP_FTRV 4'd13

`define RM_RNE 1'd0    // Round to nearest, tie to even
`define RM_RTZ 1'd1    // Round to zero

// Mode set
`define DIRECT_BOOT // Additional register intialize for direct boot
