`timescale 1ns / 1ps
`default_nettype none

// hsr_core: Hidden Surface Removal engine.
//
// Drives the per-row scan loop for one triangle, performing in-triangle
// testing (inTri_calc), Z interpolation (accumulator-based, 1 cycle/row),
// depth compare and tag/Z-buffer writes (z_buff x2).  Also owns the z_buff
// clear path.
//
// Handshake with isp_parser:
//   isp_parser asserts hsr_start for exactly one clock when state 50 is
//   entered (or re-entered for quad-second-half).  hsr_core pulses hsr_done
//   for one clock when the last pending span has been committed.
//
// Pass-through outputs (latched inside hsr_core, read by isp_parser after
// hsr_done):
//   any_tags_written, tag_row_occupied_0/1, tile_z_min/max, z_out_0/1,
//   prim_tag_out_0/1, z_clear_busy.

module hsr_core #(
    parameter [7:0] FRAC_BITS            = 8'd12,
    parameter [7:0] Z_FRAC_BITS          = 8'd17,
    parameter [7:0] FRAC_DIFF            = Z_FRAC_BITS - FRAC_BITS,
    parameter       PIXEL_CENTER_SAMPLE  = 1'b1,
    parameter       ENABLE_DEPTH_COMPARE = 1'b1,
    parameter       INTRI_PIXELS_PER_CYCLE = 32
) (
    input  wire        clock,
    input  wire        reset_n,

    // ── Handshake ────────────────────────────────────────────────────────────
    input  wire        hsr_start,        // pulse: begin scan for this triangle
    output reg         hsr_done,         // pulse: all spans flushed

    // ── Triangle geometry (from isp_parser) ──────────────────────────────────
    input  wire signed [47:0] FX1_FIXED_R, FX2_FIXED_R, FX3_FIXED_R, FX4_FIXED_R,
    input  wire signed [47:0] FY1_FIXED_R, FY2_FIXED_R, FY3_FIXED_R, FY4_FIXED_R,
    input  wire        is_quad,           // inTri_calc: treat as quad

    // ── Scan-range (tile-relative rows) ──────────────────────────────────────
    input  wire [10:0] tilex_start,       // x_ps initial value (tile left edge)
    input  wire [10:0] tiley_start,       // y_ps initial value base
    input  wire [4:0]  hsr_start_row,     // first row to scan
    input  wire [4:0]  hsr_end_row,       // last row to scan (inclusive)

    // ── Z plane coefficients (ready after interp pipeline) ───────────────────
    input  wire        z_params_hsr_ready,
    input  wire signed [47:0] FDDX_Z,
    input  wire signed [47:0] FDDY_Z,
    input  wire signed [47:0] tile_start_z,  // Z at absolute pixel (0,0): Z0 - FX1*FDDX - FY1*FDDY

    // ── Depth compare / write control ────────────────────────────────────────
    input  wire [2:0]  depth_comp,
    input  wire        z_write_disable,
    input  wire        render_bg,

    // ── z_buff bank select ───────────────────────────────────────────────────
    input  wire        isp_z_bank,        // which bank this triangle writes to
    input  wire [11:0] prim_tag,          // tag written into z_buff for this tri

    // ── z_buff clear inputs ───────────────────────────────────────────────────
    input  wire        clear_z_bank_0,
    input  wire        clear_z_bank_1,
    input  wire        clear_tags_only_bank_0,
    input  wire        clear_tags_only_bank_1,

    // ── tag_row_occupied clear pulses (from isp_parser tile boundaries) ──────
    input  wire        clear_tag_row_occ_0,  // 1-cycle pulse: zero tag_row_occupied_0
    input  wire        clear_tag_row_occ_1,  // 1-cycle pulse: zero tag_row_occupied_1

    // ── TSP/RLE read-port mux (z_buff col_sel/row_sel when TSP or RLE busy) ──
    input  wire        tsp_busy,
    input  wire        tsp_z_bank,
    input  wire [4:0]  tsp_x_ps,
    input  wire [4:0]  tsp_y_ps,
    input  wire        rle_busy,
    input  wire [4:0]  rle_col_sel,
    input  wire [4:0]  rle_row_sel,

    // ── Outputs back to isp_parser ────────────────────────────────────────────
    output reg         any_tags_written,
    output reg [31:0]  tag_row_occupied_0,
    output reg [31:0]  tag_row_occupied_1,
    output reg signed [47:0] tile_z_min,
    output reg signed [47:0] tile_z_max,

    output wire        z_clear_busy,      // either bank clearing (stalls state machine)
    output wire        z_clear_busy_0,    // bank 0 clearing (for isp_z_clear_busy mux)
    output wire        z_clear_busy_1,    // bank 1 clearing (for clear_z_target_busy mux)
    output wire [47:0] z_out_0,
    output wire [47:0] z_out_1,
    output wire [11:0] prim_tag_out_0,
    output wire [11:0] prim_tag_out_1
);

