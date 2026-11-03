`timescale 1ns/1ps
// Two matching analyses qualify a digit change. Geometry updates immediately
// thereafter; only the answer waits ~0.3 s (18 display frames at 60 Hz).
module digit_result_control #(
    parameter integer STABLE_SAMPLES=2, RESULT_DELAY_FRAMES=18
)(
    input wire clk,rst_n,enable,restart,frame_start,
    input wire det_done,det_found,
    input wire [3:0] det_lhs,
    input wire [4:0] det_result,
    input wire [23:0] det_x0,det_x1,
    input wire [26:0] det_y0,det_y1,
    output reg stable_found,
    output reg [3:0] stable_lhs,
    output reg [4:0] stable_result,
    output reg [23:0] stable_x0,stable_x1,
    output reg [26:0] stable_y0,stable_y1,
    output wire answer_ready
);
localparam CW=(RESULT_DELAY_FRAMES<1) ? 1 : $clog2(RESULT_DELAY_FRAMES+1);
reg [3:0] pending_lhs,timer_lhs;
reg [1:0] samples;
reg [CW-1:0] frames;
assign answer_ready=stable_found && timer_lhs==stable_lhs && frames>=RESULT_DELAY_FRAMES;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stable_found<=0;stable_lhs<=0;stable_result<=0;stable_x0<=0;stable_x1<=0;stable_y0<=0;stable_y1<=0;
        pending_lhs<=0;timer_lhs<=0;samples<=0;frames<=0;
    end else if(!enable || restart) begin
        stable_found<=0;stable_lhs<=0;stable_result<=0;pending_lhs<=0;timer_lhs<=0;samples<=0;frames<=0;
    end else begin
        if(frame_start) begin
            if(!stable_found || timer_lhs!=stable_lhs) begin frames<=0;timer_lhs<=stable_lhs;end
            else if(frames<RESULT_DELAY_FRAMES) frames<=frames+1'b1;
        end
        if(det_done) begin
            if(!det_found) begin
                stable_found<=0;pending_lhs<=0;samples<=0;frames<=0;timer_lhs<=0;
            end else if(samples==0 || pending_lhs!=det_lhs) begin
                pending_lhs<=det_lhs;samples<=1;stable_found<=0;frames<=0;timer_lhs<=0;
            end else begin
                if(samples<STABLE_SAMPLES) samples<=samples+1'b1;
                if(samples>=STABLE_SAMPLES-1) begin
                    stable_found<=1;stable_lhs<=det_lhs;stable_result<=det_result;
                    stable_x0<=det_x0;stable_x1<=det_x1;stable_y0<=det_y0;stable_y1<=det_y1;
                end
            end
        end
    end
end
endmodule
