`timescale 1ns / 1ps
`default_nettype none

module leading_trailing (
	input [31:0] span_bits,
	
	output reg [4:0] leading_zeros,
	output reg [4:0] trailing_zeros
);


always @* begin
		 if (span_bits[30:00]==0) leading_zeros = 31;
	else if (span_bits[29:00]==0) leading_zeros = 30;
	else if (span_bits[28:00]==0) leading_zeros = 29;
	else if (span_bits[27:00]==0) leading_zeros = 28;
	else if (span_bits[26:00]==0) leading_zeros = 27;
	else if (span_bits[25:00]==0) leading_zeros = 26;
	else if (span_bits[24:00]==0) leading_zeros = 25;
	else if (span_bits[23:00]==0) leading_zeros = 24;
	else if (span_bits[22:00]==0) leading_zeros = 23;
	else if (span_bits[21:00]==0) leading_zeros = 22;
	else if (span_bits[20:00]==0) leading_zeros = 21;
	else if (span_bits[19:00]==0) leading_zeros = 20;
	else if (span_bits[18:00]==0) leading_zeros = 19;
	else if (span_bits[17:00]==0) leading_zeros = 18;
	else if (span_bits[16:00]==0) leading_zeros = 17;
	else if (span_bits[15:00]==0) leading_zeros = 16;
	else if (span_bits[14:00]==0) leading_zeros = 15;
	else if (span_bits[13:00]==0) leading_zeros = 14;
	else if (span_bits[12:00]==0) leading_zeros = 13;
	else if (span_bits[11:00]==0) leading_zeros = 12;
	else if (span_bits[10:00]==0) leading_zeros = 11;
	else if (span_bits[09:00]==0) leading_zeros = 10;
	else if (span_bits[08:00]==0) leading_zeros = 9;
	else if (span_bits[07:00]==0) leading_zeros = 8;
	else if (span_bits[06:00]==0) leading_zeros = 7;
	else if (span_bits[05:00]==0) leading_zeros = 6;
	else if (span_bits[04:00]==0) leading_zeros = 5;
	else if (span_bits[03:00]==0) leading_zeros = 4;
	else if (span_bits[02:00]==0) leading_zeros = 3;
	else if (span_bits[01:00]==0) leading_zeros = 2;
	else if (span_bits[00:00]==0) leading_zeros = 1;
	else leading_zeros = 0;
	
		 if (span_bits[31:01]==0) trailing_zeros = 31;
	else if (span_bits[31:02]==0) trailing_zeros = 30;
	else if (span_bits[31:03]==0) trailing_zeros = 29;
	else if (span_bits[31:04]==0) trailing_zeros = 28;
	else if (span_bits[31:05]==0) trailing_zeros = 27;
	else if (span_bits[31:06]==0) trailing_zeros = 26;
	else if (span_bits[31:07]==0) trailing_zeros = 25;
	else if (span_bits[31:08]==0) trailing_zeros = 24;
	else if (span_bits[31:09]==0) trailing_zeros = 23;
	else if (span_bits[31:10]==0) trailing_zeros = 22;
	else if (span_bits[31:11]==0) trailing_zeros = 21;
	else if (span_bits[31:12]==0) trailing_zeros = 20;
	else if (span_bits[31:13]==0) trailing_zeros = 19;
	else if (span_bits[31:14]==0) trailing_zeros = 18;
	else if (span_bits[31:15]==0) trailing_zeros = 17;
	else if (span_bits[31:16]==0) trailing_zeros = 16;
	else if (span_bits[31:17]==0) trailing_zeros = 15;
	else if (span_bits[31:18]==0) trailing_zeros = 14;
	else if (span_bits[31:19]==0) trailing_zeros = 13;
	else if (span_bits[31:20]==0) trailing_zeros = 12;
	else if (span_bits[31:21]==0) trailing_zeros = 11;
	else if (span_bits[31:22]==0) trailing_zeros = 10;
	else if (span_bits[31:23]==0) trailing_zeros = 9;
	else if (span_bits[31:24]==0) trailing_zeros = 8;
	else if (span_bits[31:25]==0) trailing_zeros = 7;
	else if (span_bits[31:26]==0) trailing_zeros = 6;
	else if (span_bits[31:27]==0) trailing_zeros = 5;
	else if (span_bits[31:28]==0) trailing_zeros = 4;
	else if (span_bits[31:29]==0) trailing_zeros = 3;
	else if (span_bits[31:30]==0) trailing_zeros = 2;
	else if (span_bits[31:31]==0) trailing_zeros = 1;
	else trailing_zeros = 0;
end

endmodule