localparam signed [47:0] Z_MAX_INIT =  48'sh7fffffffffff;
localparam signed [47:0] Z_MIN_INIT = -48'sh800000000000;

// ─────────────────────────────────────────────────────────────────────────────
// Internal scan coordinates
// ─────────────────────────────────────────────────────────────────────────────
reg [10:0] x_ps;
reg [10:0] y_ps;
reg [1:0]  inTri_pixel_group;
reg        zpipe_valid;
reg        zpipe_flush;
reg [3:0]  z_span_pending;

// ─────────────────────────────────────────────────────────────────────────────
// inTri_calc: combinatorial triangle coverage test
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] inTri;
inTri_calc #(
    .PIXEL_CENTER_SAMPLE  (PIXEL_CENTER_SAMPLE),
    .FRAC_BITS            (FRAC_BITS),
    .Z_FRAC_BITS          (Z_FRAC_BITS),
    .INTRI_PIXELS_PER_CYCLE(INTRI_PIXELS_PER_CYCLE)
) inTri_calc_inst (
    .FX1_FIXED( FX1_FIXED_R ), .FX2_FIXED( FX2_FIXED_R ),
    .FX3_FIXED( FX3_FIXED_R ), .FX4_FIXED( FX4_FIXED_R ),
    .FY1_FIXED( FY1_FIXED_R ), .FY2_FIXED( FY2_FIXED_R ),
    .FY3_FIXED( FY3_FIXED_R ), .FY4_FIXED( FY4_FIXED_R ),
    .x_ps        ( x_ps ),
    .y_ps        ( y_ps ),
    .pixel_group ( inTri_pixel_group ),
    .is_quad     ( is_quad ),
    .inTri       ( inTri )
);

// ─────────────────────────────────────────────────────────────────────────────
// Z accumulator: replaces z_span_32 pipeline with a running row_base register.
//
// tile_start_z is Z at the tile corner (tilex_start, tiley_start).
// On z_params_hsr_ready, compute the initial row base for y=hsr_start_row:
//   row_base = tile_start_z + (y_ps - tiley_start)*FDDY_Z
//            = tile_start_z + hsr_start_row*FDDY_Z
// x_ps == tilex_start at this point, so the x term is zero.
// Each subsequent dispatch cycle: row_base += FDDY_Z (pure adder, no multiplier).
//
// IP_Z[c] = row_base + c*FDDX_Z  is computed combinatorially each dispatch cycle.
// ─────────────────────────────────────────────────────────────────────────────

