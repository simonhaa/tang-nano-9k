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
                    rxState <= RX_STATE_STOP_BIT;
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

    always @(posedge clk) begin
        if (byteReady) begin
            led <= ~dataIn[5:0];
        end
    end

    // data transmission
    reg [3:0] txState = 0;
    reg [24:0] txCounter = 0;
    reg [7:0] dataOut = 0;
    reg txPinRegister = 1;
    reg [2:0] txBitNumber = 0;
    reg [3:0] txByteCounter = 0;

    assign uart_tx = txPinRegister;

    // purpose is to send a message from memory, so we need to keep track of the current byte
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
    // initializes the memory

    // defining the states for the transmitter
    localparam TX_STATE_IDLE = 0;
    localparam TX_STATE_START_BIT = 1;
    localparam TX_STATE_WRITE = 2;
    localparam TX_STATE_STOP_BIT = 3;
    localparam TX_STATE_DEBOUNCE = 4;

    // State transition logic for transmitter
    always @(posedge clk) begin
        case (txState)
            TX_STATE_IDLE: begin
                if (btn1 == 0) begin // waits for the button to be pressed (active low)
                    txState <= TX_STATE_START_BIT;
                    txCounter <= 0;
                    txByteCounter <= 0;
                end else
                    txPinRegister <= 1;
            end
            TX_STATE_START_BIT: begin
                txPinRegister <= 0;
                if ((txCounter + 1) == DELAY FRAMES) begin
                    txState <= TX_STATE_WRITE;
                    dataOut <= testMemory[txByteCounter]; // puts the next byte into dataOut
                    txBitNumber <= 0; // resets to 0
                    txCounter <= 0;
                end else
                    txCounter <= txCounter + 1;
            end
            TX_STATE_WRITE: begin
                txPinRegister <= dataOut[txBitNumber];
                // sets the tx pin to the current bit of the current byte
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
            TX_STATE_STOP_BIT: begin
                txPinRegister <= 1;
                if ((txCounter + 1) == DELAY_FRAMES) begin
                    // after waiting DELAY_FRAMES, checks if there are any other bytes to send
                    // repeats if there are, goes to the debounce state if not
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
            TX_STATE_DEBOUNCE: begin
                if (txCounter == 23'b111111111111111111) begin
                    if (btn1 == 1)
                        txState <= TX_STATE_IDLE;
                end else
                    txCounter <= txCounter + 1;
            end
            // waits a minimum time on top of sending time and makes sure the button is released after this
            // ensures that for each button press, only one transmission event
        endcase
    end

endmodule