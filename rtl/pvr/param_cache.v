`timescale 1ns / 1ps
`default_nettype none

module param_cache (
	input reset_n,
	input clock,

	input [21:0] param_req_addr,
	input param_read,
	
	input ddram_waitrequest,
	output reg [21:0] ddram_addr,
	output reg ddram_read_burst,
	input [31:0] ddram_readdata,
	input ddram_readdata_valid,
	
	output [31:0] param_dout,
	output reg param_data_ready
);


reg [7:0] state;
reg [21:0] curr_req_addr;
reg [5:0] word_count;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 8'd0;
	word_count <= 6'd0;
	curr_req_addr <= 22'h32BEEF;
	param_data_ready <= 1'b0;
	ddram_read_burst <= 1'b0;
end
else begin
	param_data_ready <= 1'b0;
	ddram_read_burst <= 1'b0;
	
	case (state)
		0: begin
			if (param_read) begin
				/*if ( (param_req_addr>=curr_req_addr-32) && (param_req_addr<curr_req_addr+32) ) param_data_ready <= 1'b1;	// Cache hit.
				else begin*/
					ddram_addr <= param_req_addr;
					ddram_read_burst <= 1'b1;
					word_count <= 6'd0;
					state <= state + 8'd1;
				//end
			end
		end
		
		1: begin
			if (!ddram_waitrequest) begin
				if (ddram_readdata_valid) begin
					curr_req_addr <= curr_req_addr + 1;
					word_count <= word_count + 1;
				end
			end
			if (word_count==6'd32) begin
				param_data_ready <= 1'b1;
				state <= 8'd0;
			end
		end
		
		default: ;
	endcase
end


dpram_32  dpram_inst (
	.clk( clock ),

	.data_a( ddram_readdata ),
	.addr_a( curr_req_addr[5:0] ),
	.we_a( ddram_readdata_valid ),
	.q_a( ),
	
	.data_b( 32'h00000000 ),
	.addr_b( param_req_addr[5:0] ),
	.we_b( 1'b0 ),
	.q_b( param_dout )
);

endmodule
