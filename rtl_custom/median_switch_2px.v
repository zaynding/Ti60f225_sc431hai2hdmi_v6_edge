`timescale 1ns/1ps
//======================================================================================================
// median_switch_2px.v - switching (decision-based) median filter, 2 pixels per clock
//
//   Plain 3x3 median blurs / removes thin scratches.  This version only replaces a pixel when it is
//   a STRICT outlier of its 8 neighbours:
//
//        sort the 9 window values            -> s0 <= s1 <= ... <= s8
//        nmin = (centre <= s1) ? s1 : s0     // min of the 8 neighbours (centre excluded)
//        nmax = (centre >= s7) ? s7 : s8     // max of the 8 neighbours (centre excluded)
//        is_impulse = (centre < nmin) || (centre > nmax)
//        out = is_impulse ? s4 (median) : centre
//
//   Consequences:
//     * isolated salt/pepper pixel          -> replaced by the median   (noise removed)
//     * 1-px wide line / scratch            -> NOT strictly greater than its
//                                              neighbours, so it is kept  (detail preserved)
//     * flat areas / real edges             -> unchanged
//
//   Uses line_buffer_3x3_2px + sort9_net (parallel Batcher network, 26 comparators, depth 8).
//======================================================================================================
module median_switch_2px #(
    parameter integer PAIR_COUNT = 960,
    parameter integer MAX_LINES  = 1080
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire [15:0] in_gray2,
    input  wire        en,          // 0 = pass-through (same latency)

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [15:0] out_gray2
);

    wire        win_valid, win_hs, win_vs;
    wire [71:0] win0, win1;

    line_buffer_3x3_2px #(
        .PAIR_COUNT (PAIR_COUNT),
        .MAX_LINES  (MAX_LINES)
    ) u_lb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_gray2(in_gray2),
        .out_valid(win_valid), .out_hs(win_hs), .out_vs(win_vs),
        .win0(win0), .win1(win1)
    );

    // ---------------- lane 0 (low byte of the pair) ----------------
    wire [7:0] a0_00 = win0[71:64], a0_01 = win0[63:56], a0_02 = win0[55:48];
    wire [7:0] a0_10 = win0[47:40], a0_11 = win0[39:32], a0_12 = win0[31:24];
    wire [7:0] a0_20 = win0[23:16], a0_21 = win0[15:8],  a0_22 = win0[7:0];
    wire [7:0] b0_0, b0_1, b0_2, b0_3, b0_4, b0_5, b0_6, b0_7, b0_8;

    sort9_net u_sort0 (
        .v0(a0_00), .v1(a0_01), .v2(a0_02), .v3(a0_10), .v4(a0_11),
        .v5(a0_12), .v6(a0_20), .v7(a0_21), .v8(a0_22),
        .s0(b0_0), .s1(b0_1), .s2(b0_2), .s3(b0_3), .s4(b0_4),
        .s5(b0_5), .s6(b0_6), .s7(b0_7), .s8(b0_8)
    );

    wire [7:0] c0    = a0_11;
    wire [7:0] nmin0 = (c0 <= b0_1) ? b0_1 : b0_0;
    wire [7:0] nmax0 = (c0 >= b0_7) ? b0_7 : b0_8;
    wire       imp0  = en && ((c0 < nmin0) || (c0 > nmax0));
    wire [7:0] px0   = imp0 ? b0_4 : c0;

    // ---------------- lane 1 (high byte of the pair) ----------------
    wire [7:0] a1_00 = win1[71:64], a1_01 = win1[63:56], a1_02 = win1[55:48];
    wire [7:0] a1_10 = win1[47:40], a1_11 = win1[39:32], a1_12 = win1[31:24];
    wire [7:0] a1_20 = win1[23:16], a1_21 = win1[15:8],  a1_22 = win1[7:0];
    wire [7:0] b1_0, b1_1, b1_2, b1_3, b1_4, b1_5, b1_6, b1_7, b1_8;

    sort9_net u_sort1 (
        .v0(a1_00), .v1(a1_01), .v2(a1_02), .v3(a1_10), .v4(a1_11),
        .v5(a1_12), .v6(a1_20), .v7(a1_21), .v8(a1_22),
        .s0(b1_0), .s1(b1_1), .s2(b1_2), .s3(b1_3), .s4(b1_4),
        .s5(b1_5), .s6(b1_6), .s7(b1_7), .s8(b1_8)
    );

    wire [7:0] c1    = a1_11;
    wire [7:0] nmin1 = (c1 <= b1_1) ? b1_1 : b1_0;
    wire [7:0] nmax1 = (c1 >= b1_7) ? b1_7 : b1_8;
    wire       imp1  = en && ((c1 < nmin1) || (c1 > nmax1));
    wire [7:0] px1   = imp1 ? b1_4 : c1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            out_gray2 <= 16'd0;
        end
        else begin
            out_valid <= win_valid;
            out_hs    <= win_hs;
            out_vs    <= win_vs;
            out_gray2 <= win_valid ? {px1, px0} : 16'd0;
        end
    end

endmodule
