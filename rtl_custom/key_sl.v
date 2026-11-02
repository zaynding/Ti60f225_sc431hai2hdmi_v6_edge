`timescale 1ns/1ps
// Debounced key (active low) with short / long press detection.
//   short_p : one pulse when released before LONG_CYCLES
//   long_p  : one pulse when held for LONG_CYCLES (the following release produces no short pulse)
module key_sl #(
    parameter integer DEBOUNCE_CYCLES = 1485000,    // 20 ms @ 74.25 MHz
    parameter integer LONG_CYCLES     = 59400000    // 0.8 s
)(
    input  wire clk, rst_n, key_n,
    output reg  short_p, long_p
);
reg [1:0]  sync_q;
reg        stable, stable_d, fired;
reg [20:0] cnt;
reg [26:0] hold;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sync_q<=2'b11; stable<=1'b1; stable_d<=1'b1; cnt<=0; hold<=0; fired<=0; short_p<=0; long_p<=0; end
    else begin
        sync_q <= {sync_q[0], key_n};
        stable_d <= stable; short_p <= 1'b0; long_p <= 1'b0;
        if (sync_q[1] == stable) cnt <= 0;
        else if (cnt == DEBOUNCE_CYCLES - 1) begin stable <= sync_q[1]; cnt <= 0; end
        else cnt <= cnt + 1'b1;
        if (!stable) begin
            if (!fired) begin
                if (hold == LONG_CYCLES - 1) begin long_p <= 1'b1; fired <= 1'b1; end
                else hold <= hold + 1'b1;
            end
        end else begin
            hold <= 0; fired <= 1'b0;
            if (!stable_d) short_p <= !fired;       // release edge
        end
    end
end
endmodule
