`timescale 1ns / 1ps
`default_nettype none

module tex_stageB_fetch (
    input  wire        clock,
    input  wire        reset_n,
	input  wire        pipe_flush,

    /* ------------------------------------------------------------
     * External control / palette interface
     * ------------------------------------------------------------ */
    input  wire [31:0] TEXT_CONTROL,

    input  wire [15:0] pal_addr,
    input  wire [31:0] pal_din,
    input  wire        pal_rd,
    input  wire        pal_wr,
    output reg [31:0] pal_dout,

    input  wire        read_codebook,
    output wire        codebook_wait,
    output wire [7:0]  cb_word_index,
    input  wire [20:0] codebook_base,

    input  wire        cb_cache_clear,
    output wire        cb_cache_hit,

    /* ------------------------------------------------------------
     * From Stage A
     * ------------------------------------------------------------ */
    input  wire        tex_addr_valid,

    input wire         tex_ignore_alpha_w,

    input  wire        vq_comp_r,
    input  wire        is_pal4_r,
    input  wire        is_pal8_r,
    input  wire        texture_en_r,
    input  wire        offset_en_r,
    input  wire [2:0]  pix_fmt_r,
    input  wire [1:0]  shade_inst_r,

    input  wire [2:0]  pal8_sel_r,
    input  wire [1:0]  pix_sel_r,
    input  wire [5:0]  pal_selector_r,

    input  wire [11:0] prim_tag_r,

    input  wire [9:0]  x_ps_r,
    input  wire [9:0]  y_ps_r,
    input  wire [31:0] base_argb_r,
    input  wire [31:0] offs_argb_r,
	input  wire        trace_a,

    output reg tex_ignore_alpha_r,
    output reg texture_en_texel,
    output reg offset_en_texel,
    output reg [2:0] pix_fmt_texel,
    output reg [1:0] shade_inst_texel,
    output reg [31:0] base_argb_texel,
    output reg [31:0] offs_argb_texel,
	
	output wire stall_tex_fetch,
	output wire stall_codebook,
	output wire pipeline_busy,

    /* ------------------------------------------------------------
     * VRAM interface
     * ------------------------------------------------------------ */
    input  wire        tex_vram_valid,
    input  wire        tex_data_ready,
    input  wire [63:0] vram_din,

    /* ------------------------------------------------------------
     * Outputs to Stage C
     * ------------------------------------------------------------ */
    output reg  [15:0] pix16_r,
    output reg  [9:0]  x_ps_texel,
    output reg  [9:0]  y_ps_texel,
	output reg         texel_valid,
	output reg         trace_b
);

assign stall_tex_fetch = (tex_addr_valid && texture_en_r && !tex_data_ready) ||
                         (fetch_pending && !tex_data_ready);
assign stall_codebook = texture_en_r && vq_comp_r && codebook_wait;

    /* ============================================================
     * Codebook cache
     * ============================================================ */
    wire [63:0] cb_cache_dout;

    reg  [7:0]  pal8_byte;
    reg  [7:0]  pal8_byte_w;
    reg         fetch_pending;
    reg         pending_tex_ignore_alpha;
    reg         pending_vq_comp;
    reg         pending_is_pal4;
    reg         pending_is_pal8;
    reg         pending_texture_en;
    reg         pending_offset_en;
    reg  [2:0]  pending_pix_fmt;
    reg  [1:0]  pending_shade_inst;
    reg  [2:0]  pending_pal8_sel;
    reg  [1:0]  pending_pix_sel;
    reg  [5:0]  pending_pal_selector;
    reg  [9:0]  pending_x_ps;
    reg  [9:0]  pending_y_ps;
    reg  [31:0] pending_base_argb;
    reg  [31:0] pending_offs_argb;
    reg         pending_trace;

    wire pending_capture_en = fetch_pending && tex_data_ready;
    wire direct_capture_en  = tex_addr_valid && (!texture_en_r || tex_data_ready);
    wire capture_en = pending_capture_en || direct_capture_en;