// row offset = y_ps - tiley_start = hsr_start_row (5-bit, 0..31)
wire signed [6:0]  z_init_row_off = $signed({1'b0, y_ps[4:0]});
wire signed [63:0] z_init_y_mul   = z_init_row_off * $signed(FDDY_Z[39:0]);
wire signed [47:0] z_init_row_base = tile_start_z + z_init_y_mul;

// row_base: stable from one cycle after z_params_hsr_ready until hsr_done.
reg signed [47:0] row_base;
reg               z_params_rdy_d1;   // 1-cycle delayed: spans fire when this is 1
reg               z_base_init_done;  // prevents re-init if z_params_hsr_ready stays high

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        row_base         <= 48'sd0;
        z_params_rdy_d1  <= 1'b0;
        z_base_init_done <= 1'b0;
    end else begin
        z_params_rdy_d1 <= 1'b0;
        if (hsr_start) begin
            // New triangle: allow re-init on next z_params_hsr_ready.
            z_base_init_done <= 1'b0;
        end else if (z_params_hsr_ready && !z_base_init_done && !zpipe_flush) begin
            // First fire after z_params_hsr_ready: latch initial row base.
            row_base         <= z_init_row_base;
            z_params_rdy_d1  <= 1'b1;
            z_base_init_done <= 1'b1;
        end else if (z_params_rdy_d1 && !z_clear_busy && !zpipe_flush) begin
            // Steady-state: advance row_base by one row each dispatch cycle.
            row_base        <= row_base + {{8{FDDY_Z[39]}}, FDDY_Z[39:0]};
            z_params_rdy_d1 <= 1'b1;
        end else if (z_base_init_done && !z_params_rdy_d1 && !z_clear_busy && !zpipe_flush) begin
            // Resume after z_clear_busy stall: re-arm without re-initialising.
            z_params_rdy_d1 <= 1'b1;
        end
    end
end

// Dispatch signal: fires once per row, 1-cycle after z_params_hsr_ready.
wire z_span_start = z_params_rdy_d1 && !z_clear_busy && !zpipe_flush;

// Combinatorial 32-column Z values for current row.
wire signed [47:0] IP_Z_base0  = row_base;
wire signed [47:0] IP_Z_base8  = row_base + ($signed(FDDX_Z[39:0]) <<< 3);
wire signed [47:0] IP_Z_base16 = row_base + ($signed(FDDX_Z[39:0]) <<< 4);
wire signed [47:0] IP_Z_base24 = row_base + ($signed(FDDX_Z[39:0]) <<< 4) + ($signed(FDDX_Z[39:0]) <<< 3);
wire signed [47:0] IP_Z_row [0:31];
assign IP_Z_row[0]  = IP_Z_base0;
assign IP_Z_row[1]  = IP_Z_base0  + $signed(FDDX_Z[39:0]);
assign IP_Z_row[2]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[3]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[4]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 2);
assign IP_Z_row[5]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 2) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[6]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[7]  = IP_Z_base0  + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[8]  = IP_Z_base8;
assign IP_Z_row[9]  = IP_Z_base8  + $signed(FDDX_Z[39:0]);
assign IP_Z_row[10] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[11] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[12] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 2);
assign IP_Z_row[13] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 2) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[14] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[15] = IP_Z_base8  + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[16] = IP_Z_base16;
assign IP_Z_row[17] = IP_Z_base16 + $signed(FDDX_Z[39:0]);
assign IP_Z_row[18] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[19] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[20] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 2);
assign IP_Z_row[21] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 2) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[22] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[23] = IP_Z_base16 + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[24] = IP_Z_base24;
assign IP_Z_row[25] = IP_Z_base24 + $signed(FDDX_Z[39:0]);
assign IP_Z_row[26] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[27] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[28] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 2);
assign IP_Z_row[29] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 2) + $signed(FDDX_Z[39:0]);
assign IP_Z_row[30] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1);
assign IP_Z_row[31] = IP_Z_base24 + ($signed(FDDX_Z[39:0]) <<< 2) + ($signed(FDDX_Z[39:0]) <<< 1) + $signed(FDDX_Z[39:0]);

