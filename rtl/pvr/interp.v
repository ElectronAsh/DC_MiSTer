`timescale 1ns / 1ps
`default_nettype none

module interp (
	input clock,

	input [7:0] FRAC_BITS,

	input signed [31:0] FX1,
	input signed [31:0] FX2,
	input signed [31:0] FX3,
	
	input signed [31:0] FY1,
	input signed [31:0] FY2,
	input signed [31:0] FY3,
	
	input signed [31:0] FZ1,
	input signed [31:0] FZ2,
	input signed [31:0] FZ3,
	
	input [10:0] x_ps,
	input [10:0] y_ps,
	
	output reg signed [31:0] interp,
	
	output reg signed [31:0] interp0,  interp1,  interp2,  interp3,  interp4,  interp5,  interp6,  interp7,
	output reg signed [31:0] interp8,  interp9,  interp10, interp11, interp12, interp13, interp14, interp15,
	output reg signed [31:0] interp16, interp17, interp18, interp19, interp20, interp21, interp22, interp23,
	output reg signed [31:0] interp24, interp25, interp26, interp27, interp28, interp29, interp30, interp31
);

/*
struct PlaneStepper3
{
	float ddx, ddy;
	float c;
	
	void Setup(float FX1, float FX2, float FX3, float FY1, float FY2, float FY3, float FZ1, float FZ2, float FZ3)
	{
		float Aa = (FZ3 - FZ1) * (FY2 - FY1) - (FZ2 - FZ1) * (FY3 - FY1);
		float Ba = (FX3 - FX1) * (FZ2 - FZ1) - (FX2 - FX1) * (FZ3 - FZ1);
		float C  = (FX2 - FX1) * (FY3 - FY1) - (FX3 - FX1) * (FY2 - FY1);	// Cross Product?

		ddx = -Aa / C;
		ddy = -Ba / C;
		c = (FZ1 - ddx * FX1 - ddy * FY1);
	}

	__forceinline float Ip(float x, float y) const { return x * ddx + y * ddy + c; }
}
*/

// Setup...
//  Aa = (FZ3 - FZ1) * (FY2 - FY1) - (FZ2 - FZ1) * (FY3 - FY1);
reg signed [31:0] FZ3_sub_FZ1;	// Can work as 32-bit? (if input verts are 32-bit?)
reg signed [31:0] FY2_sub_FY1;
reg signed [31:0] FZ2_sub_FZ1;
reg signed [31:0] FY3_sub_FY1;
reg signed [47:0] Aa_mult_1;	// Works OK as 48-bit?
reg signed [47:0] Aa_mult_2;

reg signed [47:0] Aa;		// This must be > 48-bit, to get the Daytona logos to render correctly.
									// But will then use a LOT of FPGA logic for the divide.

// Ba = (FX3 - FX1) * (FZ2 - FZ1) - (FX2 - FX1) * (FZ3 - FZ1);
reg signed [31:0] FX3_sub_FX1;	// Can work as 32-bit? (if input verts are 32-bit?)
reg signed [31:0] FX2_sub_FX1;
reg signed [47:0] Ba_mult_1;	// Works OK as 48-bit?
reg signed [47:0] Ba_mult_2;

reg signed [47:0] Ba;		// This must be > 48-bit, to get the Daytona logos to render correctly.
									// But will then use a LOT of FPGA logic for the divide.

// C = (FX2 - FX1) * (FY3 - FY1) - (FX3 - FX1) * (FY2 - FY1);
reg signed [63:0] C_mult_1;		// Must be > 48-bit??
reg signed [63:0] C_mult_2;
reg signed [47:0] BIG_C;		// Seems to work best as 48-bit? Investigate value ranges later. ElectronAsh.

// ddx = Aa / C;
// ddy = Ba / C;
reg signed [31:0] FDDX;	// Can work as 32-bit? (if input verts are 32-bit?)
reg signed [31:0] FDDY;

// c = (FZ1 - ddx * FX1 - ddy * FY1);
reg signed [47:0] FDDX_mult_FX1;	// Can work as 48-bit?
reg signed [47:0] FDDY_mult_FY1;

