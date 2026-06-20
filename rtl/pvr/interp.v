`timescale 1ns / 1ps
`default_nettype none

module interp #(
	parameter PIXEL_CENTER_SAMPLE = 1'b1,
	parameter [7:0] FRAC_BITS = 8'd12,			// Q format for XY coordinates (e.g., Q21.11)
	parameter [7:0] Z_FRAC_BITS = 8'd17,		// Q format for Z values (e.g., Q20.12)
	parameter [7:0] FRAC_DIFF = Z_FRAC_BITS - FRAC_BITS
) (
	input clock,

	input signed [47:0] FY2_sub_FY1,
	input signed [47:0] FY3_sub_FY1,
	input signed [47:0] FX2_sub_FX1,
	input signed [47:0] FX3_sub_FX1,
	input signed [47:0] FX1,     		// X coordinate
	input signed [47:0] FY1,     		// Y coordinate

	input signed [63:0] BIG_C,

	input signed [47:0] FZ1,     // Z or attribute value
	input signed [47:0] FZ2,
	input signed [47:0] FZ3,

	input signed [10:0] x_ps,
	input signed [10:0] y_ps,

	output reg signed [47:0] FDDX,		// Works OK as 32-bit?
	output reg signed [47:0] FDDY,
	output reg signed [47:0] small_c,

	output reg signed [47:0] interp,	// Single output.

	output reg signed [47:0] interp_cols [0:31]
);

