module simple_cache (
	input clock,
	input reset_n,
	
	// Request from core...
	input [28:0] ddram_addr_in,
	input ddram_rd_in,
	
	// To the DDR controller...
	output reg [28:0] ddram_addr_out,
	output reg [7:0] ddram_burstcnt_out,
	output reg ddram_rd_out,
	
	// From the DDR controller...
	input ddram_valid_in,
	input [63:0] ddram_readdata_in,
	
	// Data to core...
	output reg [63:0]  ddram_readdata_out,
	output reg ddram_valid_out	
);

reg [63:0] cache [0:7];
reg [2:0] word_cnt;

reg [28:0] pend_word_addr;
reg rd_pend;

reg [2:0] state;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 3'd0;
	ddram_rd_out <= 1'b0;
	ddram_valid_out <= 1'b0;
	ddram_addr_out <= 29'h3afebeef;
	rd_pend <= 1'b0;
end
else begin
	if (ddram_rd_in) begin
		pend_word_addr <= ddram_addr_in;
		rd_pend <= 1'b1;
	end

	ddram_rd_out <= 1'b0;
	ddram_valid_out <= 1'b0;

	case (state)
	0: begin
		if (rd_pend) begin
			if (pend_word_addr>={ddram_addr_out[28:2],2'd0} && pend_word_addr<={ddram_addr_out[28:2],2'd3}) begin	// cache hit...
				ddram_readdata_out <= cache[ pend_word_addr[1:0] ];
				ddram_valid_out <= 1'b1;
				rd_pend <= 1'b0;
			end
			else begin	// cache miss...
				ddram_addr_out <= {pend_word_addr[28:2],2'd0};	// Request from start block of 4 words.
				ddram_burstcnt_out <= 8'd4;							// Request 4 WORDS from DDR3.
				ddram_rd_out <= 1'b1;
				word_cnt <= 3'd0;
				state <= state + 3'd1;
			end
		end
	end
	
	1: if (ddram_valid_in) begin
		cache[ word_cnt ] <= ddram_readdata_in;
		word_cnt <= word_cnt + 1;
		if (word_cnt==3'd3) state <= 3'd0;
	end
	
	default: ;
	endcase
end


endmodule
