`timescale 1ns / 1ps
`default_nettype none

module span_sorter_row #
(
    parameter TAG_W = 12,
    parameter Z_W   = 48
)
(
    input  wire              clk,
    input  wire              rst,

    /* Row input */
    output wire              span_busy,
    input  wire              row_valid,
    input  wire [4:0]        row_y,
    input  wire [TAG_W-1:0]  tag_row [0:31],
    input  wire signed [Z_W-1:0] z_row [0:31],

    /* Span output */
    output reg               span_valid,
    input  wire              span_accept,

    output reg  [TAG_W-1:0]  span_tag,
    output reg  [4:0]        span_x,
    output reg  [4:0]        span_y,
    output reg  [5:0]        span_width,

    output reg  signed [Z_W-1:0] span_z_start,
    output reg  signed [Z_W-1:0] span_dzdx
);

    /* Internal state */
    reg [5:0] col;
    reg active;

    assign span_busy = active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            col        <= 0;
            active     <= 0;
            span_valid <= 0;
        end
        else begin
            span_valid <= 0;

            /* Start processing a new row */
            if (row_valid && !active) begin
                active <= 1;
                col    <= 0;
            end

            /* Process row */
            if (active && !span_valid) begin
                if (col < 32) begin
                    integer start;
                    integer endi;

                    start = col;

                    /* Skip empty tags if you use one (optional) */
                    if (tag_row[start] != 0) begin
                        endi = start + 1;
                        while (endi < 32 && tag_row[endi] == tag_row[start])
                            endi = endi + 1;

                        /* Emit span */
                        span_valid   <= 1;
                        span_tag     <= tag_row[start];
                        span_x       <= start[4:0];
                        span_y       <= row_y;
                        span_width   <= endi - start;

                        span_z_start <= z_row[start];

                        if (endi - start >= 2)
                            span_dzdx <= z_row[start+1] - z_row[start];
                        else
                            span_dzdx <= {Z_W{1'b0}};

                        col <= endi;
                    end
                    else begin
                        col <= col + 1;
                    end
                end
                else begin
                    active <= 0;  // done with row
                end
            end

            /* Span handshake */
            if (span_valid && span_accept) begin
                span_valid <= 0;
            end
        end
    end

endmodule