assign pipeline_busy = tex_addr_valid || capture_en || stage_b2_valid || texel_valid;

    wire        cap_tex_ignore_alpha = pending_capture_en ? pending_tex_ignore_alpha : tex_ignore_alpha_w;
    wire        cap_vq_comp          = pending_capture_en ? pending_vq_comp          : vq_comp_r;
    wire        cap_is_pal4          = pending_capture_en ? pending_is_pal4          : is_pal4_r;
    wire        cap_is_pal8          = pending_capture_en ? pending_is_pal8          : is_pal8_r;
    wire        cap_texture_en       = pending_capture_en ? pending_texture_en       : texture_en_r;
    wire        cap_offset_en        = pending_capture_en ? pending_offset_en        : offset_en_r;
    wire [2:0]  cap_pix_fmt          = pending_capture_en ? pending_pix_fmt          : pix_fmt_r;
    wire [1:0]  cap_shade_inst       = pending_capture_en ? pending_shade_inst       : shade_inst_r;
    wire [2:0]  cap_pal8_sel         = pending_capture_en ? pending_pal8_sel         : pal8_sel_r;
    wire [1:0]  cap_pix_sel          = pending_capture_en ? pending_pix_sel          : pix_sel_r;
    wire [5:0]  cap_pal_selector     = pending_capture_en ? pending_pal_selector     : pal_selector_r;
    wire [9:0]  cap_x_ps             = pending_capture_en ? pending_x_ps             : x_ps_r;
    wire [9:0]  cap_y_ps             = pending_capture_en ? pending_y_ps             : y_ps_r;
    wire [31:0] cap_base_argb        = pending_capture_en ? pending_base_argb        : base_argb_r;
    wire [31:0] cap_offs_argb        = pending_capture_en ? pending_offs_argb        : offs_argb_r;
    wire        cap_trace            = pending_capture_en ? pending_trace            : trace_a;

    codebook_cache u_codebook_cache (
        .clock           ( clock           ),
        .reset_n         ( reset_n         ),

        .cache_clear     ( cb_cache_clear  ),
        .tag_in          ( prim_tag_r      ),
        .codebook_base   ( codebook_base   ),
        
        //.read_index      ( vq_index_r ),
        .read_index      ( capture_en ? pal8_byte_w : pal8_byte ),
        
        .cache_read      ( read_codebook   ),

        .tex_vram_valid  ( tex_vram_valid  ),
        .codebook_wait   ( codebook_wait   ),
        .ram_read_offset ( cb_word_index   ),
        .cache_din       ( vram_din        ),

        .cache_hit       ( cb_cache_hit    ),
        .cache_dout      ( cb_cache_dout   )
    );

    /* ============================================================
     * Stage B1: capture byte from VRAM (index for PAL/VQ)
     * ============================================================ */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            fetch_pending <= 1'b0;
            pal8_byte <= 8'd0;
            trace_a_lat <= 1'b0;
            x_ps_r_lat <= 10'd0;
            y_ps_r_lat <= 10'd0;
        end
        else if (pipe_flush) begin
            fetch_pending <= 1'b0;
            pal8_byte <= 8'd0;
            trace_a_lat <= 1'b0;
            x_ps_r_lat <= 10'd0;
            y_ps_r_lat <= 10'd0;
        end
        else begin
            if (pending_capture_en) begin
                fetch_pending <= 1'b0;
            end
            if (tex_addr_valid && texture_en_r && !tex_data_ready && !fetch_pending) begin
                fetch_pending <= 1'b1;
                pending_tex_ignore_alpha <= tex_ignore_alpha_w;
                pending_vq_comp <= vq_comp_r;
                pending_is_pal4 <= is_pal4_r;
                pending_is_pal8 <= is_pal8_r;
                pending_texture_en <= texture_en_r;
                pending_offset_en <= offset_en_r;
                pending_pix_fmt <= pix_fmt_r;
                pending_shade_inst <= shade_inst_r;
                pending_pal8_sel <= pal8_sel_r;
                pending_pix_sel <= pix_sel_r;
                pending_pal_selector <= pal_selector_r;
                pending_x_ps <= x_ps_r;
                pending_y_ps <= y_ps_r;
                pending_base_argb <= base_argb_r;
                pending_offs_argb <= offs_argb_r;
                pending_trace <= trace_a;
            end
            if (capture_en) begin
                pal8_byte <= pal8_byte_w;
                trace_a_lat <= cap_trace;
                x_ps_r_lat <= cap_x_ps;
                y_ps_r_lat <= cap_y_ps;
            end
        end
    end

    /* ============================================================
     * Stage B2: register codebook / VRAM data (aligns CB latency)
     * ============================================================ */
    wire [63:0] cb_or_direct = cap_vq_comp ? cb_cache_dout : vram_din;
    reg  [63:0] cb_or_direct_r;

    /* ============================================================
     * Palette address generation + RAM (1-cycle latency)
     * ============================================================ */
    wire [7:0] pal8_byte_sel =
        (pix_sel_lat == 2'd0) ? cb_or_direct_r[ 7: 0] :
        (pix_sel_lat == 2'd1) ? cb_or_direct_r[15: 8] :
        (pix_sel_lat == 2'd2) ? cb_or_direct_r[23:16] :
                                cb_or_direct_r[31:24];
    
    wire [9:0] pal_addr_next = is_pal4_lat ? { pal_selector_lat, pix_sel_lat[0] ? pal8_byte_sel[7:4] : pal8_byte_sel[3:0] }
										   : { pal_selector_lat[5:4], pal8_byte_sel };

    // 1024 × 32-bit palette RAM
    reg [31:0] pal_ram [0:1023];
	reg [31:0] pal_raw;
    always @(posedge clock) begin
        // SH4 palette access...
		if (pal_wr) pal_ram[pal_addr] <= pal_din;
        pal_dout <= pal_ram[pal_addr];

        // Texturing palette access...
		pal_raw  <= pal_ram[pal_addr_next];
	end

    /* ============================================================
     * Stage B3: final texel extraction (registered)
     * ============================================================ */
    reg stage_b2_valid;
    reg trace_a_lat;
    reg [9:0] x_ps_r_lat;
    reg [9:0] y_ps_r_lat;
	
	//reg [7:0] vq_index_r;
    reg [5:0] pal_selector_lat;
    reg [1:0] pix_sel_lat;
    reg       tex_ignore_alpha_lat;
    reg       texture_en_lat;
    reg       offset_en_lat;
    reg [2:0] pix_fmt_lat;
    reg [1:0] shade_inst_lat;
    reg [31:0] base_argb_lat;
    reg [31:0] offs_argb_lat;
    reg       vq_comp_lat;
    reg       is_pal4_lat;
    reg       is_pal8_lat;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            //pix16_r       <= 16'd0;
            //vq_index_r <= 8'd0;
            stage_b2_valid <= 1'b0;
            pal_selector_lat <= 6'd0;
            pix_sel_lat <= 2'd0;
            tex_ignore_alpha_lat <= 1'b0;
            texture_en_lat <= 1'b0;
            offset_en_lat <= 1'b0;
            pix_fmt_lat <= 3'd0;
            shade_inst_lat <= 2'd0;
            base_argb_lat <= 32'd0;
            offs_argb_lat <= 32'd0;
            vq_comp_lat <= 1'b0;
            is_pal4_lat <= 1'b0;
            is_pal8_lat <= 1'b0;
            cb_or_direct_r <= 64'd0;
        end
        else if (pipe_flush) begin
            //pix16_r       <= 16'd0;
            //vq_index_r <= 8'd0;
            stage_b2_valid <= 1'b0;
            pal_selector_lat <= 6'd0;
            pix_sel_lat <= 2'd0;
            tex_ignore_alpha_lat <= 1'b0;
            texture_en_lat <= 1'b0;
            offset_en_lat <= 1'b0;
            pix_fmt_lat <= 3'd0;
            shade_inst_lat <= 2'd0;
            base_argb_lat <= 32'd0;
            offs_argb_lat <= 32'd0;
            vq_comp_lat <= 1'b0;
            is_pal4_lat <= 1'b0;
            is_pal8_lat <= 1'b0;
            cb_or_direct_r <= 64'd0;
        end
        else begin
            stage_b2_valid <= capture_en;
							 
            //if (tex_addr_valid && tex_vram_valid) vq_index_r <= pal8_byte;
            if (capture_en) begin
                cb_or_direct_r <= cb_or_direct;
                pal_selector_lat <= cap_pal_selector;
                pix_sel_lat <= cap_pix_sel;
                tex_ignore_alpha_lat <= cap_tex_ignore_alpha;
                texture_en_lat <= cap_texture_en;
                offset_en_lat <= cap_offset_en;
                pix_fmt_lat <= cap_pix_fmt;
                shade_inst_lat <= cap_shade_inst;
                base_argb_lat <= cap_base_argb;
                offs_argb_lat <= cap_offs_argb;
                vq_comp_lat <= cap_vq_comp;
                is_pal4_lat <= cap_is_pal4;
                is_pal8_lat <= cap_is_pal8;
            end
        end
    end

reg [15:0] pix16_next;
always @(*) begin
    pal8_byte_w = 8'd0;
    pix16_next = 16'd0;

    case (cap_pal8_sel)
        3'd0: pal8_byte_w = vram_din[ 7: 0];
        3'd1: pal8_byte_w = vram_din[15: 8];
        3'd2: pal8_byte_w = vram_din[23:16];
        3'd3: pal8_byte_w = vram_din[31:24];
        3'd4: pal8_byte_w = vram_din[39:32];
        3'd5: pal8_byte_w = vram_din[47:40];
        3'd6: pal8_byte_w = vram_din[55:48];
        3'd7: pal8_byte_w = vram_din[63:56];
    endcase

    if (is_pal4_lat || is_pal8_lat) begin
        pix16_next = pal_raw[15:0];	// No data in [31:16] in the PVR regs dump, only in the lower 16-bits.
    end								// So probably just the way I'm "incorrectly" dumping the palette stuff in reicast-hacked atm. ElectronAsh.
    else if (vq_comp_lat) begin
        case (pix_sel_lat)
            2'd0: pix16_next = cb_cache_dout[15: 0];
            2'd1: pix16_next = cb_cache_dout[31:16];
            2'd2: pix16_next = cb_cache_dout[47:32];
            2'd3: pix16_next = cb_cache_dout[63:48];
        endcase
    end
    else begin
        case (pix_sel_lat)
            2'd0: pix16_next = cb_or_direct_r[15: 0];
            2'd1: pix16_next = cb_or_direct_r[31:16];
            2'd2: pix16_next = cb_or_direct_r[47:32];
            2'd3: pix16_next = cb_or_direct_r[63:48];
        endcase
    end
end

    /* ============================================================
     * Coordinate alignment + final valid
     * ============================================================ */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            texel_valid <= 1'b0;
            pix16_r     <= 16'd0;
            x_ps_texel  <= 10'd0;
            y_ps_texel  <= 10'd0;
            tex_ignore_alpha_r <= 1'b0;
            texture_en_texel <= 1'b0;
            offset_en_texel <= 1'b0;
            pix_fmt_texel <= 3'd0;
            shade_inst_texel <= 2'd0;
            base_argb_texel <= 32'd0;
            offs_argb_texel <= 32'd0;
            trace_b     <= 1'b0;
        end
        else if (pipe_flush) begin
            texel_valid <= 1'b0;
            pix16_r     <= 16'd0;
            x_ps_texel  <= 10'd0;
            y_ps_texel  <= 10'd0;
            tex_ignore_alpha_r <= 1'b0;
            texture_en_texel <= 1'b0;
            offset_en_texel <= 1'b0;
            pix_fmt_texel <= 3'd0;
            shade_inst_texel <= 2'd0;
            base_argb_texel <= 32'd0;
            offs_argb_texel <= 32'd0;
            trace_b     <= 1'b0;
        end
        else begin
            texel_valid <= stage_b2_valid;
            trace_b     <= stage_b2_valid && trace_a_lat;
            if (stage_b2_valid) begin
                pix16_r <= pix16_next;
                x_ps_texel <= x_ps_r_lat;
                y_ps_texel <= y_ps_r_lat;
                tex_ignore_alpha_r <= tex_ignore_alpha_lat;
                texture_en_texel <= texture_en_lat;
                offset_en_texel <= offset_en_lat;
                pix_fmt_texel <= pix_fmt_lat;
                shade_inst_texel <= shade_inst_lat;
                base_argb_texel <= base_argb_lat;
                offs_argb_texel <= offs_argb_lat;
            end
        end
    end

endmodule
