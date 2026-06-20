`timescale 1ns / 1ps
`default_nettype none

module pcache_mem
#(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 128,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)
(
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  we,
    output reg  [DATA_WIDTH-1:0] dout
);

    // Inferred block RAM
    (* ramstyle = "M10K" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;

        // synchronous read (required for proper BRAM inference)
        dout <= mem[addr];
    end

endmodule
