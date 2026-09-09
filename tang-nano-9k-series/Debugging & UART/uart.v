`default_nettype none

module uart
#(
    parameter DELAY_FRAMES = 234 // 27 mHz, 115200 bits per second is the default baud rate
// DELAY_FRAMES is the number of clock pulses required to reach the desired baud rate
// 27 mHz / 115200 bits per second ~234
)
(
    input clk,
    input uart_rx,
    output uart_tx,
    output reg [5:0] led,
    input btn1
);

    localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2);
    // used to read in the middle of the data transmission because, if we read at the beginning of the bit pulse,
    // there might be some drifting & we'd have to account for the .375 bits required (since 27 mHz / 115200 is ~234)

    reg [3:0] rxState = 0;
    reg [12:0] rxCounter = 0;
    reg [2:0] rxBitNumber = 0;
    reg [7:0] dataIn = 0;
    reg byteReady;

    // defining the states for the receiver
    localparam RX_STATE_IDLE = 0;
    localparam RX_STATE_START_BIT = 1;
    localparam RX_STATE_READ_WAIT = 2;
    localparam RX_STATE_READ = 3;
    localparam RX_STATE_STOP_BIT = 5;

    // State transition logic for receiver
    always @(posedge clk) begin
        case (rxState)
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