wire signed [11:0] x_ps_signed = x_ps;
wire signed [11:0] y_ps_signed = y_ps;
wire signed [47:0] pixel_sample_offset = (PIXEL_CENTER_SAMPLE && (FRAC_BITS != 8'd0)) ? (48'sd1 <<< (FRAC_BITS - 8'd1)) : 48'sd0;
wire signed [47:0] x_ps_fixed = ($signed({{36{x_ps_signed[11]}}, x_ps_signed}) <<< FRAC_BITS) + pixel_sample_offset;
wire signed [47:0] y_ps_fixed = ($signed({{36{y_ps_signed[11]}}, y_ps_signed}) <<< FRAC_BITS) + pixel_sample_offset;

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
reg signed [47:0] FZ2_sub_FZ1;
reg signed [47:0] FZ3_sub_FZ1;
reg signed [55:0] Aa_mult_1;	// Needs to be wider than 48-bit.
reg signed [55:0] Aa_mult_2;	// Needs to be wider than 48-bit.
reg signed [47:0] Aa;			// This might need to be > 48-bit, to get the Daytona logos to render correctly.
										// But will then use a LOT of logic, for the divide.

// Ba = (FX3 - FX1) * (FZ2 - FZ1) - (FX2 - FX1) * (FZ3 - FZ1);
reg signed [55:0] Ba_mult_1;	// Needs to be wider than 48-bit.
reg signed [55:0] Ba_mult_2;	// Needs to be wider than 48-bit.
reg signed [47:0] Ba;			// This might need to be > 48-bit, to get the Daytona logos to render correctly.
										// But will then use a LOT of logic, for the divide.

// C = (FX2 - FX1) * (FY3 - FY1) - (FX3 - FX1) * (FY2 - FY1);
wire signed [47:0] FY2_sub_FY1_z = FY2_sub_FY1 <<<FRAC_DIFF;
wire signed [47:0] FY3_sub_FY1_z = FY3_sub_FY1 <<<FRAC_DIFF;
wire signed [47:0] FX2_sub_FX1_z = FX2_sub_FX1 <<<FRAC_DIFF;
wire signed [47:0] FX3_sub_FX1_z = FX3_sub_FX1 <<<FRAC_DIFF;

wire signed [47:0] FX1_z = FX1 <<<FRAC_DIFF; 
wire signed [47:0] FY1_z = FY1 <<<FRAC_DIFF; 

// ddx = Aa / C;
// ddy = Ba / C;
//reg signed [31:0] FDDX;		// Works OK as 32-bit?
//reg signed [31:0] FDDY;

// c = (FZ1 - ddx * FX1 - ddy * FY1);
reg signed [47:0] FDDX_mult_FX1;	// Can work as 48-bit?
reg signed [47:0] FDDY_mult_FY1;

// Choose a dynamic shift that preserves precision but avoids overflow on (Aa << num_shift) / BIG_C.
function automatic [5:0] msb_index64;
    input [63:0] v;
    integer i;
    reg found;
begin
    msb_index64 = 6'd0;
    found = 1'b0;
    for (i = 63; i >= 0; i = i - 1) begin
        if (!found && v[i]) begin
            msb_index64 = i[5:0];
            found = 1'b1;
        end
    end
end
endfunction

wire [47:0] abs_aa = Aa[47] ? (~Aa + 1'b1) : Aa;
wire [47:0] abs_ba = Ba[47] ? (~Ba + 1'b1) : Ba;
wire [47:0] abs_max = (abs_aa > abs_ba) ? abs_aa : abs_ba;
wire [5:0]  abs_msb = msb_index64(abs_max);

// Max left shift to keep numerator within signed 64-bit range.
wire [7:0] shift_allow = (abs_max == 64'd0) ? Z_FRAC_BITS :
                         (abs_msb >= 6'd62) ? 8'd0 : (8'd62 - {2'b00, abs_msb});

wire [7:0] num_shift = (Z_FRAC_BITS < shift_allow) ? Z_FRAC_BITS : shift_allow;

// Adjust back to original scale
wire signed [47:0] FDDX_adj = FDDX <<<(Z_FRAC_BITS - num_shift);
wire signed [47:0] FDDY_adj = FDDY <<<(Z_FRAC_BITS - num_shift);

wire signed [47:0] dy_fp = y_ps_fixed - FY1;
wire signed [47:0] z_dy = (dy_fp * FDDY_adj) >>>FRAC_BITS;

// Base X for column 0 and column 16 (in fixed-point)
wire signed [47:0] x0_fp  = (($signed({{37{x_ps_signed[11]}}, {x_ps_signed[10:5],5'd0}})  <<< FRAC_BITS) + pixel_sample_offset) - FX1;
wire signed [47:0] x16_fp = (($signed({{37{x_ps_signed[11]}}, {x_ps_signed[10:5],5'd16}}) <<< FRAC_BITS) + pixel_sample_offset) - FX1;

wire signed [47:0] z_dx0  = (x0_fp  * FDDX_adj) >>>FRAC_BITS;
wire signed [47:0] z_dx16 = (x16_fp * FDDX_adj) >>>FRAC_BITS;

wire signed [47:0] interp0_wide  = FZ1 + z_dx0  + z_dy;
wire signed [47:0] interp16_wide = FZ1 + z_dx16 + z_dy;

// Compute Aa/Ba without referencing num_shift to avoid combinational loops.
always @(*) begin
	// Aa = (FZ3 - FZ1) * (FY2 - FY1) - (FZ2 - FZ1) * (FY3 - FY1);
	FZ2_sub_FZ1 = (FZ2 - FZ1);
	FZ3_sub_FZ1 = (FZ3 - FZ1);
	Aa_mult_1   = (FZ3_sub_FZ1 * FY2_sub_FY1_z);
	Aa_mult_2   = (FZ2_sub_FZ1 * FY3_sub_FY1_z);
	Aa = (Aa_mult_1 - Aa_mult_2) >>>Z_FRAC_BITS;

	// Ba = (FX3 - FX1) * (FZ2 - FZ1) - (FX2 - FX1) * (FZ3 - FZ1);
	Ba_mult_1   = (FX3_sub_FX1_z * FZ2_sub_FZ1);
	Ba_mult_2   = (FX2_sub_FX1_z * FZ3_sub_FZ1);
	Ba = (Ba_mult_1 - Ba_mult_2) >>>Z_FRAC_BITS;
end

// Might need to keep this as clocked, when doing immediate rendering.
// Works better for deferred (prim Tag) rendering when using always @(*)...
always @(*) begin
	// ddx = Aa / C;
	// ddy = Ba / C;
	// Note: We need to align the fractional bits between numerator and denominator
	//FDDX = (BIG_C==0) ? 0 : ((Aa <<<Z_FRAC_BITS) / BIG_C);
	//FDDY = (BIG_C==0) ? 0 : ((Ba <<<Z_FRAC_BITS) / BIG_C);
	FDDX = (BIG_C==0) ? 0 : ((Aa <<<num_shift) / BIG_C);
	FDDY = (BIG_C==0) ? 0 : ((Ba <<<num_shift) / BIG_C);
	
	//if (BIG_C != 0 && (FDDX == 0) && (Aa != 0)) $display("Precision loss: Aa=%0d BIG_C=%0d", Aa, BIG_C);
	
	// c = (FZ1 - ddx * FX1 - ddy * FY1);
    FDDX_mult_FX1 = (FDDX_adj * FX1_z) >>>Z_FRAC_BITS;
    FDDY_mult_FY1 = (FDDY_adj * FY1_z) >>>Z_FRAC_BITS;
	//small_c = FZ1 - FDDX_mult_FX1 - FDDY_mult_FY1;
	small_c = sat_add48( sat_add48(FZ1, -FDDX_mult_FX1), -FDDY_mult_FY1 );
	
	// Interp ("IP" in C-code PlaneStepper3)...
	// (x * ddx) + (y * ddy) + c;
	//
	// No need to shift the result right, as x_ps and y_ps are not fixed-point...
	//interp = sat_add48( sat_add48((x_ps_signed<<<FRAC_BITS) * FDDX_adj, (y_ps_signed<<<FRAC_BITS) * FDDY_adj), small_c);
	interp = sat_add48( sat_add48((x_ps_fixed * FDDX_adj) >>>FRAC_BITS, (y_ps_fixed * FDDY_adj) >>>FRAC_BITS), small_c);

	// Clamp interp0
	if (interp0_wide > 48'sh7FFF_FFFF_FFFF) interp_cols[0] = 48'sh7FFF_FFFF_FFFF;
	else if (interp0_wide < 48'sh8000_0000_0000) interp_cols[0] = 48'sh8000_0000_0000;
	else interp_cols[0] = interp0_wide[47:0];

    //interp_cols[0] = ({x_ps_signed[11:5],5'd0} * FDDX_adj) + (y_ps_signed * FDDY_adj) + small_c;	// Calc for first COLUMN (pixel) only.
    interp_cols[1]  = sat_add48(interp_cols[0],  FDDX_adj);											// Add X Delta for the rest of the Columns.
    interp_cols[2]  = sat_add48(interp_cols[1] , FDDX_adj);
    interp_cols[3]  = sat_add48(interp_cols[2] , FDDX_adj);
    interp_cols[4]  = sat_add48(interp_cols[3] , FDDX_adj);
    interp_cols[5]  = sat_add48(interp_cols[4] , FDDX_adj);
    interp_cols[6]  = sat_add48(interp_cols[5] , FDDX_adj);
    interp_cols[7]  = sat_add48(interp_cols[6] , FDDX_adj);
    interp_cols[8]  = sat_add48(interp_cols[7] , FDDX_adj);
    interp_cols[9]  = sat_add48(interp_cols[8] , FDDX_adj);
    interp_cols[10] = sat_add48(interp_cols[9] , FDDX_adj);
    interp_cols[11] = sat_add48(interp_cols[10], FDDX_adj);
    interp_cols[12] = sat_add48(interp_cols[11], FDDX_adj);
    interp_cols[13] = sat_add48(interp_cols[12], FDDX_adj);
    interp_cols[14] = sat_add48(interp_cols[13], FDDX_adj);
    interp_cols[15] = sat_add48(interp_cols[14], FDDX_adj);

	// Clamp interp16
	if (interp16_wide > 48'sh7FFF_FFFF_FFFF) interp_cols[16] = 48'sh7FFF_FFFF_FFFF;
	else if (interp16_wide < 48'sh8000_0000_0000) interp_cols[16] = 48'sh8000_0000_0000;
	else interp_cols[16] = interp16_wide[47:0];
	
    //interp_cols[16] = ({x_ps_signed[11:5],5'd16} * FDDX_adj) + (y_ps_signed * FDDY_adj) + small_c;
    interp_cols[17] = sat_add48(interp_cols[16], FDDX_adj);
    interp_cols[18] = sat_add48(interp_cols[17], FDDX_adj);
    interp_cols[19] = sat_add48(interp_cols[18], FDDX_adj);
    interp_cols[20] = sat_add48(interp_cols[19], FDDX_adj);
    interp_cols[21] = sat_add48(interp_cols[20], FDDX_adj);
    interp_cols[22] = sat_add48(interp_cols[21], FDDX_adj);
    interp_cols[23] = sat_add48(interp_cols[22], FDDX_adj);
    interp_cols[24] = sat_add48(interp_cols[23], FDDX_adj);
    interp_cols[25] = sat_add48(interp_cols[24], FDDX_adj);
    interp_cols[26] = sat_add48(interp_cols[25], FDDX_adj);
    interp_cols[27] = sat_add48(interp_cols[26], FDDX_adj);
    interp_cols[28] = sat_add48(interp_cols[27], FDDX_adj);
    interp_cols[29] = sat_add48(interp_cols[28], FDDX_adj);
    interp_cols[30] = sat_add48(interp_cols[29], FDDX_adj);
    interp_cols[31] = sat_add48(interp_cols[30], FDDX_adj);
end

endmodule

function automatic signed [47:0] sat_add48;
    input signed [47:0] a, b;
    reg signed [48:0] s;
begin
    s = a + b;
    if (s[48] != s[47])
        sat_add48 = s[48] ? 48'sh8000_0000_0000 : 48'sh7FFF_FFFF_FFFF;
    else
        sat_add48 = s[47:0];
end
endfunction

function automatic signed [47:0] sat_mul11x48;
    input signed [11:0] a;
    input signed [47:0] b;
    reg signed [59:0] p;
begin
    p = a * b;
    if (|p[59:48] && ~&p[59:48])
        sat_mul11x48 = p[59] ? 48'sh8000_0000_0000 : 48'sh7FFF_FFFF_FFFF;
    else
        sat_mul11x48 = p[47:0];
end
endfunction
