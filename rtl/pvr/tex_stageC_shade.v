`timescale 1ns / 1ps
`default_nettype none

module tex_stageC_shade (
    input  wire        clock,
    input  wire        reset_n,
	input  wire        pipe_flush,

	input [1:0] PAL_RAM_CTRL,	// From PAL_RAM_CTRL[1:0].

    /* ------------------------------------------------------------
     * From Stage B
     * ------------------------------------------------------------ */
     input wire        tex_ignore_alpha,
    input  wire        texel_valid,		// texel ready
    input  wire [15:0] pix16_r,			// 16-bit texel
    input  wire [2:0]  pix_fmt_r,		// pixel format
    input  wire [1:0]  shade_inst_r,	// shading instruction
    input  wire        texture_en_r,	// texture enable
    input  wire        offset_en_r,		// offset colour enable

    /* ------------------------------------------------------------
     * Shading inputs
     * ------------------------------------------------------------ */
    input  wire [31:0] base_argb,		// base colour (flat / gouraud)
    input  wire [31:0] offs_argb,		// offset colour

    /* ------------------------------------------------------------
     * Pixel coordinates
     * ------------------------------------------------------------ */
    input  wire [9:0]  x_ps_in,
    input  wire [9:0]  y_ps_in,
	input  wire        trace_b,
    input  wire [31:0] dbg_cycle,

    /* ------------------------------------------------------------
     * Outputs
     * ------------------------------------------------------------ */
    output reg         pix_valid,		// final pixel valid
    output reg  [31:0] final_argb,		// final ARGB8888
    output reg  [9:0]  x_ps_out,
    output reg  [9:0]  y_ps_out,
	output reg         trace_c
);

    /* ============================================================
     * Expand 16-bit texel → ARGB8888
     * ============================================================ */
    reg [31:0] texel_argb;

    always @(*) begin
            case (col_decode_sel)
			0: texel_argb = { {8{pix16_r[15]}},    pix16_r[14:10],pix16_r[14:12], pix16_r[09:05],pix16_r[09:07], pix16_r[04:00],pix16_r[04:02] };		// ARGB 1555
			1: texel_argb = {              8'hff,    pix16_r[15:11],pix16_r[15:13], pix16_r[10:05],pix16_r[10:09], pix16_r[04:00],pix16_r[04:02] };	//  RGB 565
			2: texel_argb = { {2{pix16_r[15:12]}}, {2{pix16_r[11:08]}},             {2{pix16_r[07:04]}},             {2{pix16_r[03:00]}} };			// ARGB 4444
			3: texel_argb = pix16_r;			// TODO. YUV422 (32-bit Y8 U8 Y8 V8).
			4: texel_argb = pix16_r;			// TODO. Bump Map (16-bit S8 R8).
			//5: texel_argb <= pal_final;		// PAL4 or PAL8 can be ARGB1555, RGB565, ARGB4444, or even ARGB8888.
			//6: texel_argb <= pal_final;		// Palette format read from PAL_RAM_CTRL[1:0].
			7: texel_argb = { {8{pix16_r[15]}},    pix16_r[14:10],pix16_r[14:12], pix16_r[09:05],pix16_r[09:07], pix16_r[04:00],pix16_r[04:02] };	// Rsvd. (considered ARGB 1555)
			default: texel_argb = pix16_r;	// Just to show anything at all, if some of the above cases are disabled. ElectronAsh.
			endcase
    end

    wire [2:0] col_decode_sel = (pix_fmt_r==4 || pix_fmt_r==5) ? PAL_RAM_CTRL[1:0] : pix_fmt_r;

    /* ============================================================
     * Channel extraction
     * ============================================================ */
    wire [7:0] tex_a  = tex_ignore_alpha ? 8'hff : texel_argb[31:24];
    wire [7:0] tex_r  = texel_argb[23:16];
    wire [7:0] tex_g  = texel_argb[15: 8];
    wire [7:0] tex_b  = texel_argb[ 7: 0];

    wire [7:0] base_a = base_argb[31:24];
    wire [7:0] base_r = base_argb[23:16];
    wire [7:0] base_g = base_argb[15: 8];
    wire [7:0] base_b = base_argb[ 7: 0];

    /* ============================================================
     * Multiply terms
     * ============================================================ */
    wire [15:0] a_tex_mult_base = base_a * tex_a;
    wire [15:0] r_tex_mult_base = base_r * tex_r;
    wire [15:0] g_tex_mult_base = base_g * tex_g;
    wire [15:0] b_tex_mult_base = base_b * tex_b;

    wire [7:0] inv_alpha = 8'd255 - tex_a;

    /* ============================================================
     * Shade instruction evaluation
     * ============================================================ */
    reg [7:0] blend_a, blend_r, blend_g, blend_b;

    always @(*) begin
            case (shade_inst_r)
                2'd0: begin // Decal
                    blend_a = tex_a;
                    blend_r = tex_r;
                    blend_g = tex_g;
                    blend_b = tex_b;
                end

                2'd1: begin // Modulate
                    blend_a = tex_a;
                    blend_r = r_tex_mult_base[15:8];
                    blend_g = g_tex_mult_base[15:8];
                    blend_b = b_tex_mult_base[15:8];
                end

                2'd2: begin // Decal Alpha
                    blend_a = base_a;
                    blend_r = ((tex_r * tex_a) + (base_r * inv_alpha)) /256; // >> 8;
                    blend_g = ((tex_g * tex_a) + (base_g * inv_alpha)) /256; // >> 8;
                    blend_b = ((tex_b * tex_a) + (base_b * inv_alpha)) /256; // >> 8;
                end

                2'd3: begin // Modulate Alpha
                    blend_a = a_tex_mult_base[15:8];
                    blend_r = r_tex_mult_base[15:8];
                    blend_g = g_tex_mult_base[15:8];
                    blend_b = b_tex_mult_base[15:8];
                end
            endcase
    end

    /* ============================================================
     * Offset colour + clamp
     * ============================================================ */
    wire [8:0] add_a = blend_a + offs_argb[31:24];
    wire [8:0] add_r = blend_r + offs_argb[23:16];
    wire [8:0] add_g = blend_g + offs_argb[15: 8];
    wire [8:0] add_b = blend_b + offs_argb[ 7: 0];

    wire [31:0] blend_offs_argb =
        offset_en_r
            ? { add_a[8] ? 8'hFF : add_a[7:0],
                add_r[8] ? 8'hFF : add_r[7:0],
                add_g[8] ? 8'hFF : add_g[7:0],
                add_b[8] ? 8'hFF : add_b[7:0] }
            : { blend_a, blend_r, blend_g, blend_b };

    /* ============================================================
     * Final output bundle
     * ============================================================ */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            pix_valid  <= 1'b0;
            final_argb <= 32'd0;
            x_ps_out   <= 10'd0;
            y_ps_out   <= 10'd0;
            trace_c    <= 1'b0;
        end
        else if (pipe_flush) begin
            pix_valid  <= 1'b0;
            final_argb <= 32'd0;
            x_ps_out   <= 10'd0;
            y_ps_out   <= 10'd0;
            trace_c    <= 1'b0;
        end
        else begin
            pix_valid  <= texel_valid;
            final_argb <= texture_en_r ? blend_offs_argb : base_argb;	// Textured or flat-shaded.
            x_ps_out   <= x_ps_in;
            y_ps_out   <= y_ps_in;
            trace_c    <= trace_b;
        end
    end

endmodule
