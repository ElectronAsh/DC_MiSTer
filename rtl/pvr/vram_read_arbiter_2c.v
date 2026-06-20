`timescale 1ns / 1ps
`default_nettype none

module vram_read_arbiter_2c #(
`ifdef VERILATOR
    parameter CACHE_WORDS = 64,
    parameter CACHE_BITS  = 6,
    parameter BURST_WORDS = 32,
`else
    parameter CACHE_WORDS = 1,
    parameter CACHE_BITS  = 1,
    parameter BURST_WORDS = 1,
`endif
    parameter WRITE_BURST_WORDS = 8
) (
    input  wire        clock,
    input  wire        reset_n,

    // Client A (RA)
    input  wire        a_rd,
    input  wire [21:0] a_addr,
    output reg  [63:0] a_din,
    output reg         a_wait,
    output reg         a_valid,
    output reg         a_req_ack,

    // Client B (ISP)
    input  wire        b_rd,
    input  wire [21:0] b_addr,
    output reg  [63:0] b_din,
    output reg         b_wait,
    output reg         b_valid,
    output reg         b_req_ack,

    // Client C (tile/framebuffer writeback)
    input  wire        c_pending,
    input  wire        c_wr,
    input  wire [28:0] c_addr,
    input  wire [63:0] c_dout,
    input  wire [7:0]  c_be,
    input  wire [7:0]  c_burstcnt,
    output wire        c_wait,

    // DDRAM
    output reg  [28:0] DDRAM_ADDR,
    output reg         DDRAM_RD,
    output reg  [63:0] DDRAM_DIN,
    output reg  [7:0]  DDRAM_BE,
    output reg         DDRAM_WE,
    output reg  [7:0]  DDRAM_BURSTCNT,
    input  wire [63:0] DDRAM_DOUT,
    input  wire        DDRAM_DOUT_READY,
    input  wire        DDRAM_BUSY,
    input  wire        DDRAM_PAUSE
);

    localparam OWNER_A = 1'b0;
    localparam OWNER_B = 1'b1;
    localparam [7:0] BURST_LEN = BURST_WORDS;
    localparam [19:0] BURST_INC = BURST_WORDS;
    localparam [7:0] WRITE_BURST_LEN = WRITE_BURST_WORDS;

    wire [19:0] a_req_word = a_addr[21:2];
    wire [19:0] b_req_word = b_addr[21:2];

    reg [63:0] a_cache [0:CACHE_WORDS-1];
    reg [63:0] b_cache [0:CACHE_WORDS-1];
    reg [CACHE_WORDS-1:0] a_cache_valid;
    reg [CACHE_WORDS-1:0] b_cache_valid;
    reg [19:0] a_cache_base;
    reg [19:0] b_cache_base;
    reg        a_cache_base_valid;
    reg        b_cache_base_valid;

    reg        a_pend_valid;
    reg [19:0] a_pend_word;
    reg        b_pend_valid;
    reg [19:0] b_pend_word;
    reg        a_prefetch_valid;
    reg [19:0] a_prefetch_word;
    reg        b_prefetch_valid;
    reg [19:0] b_prefetch_word;

    reg        fill_active;
    reg        fill_cmd_pending;
    reg        fill_owner;
    reg [19:0] fill_word;
    reg [7:0]  fill_count;
    reg [7:0]  fill_len;

    reg        rr_owner; // 0=A next on tie, 1=B next on tie

    reg        write_active;
    reg        write_cmd_pending;
    reg [7:0]  write_count;
    reg [7:0]  write_len;
    reg [63:0] write_din_hold;
    reg [7:0]  write_be_hold;

    (* noprune *) reg inflight;
    (* noprune *) reg inflight_owner;

    wire [20:0] a_req_delta = {1'b0, a_req_word} - {1'b0, a_cache_base};
    wire [20:0] b_req_delta = {1'b0, b_req_word} - {1'b0, b_cache_base};
    wire        a_req_in_cache = a_cache_base_valid && (a_req_delta < CACHE_WORDS);
    wire        b_req_in_cache = b_cache_base_valid && (b_req_delta < CACHE_WORDS);
    wire [CACHE_BITS-1:0] a_req_index = a_req_delta[CACHE_BITS-1:0];
    wire [CACHE_BITS-1:0] b_req_index = b_req_delta[CACHE_BITS-1:0];
    wire        a_req_hit = a_req_in_cache && a_cache_valid[a_req_index];
    wire        b_req_hit = b_req_in_cache && b_cache_valid[b_req_index];

    wire [20:0] a_pend_delta = {1'b0, a_pend_word} - {1'b0, a_cache_base};
    wire [20:0] b_pend_delta = {1'b0, b_pend_word} - {1'b0, b_cache_base};
    wire        a_pend_in_cache = a_cache_base_valid && (a_pend_delta < CACHE_WORDS);
    wire        b_pend_in_cache = b_cache_base_valid && (b_pend_delta < CACHE_WORDS);
    wire [CACHE_BITS-1:0] a_pend_index = a_pend_delta[CACHE_BITS-1:0];
    wire [CACHE_BITS-1:0] b_pend_index = b_pend_delta[CACHE_BITS-1:0];
    wire        a_pend_hit = a_pend_in_cache && a_cache_valid[a_pend_index];
    wire        b_pend_hit = b_pend_in_cache && b_cache_valid[b_pend_index];
    wire        a_need_fill = a_pend_valid && !a_pend_hit;
    wire        b_need_fill = b_pend_valid && !b_pend_hit;

    wire [20:0] fill_delta_a = {1'b0, fill_word} - {1'b0, a_cache_base};
    wire [20:0] fill_delta_b = {1'b0, fill_word} - {1'b0, b_cache_base};
    wire        fill_in_a_cache = a_cache_base_valid && (fill_delta_a < CACHE_WORDS);
    wire        fill_in_b_cache = b_cache_base_valid && (fill_delta_b < CACHE_WORDS);
    wire [CACHE_BITS-1:0] fill_index_a = fill_delta_a[CACHE_BITS-1:0];
    wire [CACHE_BITS-1:0] fill_index_b = fill_delta_b[CACHE_BITS-1:0];

    wire [7:0] c_burstcnt_safe = (c_burstcnt == 8'd0) ? 8'd1 : c_burstcnt;

    assign c_wait = fill_active || DDRAM_BUSY || DDRAM_PAUSE || (write_active && write_cmd_pending);

    wire any_busy = a_pend_valid || b_pend_valid || fill_active || write_active || DDRAM_BUSY || DDRAM_PAUSE;

    // Debug stats for ImGui visibility.
    (* noprune *) reg [31:0] a_req_count;
    (* noprune *) reg [31:0] b_req_count;
    (* noprune *) reg [31:0] a_drop_count;
    (* noprune *) reg [31:0] b_drop_count;
    (* noprune *) reg [31:0] ddr_issue_count;
    (* noprune *) reg [31:0] a_resp_count;
    (* noprune *) reg [31:0] b_resp_count;
    (* noprune *) reg [31:0] a_cache_hit_count;
    (* noprune *) reg [31:0] b_cache_hit_count;
    (* noprune *) reg [31:0] a_cache_miss_count;
    (* noprune *) reg [31:0] b_cache_miss_count;
    (* noprune *) reg [31:0] a_refill_count;
    (* noprune *) reg [31:0] b_refill_count;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            DDRAM_ADDR          <= 29'd0;
            DDRAM_RD            <= 1'b0;
            DDRAM_DIN           <= 64'd0;
            DDRAM_BE            <= 8'hff;
            DDRAM_WE            <= 1'b0;
            DDRAM_BURSTCNT      <= 8'd1;
            a_cache_valid       <= {CACHE_WORDS{1'b0}};
            b_cache_valid       <= {CACHE_WORDS{1'b0}};
            a_cache_base        <= 20'd0;
            b_cache_base        <= 20'd0;
            a_cache_base_valid  <= 1'b0;
            b_cache_base_valid  <= 1'b0;
            a_pend_valid        <= 1'b0;
            a_pend_word         <= 20'd0;
            b_pend_valid        <= 1'b0;
            b_pend_word         <= 20'd0;
            a_prefetch_valid    <= 1'b0;
            a_prefetch_word     <= 20'd0;
            b_prefetch_valid    <= 1'b0;
            b_prefetch_word     <= 20'd0;
            fill_active         <= 1'b0;
            fill_cmd_pending    <= 1'b0;
            fill_owner          <= OWNER_A;
            fill_word           <= 20'd0;
            fill_count          <= 8'd0;
            fill_len            <= 8'd0;
            inflight            <= 1'b0;
            inflight_owner      <= OWNER_A;
            rr_owner            <= OWNER_A;
            write_active        <= 1'b0;
            write_cmd_pending   <= 1'b0;
            write_count         <= 8'd0;
            write_len           <= WRITE_BURST_LEN;
            write_din_hold      <= 64'd0;
            write_be_hold       <= 8'hff;
            a_din               <= 64'd0;
            b_din               <= 64'd0;
            a_wait              <= 1'b0;
            b_wait              <= 1'b0;
            a_valid             <= 1'b0;
            b_valid             <= 1'b0;
            a_req_ack           <= 1'b0;
            b_req_ack           <= 1'b0;
            a_req_count         <= 32'd0;
            b_req_count         <= 32'd0;
            a_drop_count        <= 32'd0;
            b_drop_count        <= 32'd0;
            ddr_issue_count     <= 32'd0;
            a_resp_count        <= 32'd0;
            b_resp_count        <= 32'd0;
            a_cache_hit_count   <= 32'd0;
            b_cache_hit_count   <= 32'd0;
            a_cache_miss_count  <= 32'd0;
            b_cache_miss_count  <= 32'd0;
            a_refill_count      <= 32'd0;
            b_refill_count      <= 32'd0;
        end else begin
            DDRAM_RD       <= 1'b0;
            DDRAM_WE       <= 1'b0;
            DDRAM_DIN      <= 64'd0;
            DDRAM_BE       <= 8'hff;
            DDRAM_BURSTCNT <= 8'd1;
            a_valid        <= 1'b0;
            b_valid        <= 1'b0;
            a_req_ack      <= 1'b0;
            b_req_ack      <= 1'b0;
            inflight       <= fill_active;
            inflight_owner <= fill_owner;

            a_wait <= a_pend_valid;
            b_wait <= b_pend_valid;

            if (fill_cmd_pending) begin
                DDRAM_RD <= 1'b1;
                DDRAM_BURSTCNT <= fill_len;
                if (!DDRAM_BUSY && !DDRAM_PAUSE) begin
                    DDRAM_RD <= 1'b0;
                    fill_cmd_pending <= 1'b0;
                end
            end

            if (write_cmd_pending) begin
                DDRAM_WE <= 1'b1;
                DDRAM_DIN <= write_din_hold;
                DDRAM_BE <= write_be_hold;
                DDRAM_BURSTCNT <= write_len;
                if (!DDRAM_BUSY && !DDRAM_PAUSE) begin
                    DDRAM_WE <= 1'b0;
                    write_cmd_pending <= 1'b0;
                    if (write_len == 8'd1) begin
                        write_active <= 1'b0;
                        write_count <= 8'd0;
                    end else begin
                        write_count <= 8'd1;
                    end
                end
            end

            if (c_wr && ((!write_active && !fill_active && !DDRAM_PAUSE) || (write_active && !write_cmd_pending && !c_wait))) begin
                DDRAM_DIN <= c_dout;
                DDRAM_BE  <= c_be;
                DDRAM_BURSTCNT <= write_active ? write_len : c_burstcnt_safe;
                if (!write_active) begin
                    DDRAM_WE <= 1'b1;
                    DDRAM_ADDR <= c_addr;
                    write_din_hold <= c_dout;
                    write_be_hold <= c_be;
                    write_len <= c_burstcnt_safe;
                    write_active <= 1'b1;
                    write_cmd_pending <= 1'b1;
                    write_count <= 8'd0;
                end else begin
                    if (write_count == (write_len - 8'd1)) begin
                        write_active <= 1'b0;
                        write_cmd_pending <= 1'b0;
                        write_count <= 8'd0;
                    end else begin
                        write_count <= write_count + 8'd1;
                    end
                end
            end

            // Client hits return immediately from the local stream cache.
            if (a_rd && !a_pend_valid) begin
                a_req_ack <= 1'b1;
                a_req_count <= a_req_count + 1'd1;
                if (a_req_hit) begin
                    a_din <= a_cache[a_req_index];
                    a_valid <= 1'b1;
                    a_resp_count <= a_resp_count + 1'd1;
                    a_cache_hit_count <= a_cache_hit_count + 1'd1;
                end else begin
                    a_pend_valid <= 1'b1;
                    a_pend_word <= a_req_word;
                    a_cache_miss_count <= a_cache_miss_count + 1'd1;
                end
            end else if (a_rd && a_pend_valid) begin
                a_drop_count <= a_drop_count + 1'd1;
            end

            if (b_rd && !b_pend_valid) begin
                b_req_ack <= 1'b1;
                b_req_count <= b_req_count + 1'd1;
                if (b_req_hit) begin
                    b_din <= b_cache[b_req_index];
                    b_valid <= 1'b1;
                    b_resp_count <= b_resp_count + 1'd1;
                    b_cache_hit_count <= b_cache_hit_count + 1'd1;
                end else begin
                    b_pend_valid <= 1'b1;
                    b_pend_word <= b_req_word;
                    b_cache_miss_count <= b_cache_miss_count + 1'd1;
                end
            end else if (b_rd && b_pend_valid) begin
                b_drop_count <= b_drop_count + 1'd1;
            end

            // A pending request may become valid while a burst for the same port
            // is still filling.
            if (a_pend_valid && a_pend_hit) begin
                a_din <= a_cache[a_pend_index];
                a_valid <= 1'b1;
                a_pend_valid <= 1'b0;
                a_resp_count <= a_resp_count + 1'd1;
                a_cache_hit_count <= a_cache_hit_count + 1'd1;
            end
            if (b_pend_valid && b_pend_hit) begin
                b_din <= b_cache[b_pend_index];
                b_valid <= 1'b1;
                b_pend_valid <= 1'b0;
                b_resp_count <= b_resp_count + 1'd1;
                b_cache_hit_count <= b_cache_hit_count + 1'd1;
            end

            // Capture burst data into the owning port cache.
            if (fill_active && DDRAM_DOUT_READY) begin
                if (fill_owner == OWNER_A) begin
                    if (fill_in_a_cache) begin
                        a_cache[fill_index_a] <= DDRAM_DOUT;
                        a_cache_valid[fill_index_a] <= 1'b1;
                    end
                    if (a_pend_valid && (a_pend_word == fill_word)) begin
                        a_din <= DDRAM_DOUT;
                        a_valid <= 1'b1;
                        a_pend_valid <= 1'b0;
                        a_resp_count <= a_resp_count + 1'd1;
                    end
                end else begin
                    if (fill_in_b_cache) begin
                        b_cache[fill_index_b] <= DDRAM_DOUT;
                        b_cache_valid[fill_index_b] <= 1'b1;
                    end
                    if (b_pend_valid && (b_pend_word == fill_word)) begin
                        b_din <= DDRAM_DOUT;
                        b_valid <= 1'b1;
                        b_pend_valid <= 1'b0;
                        b_resp_count <= b_resp_count + 1'd1;
                    end
                end

                if (fill_count == (fill_len - 8'd1)) begin
                    fill_active <= 1'b0;
                end else begin
                    fill_count <= fill_count + 8'd1;
                    fill_word <= fill_word + 20'd1;
                end
            end

            // Launch the next burst for a pending miss. A miss outside the current
            // 64-word window starts a new window at the requested word.
            if (!fill_active && !write_active && !c_pending && !DDRAM_PAUSE) begin
                if (a_need_fill && b_need_fill) begin
                    if (rr_owner) begin
                        if (!a_pend_in_cache) begin
                            a_cache_base <= a_pend_word;
                            a_cache_base_valid <= 1'b1;
                            a_cache_valid <= {CACHE_WORDS{1'b0}};
                        end
                        DDRAM_ADDR <= {9'd0, a_pend_word};
                        DDRAM_RD <= 1'b1;
                        DDRAM_BURSTCNT <= BURST_LEN;
                        fill_active <= 1'b1;
                        fill_cmd_pending <= 1'b1;
                        fill_owner <= OWNER_A;
                        fill_word <= a_pend_word;
                        fill_count <= 8'd0;
                        fill_len <= BURST_LEN;
                        a_prefetch_valid <= !a_pend_in_cache ? (BURST_LEN < CACHE_WORDS) : ((a_pend_delta + BURST_WORDS) < CACHE_WORDS);
                        a_prefetch_word <= a_pend_word + BURST_INC;
                        rr_owner <= OWNER_B;
                        ddr_issue_count <= ddr_issue_count + 1'd1;
                        a_refill_count <= a_refill_count + 1'd1;
                    end else begin
                        if (!b_pend_in_cache) begin
                            b_cache_base <= b_pend_word;
                            b_cache_base_valid <= 1'b1;
                            b_cache_valid <= {CACHE_WORDS{1'b0}};
                        end
                        DDRAM_ADDR <= {9'd0, b_pend_word};
                        DDRAM_RD <= 1'b1;
                        DDRAM_BURSTCNT <= BURST_LEN;
                        fill_active <= 1'b1;
                        fill_cmd_pending <= 1'b1;
                        fill_owner <= OWNER_B;
                        fill_word <= b_pend_word;
                        fill_count <= 8'd0;
                        fill_len <= BURST_LEN;
                        b_prefetch_valid <= !b_pend_in_cache ? (BURST_LEN < CACHE_WORDS) : ((b_pend_delta + BURST_WORDS) < CACHE_WORDS);
                        b_prefetch_word <= b_pend_word + BURST_INC;
                        rr_owner <= OWNER_A;
                        ddr_issue_count <= ddr_issue_count + 1'd1;
                        b_refill_count <= b_refill_count + 1'd1;
                    end
                end else if (a_need_fill) begin
                    if (!a_pend_in_cache) begin
                        a_cache_base <= a_pend_word;
                        a_cache_base_valid <= 1'b1;
                        a_cache_valid <= {CACHE_WORDS{1'b0}};
                    end
                    DDRAM_ADDR <= {9'd0, a_pend_word};
                    DDRAM_RD <= 1'b1;
                    DDRAM_BURSTCNT <= BURST_LEN;
                    fill_active <= 1'b1;
                    fill_cmd_pending <= 1'b1;
                    fill_owner <= OWNER_A;
                    fill_word <= a_pend_word;
                    fill_count <= 8'd0;
                    fill_len <= BURST_LEN;
                    a_prefetch_valid <= !a_pend_in_cache ? (BURST_LEN < CACHE_WORDS) : ((a_pend_delta + BURST_WORDS) < CACHE_WORDS);
                    a_prefetch_word <= a_pend_word + BURST_INC;
                    rr_owner <= OWNER_B;
                    ddr_issue_count <= ddr_issue_count + 1'd1;
                    a_refill_count <= a_refill_count + 1'd1;
                end else if (b_need_fill) begin
                    if (!b_pend_in_cache) begin
                        b_cache_base <= b_pend_word;
                        b_cache_base_valid <= 1'b1;
                        b_cache_valid <= {CACHE_WORDS{1'b0}};
                    end
                    DDRAM_ADDR <= {9'd0, b_pend_word};
                    DDRAM_RD <= 1'b1;
                    DDRAM_BURSTCNT <= BURST_LEN;
                    fill_active <= 1'b1;
                    fill_cmd_pending <= 1'b1;
                    fill_owner <= OWNER_B;
                    fill_word <= b_pend_word;
                    fill_count <= 8'd0;
                    fill_len <= BURST_LEN;
                    b_prefetch_valid <= !b_pend_in_cache ? (BURST_LEN < CACHE_WORDS) : ((b_pend_delta + BURST_WORDS) < CACHE_WORDS);
                    b_prefetch_word <= b_pend_word + BURST_INC;
                    rr_owner <= OWNER_A;
                    ddr_issue_count <= ddr_issue_count + 1'd1;
                    b_refill_count <= b_refill_count + 1'd1;
                end else if (a_prefetch_valid) begin
                    DDRAM_ADDR <= {9'd0, a_prefetch_word};
                    DDRAM_RD <= 1'b1;
                    DDRAM_BURSTCNT <= BURST_LEN;
                    fill_active <= 1'b1;
                    fill_cmd_pending <= 1'b1;
                    fill_owner <= OWNER_A;
                    fill_word <= a_prefetch_word;
                    fill_count <= 8'd0;
                    fill_len <= BURST_LEN;
                    a_prefetch_valid <= 1'b0;
                    ddr_issue_count <= ddr_issue_count + 1'd1;
                    a_refill_count <= a_refill_count + 1'd1;
                end else if (b_prefetch_valid) begin
                    DDRAM_ADDR <= {9'd0, b_prefetch_word};
                    DDRAM_RD <= 1'b1;
                    DDRAM_BURSTCNT <= BURST_LEN;
                    fill_active <= 1'b1;
                    fill_cmd_pending <= 1'b1;
                    fill_owner <= OWNER_B;
                    fill_word <= b_prefetch_word;
                    fill_count <= 8'd0;
                    fill_len <= BURST_LEN;
                    b_prefetch_valid <= 1'b0;
                    ddr_issue_count <= ddr_issue_count + 1'd1;
                    b_refill_count <= b_refill_count + 1'd1;
                end
            end
        end
    end
endmodule