// inTri passed directly to z_buff; z_buff's internal inTri_d provides the 1-cycle
// write delay automatically (same mechanism as before, no explicit delay chain needed).
wire [31:0] z_inTri_to_zbuff = z_span_start ? (render_bg ? 32'hffffffff : inTri) : 32'd0;

// z_span_valid: 1-cycle write-completion pulse (z_buff write fires the following cycle).
wire z_span_valid = z_span_start;

// ─────────────────────────────────────────────────────────────────────────────
// z_span write pipeline: register IP_Z and inTri for use in tile_z_min/max
// tracking.  z_buff's own trig_z_row_write_d / inTri_d / row_sel_d registers
// handle the 1-cycle write delay internally; IP_Z_R here is only for the
// any_tags_written / tile_z_min / tile_z_max logic below.
// ─────────────────────────────────────────────────────────────────────────────
reg        z_span_write_valid;
reg signed [15:0] z_span_y_write;
reg [31:0] z_inTri_write;
reg signed [47:0] IP_Z_R [0:31];

integer ip_z_i;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        z_span_write_valid <= 1'b0;
        z_span_y_write     <= 16'sd0;
        z_inTri_write      <= 32'd0;
        for (ip_z_i = 0; ip_z_i < 32; ip_z_i = ip_z_i + 1)
            IP_Z_R[ip_z_i] <= 48'sd0;
    end else begin
        z_span_write_valid <= z_span_valid;
        z_span_y_write     <= $signed({5'd0, y_ps});
        z_inTri_write      <= z_inTri_to_zbuff;
        for (ip_z_i = 0; ip_z_i < 32; ip_z_i = ip_z_i + 1)
            IP_Z_R[ip_z_i] <= IP_Z_row[ip_z_i];
    end
end

// ─────────────────────────────────────────────────────────────────────────────
// z_buff read/write row address.
// z_mem_dual is a synchronous RAM: addr_rd=R at dispatch cycle N produces q=z_mem[R]
// at cycle N+1.  z_buff's row_sel_d (write addr) captures y_ps[4:0]=R at posedge N,
// so the write at N+1 correctly targets row R while depth_allow from q at N+1
// compares row R's stored Z against the registered IP_Z_R.
// ─────────────────────────────────────────────────────────────────────────────
wire [4:0] z_write_row_sel = y_ps[4:0];

// ─────────────────────────────────────────────────────────────────────────────
// z_buff instantiations (bank 0 and bank 1)
// ─────────────────────────────────────────────────────────────────────────────
// z_clear_busy_0 and z_clear_busy_1 are output ports driven by z_buff instances.
assign z_clear_busy = z_clear_busy_0 | z_clear_busy_1;

wire [31:0] depth_allow_0, depth_allow_1;
wire [31:0] depth_allow = isp_z_bank ? depth_allow_1 : depth_allow_0;

wire trig_z_row_write = z_span_start;

z_buff #(
    .ENABLE_DEPTH_COMPARE(ENABLE_DEPTH_COMPARE)
) z_buff_inst_0 (
    .clock   ( clock ),
    .reset_n ( reset_n ),
    .debug_bank( 1'b0 ),

    .clear_z       ( clear_z_bank_0 ),
    .clear_tags_only( clear_tags_only_bank_0 ),
    .z_clear_busy  ( z_clear_busy_0 ),

    .col_sel   ( rle_busy ? rle_col_sel : ((tsp_busy && !tsp_z_bank) ? tsp_x_ps : x_ps[4:0]) ),
    .row_sel   ( rle_busy ? rle_row_sel : ((tsp_busy && !tsp_z_bank) ? tsp_y_ps : z_write_row_sel) ),
    .row_sel_rd( rle_busy ? rle_row_sel : ((tsp_busy && !tsp_z_bank) ? tsp_y_ps : z_write_row_sel) ),

    .inTri             ( z_inTri_to_zbuff ),
    .trig_z_row_write  ( trig_z_row_write & !isp_z_bank ),
    .z_write_disable   ( z_write_disable & !isp_z_bank ),
    .depth_comp_in     ( depth_comp ),
    .tag_in            ( prim_tag ),
    .z_in_cols         ( IP_Z_R ),
    .z_out             ( z_out_0 ),
    .prim_tag_out      ( prim_tag_out_0 ),
    .depth_allow       ( depth_allow_0 )
);

z_buff #(
    .ENABLE_DEPTH_COMPARE(ENABLE_DEPTH_COMPARE)
) z_buff_inst_1 (
    .clock   ( clock ),
    .reset_n ( reset_n ),
    .debug_bank( 1'b1 ),

    .clear_z       ( clear_z_bank_1 ),
    .clear_tags_only( clear_tags_only_bank_1 ),
    .z_clear_busy  ( z_clear_busy_1 ),

    .col_sel   ( rle_busy ? rle_col_sel : ((tsp_busy && tsp_z_bank) ? tsp_x_ps : x_ps[4:0]) ),
    .row_sel   ( rle_busy ? rle_row_sel : ((tsp_busy && tsp_z_bank) ? tsp_y_ps : z_write_row_sel) ),
    .row_sel_rd( rle_busy ? rle_row_sel : ((tsp_busy && tsp_z_bank) ? tsp_y_ps : z_write_row_sel) ),

    .inTri             ( z_inTri_to_zbuff ),
    .trig_z_row_write  ( trig_z_row_write & isp_z_bank ),
    .z_write_disable   ( z_write_disable & isp_z_bank ),
    .depth_comp_in     ( depth_comp ),
    .tag_in            ( prim_tag ),
    .z_in_cols         ( IP_Z_R ),
    .z_out             ( z_out_1 ),
    .prim_tag_out      ( prim_tag_out_1 ),
    .depth_allow       ( depth_allow_1 )
);

// ─────────────────────────────────────────────────────────────────────────────
// z_span_pending: with 1-cycle latency, z_span_valid == z_span_start so the
// counter never exceeds 1 and stays at 0 during back-to-back spans.
// It only matters for the hsr_done drain: after zpipe_flush the last span's
// write-valid fires 1 cycle later (= z_span_write_valid).
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        z_span_pending <= 4'd0;
    end else begin
        // dispatch and complete always happen on the same cycle (1-cycle latency),
        // so the counter stays at 0 during steady-state. It briefly hits 1 only
        // on the final row when zpipe_flush stops new dispatches.
        case ({z_span_start, z_span_write_valid})
            2'b10:   z_span_pending <= z_span_pending + 4'd1;
            2'b01:   z_span_pending <= z_span_pending - 4'd1;
            default: ;
        endcase
    end
end

// ─────────────────────────────────────────────────────────────────────────────
// HSR row-scan state machine
// Replaces state 50 in isp_parser.
// ─────────────────────────────────────────────────────────────────────────────
integer z_i_inner;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        x_ps              <= 11'd0;
        y_ps              <= 11'd0;
        inTri_pixel_group <= 2'd0;
        zpipe_valid       <= 1'b0;
        zpipe_flush       <= 1'b0;
        any_tags_written  <= 1'b0;
        tag_row_occupied_0 <= 32'd0;
        tag_row_occupied_1 <= 32'd0;
        tile_z_min        <= Z_MAX_INIT;
        tile_z_max        <= Z_MIN_INIT;
        hsr_done          <= 1'b0;
    end else begin
        hsr_done <= 1'b0;

        // ── tag_row_occupied clears (tile boundary, driven by isp_parser) ──────
        if (clear_tag_row_occ_0) tag_row_occupied_0 <= 32'd0;
        if (clear_tag_row_occ_1) tag_row_occupied_1 <= 32'd0;

        // ── Start: initialise scan state ─────────────────────────────────────
        if (hsr_start) begin
            x_ps              <= tilex_start;
            y_ps              <= tiley_start + {6'd0, hsr_start_row};
            inTri_pixel_group <= 2'd0;
            zpipe_valid       <= 1'b0;
            zpipe_flush       <= 1'b0;
            any_tags_written  <= 1'b0;
            tile_z_min        <= Z_MAX_INIT;
            tile_z_max        <= Z_MIN_INIT;
        end

        // ── Active scan (equivalent to isp_state 50) ─────────────────────────
        if (!hsr_start && !z_clear_busy) begin

            // Handle the write-back result (1 cycle after dispatch, matched by z_span_write_valid).
            if (z_span_write_valid) begin
                if (z_inTri_write != 32'd0) any_tags_written <= 1'b1;
                if ((z_inTri_write & (depth_allow | {32{render_bg}})) != 32'd0) begin
                    if (isp_z_bank) begin
                        tag_row_occupied_1[z_span_y_write[4:0]] <= 1'b1;
                        if (z_span_y_write[4:0] != 5'd0)
                            tag_row_occupied_1[z_span_y_write[4:0] - 5'd1] <= 1'b1;
                    end else begin
                        tag_row_occupied_0[z_span_y_write[4:0]] <= 1'b1;
                        if (z_span_y_write[4:0] != 5'd0)
                            tag_row_occupied_0[z_span_y_write[4:0] - 5'd1] <= 1'b1;
                    end
                end
                if (!z_write_disable) begin
                    for (z_i_inner = 0; z_i_inner < 32; z_i_inner = z_i_inner + 1) begin
                        if (z_inTri_write[z_i_inner] && depth_allow[z_i_inner]) begin
                            if (IP_Z_R[z_i_inner] < tile_z_min) tile_z_min <= IP_Z_R[z_i_inner];
                            if (IP_Z_R[z_i_inner] > tile_z_max) tile_z_max <= IP_Z_R[z_i_inner];
                        end
                    end
                end
            end

            // Advance the scan row on each actual dispatch (z_span_start).
            // y_ps is set to hsr_start_row on hsr_start; z_params_hsr_ready
            // initialises row_base without advancing y_ps, so the first dispatch
            // (z_params_rdy_d1) sees y_ps = hsr_start_row.
            if (z_span_start) begin
                zpipe_valid <= 1'b1;
                if (INTRI_PIXELS_PER_CYCLE <= 8 && inTri_pixel_group != 2'd3) begin
                    inTri_pixel_group <= inTri_pixel_group + 2'd1;
                end else begin
                    inTri_pixel_group <= 2'd0;
                    if (y_ps[4:0] >= hsr_end_row) begin
                        zpipe_flush <= 1'b1;
                    end else begin
                        y_ps[4:0] <= y_ps[4:0] + 5'd1;
                    end
                end
            end

            // Done: last span's write-complete fired and pipeline is empty.
            if (zpipe_flush && (z_span_pending == 4'd0) && !z_span_valid) begin
                hsr_done <= 1'b1;
            end
        end
    end
end

endmodule
