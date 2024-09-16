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
reg rd_pend;

reg [28:0] pend_word_addr;

reg [2:0] state;

wire cache_hit = ddram_addr_in>={ddram_addr_out[28:3],3'd0} && ddram_addr_in<={ddram_addr_out[28:3],3'd7};

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 3'd0;
	ddram_rd_out <= 1'b0;
	ddram_valid_out <= 1'b0;
	ddram_addr_out <= 29'h3afebeef;
	rd_pend <= 1'b0;
end
else begin
	ddram_rd_out <= 1'b0;
	ddram_valid_out <= 1'b0;

	//if (ddram_rd_in) pend_word_addr <= ddram_addr_in;
	
	case (state)
	0: begin
		if (ddram_rd_in || rd_pend) begin
			if (cache_hit) begin	// cache hit...
				ddram_readdata_out <= cache[ /*rd_pend ? pend_word_addr[2:0] :*/ ddram_addr_in[2:0] ];
				ddram_valid_out <= 1'b1;
				rd_pend <= 1'b0;
			end
			else begin	// cache miss...
				ddram_addr_out <= {ddram_addr_in[28:3],3'd0};	// Request from start block of 8 words.
				ddram_burstcnt_out <= 8'd8;							// Request 8 WORDS from DDR3.
				ddram_rd_out <= 1'b1;
				rd_pend <= 1'b1;
				word_cnt <= 3'd0;
				state <= state + 3'd1;
			end
		end
	end
	
	1: if (ddram_valid_in) begin
		cache[ word_cnt ] <= ddram_readdata_in;
		word_cnt <= word_cnt + 1;
		if (word_cnt==3'd7) state <= 3'd0;
	end
	
	default: ;
	endcase
end


endmodule
