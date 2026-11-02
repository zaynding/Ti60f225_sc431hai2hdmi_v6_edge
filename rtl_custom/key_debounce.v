`timescale 1ns/1ps

module key_debounce #(
    parameter integer DEBOUNCE_CYCLES = 1485000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  key_press
);

    reg [1:0]  sync_q;
    reg        stable;
    reg        stable_d;
    reg [20:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_q <= 2'b11;
        else
            sync_q <= {sync_q[0], key_n};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable   <= 1'b1;
            stable_d <= 1'b1;
            cnt      <= 21'd0;
            key_press <= 1'b0;
        end
        else begin
            stable_d <= stable;
            key_press <= 1'b0;

            if (sync_q[1] == stable) begin
                cnt <= 21'd0;
            end
            else begin
                if (cnt == DEBOUNCE_CYCLES - 1) begin
                    stable <= sync_q[1];
                    cnt    <= 21'd0;
                end
                else begin
                    cnt <= cnt + 21'd1;
                end
            end

            // Active-low key: falling edge after debounce means press.
            if (stable_d && !stable)
                key_press <= 1'b1;
        end
    end

endmodule
