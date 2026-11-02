`timescale 1ns/1ps
//======================================================================================================
// edge_algo_2px.v - Sobel / Canny edge stage, 2 pixels per clock, fully pipelined, CONSTANT LATENCY.
//
//   gray -> Gaussian -> 3x3 window -> Sobel (|Gx|+|Gy|, direction) -> NMS -> double threshold + linking
//
//   The same chain is used for both algorithms; `algo` only changes what three of the stages compute, never
//   their timing, so the HDMI timing derived from this stream is identical in both modes (no re-lock/black screen):
//     Canny (algo=1): Gaussian smoothing, non-maximum suppression, hysteresis (TH, TH/2) with linking
//     Sobel (algo=0): centre pixel passes the Gaussian stage, NMS passes the raw magnitude, single threshold TH
//   Each stage samples `algo` at the start of its own frame, so a frame is never half Sobel and half Canny.
//======================================================================================================
module edge_algo_2px #(
    parameter integer PAIR_COUNT  = 960,
    parameter integer MAX_LINES   = 1080,
    parameter integer LINE_CYCLES = 1100
)(
    input  wire        clk, rst_n,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [15:0] in_gray2,
    input  wire        algo,                // 0 = Sobel, 1 = Canny
    input  wire [11:0] threshold,
    output wire        out_valid, out_hs, out_vs,
    output wire        edge0, edge1
);
reg vs0_d, a_g;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vs0_d <= 1'b0; a_g <= 1'b0; end
    else begin vs0_d <= in_vs; if (in_vs && !vs0_d) a_g <= algo; end

wire        gv, gh, gs;  wire [15:0] g2;
gaussian3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_gauss (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_gray2(in_gray2), .en(a_g),
    .out_valid(gv), .out_hs(gh), .out_vs(gs), .out_gray2(g2));

wire [71:0] win0, win1;  wire lv, lh, ls;
line_buffer_3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES)) u_win (
    .clk(clk), .rst_n(rst_n), .in_valid(gv), .in_hs(gh), .in_vs(gs), .in_gray2(g2),
    .out_valid(lv), .out_hs(lh), .out_vs(ls), .win0(win0), .win1(win1));
wire [11:0] m0, m1;  wire [1:0] d0, d1;  wire sv, sh, ss;
sobel3x3_2px u_sobel (.clk(clk), .rst_n(rst_n), .in_valid(lv), .in_hs(lh), .in_vs(ls), .win0(win0), .win1(win1),
    .out_valid(sv), .out_hs(sh), .out_vs(ss), .mag0(), .mag1(), .magnitude0(m0), .magnitude1(m1),
    .direction0(d0), .direction1(d1));

reg vs1_d, a_n;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vs1_d <= 1'b0; a_n <= 1'b0; end
    else begin vs1_d <= ss; if (ss && !vs1_d) a_n <= a_g; end
wire nv, nh, ns;  wire [11:0] n0, n1;  wire [1:0] nd0, nd1;
nms3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_nms (
    .clk(clk), .rst_n(rst_n), .in_valid(sv), .in_hs(sh), .in_vs(ss), .in_mag0(m0), .in_mag1(m1), .in_dir0(d0), .in_dir1(d1), .en(a_n),
    .out_valid(nv), .out_hs(nh), .out_vs(ns), .out_mag0(n0), .out_mag1(n1), .out_dir0(nd0), .out_dir1(nd1));

reg vs2_d, a_l;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vs2_d <= 1'b0; a_l <= 1'b0; end
    else begin vs2_d <= ns; if (ns && !vs2_d) a_l <= a_n; end
wire e0, e1;
edge_link_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_link (
    .clk(clk), .rst_n(rst_n), .in_valid(nv), .in_hs(nh), .in_vs(ns), .mag0(n0), .mag1(n1), .threshold(threshold),
    .dir0(nd0), .dir1(nd1), .en(a_l), .out_valid(out_valid), .out_hs(out_hs), .out_vs(out_vs), .edge0(edge0), .edge1(edge1));
endmodule
