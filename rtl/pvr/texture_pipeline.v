`timescale 1ns / 1ps
`default_nettype none

module texture_pipeline (
    input  wire        clock,
    input  wire        reset_n,
	input  wire        pipe_flush,

	input [31:0] TEXT_CONTROL,	// From TEXT_CONTROL reg.
	
	input [1:0] PAL_RAM_CTRL,	// From PAL_RAM_CTRL[1:0].
	input [15:0] pal_addr,
	input [31:0] pal_din,
	input pal_rd,
	input pal_wr,
	output [31:0] pal_dout,
	input [31:0] dbg_cycle,
	
	input wire read_codebook,
	output wire codebook_wait,
	
	input wire cb_cache_clear,
	input wire [11:0] prim_tag,
	output wire cb_cache_hit,
	
	output wire stall_tex_fetch,
	output wire stall_codebook,

    // Rasterizer inputs
    input  wire        tsp_valid,
    input  wire [9:0]  ui,
    input  wire [9:0]  vi,
    input  wire [9:0]  x_ps,
    input  wire [9:0]  y_ps,

    // Control words
    input  wire [31:0] isp_inst,
    input  wire [31:0] tsp_inst,
    input  wire [31:0] tcw_word,

    // VRAM interface
    input  wire        vram_wait,
    input  wire        tex_vram_valid,
    input  wire        tex_data_ready,
    input  wire [63:0] vram_din,

    // Shading inputs
    input  wire [31:0] base_argb,
    input  wire [31:0] offs_argb,

    // Outputs
    output reg [20:0] vram_word_addr,
    output wire        pix_valid,
    output wire [31:0] final_argb,
    output wire [9:0]  x_ps_out,
    output wire [9:0]  y_ps_out,
	output wire        trace_a,
	output wire        trace_b,
	output wire        trace_c,

    output wire        pipeline_busy,
    output wire        texel_valid
);


    /* ============================================================
     * Stage A → Stage B
     * ============================================================ */
    wire        tex_addr_valid;        // address / fetch request valid
    wire        tex_ignore_alpha_r;
	
    wire [2:0]  pix_fmt_r;             // texture pixel format
    wire [1:0]  shade_inst_r;           // shading instruction
    wire        texture_en_r;           // texture enable
    wire        offset_en_r;            // offset colour enable

    // --- NEW: texture format / selection ---
    wire        vq_comp_r;              // VQ compression enable
    wire        is_pal4_r;              // PAL4 texture
    wire        is_pal8_r;              // PAL8 texture

    wire [2:0]  pal8_sel_r;             // byte select within 64-bit word
    wire [1:0]  pix_sel_r;              // 16-bit word select
    wire [5:0]  pal_selector_r;         // palette bank selector

    // --- NEW: codebook ---
    wire [11:0] prim_tag_r;              // primitive / triangle tag
	
	wire [9:0] x_ps_r;
	wire [9:0] y_ps_r;
	wire [31:0] base_argb_r;
	wire [31:0] offs_argb_r;

    /* ============================================================
     * Stage A: texture address generation
     * ============================================================ */
    tex_stageA_addrgen  u_addrgen (
        .clock           ( clock           ),
        .reset_n         ( reset_n         ),
		.pipe_flush      ( pipe_flush      ),
        .vram_wait       ( vram_wait       ),

        .tsp_valid    ( tsp_valid    ),
        .ui           ( ui           ),
        .vi           ( vi           ),
        .x_ps         ( x_ps         ),
        .y_ps         ( y_ps         ),
        .base_argb    ( base_argb    ),
        .offs_argb    ( offs_argb    ),
		
		.prim_tag        ( prim_tag        ),

        .isp_inst        ( isp_inst        ),
        .tsp_inst        ( tsp_inst        ),
        .tcw_word        ( tcw_word        ),

        .tex_addr_valid  ( tex_addr_valid  ),
		
		.tex_base_word_addr( tex_base_word_addr ),	// output [20:0] 
		.texel_word_offs( texel_word_offs ),		// output [20:0] 

        .x_ps_r         ( x_ps_r         ),
        .y_ps_r         ( y_ps_r         ),
        .base_argb_r    ( base_argb_r    ),
        .offs_argb_r    ( offs_argb_r    ),
        .trace_a        ( trace_a        ),

        .tex_ignore_alpha_r ( tex_ignore_alpha_r ),

        .pix_fmt_r       ( pix_fmt_r       ),
        .shade_inst_r    ( shade_inst_r    ),
        .texture_en_r    ( texture_en_r    ),
        .offset_en_r     ( offset_en_r     ),

        // --- NEW outputs ---
        .vq_comp_r       ( vq_comp_r       ),
        .is_pal4_r       ( is_pal4_r       ),
        .is_pal8_r       ( is_pal8_r       ),
        .pal8_sel_r      ( pal8_sel_r      ),
        .pix_sel_r       ( pix_sel_r       ),
        .pal_selector_r  ( pal_selector_r  ),
        .prim_tag_r      ( prim_tag_r      )
    );

	
	wire [7:0] cb_word_index;

   /* ============================================================
     * Stage B → Stage C
     * ============================================================ */
    //wire        texel_valid;             // texel ready
    wire [15:0] pix16_r;                 // 16-bit texel
    wire [9:0]  x_ps_texel;
    wire [9:0]  y_ps_texel;

	wire [20:0] tex_base_word_addr;
	wire [20:0] texel_word_offs;

    wire tex_ignore_alpha_out;
    wire texture_en_texel;
    wire offset_en_texel;
    wire [2:0] pix_fmt_texel;
    wire [1:0] shade_inst_texel;
    wire [31:0] base_argb_texel;
    wire [31:0] offs_argb_texel;
    wire stage_b_busy;

    /* ============================================================
     * Stage B: VRAM / Codebook / Palette fetch
     * ============================================================ */
    tex_stageB_fetch  u_fetch (
        .clock           ( clock           ),
        .reset_n         ( reset_n         ),
		.pipe_flush      ( pipe_flush      ),

		.TEXT_CONTROL    ( TEXT_CONTROL    ),
		
		.pal_addr( pal_addr ),				// input [9:0]  pal_addr
		.pal_din( pal_din ),				// input [31:0]  pal_din
		.pal_wr( pal_wr ),					// input  pal_wr
		.pal_rd( pal_rd ),					// input  pal_rd
		.pal_dout( pal_dout ),				// output [31:0]  pal_dout
		
		.read_codebook   ( read_codebook ),
		.codebook_wait   ( codebook_wait ),
		.cb_word_index   ( cb_word_index ),
		.codebook_base   ( tex_base_word_addr ),
		
		.cb_cache_clear  ( cb_cache_clear ),
        .prim_tag_r      ( prim_tag_r     ),
		.cb_cache_hit    ( cb_cache_hit ),

		.stall_tex_fetch( stall_tex_fetch ),
		.stall_codebook( stall_codebook ),
		.pipeline_busy ( stage_b_busy ),

        .tex_addr_valid  ( tex_addr_valid ),

        .tex_ignore_alpha_w ( tex_ignore_alpha_r ),
        .tex_ignore_alpha_r ( tex_ignore_alpha_out ),

        .vq_comp_r       ( vq_comp_r       ),
        .is_pal4_r       ( is_pal4_r       ),
        .is_pal8_r       ( is_pal8_r       ),
        .texture_en_r    ( texture_en_r    ),
        .offset_en_r     ( offset_en_r     ),
        .pix_fmt_r       ( pix_fmt_r       ),
        .shade_inst_r    ( shade_inst_r    ),

        .pal8_sel_r      ( pal8_sel_r      ),
        .pix_sel_r       ( pix_sel_r       ),
        .pal_selector_r  ( pal_selector_r  ),

        .x_ps_r          ( x_ps_r          ),
        .y_ps_r          ( y_ps_r          ),
        .base_argb_r     ( base_argb_r     ),
        .offs_argb_r     ( offs_argb_r     ),
        .trace_a         ( trace_a         ),

        .tex_vram_valid  ( tex_vram_valid  ),
        .tex_data_ready  ( tex_data_ready  ),
        .vram_din        ( vram_din        ),

        .texel_valid     ( texel_valid     ),
        .pix16_r         ( pix16_r         ),
        .x_ps_texel      ( x_ps_texel      ),
        .y_ps_texel      ( y_ps_texel      ),
        .texture_en_texel( texture_en_texel),
        .offset_en_texel ( offset_en_texel ),
        .pix_fmt_texel   ( pix_fmt_texel   ),
        .shade_inst_texel( shade_inst_texel),
        .base_argb_texel ( base_argb_texel ),
        .offs_argb_texel ( offs_argb_texel ),
        .trace_b         ( trace_b         )
    );
	
	assign vram_word_addr = tex_base_word_addr + ((read_codebook || codebook_wait) ? cb_word_index : texel_word_offs);

    /* ============================================================
     * Stage C: texel expand + shade + offset
     * ============================================================ */
    wire        pix_valid_c;
    wire [31:0] final_argb_c;
    wire [9:0]  x_ps_out_c;
    wire [9:0]  y_ps_out_c;
    tex_stageC_shade  u_shade (
        .clock          ( clock          ),
        .reset_n        ( reset_n        ),
		.pipe_flush     ( pipe_flush     ),

		.PAL_RAM_CTRL( PAL_RAM_CTRL ),		// input from PAL_RAM_CTRL, bits [1:0].

        .tex_ignore_alpha( tex_ignore_alpha_out ),

        .texel_valid    ( texel_valid    ),
    	.pix16_r        ( pix16_r        ),
        .pix_fmt_r      ( pix_fmt_texel  ),
        .shade_inst_r   ( shade_inst_texel ),
        .texture_en_r   ( texture_en_texel ),
        .offset_en_r    ( offset_en_texel ),

        .base_argb      ( base_argb_texel ),
        .offs_argb      ( offs_argb_texel ),

        .x_ps_in        ( x_ps_texel     ),
        .y_ps_in        ( y_ps_texel     ),
        .trace_b        ( trace_b        ),

        .pix_valid      ( pix_valid_c    ),
        .final_argb     ( final_argb_c   ),
        .x_ps_out       ( x_ps_out_c     ),
        .y_ps_out       ( y_ps_out_c     ),
        .trace_c        ( trace_c        ),
		.dbg_cycle      ( dbg_cycle      )
    );

    // ------------------------------------------------------------
    // Direct outputs (no extra delay)
    // ------------------------------------------------------------
    assign pix_valid = pix_valid_c;
    assign final_argb = final_argb_c;
    assign x_ps_out = x_ps_out_c;
    assign y_ps_out = y_ps_out_c;
    assign pipeline_busy = tex_addr_valid || stage_b_busy || texel_valid || pix_valid_c;

endmodule
