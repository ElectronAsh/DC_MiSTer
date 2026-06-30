`timescale 1ns / 1ps
`default_nettype none

module vram_read_cache #(
    parameter TEX_COMBO_HIT = 1'b0,
    parameter CACHE_LINES   = 2,
    parameter CRITICAL_WORD_FIRST = 1'b0,
    parameter ALIGN_LINE_BASE = 1'b1,
    parameter NEXT_LINE_PREFETCH = 1'b0,
    parameter HIT_UNDER_MISS = 1'b0
) (
    input  wire        clock,
    input  wire        reset_n,

    input  wire        vram_rd,
    input  wire [21:0] vram_addr,   // BYTE address (32-bit word address, aligned). Bit 22 selects bank.

    output wire [63:0] vram_din,
    output reg         vram_wait,
    output wire        vram_valid,
    output reg         vram_req_ack,

    output wire        cache_hit,

    // Combinatorial peek: check if peek_addr is cached without issuing a request.
    input  wire [21:0] peek_addr,
    output wire        peek_hit,

    output reg  [28:0] DDRAM_ADDR,    // 64-bit WORD address
    output reg         DDRAM_RD,
    output reg  [7:0]  DDRAM_BURSTCNT,
    input  wire [63:0] DDRAM_DOUT,
    input  wire        DDRAM_DOUT_READY,
    input  wire        DDRAM_BUSY
);

    localparam LINE_WORDS = 8;
    localparam LINE_BITS  = $clog2(LINE_WORDS);
    localparam WAY_BITS   = $clog2(CACHE_LINES);
    localparam [31:0] LINE_WORD_MASK = LINE_WORDS - 1;

    reg [63:0] cache_line [0:CACHE_LINES-1][0:LINE_WORDS-1];
    reg [31:0] cache_base [0:CACHE_LINES-1];
    reg [CACHE_LINES-1:0] cache_valid;
    reg [WAY_BITS-1:0] replace_way;

    reg [63:0] prefetch_line [0:LINE_WORDS-1];
    reg [31:0] prefetch_cache_base;
    reg prefetch_cache_valid;

    wire [31:0] word_addr = {9'd0, vram_addr[21:2]};
    wire [31:0] line_base_addr = word_addr & ~LINE_WORD_MASK;
    wire [31:0] fill_base_addr = (CRITICAL_WORD_FIRST || !ALIGN_LINE_BASE) ? word_addr : line_base_addr;

    wire hot_hit = 1'b0;
    wire [63:0] hot_hit_data = 64'd0;

    reg hit_now;
    reg [WAY_BITS-1:0] hit_way;
    reg [LINE_BITS-1:0] hit_index;

    integer hit_i;
    always @(*) begin
        hit_now = 1'b0;
        hit_way = {WAY_BITS{1'b0}};
        hit_index = {LINE_BITS{1'b0}};
        for (hit_i = 0; hit_i < CACHE_LINES; hit_i = hit_i + 1) begin
            if (!hit_now && cache_valid[hit_i] &&
                (word_addr >= cache_base[hit_i]) &&
                (word_addr < (cache_base[hit_i] + LINE_WORDS))) begin
                hit_now = 1'b1;
                hit_way = hit_i;
                hit_index = word_addr - cache_base[hit_i];
            end
        end
    end

    reg prefetch_hit_now;
    reg [LINE_BITS-1:0] prefetch_hit_index;
    always @(*) begin
        prefetch_hit_now = prefetch_cache_valid &&
                           (word_addr >= prefetch_cache_base) &&
                           (word_addr < (prefetch_cache_base + LINE_WORDS));
        prefetch_hit_index = word_addr - prefetch_cache_base;
    end

    assign cache_hit = hit_now || hot_hit || prefetch_hit_now;

    // Peek: combinatorial hit check against an arbitrary address (no side effects).
    // peek_addr is a 32-bit WORD address (same format as cache_base / word_addr).
    wire [31:0] peek_word_addr = {10'd0, peek_addr[21:0]};
    reg peek_hit_now;
    integer peek_i;
    always @(*) begin
        peek_hit_now = 1'b0;
        for (peek_i = 0; peek_i < CACHE_LINES; peek_i = peek_i + 1) begin
            if (!peek_hit_now && cache_valid[peek_i] &&
                (peek_word_addr >= cache_base[peek_i]) &&
                (peek_word_addr < (cache_base[peek_i] + LINE_WORDS)))
                peek_hit_now = 1'b1;
        end
        if (!peek_hit_now && prefetch_cache_valid &&
            (peek_word_addr >= prefetch_cache_base) &&
            (peek_word_addr < (prefetch_cache_base + LINE_WORDS)))
            peek_hit_now = 1'b1;
    end
    assign peek_hit = peek_hit_now;

    // Optional combinational hit path for texture cache. Only assert it for a
    // new request; otherwise a changing address can masquerade as the response
    // to an older outstanding request and feed the texture pipe the wrong word.
    wire combo_hit = TEX_COMBO_HIT && vram_rd && !vram_rd_block &&
                     (hit_now || hot_hit || prefetch_hit_now) &&
                     !filling && !req_active && !pending && !read_pending && !hit_pending;
    wire hit_under_miss_now = HIT_UNDER_MISS && vram_rd && !vram_rd_block &&
                              (req_active || filling || read_pending) &&
                              !pending && !hit_pending &&
                              (hit_now || hot_hit || prefetch_hit_now);
    assign vram_din   = combo_hit ? (hot_hit ? hot_hit_data :
                                     (prefetch_hit_now ? prefetch_line[prefetch_hit_index] :
                                                         cache_line[hit_way][hit_index])) : vram_din_r;
    assign vram_valid = combo_hit ? 1'b1 : vram_valid_r;

    reg pending;
    reg [21:0] pending_byte_addr;
    reg pending_prefetch_ok;
    wire [31:0] pending_word_addr = {9'd0, pending_byte_addr[21:2]};
    wire [31:0] pending_line_base_addr = pending_word_addr & ~LINE_WORD_MASK;
    wire [31:0] pending_fill_base_addr = (CRITICAL_WORD_FIRST || !ALIGN_LINE_BASE) ? pending_word_addr : pending_line_base_addr;

    reg pending_hit;
    reg [WAY_BITS-1:0] pending_hit_way;
    reg [LINE_BITS-1:0] pending_hit_index;
    reg pending_prefetch_hit;
    reg [LINE_BITS-1:0] pending_prefetch_hit_index;
    integer pend_i;
    always @(*) begin
        pending_hit = 1'b0;
        pending_hit_way = {WAY_BITS{1'b0}};
        pending_hit_index = {LINE_BITS{1'b0}};
        pending_prefetch_hit = prefetch_cache_valid &&
                               (pending_word_addr >= prefetch_cache_base) &&
                               (pending_word_addr < (prefetch_cache_base + LINE_WORDS));
        pending_prefetch_hit_index = pending_word_addr - prefetch_cache_base;
        for (pend_i = 0; pend_i < CACHE_LINES; pend_i = pend_i + 1) begin
            if (!pending_hit && cache_valid[pend_i] &&
                (pending_word_addr >= cache_base[pend_i]) &&
                (pending_word_addr < (cache_base[pend_i] + LINE_WORDS))) begin
                pending_hit = 1'b1;
                pending_hit_way = pend_i;
                pending_hit_index = pending_word_addr - cache_base[pend_i];
            end
        end
    end

    reg prefetch_pending;
    reg [31:0] prefetch_base_addr;
    reg prefetch_line_hit;
    integer prefetch_i;
    always @(*) begin
        prefetch_line_hit = 1'b0;
        for (prefetch_i = 0; prefetch_i < CACHE_LINES; prefetch_i = prefetch_i + 1) begin
            if (!prefetch_line_hit && cache_valid[prefetch_i] &&
                (prefetch_base_addr >= cache_base[prefetch_i]) &&
                (prefetch_base_addr < (cache_base[prefetch_i] + LINE_WORDS))) begin
                prefetch_line_hit = 1'b1;
            end
        end
        if (!prefetch_line_hit && prefetch_cache_valid &&
            (prefetch_base_addr >= prefetch_cache_base) &&
            (prefetch_base_addr < (prefetch_cache_base + LINE_WORDS))) begin
            prefetch_line_hit = 1'b1;
        end
    end

    reg req_active;
    reg [31:0] req_word_addr;

    reg filling;
    reg fill_is_prefetch;
    reg fill_prefetch_ok;
    reg [31:0] prefetch_fill_base_addr;
    reg [WAY_BITS-1:0] fill_way;
    reg [LINE_BITS-1:0] fill_ptr;
    reg [LINE_WORDS-1:0] fill_valid;
    reg read_pending;

    wire req_fill_range = filling && req_active &&
                          (req_word_addr >= (fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way])) &&
                          (req_word_addr < ((fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way]) + LINE_WORDS));
    wire [LINE_BITS-1:0] req_fill_index = req_word_addr - (fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way]);
    wire early_hit_possible = req_fill_range && fill_valid[req_fill_index];

    wire pending_fill_range = filling && pending &&
                              (pending_word_addr >= (fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way])) &&
                              (pending_word_addr < ((fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way]) + LINE_WORDS));
    wire [LINE_BITS-1:0] pending_fill_index = pending_word_addr - (fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way]);
    wire pending_early_possible = pending_fill_range && fill_valid[pending_fill_index];

    reg hit_pending;
    reg hit_pending_prefetch;
    reg [WAY_BITS-1:0] hit_pending_way;
    reg [LINE_BITS-1:0] hit_pending_index;

    reg [63:0] vram_din_r;
    reg        vram_valid_r;
    reg        vram_rd_block;

`ifdef VERILATOR
    // Minimal locality stats.
    reg [31:0] hit_count;
    reg [31:0] line_hit_count;
    reg [31:0] hot_hit_count;
    reg [31:0] hot_evict_count;
    reg [31:0] miss_count;
    reg [31:0] delta_0;
    reg [31:0] delta_1;
    reg [31:0] delta_2_3;
    reg [31:0] delta_4_7;
    reg [31:0] delta_8_15;
    reg [31:0] delta_16p;
    reg [31:0] prefetch_start_count;
    reg [31:0] prefetch_fill_count;
    reg [31:0] prefetch_hit_count;
    reg [31:0] hit_under_miss_count;
`endif
    reg [31:0] last_word_addr;

    integer reset_i;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            pending        <= 1'b0;
            cache_valid    <= {CACHE_LINES{1'b0}};
            prefetch_cache_valid <= 1'b0;
            replace_way    <= {WAY_BITS{1'b0}};
            filling        <= 1'b0;
            fill_is_prefetch <= 1'b0;
            req_active     <= 1'b0;
            DDRAM_RD       <= 1'b0;
            read_pending   <= 1'b0;
            vram_valid_r   <= 1'b0;
            vram_wait      <= 1'b0;
            vram_req_ack   <= 1'b0;
            vram_din_r     <= 64'd0;
            hit_pending    <= 1'b0;
            last_word_addr <= 32'd0;
`ifdef VERILATOR
            hit_count      <= 32'd0;
            line_hit_count <= 32'd0;
            hot_hit_count  <= 32'd0;
            hot_evict_count <= 32'd0;
            miss_count     <= 32'd0;
            delta_0        <= 32'd0;
            delta_1        <= 32'd0;
            delta_2_3      <= 32'd0;
            delta_4_7      <= 32'd0;
            delta_8_15     <= 32'd0;
            delta_16p      <= 32'd0;
            prefetch_start_count <= 32'd0;
            prefetch_fill_count <= 32'd0;
            prefetch_hit_count <= 32'd0;
            hit_under_miss_count <= 32'd0;
`endif
            vram_rd_block  <= 1'b0;
            fill_valid     <= {LINE_WORDS{1'b0}};
            fill_ptr       <= {LINE_BITS{1'b0}};
            fill_way       <= {WAY_BITS{1'b0}};
            req_word_addr  <= 32'd0;
            prefetch_pending <= 1'b0;
            prefetch_base_addr <= 32'd0;
            prefetch_cache_base <= 32'd0;
            prefetch_fill_base_addr <= 32'd0;
            pending_byte_addr <= 22'd0;
            pending_prefetch_ok <= 1'b0;
            fill_prefetch_ok <= 1'b0;
            hit_pending_prefetch <= 1'b0;
            hit_pending_way <= {WAY_BITS{1'b0}};
            hit_pending_index <= {LINE_BITS{1'b0}};
            for (reset_i = 0; reset_i < CACHE_LINES; reset_i = reset_i + 1) begin
                cache_base[reset_i] <= 32'd0;
            end
            for (reset_i = 0; reset_i < LINE_WORDS; reset_i = reset_i + 1) begin
                prefetch_line[reset_i] <= 64'd0;
            end
        end else begin
            DDRAM_RD     <= 1'b0;
            vram_valid_r <= 1'b0;
            vram_req_ack <= 1'b0;

            if (!vram_rd) vram_rd_block <= 1'b0;

            vram_wait <= (req_active || filling || pending || read_pending || hit_pending) &&
                         !(early_hit_possible || pending_early_possible || combo_hit ||
                           hit_under_miss_now ||
                           (hot_hit && !req_active && !hit_pending));

            // Latch one request behind the active miss/hit so callers do not need to pulse-stretch.
            if (vram_rd && !vram_rd_block && !pending) begin
                last_word_addr <= word_addr;
`ifdef VERILATOR
                begin
                    reg [31:0] delta;
                    delta = (word_addr >= last_word_addr) ? (word_addr - last_word_addr)
                                                          : (last_word_addr - word_addr);
                    if (delta == 0)       delta_0    <= delta_0 + 1'b1;
                    else if (delta == 1)  delta_1    <= delta_1 + 1'b1;
                    else if (delta <= 3)  delta_2_3  <= delta_2_3 + 1'b1;
                    else if (delta <= 7)  delta_4_7  <= delta_4_7 + 1'b1;
                    else if (delta <= 15) delta_8_15 <= delta_8_15 + 1'b1;
                    else                  delta_16p  <= delta_16p + 1'b1;
                end
`endif

                vram_req_ack  <= 1'b1;
                vram_rd_block <= 1'b1;

                if (hit_under_miss_now) begin
`ifdef VERILATOR
                    hit_under_miss_count <= hit_under_miss_count + 1'b1;
                    hit_count <= hit_count + 1'b1;
`endif
                    if (hot_hit) begin
`ifdef VERILATOR
                        hot_hit_count <= hot_hit_count + 1'b1;
`endif
                        vram_din_r <= hot_hit_data;
                    end
                    else if (prefetch_hit_now) begin
`ifdef VERILATOR
                        line_hit_count <= line_hit_count + 1'b1;
                        prefetch_hit_count <= prefetch_hit_count + 1'b1;
`endif
                        vram_din_r <= prefetch_line[prefetch_hit_index];
                    end
                    else begin
`ifdef VERILATOR
                        line_hit_count <= line_hit_count + 1'b1;
`endif
                        vram_din_r <= cache_line[hit_way][hit_index];
                    end
                    vram_valid_r <= 1'b1;
                end else if (hot_hit && !req_active && !hit_pending) begin
`ifdef VERILATOR
                    hit_count <= hit_count + 1'b1;
                    hot_hit_count <= hot_hit_count + 1'b1;
`endif
                    if (!TEX_COMBO_HIT) begin
                        vram_din_r <= hot_hit_data;
                        vram_valid_r <= 1'b1;
                    end
                end else if (prefetch_hit_now && !req_active && !hit_pending) begin
`ifdef VERILATOR
                    hit_count <= hit_count + 1'b1;
                    line_hit_count <= line_hit_count + 1'b1;
                    prefetch_hit_count <= prefetch_hit_count + 1'b1;
`endif
                    hit_pending <= 1'b1;
                    hit_pending_prefetch <= 1'b1;
                    hit_pending_index <= prefetch_hit_index;
                end else if (hit_now && !req_active && !hit_pending) begin
`ifdef VERILATOR
                    hit_count <= hit_count + 1'b1;
                    line_hit_count <= line_hit_count + 1'b1;
`endif
                    hit_pending <= !TEX_COMBO_HIT;
                    hit_pending_prefetch <= 1'b0;
                    hit_pending_way <= hit_way;
                    hit_pending_index <= hit_index;
                    if (TEX_COMBO_HIT) begin
                        vram_din_r   <= cache_line[hit_way][hit_index];
                        vram_valid_r <= 1'b1;
                    end
                end else if (!req_active && !hit_pending && !filling && !read_pending) begin
`ifdef VERILATOR
                    miss_count <= miss_count + 1'b1;
`endif
                    req_active <= 1'b1;
                    req_word_addr <= word_addr;
                    fill_way <= replace_way;
                    cache_base[replace_way] <= fill_base_addr;
                    cache_valid[replace_way] <= 1'b0;
                    filling <= 1'b1;
                    fill_is_prefetch <= 1'b0;
                    fill_prefetch_ok <= (word_addr >= last_word_addr) &&
                                        ((word_addr - last_word_addr) <= (LINE_WORDS << 1));
                    fill_ptr <= {LINE_BITS{1'b0}};
                    fill_valid <= {LINE_WORDS{1'b0}};
                    read_pending <= 1'b1;
                    replace_way <= replace_way + 1'b1;
                end else begin
                    pending <= 1'b1;
                    pending_byte_addr <= vram_addr;
                    pending_prefetch_ok <= (word_addr >= last_word_addr) &&
                                           ((word_addr - last_word_addr) <= (LINE_WORDS << 1));
                end
            end

            // Start a pending request once the active miss has responded.
            if (pending && !req_active && !hit_pending) begin
                pending <= 1'b0;
                if (pending_prefetch_hit) begin
                    vram_req_ack <= 1'b1;
`ifdef VERILATOR
                    hit_count <= hit_count + 1'b1;
                    line_hit_count <= line_hit_count + 1'b1;
                    prefetch_hit_count <= prefetch_hit_count + 1'b1;
`endif
                    hit_pending <= 1'b1;
                    hit_pending_prefetch <= 1'b1;
                    hit_pending_index <= pending_prefetch_hit_index;
                end else if (pending_hit) begin
                    vram_req_ack <= 1'b1;
`ifdef VERILATOR
                    hit_count <= hit_count + 1'b1;
                    line_hit_count <= line_hit_count + 1'b1;
`endif
                    hit_pending <= 1'b1;
                    hit_pending_prefetch <= 1'b0;
                    hit_pending_way <= pending_hit_way;
                    hit_pending_index <= pending_hit_index;
                end else if (pending_early_possible) begin
                    vram_req_ack <= 1'b1;
                    vram_din_r <= fill_is_prefetch ? prefetch_line[pending_fill_index] : cache_line[fill_way][pending_fill_index];
                    vram_valid_r <= 1'b1;
                end else if (!filling && !read_pending) begin
                    vram_req_ack <= 1'b1;
`ifdef VERILATOR
                    miss_count <= miss_count + 1'b1;
`endif
                    req_active <= 1'b1;
                    req_word_addr <= pending_word_addr;
                    fill_way <= replace_way;
                    cache_base[replace_way] <= pending_fill_base_addr;
                    cache_valid[replace_way] <= 1'b0;
                    filling <= 1'b1;
                    fill_is_prefetch <= 1'b0;
                    fill_prefetch_ok <= pending_prefetch_ok;
                    fill_ptr <= {LINE_BITS{1'b0}};
                    fill_valid <= {LINE_WORDS{1'b0}};
                    read_pending <= 1'b1;
                    replace_way <= replace_way + 1'b1;
                end else begin
                    pending <= 1'b1;
                end
            end

            if (read_pending && !DDRAM_BUSY) begin
                DDRAM_ADDR     <= (fill_is_prefetch ? prefetch_fill_base_addr : cache_base[fill_way]) + fill_ptr;
                DDRAM_RD       <= 1'b1;
                DDRAM_BURSTCNT <= LINE_WORDS[7:0];
                read_pending   <= 1'b0;
            end

            if (filling && DDRAM_DOUT_READY) begin
                if (fill_is_prefetch)
                    prefetch_line[fill_ptr] <= DDRAM_DOUT;
                else
                    cache_line[fill_way][fill_ptr] <= DDRAM_DOUT;
                fill_valid[fill_ptr] <= 1'b1;

                if (fill_ptr == LINE_WORDS-1) begin
                    filling <= 1'b0;
                    if (fill_is_prefetch) begin
                        prefetch_cache_valid <= 1'b1;
                        prefetch_cache_base <= prefetch_fill_base_addr;
                    end
                    else begin
                        cache_valid[fill_way] <= 1'b1;
                    end
                    fill_valid <= {LINE_WORDS{1'b1}};
                    if (fill_is_prefetch) begin
`ifdef VERILATOR
                        prefetch_fill_count <= prefetch_fill_count + 1'b1;
`endif
                    end
                    else if (NEXT_LINE_PREFETCH && fill_prefetch_ok) begin
                        prefetch_pending <= 1'b1;
                        prefetch_base_addr <= cache_base[fill_way] + LINE_WORDS;
                    end
                    if (req_active && (req_word_addr >= cache_base[fill_way]) &&
                        (req_word_addr < (cache_base[fill_way] + LINE_WORDS))) begin
                        hit_pending <= 1'b1;
                        hit_pending_way <= fill_way;
                        hit_pending_index <= req_word_addr - cache_base[fill_way];
                    end
                end else begin
                    fill_ptr <= fill_ptr + 1'b1;
                end
            end

            if (hit_pending) begin
                vram_din_r <= hit_pending_prefetch ? prefetch_line[hit_pending_index] :
                                                      cache_line[hit_pending_way][hit_pending_index];
                vram_valid_r <= 1'b1;
                hit_pending <= 1'b0;
                hit_pending_prefetch <= 1'b0;
                req_active <= 1'b0;
            end else if (early_hit_possible) begin
                vram_din_r <= fill_is_prefetch ? prefetch_line[req_fill_index] : cache_line[fill_way][req_fill_index];
                vram_valid_r <= 1'b1;
                req_active <= 1'b0;
            end else if (pending_early_possible && !req_active) begin
                vram_din_r <= fill_is_prefetch ? prefetch_line[pending_fill_index] : cache_line[fill_way][pending_fill_index];
                vram_valid_r <= 1'b1;
                pending <= 1'b0;
            end

            if (NEXT_LINE_PREFETCH && prefetch_pending && !prefetch_line_hit &&
                !vram_rd && !req_active && !pending && !hit_pending &&
                !filling && !read_pending && !DDRAM_BUSY) begin
                prefetch_fill_base_addr <= prefetch_base_addr;
                filling <= 1'b1;
                fill_is_prefetch <= 1'b1;
                fill_prefetch_ok <= 1'b0;
                fill_ptr <= {LINE_BITS{1'b0}};
                fill_valid <= {LINE_WORDS{1'b0}};
                read_pending <= 1'b1;
                prefetch_pending <= 1'b0;
`ifdef VERILATOR
                prefetch_start_count <= prefetch_start_count + 1'b1;
`endif
            end
            else if (NEXT_LINE_PREFETCH && prefetch_pending && prefetch_line_hit) begin
                prefetch_pending <= 1'b0;
            end
        end
    end

endmodule
