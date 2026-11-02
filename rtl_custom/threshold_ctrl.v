`timescale 1ns/1ps
//======================================================================================================
// threshold_ctrl.v - single-button cyclic Sobel threshold control
//
//   KEY1 : decrease the Sobel threshold by STEP (more edges)
//          when THR_MIN is reached, the next press wraps to THR_INIT
//
//   Example with STEP=8, THR_MIN=8, THR_INIT=50:
//       50 -> 42 -> 34 -> 26 -> 18 -> 10 -> 8 -> 50 -> ...
//
//   THR_INIT is the first threshold shown after configuration, i.e. the
//   minimum-edge setting requested for the wrap point.
//======================================================================================================
module threshold_ctrl #(
    parameter integer STEP    = 8,
    parameter integer THR_MIN = 8,
    parameter integer THR_INIT = 50
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_press,
    output reg  [7:0] threshold
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            threshold <= THR_INIT;
        else if (cycle_press) begin
            if (threshold <= THR_MIN)
                threshold <= THR_INIT;
            else if (threshold <= (THR_MIN + STEP))
                threshold <= THR_MIN;
            else
                threshold <= threshold - STEP;
        end
    end

endmodule
