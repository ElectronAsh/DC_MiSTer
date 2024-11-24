`timescale 1ns / 1ps
`default_nettype none

module z_buffer (
	input clock,
	input reset_n,
	
	input clear_z,
	input clear_z_pix,
	output reg clear_done,
	
	input [9:0] z_buff_addr,
	input [31:0] z_in,
	input z_write_disable,
	
	output [31:0] z_out,
	
	input inTriangle,
	
	input [2:0] type_cnt,	// From the RA. 0=Opaque, 1=Opaque Mod, 2=Trans, 3=Trans mod, 4=PunchThrough.
	input [2:0] depth_comp,
	output wire depth_allow
);

reg clear_pend;
reg [9:0] clear_cnt;
reg [31:0] z_buffer [0:1023];

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	clear_pend <= 1'b0;
	clear_done <= 1'b0;
end
else begin
	clear_done <= 1'b0;

	if (clear_pend) begin
		z_buffer[ clear_cnt ] <= 32'h00000000;
		clear_cnt <= clear_cnt + 10'd1;
		if (clear_cnt==10'd1023) begin
			clear_done <= 1'b1;
			clear_pend <= 1'b0;
		end
	end
	else begin
		if (clear_z) begin
			clear_cnt <= 10'd0;
			clear_pend <= 1'b1;
		end
		
		if (clear_z_pix) z_buffer[ z_buff_addr ] <= 32'd0;
		else if (inTriangle && depth_allow && !z_write_disable) z_buffer[ z_buff_addr ] <= z_in;
	end
	
	old_z <= z_buffer[ z_buff_addr+1 ];		// TESTING. The +1 is a kludge, to lessen the vertical lines.
end

reg [31:0] old_z;

// From the RA. 0=Opaque, 1=Opaque Mod, 2=Trans, 3=Trans mod, 4=PunchThrough.
wire [2:0] depth_comp_in = (type_cnt==4 || type_cnt==1 || type_cnt==3) ? 3'd6 : (type_cnt==2) ? 3'd3 : depth_comp;

depth_compare depth_compare_inst (
	.depth_comp( depth_comp_in ),	// input [2:0]  depth_comp
	.old_z( old_z ),				// input [31:0]  old_z
	.invW( z_in ),					// input [31:0]  invW
	.depth_allow( depth_allow )		// output depth_allow
);

endmodule
