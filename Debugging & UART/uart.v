`default_nettype none

module uart
#(
    parameter DELAY_FRAMES = 234 // 27 mHz, 115200 bits per second is the default baud rate
// DELAY_FRAMES is the number of clock pulses required to reach the desired baud rate
// 27 mHz / 115200 bits per second = 
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

endmodule

