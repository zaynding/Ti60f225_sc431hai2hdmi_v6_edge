`timescale 1ns/1ps
//======================================================================================================
// edge_algo_2px.v - Sobel / Canny / side-by-side edge stage, 2 pixels per clock, CONSTANT LATENCY.
//
//   main chain (always running, one latency for every mode):
//       gray -> Gaussian -> 3x3 window -> Sobel -> NMS -> double threshold + linking
//     algo = 0 (Sobel)   : the Gaussian passes the centre pixel, NMS passes the raw magnitude, single threshold
//     algo = 1 (Canny)   : full Gaussian / NMS / hysteresis (TH, TH/2)
//     algo = 2 (Compare) : Canny on the main chain, and ...
//   raw Sobel branch (always running, in parallel on the same input, no Gaussian):
//       gray -> 3x3 window -> Sobel -> single threshold -> delay line that aligns it with the main chain output.
//       Its output (s_edge*) is what the left half of the screen shows in Compare mode.
//   Each stage samples `algo` at the start of its own frame, so a frame is never half one algorithm.
//   auto_main / auto_raw: automatic thresholds measured on the main / raw Sobel magnitudes (see auto_thr_2px).
//   SOBEL_DELAY = (latency of the main chain) - (latency of the raw branch) in clocks; measured in simulation
//   (sim/tb_edge_algo.sv) = 3*LINE_CYCLES + SOBEL_DELAY_BASE.
//======================================================================================================
module edge_algo_2px #(
    parameter integer PAIR_COUNT  = 960,
    parameter integer MAX_LINES   = 1080,
    parameter integer LINE_CYCLES = 1100,
    parameter integer SOBEL_DELAY_BASE = 0,
    parameter integer AUTO_MIN_TOTAL   = 400000
)(
    input  wire        clk, rst_n,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [15:0] in_gray2,
    input  wire [1:0]  algo,                // 0 Sobel, 1 Canny, 2 Compare
    input  wire [11:0] th_main, th_raw,
    output wire        out_valid, out_hs, out_vs,
    output wire        edge0, edge1,
    output wire        s_edge0, s_edge1,    // raw Sobel, aligned with edge0/edge1
    output wire [11:0] auto_main, auto_raw
);
localparam integer SOBEL_DELAY = 3 * LINE_CYCLES + SOBEL_DELAY_BASE;

// ---------------- main chain ----------------
reg vs0_d, a_g;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vs0_d <= 1'b0; a_g <= 1'b0; end
    else begin vs0_d <= in_vs; if (in_vs && !vs0_d) a_g <= (algo != 2'd0); end

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
auto_thr_2px #(.MIN_IDX(6), .MIN_TOTAL(AUTO_MIN_TOTAL), .TH_INIT(12'd192)) u_auto_main (.clk(clk), .rst_n(rst_n), .in_valid(sv), .in_vs(ss),
    .mag0(m0), .mag1(m1), .th(auto_main));

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
edge_link_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES), .LINE_CYCLES(LINE_CYCLES)) u_link (
    .clk(clk), .rst_n(rst_n), .in_valid(nv), .in_hs(nh), .in_vs(ns), .mag0(n0), .mag1(n1), .threshold(th_main),
    .dir0(nd0), .dir1(nd1), .en(a_l), .out_valid(out_valid), .out_hs(out_hs), .out_vs(out_vs), .edge0(edge0), .edge1(edge1));

// ---------------- raw Sobel branch ----------------
wire [71:0] rw0, rw1;  wire rlv, rlh, rls;
line_buffer_3x3_2px #(.PAIR_COUNT(PAIR_COUNT), .MAX_LINES(MAX_LINES)) u_rwin (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_gray2(in_gray2),
    .out_valid(rlv), .out_hs(rlh), .out_vs(rls), .win0(rw0), .win1(rw1));
wire [11:0] rm0, rm1;  wire rsv, rsh, rss;
sobel3x3_2px u_rsobel (.clk(clk), .rst_n(rst_n), .in_valid(rlv), .in_hs(rlh), .in_vs(rls), .win0(rw0), .win1(rw1),
    .out_valid(rsv), .out_hs(rsh), .out_vs(rss), .mag0(), .mag1(), .magnitude0(rm0), .magnitude1(rm1),
    .direction0(), .direction1());
auto_thr_2px #(.MIN_IDX(6), .MIN_TOTAL(AUTO_MIN_TOTAL), .TH_INIT(12'd192)) u_auto_raw (.clk(clk), .rst_n(rst_n), .in_valid(rsv), .in_vs(rss),
    .mag0(rm0), .mag1(rm1), .th(auto_raw));
wire rtv, rth, rts, re0, re1;
threshold_compare #(.PAIR_COUNT(PAIR_COUNT), .BLANK_PAIRS(2)) u_rthr (
    .clk(clk), .rst_n(rst_n), .in_valid(rsv), .in_hs(rsh), .in_vs(rss), .mag0(rm0), .mag1(rm1), .threshold(th_raw),
    .out_valid(rtv), .out_hs(rth), .out_vs(rts), .edge0(re0), .edge1(re1));

// delay line (one block RAM, circular): data written at t is read back at t + SOBEL_DELAY
localparam integer DW = $clog2(SOBEL_DELAY);
reg [DW-1:0] dptr;
wire [1:0] dq;
always @(posedge clk or negedge rst_n)
    if (!rst_n) dptr <= 0;
    else dptr <= (dptr == SOBEL_DELAY - 2) ? {DW{1'b0}} : dptr + 1'b1;
simple_dual_port_ram #(.DATA_WIDTH(2), .ADDR_WIDTH(DW), .OUTPUT_REG("FALSE")) u_dly (
    .wdata({re1, re0}), .waddr(dptr), .we(1'b1), .wclk(clk), .raddr(dptr), .re(1'b1), .rclk(clk), .rdata(dq));
assign s_edge0 = dq[0];
assign s_edge1 = dq[1];
endmodule
