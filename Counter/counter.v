module top (
    input clk,
    output [5:0] led );
// Crystal oscillater moves at 27 mHz
localparam WAIT_TIME = 13500000; // led counter counts every half second (13,500,000)
reg [5:0] ledCounter = 0;
reg [23:0] clockCounter = 0;

always @(posedge clk) begin
    clockCounter <= clockCounter + 1'b1;
    if (clockCounter == WAIT_TIME) begin
        clockCounter <= 0;
        ledCounter <= ledCounter + 1;
    end
end

assign led = ~ledCounter;

endmodule