reg signed [31:0] small_c;			// Can work OK as 32-bit?

reg signed [47:0] y_mult_FDDY_plus_c;	// Can work as 48-bit?

always @(posedge clock) begin
//always @(*) begin
	// Aa = (FZ3 - FZ1) * (FY2 - FY1) - (FZ2 - FZ1) * (FY3 - FY1);
	FZ3_sub_FZ1 = (FZ3 - FZ1);
	FY2_sub_FY1 = (FY2 - FY1);
	Aa_mult_1   = (FZ3_sub_FZ1 * FY2_sub_FY1) >>FRAC_BITS;

	FZ2_sub_FZ1 = (FZ2 - FZ1);
	FY3_sub_FY1 = (FY3 - FY1);
	Aa_mult_2   = (FZ2_sub_FZ1 * FY3_sub_FY1) >>FRAC_BITS;
	Aa = Aa_mult_1 - Aa_mult_2;

	// Ba = (FX3 - FX1) * (FZ2 - FZ1) - (FX2 - FX1) * (FZ3 - FZ1);
	FX3_sub_FX1 = (FX3 - FX1);
	Ba_mult_1   = (FX3_sub_FX1 * FZ2_sub_FZ1) >>FRAC_BITS;

	FX2_sub_FX1 = (FX2 - FX1);
	Ba_mult_2   = (FX2_sub_FX1 * FZ3_sub_FZ1) >>FRAC_BITS;
	Ba = Ba_mult_1 - Ba_mult_2;

	// C = (FX2 - FX1) * (FY3 - FY1) - (FX3 - FX1) * (FY2 - FY1);
	C_mult_1 = (FX2_sub_FX1 * FY3_sub_FY1) >>FRAC_BITS;
	C_mult_2 = (FX3_sub_FX1 * FY2_sub_FY1) >>FRAC_BITS;
	BIG_C = C_mult_2 - C_mult_1;  // Swapped the order of subtraction, so we can ditch the neg sign on -C below...

	// ddx = Aa / C;
	// ddy = Ba / C;
	FDDX = (Aa<<FRAC_BITS) / BIG_C;
	FDDY = (Ba<<FRAC_BITS) / BIG_C;
	
	// c = (FZ1 - ddx * FX1 - ddy * FY1);
	FDDX_mult_FX1 = (FDDX * FX1) >>FRAC_BITS;
	FDDY_mult_FY1 = (FDDY * FY1) >>FRAC_BITS;
	small_c = FZ1 - FDDX_mult_FX1 - FDDY_mult_FY1;
end


