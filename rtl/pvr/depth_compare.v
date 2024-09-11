module depth_compare (
	input [2:0] depth_comp,
	
	input signed [31:0] old_z,
	input signed [31:0] invW,
	
	output reg depth_allow
);

always @* begin
	case (depth_comp)
		0: depth_allow = 0;						// Never.
		1: depth_allow = (invW <  old_z);	// Less.
		2: depth_allow = (invW == old_z);	// Equal.
		3: depth_allow = (invW <= old_z);	// Less or Equal
		4: depth_allow = (invW >  old_z);	// Greater.
		5: depth_allow = (invW != old_z);	// Not Equal.
		6: depth_allow = (invW >= old_z);	// Greater or Equal.
		7: depth_allow = 1;						// Always
	endcase
end

endmodule
