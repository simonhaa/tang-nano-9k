`default_nettype none

// Simple UART
// Receives an incoming 8 bits and checks two of the following:
//  - a specific pattern is detected
//  - odd parity is satisfied
// Transmits a fixed 4-byte message stored in 'testMemory' once btn1 is pressed
// 1 parity bit
// Board: Xilinx Nexsys A7

module uart
    
#(
    parameter DELAY_FRAMES = 868;
    // Clock speed / baud rate: 100 MHz / 115200 bits per second
)
(
    input clk,
    input uart_rx,
    output uart_tx,
    output reg [5:0] led,
    input btn1
);

    localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2);

    reg [3:0] rxState = 0;              // Current state of the RX state machine
    reg [12:0] rxCounter = 0;           // Counts clock cycles within the current bit period
    reg [2:0] rxBitNumber = 0;          // Which data bit (0-7) is currently being received
    reg [8:0] dataIn = 0;               // Shift register that accumulates the incoming byte
                                        // 9 total bits = 8 data bits + 1 parity bit
    reg byteReady;                      // Pulses/holds high for one cycle when a full byte has arrived
    reg paritySatisfied;                // Pulses/holds high for one cycle when parity (odd) is satisfied

    // RX state machine states
    localparam RX_STATE_IDLE = 0;       // Waiting for the start bit (line goes low)
    localparam RX_STATE_START_BIT = 1;  // Confirming the start bit, waiting to reach bit-middle
    localparam RX_STATE_READ_WAIT = 2;  // Waiting out the rest of a bit period before sampling
    localparam RX_STATE_READ = 3;       // Sampling the current data bit
    localparam RX_STATE_STOP_BIT = 4;   // Waiting out the stop bit period

    // State transition logic for receiver
    always @(posedge clk) begin
        case (rxState)
            // Idle: watches the RX line. UART idles high, so a transitions to 0 should signal the start bit.
            RX_STATE_IDLE: begin
                if (uart_rx == 0) begin // active-low, so waiting for it to be pulled low to begin
                    rxState <= RX_STATE_START_BIT;
                    rxCounter <= 1; // includes the current clock pulse 
                    rxBitNumber <= 0;
                    byteReady <= 0;
                end
            end
            RX_STATE_START_BIT: begin
                if (rxCounter == HALF_DELAY_WAIT) begin // initially waits half a bit frame in order to be in the middle
                    rxState <= RX_STATE_READ_WAIT;
                    rxCounter <= 1; // includes current clock pulse
                end else
                    rxCounter <= rxCounter + 1;
            end
            RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin // will be in the middle of the signal when it is read
                rxState <= RX_STATE_READ;
                end
            end
            RX_STATE_READ: begin
                rxCounter <= 1;
                dataIn <= {uart_rx, dataIn[7:0]}; // right shift --> MSB first
                rxBitNumber <= rxBitNumber + 1; // keeps track of how many bits we've read
                if (rxBitNumber == 3'b111)
                    rxState <= RX_STATE_STOP_BIT ? paritySatisfied : RX_STATE_IDLE;
                else
                    rxState <= RX_STATE_READ_WAIT;
            end
            RX_STATE_STOP_BIT: begin
                rxCounter <= rxCounter + 1;
                if ((rxCounter + 1) == DELAY_FRAMES) begin
                    rxState <= RX_STATE_IDLE;
                    rxCounter <= 0;
                    byteReady <= 1;
                end
            end
        endcase
    end

endmodule

module parity (

);

endmodule
