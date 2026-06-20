`timescale 1ns / 1ps
`default_nettype none

module float_to_fixed #(
    parameter [7:0] FRAC_BITS = 8'd12
) (
    input  wire [31:0] float_in,
    output reg  signed [47:0] fixed
);

//localparam signed [47:0] FIXED_MAX =  48'sh7FFF_FFFF_FFFF;
//localparam signed [47:0] FIXED_MIN = -48'sh7FFF_FFFF_FFFF; // note: symmetric

// Fix...
localparam signed [47:0] FIXED_MAX =  48'sh7FFF_FFFF_FFFF;
localparam signed [47:0] FIXED_MIN = -48'sh8000_0000_0000;

wire sign        = float_in[31];
wire [7:0] exp   = float_in[30:23];
wire [22:0] frac = float_in[22:0];

wire [23:0] mantissa = {1'b1, frac};

integer shift_amt;
reg [63:0] mag;        // magnitude only (ALWAYS positive)
reg [63:0] scaled;

always @* begin
	fixed     = 0;
	mag       = 0;
	scaled    = 0;
	shift_amt = 0;

	// NaN / Inf
	if (exp == 8'hFF) begin
		fixed = sign ? FIXED_MIN : FIXED_MAX;
	end
	// Zero / denormal
	else if (exp == 0) begin
		fixed = 0;
	end
	else begin
		shift_amt = exp - 127;

		// magnitude = mantissa * 2^FRAC_BITS
		mag = mantissa;
		mag = mag << FRAC_BITS;

		// apply exponent scaling (truncate only)
		if (shift_amt > 31)
			mag = mag << 31;
		else if (shift_amt < -31)
			mag = mag >> 31;
		else if (shift_amt > 0)
			mag = mag << shift_amt;
		else
			mag = mag >> -shift_amt;

		// remove mantissa fractional bits
		mag = mag >> 23;

		// saturate on magnitude
		if (mag > FIXED_MAX)
			fixed = sign ? FIXED_MIN : FIXED_MAX;
		else
			fixed = sign ? -mag[47:0] : mag[47:0];
	end
end

endmodule
