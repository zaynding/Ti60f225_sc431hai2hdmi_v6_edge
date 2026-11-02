`timescale 1ns/1ps

module nms3x3_2px #(
    parameter PAIR_COUNT = 960,
    parameter MAX_LINES = 1080,
    parameter LINE_CYCLES = 1100
)(
    input wire clk, rst_n,
    input wire in_valid, in_hs, in_vs,
    input wire [11:0] in_mag0, in_mag1,
    input wire [1:0] in_dir0, in_dir1,
    output reg out_valid, out_hs, out_vs,
    output reg [11:0] out_mag0, out_mag1,
    output reg [1:0] out_dir0, out_dir1
);

wire valid, hs, vs;
wire [125:0] win0, win1;
line_buffer_3x3_2px_p #(
    .PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES),
    .LINE_CYCLES(LINE_CYCLES), .PIXEL_WIDTH(14)
) u_window (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs),
    .in_gray2({in_dir1, in_mag1, in_dir0, in_mag0}),
    .out_valid(valid), .out_hs(hs), .out_vs(vs), .win0(win0), .win1(win1)
);

function [11:0] suppress;
    input [125:0] w;
    reg [11:0] center, prev_mag, next_mag;
    begin
        center = w[4*14 +: 12];
        case (w[4*14+12 +: 2])
            0: begin prev_mag = w[5*14 +: 12]; next_mag = w[3*14 +: 12]; end
            1: begin prev_mag = w[8*14 +: 12]; next_mag = w[0*14 +: 12]; end
            2: begin prev_mag = w[7*14 +: 12]; next_mag = w[1*14 +: 12]; end
            3: begin prev_mag = w[6*14 +: 12]; next_mag = w[2*14 +: 12]; end
        endcase
        suppress = (center > prev_mag && center >= next_mag) ? center : 12'd0;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid <= 0; out_hs <= 0; out_vs <= 0;
        out_mag0 <= 0; out_mag1 <= 0;
        out_dir0 <= 0; out_dir1 <= 0;
    end else begin
        out_valid <= valid; out_hs <= hs; out_vs <= vs;
        out_mag0 <= suppress(win0);
        out_mag1 <= suppress(win1);
        out_dir0 <= win0[4*14+12 +: 2];
        out_dir1 <= win1[4*14+12 +: 2];
    end
end
endmodule
