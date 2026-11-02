`timescale 1ns/1ps
//======================================================================================================
// edge_algo_2px.v - Sobel / Canny edge stage, 2 pixels per clock, fully pipelined (no stalls).
//
//   in  : median-filtered gray stream
//   Canny  : 3x3 Gaussian -> 3x3 window -> Sobel (|Gx|+|Gy|, 4 directions) -> NMS thinning
//            -> double threshold (TH, TH/2) with direction-aware linking
//   Sobel  : (Gaussian bypassed) -> 3x3 window -> Sobel -> single threshold
//   Both back ends hang off the same Sobel output and run in parallel every frame; only the Gaussian
//   bypass and the final output multiplexer depend on `algo`.  `algo` is sampled at the start of a frame,
//   so a change of mode never tears a frame (the frame in flight at the switch may be partly wrong).
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
    output reg         out_valid, out_hs, out_vs,
    output reg         edge0, edge1
);
// ---- sample the mode at the frame start of the input stream ----
reg vs_d, algo_g;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vs_d <= 1'b0; algo_g <= 1'b0; end
    else begin vs_d <= in_vs; if (in_vs && !vs_d) algo_g <= algo; end

// ---- Gaussian (always computed, bypassed for Sobel) ----
wire        gv, gh, gs;  wire [15:0] g2;
gaussian3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_gauss (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_gray2(in_gray2),
    .out_valid(gv), .out_hs(gh), .out_vs(gs), .out_gray2(g2));
wire        wv_i = algo_g ? gv : in_valid;
wire        wh_i = algo_g ? gh : in_hs;
wire        ws_i = algo_g ? gs : in_vs;
wire [15:0] wg_i = algo_g ? g2 : in_gray2;

// ---- window + Sobel ----
wire [71:0] win0, win1;  wire lv, lh, ls;
line_buffer_3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES)) u_win (
    .clk(clk), .rst_n(rst_n), .in_valid(wv_i), .in_hs(wh_i), .in_vs(ws_i), .in_gray2(wg_i),
    .out_valid(lv), .out_hs(lh), .out_vs(ls), .win0(win0), .win1(win1));
wire [11:0] m0, m1;  wire [1:0] d0, d1;  wire sv, sh, ss;
sobel3x3_2px u_sobel (.clk(clk), .rst_n(rst_n), .in_valid(lv), .in_hs(lh), .in_vs(ls), .win0(win0), .win1(win1),
    .out_valid(sv), .out_hs(sh), .out_vs(ss), .mag0(), .mag1(), .magnitude0(m0), .magnitude1(m1),
    .direction0(d0), .direction1(d1));

// ---- Sobel back end ----
wire tv, th, ts, te0, te1;
threshold_compare #(.PAIR_COUNT(PAIR_COUNT), .BLANK_PAIRS(2)) u_thr (
    .clk(clk), .rst_n(rst_n), .in_valid(sv), .in_hs(sh), .in_vs(ss), .mag0(m0), .mag1(m1), .threshold(threshold),
    .out_valid(tv), .out_hs(th), .out_vs(ts), .edge0(te0), .edge1(te1));

// ---- Canny back end ----
wire nv, nh, ns;  wire [11:0] n0, n1;  wire [1:0] nd0, nd1;
nms3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_nms (
    .clk(clk), .rst_n(rst_n), .in_valid(sv), .in_hs(sh), .in_vs(ss), .in_mag0(m0), .in_mag1(m1), .in_dir0(d0), .in_dir1(d1),
    .out_valid(nv), .out_hs(nh), .out_vs(ns), .out_mag0(n0), .out_mag1(n1), .out_dir0(nd0), .out_dir1(nd1));
wire cv, ch, cs, ce0, ce1;
edge_link_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_link (
    .clk(clk), .rst_n(rst_n), .in_valid(nv), .in_hs(nh), .in_vs(ns), .mag0(n0), .mag1(n1), .threshold(threshold),
    .dir0(nd0), .dir1(nd1), .out_valid(cv), .out_hs(ch), .out_vs(cs), .edge0(ce0), .edge1(ce1));

// ---- output select: switch only on the first frame start of the newly selected branch ----
reg ts_d, cs_d, sel_o;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin ts_d <= 1'b0; cs_d <= 1'b0; sel_o <= 1'b0; end
    else begin
        ts_d <= ts; cs_d <= cs;
        if (!algo_g && ts && !ts_d) sel_o <= 1'b0;
        else if (algo_g && cs && !cs_d) sel_o <= 1'b1;
    end
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin out_valid<=0; out_hs<=0; out_vs<=0; edge0<=0; edge1<=0; end
    else begin
        out_valid <= sel_o ? cv : tv;  out_hs <= sel_o ? ch : th;  out_vs <= sel_o ? cs : ts;
        edge0     <= sel_o ? ce0 : te0; edge1 <= sel_o ? ce1 : te1;
    end
endmodule
