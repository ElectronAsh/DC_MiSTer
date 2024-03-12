`timescale 1ns / 1ps
`default_nettype none

module tile_tag_buffer (
	input clock,
	input reset_n,
	
	input [5:0] tile_x,
	input [5:0] tile_y,
	
	input [31:0] vert_a_z,
	input [31:0] vert_b_z,
	input [31:0] vert_c_z,
	input [31:0] vert_d_z,

	input [31:0] poly_addr,
	
	input z_clear,
	input tag_clear,
	
	input tag_poly,
	output tag_done,
	
	output reg tag_vram_rd,
	output reg tag_vram_wr,
	output reg [23:0] tag_vram_addr,
	input [31:0] tag_vram_din
);


reg [31:0] z_buf [0:1023];
reg [31:0] tag_buf [0:1023];

reg [7:0] tag_state;
reg [9:0] cnt;

reg do_z_clear;
reg do_tag_clear;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	tag_state <= 8'd0;
	do_z_clear <= 1'b0;
	do_tag_clear <= 1'b0;
end
else begin


	case (tag_state)
		0: begin
			if (clear_z | clear_tag) begin
				cnt <= 10'd1023;
				if (z_clear) do_z_clear <= 1'b1;
				if (tag_clear) do_tag_clear <= 1'b1;
				tag_state <= tag_state + 8'd1;
			end
			else if (tag_poly) tag_state <= 8'd2;
		end
		
		1: begin
			if (cnt>0) begin
				if (do_z_clear)     z_buf[ cnt ] <= 32'h00000000;
				if (do_tag_clear) tag_buf[ cnt ] <= 32'h00000000;
				cnt <= cnt - 10'd1;
			end
			else begin
				
				tag_state <= 8'd0;
			end
		end
		
		2: begin
		
			tag_state <= tag_state + 8'd1;
		end
		
		default: ;
	endcase
end



endmodule
