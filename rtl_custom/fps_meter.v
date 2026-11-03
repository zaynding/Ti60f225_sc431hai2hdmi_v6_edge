`timescale 1ns/1ps
//======================================================================================================
// fps_meter.v - frames per second of (a) the HDMI output stream and (b) the camera, refreshed once a second.
//
//   vs_out  : output vertical sync, video clock domain (one rising edge per displayed frame)
//   cam_tog : toggles once per camera frame; generated in the camera pixel-clock domain, so it is re-synchronised
//             here with two flip-flops (the two clocks are declared asynchronous in the .sdc)
//   Values saturate at 99.  CLK_HZ is the frequency of `clk` (vid_clk_dvi2 = 74.25 MHz).
//======================================================================================================
module fps_meter #(
    parameter integer CLK_HZ = 74250000
)(
    input  wire       clk, rst_n,
    input  wire       vs_out,
    input  wire       cam_tog,
    output reg  [6:0] fps_out, fps_cam
);
reg [26:0] sec;
reg        vs_d, tg1, tg2, tg3;
reg [6:0]  c_out, c_cam;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sec<=0; vs_d<=0; tg1<=0; tg2<=0; tg3<=0; c_out<=0; c_cam<=0; fps_out<=0; fps_cam<=0; end
    else begin
        vs_d <= vs_out; tg1 <= cam_tog; tg2 <= tg1; tg3 <= tg2;
        if (sec == CLK_HZ - 1) begin
            sec <= 0;
            fps_out <= c_out + ((vs_out && !vs_d) ? 7'd1 : 7'd0);
            fps_cam <= c_cam + ((tg2 ^ tg3) ? 7'd1 : 7'd0);
            c_out <= 0; c_cam <= 0;
        end else begin
            sec <= sec + 1'b1;
            if (vs_out && !vs_d && c_out != 7'd99) c_out <= c_out + 1'b1;
            if ((tg2 ^ tg3) && c_cam != 7'd99) c_cam <= c_cam + 1'b1;
        end
    end
end
endmodule
