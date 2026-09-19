`default_nettype none
// -----------------------------------------------------------------------
// Simple UART (Universal Asynchronous Receiver/Transmitter)
//
// - Receives 8-bit bytes over `uart_rx` and displays the low 6 bits on
//   `led` (active-low LEDs, since the value is inverted before driving).
// - Transmits a fixed 12-byte message stored in `testMemory` over
//   `uart_tx` whenever `btn1` is pressed.
// - No parity bit, 1 start bit, 1 stop bit (standard 8N1 framing).
// -----------------------------------------------------------------------
module uart
#(
    // Number of clock cycles that make up one UART bit period
    // At a 27 MHz clock and 115200 baud: 27,000,000 / 115,200 = ~234
    parameter DELAY_FRAMES = 234
)
(
    input clk, // System clock of the board (27 MHz)
    input uart_rx, // Serial data in (idle high, active low)
    output uart_tx, // Serial data out
    output reg [5:0] led, // 6 LEDs, driven active-low from received byte
    input btn1 // Push button (active low) transmission trigger
);

    // Half of one bit period. Used so that, after detecting the falling start-bit edge,
    // we wait to the *middle* of the following bits before sampling them. Sampling in the middle
    // avoid errors from clock drift near bit edges
    localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2);

    // RECEIVER STATE
    reg [3:0] rxState = 0;              // Current state of the RX state machine
    reg [12:0] rxCounter = 0;           // Counts clock cycles within the current bit period
    reg [2:0] rxBitNumber = 0;          // Which data bit (0-7) is currently being received
    reg [7:0] dataIn = 0;               // Shift register that accumulates the incoming byte
    reg byteReady;                      // Pulses/holds high for one cycle when a full byte has arrived

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
                if (uart_rx == 0) begin
                    rxState <= RX_STATE_START_BIT;
                    rxCounter <= 1; // count this clock edge as cycle 1 
                    rxBitNumber <= 0;
                    byteReady <= 0; // clears any previous 'byte ready' flag
                end
            end

            // Start bit: waits until we're halfway through the start bit period.
            // Lands us in the middle of the next bit (bit 0), keeping every subsequent sample centered on its bit
            RX_STATE_START_BIT: begin
                if (rxCounter == HALF_DELAY_WAIT) begin
                    rxState <= RX_STATE_READ_WAIT;
                    rxCounter <= 1; // counts this clock edge as cycle 1
                end else
                    rxCounter <= rxCounter + 1;
            end

            // Read wait: count out the remainder of a full bit period so that, combined with the half delay,
            // we land in the middle of the current data bit before sampling
            RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin // will be in the middle of the signal when it is read
                rxState <= RX_STATE_READ;
                end
            end

            // Read: sample the RX line now
            // Shifts it into dataIn
            // Right shift makes it so that when we begin inserting at the MSB position, the first bit ends at the LSB position
            // Successive bits shift previous data down, reconstructing the byte MSB-first as bits arrive LSB-first
            RX_STATE_READ: begin
                rxCounter <= 1;
                dataIn <= {uart_rx, dataIn[7:0]};
                rxBitNumber <= rxBitNumber + 1;
                if (rxBitNumber == 3'b111)
                    rxState <= RX_STATE_STOP_BIT; // all 8 bits have been received, so we can move to the stop bit state
                else
                    rxState <= RX_STATE_READ_WAIT; // otherwise, wait out the rest of the bit period before sampling the next bit
            end

            // Stop bit: wait out one more bit period, then declare byteReady and return to idle to wait for the next stop bit
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

    // When a byte is ready, latch the lower 6 bits into the LED register, inverting them to drive the active-low LEDs
    // Inverted because the LEDs are wired active-low: a 1 in the register turns the LED off, and a 0 turns it on
    always @(posedge clk) begin
        if (byteReady) begin
            led <= ~dataIn[5:0];
        end
    end

    // TRANSMITTER STATE
    reg [3:0] txState = 0;              // Current state of the TX state machine
    reg [24:0] txCounter = 0;           // Counts clock cycles within the current bit period / debounce wait
    reg [7:0] dataOut = 0;              // Byte currently being shifted out
    reg txPinRegister = 1;              // Drives uart_tx; idles high per UART convention
    reg [2:0] txBitNumber = 0;          // Which data bit (0--7) is currently being transmitted
    reg [3:0] txByteCounter = 0;        // Index of the current byte within testMemory

    assign uart_tx = txPinRegister;

    // Message to transmit, stored as a small ROM-like memory: one byte per character,
    // sent out in order each time the button is pressed
    localparam MEMORY_LENGTH = 12;
    reg [7:0] testMemory [MEMORY_LENGTH-1:0]; // defines a memory of 12 bytes, each 8 bits wide

    initial begin
        testMemory[0] = "L";
        testMemory[1] = "u";
        testMemory[2] = "s";
        testMemory[3] = "h";
        testMemory[4] = "a";
        testMemory[5] = "y";
        testMemory[6] = " ";
        testMemory[7] = "L";
        testMemory[8] = "a";
        testMemory[9] = "b";
        testMemory[10] = "s";
        testMemory[10] = " ";
    end

    // TX state machine states          
    localparam TX_STATE_IDLE = 0;       // Waiting for button press
    localparam TX_STATE_START_BIT = 1;  // Driving the start bit (line low)
    localparam TX_STATE_WRITE = 2;      // Shifting out the 8 data bits
    localparam TX_STATE_STOP_BIT = 3;   // Driving the stop bit (line high)
    localparam TX_STATE_DEBOUNCE = 4;   // Post-transmission delay + button-release check

    // State transition logic for transmitter
    always @(posedge clk) begin
        case (txState)

            // Idle: line stays high (idle) until the button is pressed (active low)
            // When pressed, start sending from the first byte in testMemory, and reset the counters
            TX_STATE_IDLE: begin
                if (btn1 == 0) begin // waits for the button to be pressed (active low)
                    txState <= TX_STATE_START_BIT;
                    txCounter <= 0;
                    txByteCounter <= 0;
                end else
                    txPinRegister <= 1;
            end

            // Start bit: pulls the line low for one full bit period, then load the next
            // byte to send from memory and resets the bit index
            TX_STATE_START_BIT: begin
                txPinRegister <= 0;
                if ((txCounter + 1) == DELAY FRAMES) begin
                    txState <= TX_STATE_WRITE;
                    dataOut <= testMemory[txByteCounter]; // loads the current byte to be sent into the shift register
                    txBitNumber <= 0; // resets the bit counter to start sending the first bit of the byte
                    txCounter <= 0;
                end else
                    txCounter <= txCounter + 1;
            end

            // Write: drive each data bit (LSB first, standard UART order)
            // for one full bit period each, then advence to the next bit or,
            // once all 8 bits are sent, move on to the stop bit state
            TX_STATE_WRITE: begin
                txPinRegister <= dataOut[txBitNumber]; // sends the current bit of the byte, LSB first
                if ((txCounter + 1) == DELAY_FRAMES) begin
                    // checks if we're on the last bit --> stop
                    // else, increments the bit number and keeps the current state
                    if (txBitNumber == 3'b111) begin
                        txState <= TX_STATE_STOP_BIT;
                    end else begin
                        txState <= TX_STATE_WRITE;
                        txBitNumber <= txBitNumber + 1;
                    end
                    txCounter <= 0;
                end else 
                    txCounter <= txCounter + 1;
            end

            // Stop bit: drive the line high for one full bit period. Once done,
            // either move onto the next byte in memory, or, if this was the last byte,
            // go wait in the debounce state
            TX_STATE_STOP_BIT: begin
                txPinRegister <= 1;
                if ((txCounter + 1) == DELAY_FRAMES) begin
                    if (txByteCounter == MEMORY_LENGTH - 1) begin
                        txState <= TX_STATE_DEBOUNCE;
                    end else begin
                        txByteCounter <= txByteCounter + 1;
                        txState <= TX_STATE_START_BIT;
                    end
                    txCounter <= 0;
                end else 
                    txCounter <= txCounter + 1;
            end

            // Debounce: after finishing transmission, wait a long fixed delay (2^23-1 cyles)
            // to avoid re-triggering on switch bounce (rapidly opens/closes several times when pressed or released),
            // then require the button to be released (btn == 1, i.e. not pressed) before
            // returning to idle. This guarantees exactly one transmission per physical button press
            TX_STATE_DEBOUNCE: begin
                if (txCounter == 23'b111111111111111111111) begin // correction: original literal had only 21 ones for a 23-bit constant; corrected to 23 bits
                    if (btn1 == 1)
                        txState <= TX_STATE_IDLE;
                end else
                    txCounter <= txCounter + 1;
            end
        endcase
    end

endmodule