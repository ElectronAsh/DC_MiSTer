module maple_phy
#(
    parameter CLK_HZ     = 100_000_000,
    parameter PHASE_CLKS = 25        // ~250ns @100MHz
)
(
    input  wire clk,
    input  wire reset,

    // Maple pins
    inout  wire maple_a,
    inout  wire maple_b,

    // TX interface
    input  wire        tx_start,
    input  wire [255:0] tx_data,
    input  wire [8:0]  tx_bits,
    output reg         tx_busy,
    output reg         tx_done,

    // RX interface
    output reg         rx_valid,
    output reg [255:0] rx_data,
    output reg [8:0]   rx_bits
);

//////////////////////////////////////////////////////////////////////////
// Open-drain Maple drivers
//////////////////////////////////////////////////////////////////////////

reg maple_a_drive;
reg maple_b_drive;

assign maple_a = maple_a_drive ? 1'b0 : 1'bz;
assign maple_b = maple_b_drive ? 1'b0 : 1'bz;

wire maple_a_in = maple_a;
wire maple_b_in = maple_b;

//////////////////////////////////////////////////////////////////////////
// RX Edge Detector
//////////////////////////////////////////////////////////////////////////

reg a_prev;
reg b_prev;

reg [255:0] rx_shift;
reg [8:0]   rx_count;

always @(posedge clk) begin
    a_prev <= maple_a_in;
    b_prev <= maple_b_in;

    rx_valid <= 0;

    // Falling edge on A
    if(a_prev && !maple_a_in) begin
        rx_shift <= {maple_b_in, rx_shift[255:1]};
        rx_count <= rx_count + 1'd1;
    end

    // Falling edge on B
    else if(b_prev && !maple_b_in) begin
        rx_shift <= {maple_a_in, rx_shift[255:1]};
        rx_count <= rx_count + 1'd1;
    end
end

//////////////////////////////////////////////////////////////////////////
// RX Packet Timeout
//////////////////////////////////////////////////////////////////////////

localparam RX_TIMEOUT = CLK_HZ / 10000; // ~100us

reg [31:0] idle_timer;

always @(posedge clk) begin

    if(reset) begin
        idle_timer <= 0;
        rx_count   <= 0;
    end
    else begin

        if((a_prev && !maple_a_in) ||
           (b_prev && !maple_b_in))
            idle_timer <= 0;
        else
            idle_timer <= idle_timer + 1'd1;

        if(idle_timer == RX_TIMEOUT && rx_count != 0) begin
            rx_data  <= rx_shift;
            rx_bits  <= rx_count;
            rx_valid <= 1;

            rx_count <= 0;
            rx_shift <= 0;
        end
    end
end

//////////////////////////////////////////////////////////////////////////
// TX Engine
//////////////////////////////////////////////////////////////////////////

localparam
    TX_IDLE      = 0,
    TX_SYNC0     = 1,
    TX_SYNC1     = 2,
    TX_SYNC2     = 3,
    TX_SYNC3     = 4,
    TX_SETUP     = 5,
    TX_CLOCK     = 6,
    TX_RELEASE   = 7,
    TX_NEXT      = 8,
    TX_END       = 9;

reg [3:0] state;

reg [31:0] phase_ctr;
reg [255:0] shift_reg;
reg [8:0] bit_count;
reg odd_phase;

wire current_bit = shift_reg[0];

always @(posedge clk) begin

    tx_done <= 0;

    if(reset) begin

        state <= TX_IDLE;

        maple_a_drive <= 0;
        maple_b_drive <= 0;

        tx_busy <= 0;

    end
    else begin

        case(state)

        ////////////////////////////////////////////////////////////////
        // Idle
        ////////////////////////////////////////////////////////////////

        TX_IDLE:
        begin
            maple_a_drive <= 0;
            maple_b_drive <= 0;

            tx_busy <= 0;

            if(tx_start) begin

                shift_reg <= tx_data;
                bit_count <= tx_bits;

                tx_busy <= 1;

                phase_ctr <= 0;

                state <= TX_SYNC0;
            end
        end

        ////////////////////////////////////////////////////////////////
        // Maple start sequence
        ////////////////////////////////////////////////////////////////

        TX_SYNC0:
        begin
            maple_a_drive <= 1;
            maple_b_drive <= 0;

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;
                state <= TX_SYNC1;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_SYNC1:
        begin
            maple_b_drive <= ~maple_b_drive;

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;

                if(maple_b_drive)
                    state <= TX_SYNC2;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_SYNC2:
        begin
            maple_b_drive <= ~maple_b_drive;

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;

                if(maple_b_drive)
                    state <= TX_SYNC3;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_SYNC3:
        begin
            maple_a_drive <= 0;

            odd_phase <= 0;

            phase_ctr <= 0;

            state <= TX_SETUP;
        end

        ////////////////////////////////////////////////////////////////
        // Bit transmission
        ////////////////////////////////////////////////////////////////

        TX_SETUP:
        begin

            if(!odd_phase) begin

                maple_a_drive <= 0;
                maple_b_drive <= !current_bit;

            end
            else begin

                maple_b_drive <= 0;
                maple_a_drive <= !current_bit;

            end

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;
                state <= TX_CLOCK;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_CLOCK:
        begin

            if(!odd_phase)
                maple_a_drive <= 1;
            else
                maple_b_drive <= 1;

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;
                state <= TX_RELEASE;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_RELEASE:
        begin

            if(!odd_phase)
                maple_a_drive <= 0;
            else
                maple_b_drive <= 0;

            if(phase_ctr == PHASE_CLKS) begin
                phase_ctr <= 0;
                state <= TX_NEXT;
            end
            else
                phase_ctr <= phase_ctr + 1'd1;
        end

        TX_NEXT:
        begin

            shift_reg <= shift_reg >> 1;

            bit_count <= bit_count - 1'd1;

            odd_phase <= ~odd_phase;

            if(bit_count == 1)
                state <= TX_END;
            else
                state <= TX_SETUP;
        end

        ////////////////////////////////////////////////////////////////
        // End Of Packet
        ////////////////////////////////////////////////////////////////

        TX_END:
        begin
            maple_a_drive <= 0;
            maple_b_drive <= 0;

            tx_busy <= 0;
            tx_done <= 1;

            state <= TX_IDLE;
        end

        endcase
    end
end

endmodule
