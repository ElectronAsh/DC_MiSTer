`timescale 1ns / 1ps
`default_nettype none

module simple_cache (
    input  wire        clock,
    input  wire        reset_n,

    // Request from ISP (BYTE address)
    input  wire [7:0]  ddram_burstcnt_in,   // 1–8
    input  wire [23:0] ddram_addr_in,
    input  wire        ddram_rd_in,

    // To DDR controller (BYTE address)
    output reg  [23:0] ddram_addr_out,
    output reg         ddram_rd_out,

    // From DDR controller
    input  wire        ddram_valid_in,
    input  wire [63:0] ddram_readdata_in,

    // To ISP
    output reg  [63:0] cache_readdata_out,
    output reg         cache_valid_out
);

    /* ------------------------------------------------------------
     * Cache storage: 8 × 64-bit words (64 bytes)
     * ------------------------------------------------------------ */
    reg [63:0] cache [0:7];

    /* ------------------------------------------------------------
     * State machine
     * ------------------------------------------------------------ */
    localparam ST_IDLE   = 2'd0;
    localparam ST_REFILL = 2'd1;
    localparam ST_RETURN = 2'd2;

    reg [1:0] state;

    /* ------------------------------------------------------------
     * Bookkeeping
     * ------------------------------------------------------------ */
    reg [23:0] pend_addr;          // ISP byte address
    reg [20:0] cache_base_word;    // 64-bit word index (aligned)
    reg        cache_line_valid;

    reg [2:0]  word_cnt;           // 0–7
    reg [2:0]  refill_len;         // actual words to refill (1–8)

    /* ------------------------------------------------------------
     * Address decode
     * ------------------------------------------------------------ */
    wire [20:0] req_word_addr = ddram_addr_in[23:3]; // 64-bit word index
    wire [2:0]  req_index     = ddram_addr_in[5:3];

    wire hit =
        cache_line_valid &&
        (req_word_addr >= cache_base_word) &&
        (req_word_addr <  cache_base_word + 8);

    /* ------------------------------------------------------------
     * FSM
     * ------------------------------------------------------------ */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state              <= ST_IDLE;
            ddram_rd_out       <= 1'b0;
            ddram_addr_out     <= 24'd0;

            cache_valid_out    <= 1'b0;
            cache_line_valid   <= 1'b0;

            word_cnt           <= 3'd0;
            refill_len         <= 3'd0;
        end else begin
            ddram_rd_out    <= 1'b0;
            cache_valid_out <= 1'b0;

            case (state)

            /* ------------------------------------------------
             * IDLE / LOOKUP
             * ------------------------------------------------ */
            ST_IDLE: begin
                if (ddram_rd_in) begin
                    pend_addr <= ddram_addr_in;

                    if (hit) begin
                        cache_readdata_out <= cache[req_index];
                        cache_valid_out    <= 1'b1;
                    end else begin
                        // Start refill
                        cache_line_valid <= 1'b0;
                        word_cnt         <= 3'd0;

                        // Clamp burst to cache size
                        refill_len <= (ddram_burstcnt_in > 8)
                                      ? 3'd7
                                      : ddram_burstcnt_in[2:0] - 3'd1;

                        // Align to 64-byte line
                        cache_base_word <= { req_word_addr[20:3], 3'b000 };

                        ddram_addr_out <= { req_word_addr[20:3], 3'b000, 3'b000 };
                        ddram_rd_out <= 1'b1;

                        state <= ST_REFILL;
                    end
                end
            end

            /* ------------------------------------------------
             * REFILL (gap-tolerant)
             * ------------------------------------------------ */
            ST_REFILL: begin
                if (ddram_valid_in) begin
                    cache[word_cnt] <= ddram_readdata_in;

                    if (word_cnt == refill_len) begin
                        cache_line_valid <= 1'b1;
                        state            <= ST_RETURN;
                    end else begin
                        word_cnt <= word_cnt + 3'd1;
                    end
                end
            end

            /* ------------------------------------------------
             * RETURN DATA
             * ------------------------------------------------ */
            ST_RETURN: begin
                cache_readdata_out <= cache[pend_addr[5:3]];
                cache_valid_out    <= 1'b1;
                state              <= ST_IDLE;
            end

            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