always @(*) begin
	y_mult_FDDY_plus_c = (y_ps * FDDY) + small_c;		// TESTING !!

	// Interp ("IP" in C-code PlaneStepper3)...
	// (x * ddx) + (y * ddy) + c;
	//
	// No need to shift the result right, as x_ps and y_ps are not fixed-point...
	interp = (x_ps * FDDX) + y_mult_FDDY_plus_c;
	
	// Use accumulation instead of repeated multiplications.
	interp0  = ({x_ps[10:5],5'd0} * FDDX) + y_mult_FDDY_plus_c;	// Calc for first COLUMN (pixel) only.
	interp1  = interp0  + FDDX;											// Add X Delta for the rest of the Columns.
	interp2  = interp1  + FDDX;
	interp3  = interp2  + FDDX;
	interp4  = interp3  + FDDX;
	interp5  = interp4  + FDDX;
	interp6  = interp5  + FDDX;
	interp7  = interp6  + FDDX;
	interp8  = interp7  + FDDX;
	interp9  = interp8  + FDDX;
	interp10 = interp9  + FDDX;
	interp11 = interp10 + FDDX;
	interp12 = interp11 + FDDX;
	interp13 = interp12 + FDDX;
	interp14 = interp13 + FDDX;
	interp15 = interp14 + FDDX;

	//interp16 = ({x_ps[10:5],5'd16} * FDDX) + y_mult_FDDY_plus_c;
	interp16 = interp15 + FDDX;
	interp17 = interp16 + FDDX;
	interp18 = interp17 + FDDX;
	interp19 = interp18 + FDDX;
	interp20 = interp19 + FDDX;
	interp21 = interp20 + FDDX;
	interp22 = interp21 + FDDX;
	interp23 = interp22 + FDDX;
	interp24 = interp23 + FDDX;
	interp25 = interp24 + FDDX;
	interp26 = interp25 + FDDX;
	interp27 = interp26 + FDDX;
	interp28 = interp27 + FDDX;
	interp29 = interp28 + FDDX;
	interp30 = interp29 + FDDX;
	interp31 = interp30 + FDDX;

	/*
	interp0  = ({x_ps[9:5],5'd00} * FDDX) + y_mult_FDDY_plus_c;
	interp1  = ({x_ps[9:5],5'd01} * FDDX) + y_mult_FDDY_plus_c;
	interp2  = ({x_ps[9:5],5'd02} * FDDX) + y_mult_FDDY_plus_c;
	interp3  = ({x_ps[9:5],5'd03} * FDDX) + y_mult_FDDY_plus_c;
	interp4  = ({x_ps[9:5],5'd04} * FDDX) + y_mult_FDDY_plus_c;
	interp5  = ({x_ps[9:5],5'd05} * FDDX) + y_mult_FDDY_plus_c;
	interp6  = ({x_ps[9:5],5'd06} * FDDX) + y_mult_FDDY_plus_c;
	interp7  = ({x_ps[9:5],5'd07} * FDDX) + y_mult_FDDY_plus_c;
	interp8  = ({x_ps[9:5],5'd08} * FDDX) + y_mult_FDDY_plus_c;
	interp9  = ({x_ps[9:5],5'd09} * FDDX) + y_mult_FDDY_plus_c;
	interp10 = ({x_ps[9:5],5'd10} * FDDX) + y_mult_FDDY_plus_c;
	interp11 = ({x_ps[9:5],5'd11} * FDDX) + y_mult_FDDY_plus_c;
	interp12 = ({x_ps[9:5],5'd12} * FDDX) + y_mult_FDDY_plus_c;
	interp13 = ({x_ps[9:5],5'd13} * FDDX) + y_mult_FDDY_plus_c;
	interp14 = ({x_ps[9:5],5'd14} * FDDX) + y_mult_FDDY_plus_c;
	interp15 = ({x_ps[9:5],5'd15} * FDDX) + y_mult_FDDY_plus_c;
	interp16 = ({x_ps[9:5],5'd16} * FDDX) + y_mult_FDDY_plus_c;
	interp17 = ({x_ps[9:5],5'd17} * FDDX) + y_mult_FDDY_plus_c;
	interp18 = ({x_ps[9:5],5'd18} * FDDX) + y_mult_FDDY_plus_c;
	interp19 = ({x_ps[9:5],5'd19} * FDDX) + y_mult_FDDY_plus_c;
	interp20 = ({x_ps[9:5],5'd20} * FDDX) + y_mult_FDDY_plus_c;
	interp21 = ({x_ps[9:5],5'd21} * FDDX) + y_mult_FDDY_plus_c;
	interp22 = ({x_ps[9:5],5'd22} * FDDX) + y_mult_FDDY_plus_c;
	interp23 = ({x_ps[9:5],5'd23} * FDDX) + y_mult_FDDY_plus_c;
	interp24 = ({x_ps[9:5],5'd24} * FDDX) + y_mult_FDDY_plus_c;
	interp25 = ({x_ps[9:5],5'd25} * FDDX) + y_mult_FDDY_plus_c;
	interp26 = ({x_ps[9:5],5'd26} * FDDX) + y_mult_FDDY_plus_c;
	interp27 = ({x_ps[9:5],5'd27} * FDDX) + y_mult_FDDY_plus_c;
	interp28 = ({x_ps[9:5],5'd28} * FDDX) + y_mult_FDDY_plus_c;
	interp29 = ({x_ps[9:5],5'd29} * FDDX) + y_mult_FDDY_plus_c;
	interp30 = ({x_ps[9:5],5'd30} * FDDX) + y_mult_FDDY_plus_c;
	interp31 = ({x_ps[9:5],5'd31} * FDDX) + y_mult_FDDY_plus_c;
	*/
end


endmodule
