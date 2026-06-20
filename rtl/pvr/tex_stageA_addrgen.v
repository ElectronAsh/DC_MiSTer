`timescale 1ns / 1ps
`default_nettype none

module tex_stageA_addrgen (
    input  wire        clock,
    input  wire        reset_n,
	input  wire        pipe_flush,
    input  wire        vram_wait,

    input  wire        tsp_valid,
    input  wire [9:0]  ui,
    input  wire [9:0]  vi,
    input  wire [9:0]  x_ps,
    input  wire [9:0]  y_ps,
    input  wire [31:0] base_argb,
    input  wire [31:0] offs_argb,
	
	input wire [11:0]  prim_tag,

    /* ------------------------------------------------------------
     * Control words
     * ------------------------------------------------------------ */
    input  wire [31:0] isp_inst,
    input  wire [31:0] tsp_inst,
    input  wire [31:0] tcw_word,

    /* ------------------------------------------------------------
     * Outputs to Stage B
     * ------------------------------------------------------------ */
    output reg         tex_addr_valid,
	
	output reg  [9:0]  x_ps_r,
	output reg  [9:0]  y_ps_r,
	output reg  [31:0] base_argb_r,
	output reg  [31:0] offs_argb_r,
	output reg         trace_a,
	
	output wire [20:0] tex_base_word_addr,
	output reg [20:0] texel_word_offs,

    output reg         tex_ignore_alpha_r,

    output reg  [2:0]  pix_fmt_r,
    output reg  [1:0]  shade_inst_r,
    output reg         texture_en_r,
    output reg         offset_en_r,

    output reg         vq_comp_r,
    output reg         is_pal4_r,
    output reg         is_pal8_r,

    output reg  [2:0]  pal8_sel_r,
    output reg  [1:0]  pix_sel_r,

    output reg  [5:0]  pal_selector_r,
    output reg  [11:0] prim_tag_r
);

	localparam [9:0] TRACE_X = 10'd0;
	localparam [9:0] TRACE_Y = 10'd1;

    reg [9:0]  ui_r;
    reg [9:0]  vi_r;
	
	wire input_accept = tsp_valid && !vram_wait;
    wire [9:0] ui_addr = input_accept ? ui : ui_r;
    wire [9:0] vi_addr = input_accept ? vi : vi_r;

	always @(posedge clock or negedge reset_n)
	if (!reset_n) begin
		ui_r <= 10'd0;
		vi_r <= 10'd0;
	end else if (pipe_flush) begin
		ui_r <= 10'd0;
		vi_r <= 10'd0;
	end else begin
		if (input_accept) begin
			ui_r   <= ui;
			vi_r   <= vi;
		end
	end


    /* ============================================================
     * Instruction decode
     * ============================================================ */
    wire tex_ignore_alpha_w = tsp_inst[19];

    wire texture_en_w       = isp_inst[25];
    wire offset_en_w        = isp_inst[24];
    wire [1:0] shade_inst_w = tsp_inst[7:6];

    wire mip_map              = tcw_word[31];
    wire vq_comp_w            = tcw_word[30];
    wire [2:0] pix_fmt_w      = tcw_word[29:27];
    wire scan_order           = tcw_word[26];
    wire [5:0] pal_selector_w = tcw_word[26:21];
    assign tex_base_word_addr = tcw_word[20:0];

    wire is_pal4_w = (pix_fmt_w == 3'd5);
    wire is_pal8_w = (pix_fmt_w == 3'd6);
    wire is_twid   = (scan_order == 1'b0) || vq_comp_w;

    /* ============================================================
     * Texture size masks
     * ============================================================ */
    wire [2:0] tex_u_size = tsp_inst[5:3];
    wire [2:0] tex_v_size = tsp_inst[2:0];

    reg [9:0] size_mask_u, size_mask_v;
    always @(*) begin
		size_mask_u = (10'd1 << (tex_u_size + 3)) -1;
		size_mask_v = (10'd1 << (tex_v_size + 3)) -1;
    end

    wire [9:0] ui_masked = ui_addr & size_mask_u;
    wire [9:0] vi_masked = vi_addr & size_mask_v;

    /* ============================================================
     * Twiddle logic
     * ============================================================ */
    wire [19:0] twop_full = {
        ui_masked[9], vi_masked[9],
        ui_masked[8], vi_masked[8],
        ui_masked[7], vi_masked[7],
        ui_masked[6], vi_masked[6],
        ui_masked[5], vi_masked[5],
        ui_masked[4], vi_masked[4],
        ui_masked[3], vi_masked[3],
        ui_masked[2], vi_masked[2],
        ui_masked[1], vi_masked[1],
        ui_masked[0], vi_masked[0]
    };
    
    reg [19:0] twop;
    wire [2:0] which_uv = (tex_u_size > tex_v_size) ? tex_v_size : tex_u_size;

    wire [9:0] upper_bits = (tex_u_size == tex_v_size || mip_map) ? 10'd0 :     // Square textures, force the upper_bits to zero. MIPMAPs are always square.
							(tex_u_size > tex_v_size) ? ui_masked : vi_masked;  // Twiddled textures can be either Square or Rectangular.

    always @(*) begin
        case (which_uv)
            0: twop = {7'b0, upper_bits[9:3], twop_full[5:0]};  // Smaller dimension = 8
            1: twop = {6'b0, upper_bits[9:4], twop_full[7:0]};  // Smaller dimension = 16
            2: twop = {5'b0, upper_bits[9:5], twop_full[9:0]};  // Smaller dimension = 32
            3: twop = {4'b0, upper_bits[9:6], twop_full[11:0]}; // Smaller dimension = 64
            4: twop = {3'b0, upper_bits[9:7], twop_full[13:0]}; // Smaller dimension = 128
            5: twop = {2'b0, upper_bits[9:8], twop_full[15:0]}; // Smaller dimension = 256
            6: twop = {1'b0, upper_bits[9],   twop_full[17:0]}; // Smaller dimension = 512
            default: twop = twop_full;							// 1024 / Default.
        endcase
    end

    /* ============================================================
     * Mipmap offset (unchanged)
     * ============================================================ */
	reg [19:0] mipmap_byte_offs_norm;
	always @(*) begin
		case (tex_u_size + 3)
			0:  mipmap_byte_offs_norm = 20'h6;
			1:  mipmap_byte_offs_norm = 20'h8;
			2:  mipmap_byte_offs_norm = 20'h10;
			3:  mipmap_byte_offs_norm = 20'h30;
			4:  mipmap_byte_offs_norm = 20'hb0;
			5:  mipmap_byte_offs_norm = 20'h2b0;
			6:  mipmap_byte_offs_norm = 20'hab0;
			7:  mipmap_byte_offs_norm = 20'h2ab0;
			8:  mipmap_byte_offs_norm = 20'haab0;
			9:  mipmap_byte_offs_norm = 20'h2aab0;
			10: mipmap_byte_offs_norm = 20'haaab0;
			default: mipmap_byte_offs_norm = 20'haaab0;
		endcase
	end
	
	reg [19:0] mipmap_byte_offs;
	always @(*) begin
		mipmap_byte_offs =
			(!mip_map)               ? 20'd0 :
			(vq_comp_w)              ? mipmap_byte_offs_norm >> 3 :	// VQ.
			(is_pal4_w || is_pal8_w) ? mipmap_byte_offs_norm >> 1 :	// PAL4 or PAL8
									   mipmap_byte_offs_norm;		// Uncompressed?
	end

	/* ============================================================
	 * Final address calculation
	 * ============================================================ */
    wire [19:0] non_twid_addr = (ui_masked + (vi_masked * (8<<tex_u_size)));

	wire [19:0] twop_or_not = vq_comp_w ? ((12'd2048 + mipmap_byte_offs) << 2) + twop :
	(is_pal4_w || is_pal8_w || is_twid) ? (mipmap_byte_offs >> 1) + twop :
									       mipmap_byte_offs + non_twid_addr;

	/* ============================================================
	 * Selection bits for Stage B
	 * ============================================================ */
	wire [2:0] pal8_sel_w = vq_comp_w ? twop_or_not[4:2] :
                            is_pal4_w ? twop_or_not[3:1] :
										twop_or_not[2:0];

	wire [1:0] pix_sel_w = is_twid ? twop[1:0] : non_twid_addr[1:0];

    /* ============================================================
     * Stage A register boundary
     * ============================================================ */
	always @(posedge clock or negedge reset_n)
		if (!reset_n) begin
			tex_addr_valid <= 1'b0;
			base_argb_r <= 32'd0;
			offs_argb_r <= 32'd0;
			trace_a <= 1'b0;
		end
		else if (pipe_flush) begin
			tex_addr_valid <= 1'b0;
			base_argb_r <= 32'd0;
			offs_argb_r <= 32'd0;
			trace_a <= 1'b0;
		end
		else begin
			tex_addr_valid <= 1'b0;
			trace_a <= 1'b0;

			if (input_accept) begin
				tex_addr_valid <= 1'b1;
				x_ps_r <= x_ps;
				y_ps_r <= y_ps;
				base_argb_r <= base_argb;
				offs_argb_r <= offs_argb;
				trace_a <= (x_ps == TRACE_X) && (y_ps == TRACE_Y);

				if ((x_ps == TRACE_X) && (y_ps == TRACE_Y)) begin
					//$display("[%0t] tex_stageA: trace_a tex_addr_valid=1 vq=%0d pal4=%0d pal8=%0d x_ps_r=%d y_ps_r=%d",
					         //$time, vq_comp_w, is_pal4_w, is_pal8_w, x_ps, y_ps);
				end

                texel_word_offs <= vq_comp_w ? (twop_or_not >> 5) :	// VQ (32 Texels per Word).  Increment Word addr half as often as for 4BPP.
                                   is_pal4_w ? (twop_or_not >> 4) :	// PAL4 (4BPP). Increment Word addr half as often as for 8BPP.
                                   is_pal8_w ? (twop_or_not >> 3) :	// PAL8 (8BPP). Increment Word addr half as often as for 16BPP.
                                               (twop_or_not >> 2);	// 16BPP.

                tex_ignore_alpha_r <= tex_ignore_alpha_w;

				pix_fmt_r      <= pix_fmt_w;
				shade_inst_r   <= shade_inst_w;
				texture_en_r   <= texture_en_w;
				offset_en_r    <= offset_en_w;

				vq_comp_r      <= vq_comp_w;
				is_pal4_r      <= is_pal4_w;
				is_pal8_r      <= is_pal8_w;

				pal8_sel_r     <= pal8_sel_w;
				pix_sel_r      <= pix_sel_w;

				pal_selector_r <= pal_selector_w;
				prim_tag_r     <= prim_tag;
			end
		end

endmodule
