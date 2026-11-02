`timescale 1ns/1ps
//======================================================================================================
// despeckle_2px.v - remove isolated pixels from the 1-bit edge map, 2 pixels per clock
//
//   3x3 neighbourhood (1-bit), count the 8 neighbours:
//        centre = 1 : keep only if count >= KEEP_MIN   (otherwise it is an isolated speck)
//        centre = 0 : set  only if count >= FILL_MIN   (optional single-pixel hole filling)
//
//   Default KEEP_MIN=2, FILL_MIN=6.  Set FILL_MIN=9 to disable hole filling.
//   Uses line_buffer_3x3_2px (2-bit word packed per pixel, only bit0 of each byte is used).
//======================================================================================================
module despeckle_2px #(
    parameter integer PAIR_COUNT = 960,
    parameter integer MAX_LINES  = 1080,
    parameter integer KEEP_MIN   = 2,
    parameter integer FILL_MIN   = 6
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       in_valid,
    input  wire       in_hs,
    input  wire       in_vs,
    input  wire [1:0] in_edge2,      // {edge1, edge0}

    output reg        out_valid,
    output reg        out_hs,
    output reg        out_vs,
    output reg  [1:0] out_edge2
);

    wire        win_valid, win_hs, win_vs;
    wire [71:0] win0, win1;

    line_buffer_3x3_2px #(
        .PAIR_COUNT (PAIR_COUNT),
        .MAX_LINES  (MAX_LINES)
    ) u_lb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs),
        .in_gray2({7'b0, in_edge2[1], 7'b0, in_edge2[0]}),
        .out_valid(win_valid), .out_hs(win_hs), .out_vs(win_vs),
        .win0(win0), .win1(win1)
    );

    // lane 0 : bit0 of each window byte
    wire [7:0] nb0 = { win0[64], win0[56], win0[48], win0[40],
                       win0[24], win0[16], win0[8],  win0[0] };
    wire [3:0] cnt0 = nb0[0] + nb0[1] + nb0[2] + nb0[3] +
                      nb0[4] + nb0[5] + nb0[6] + nb0[7];
    wire       c0   = win0[32];
    wire       o0   = c0 ? (cnt0 >= KEEP_MIN) : (cnt0 >= FILL_MIN);

    // lane 1 : bit1 of each window byte
    wire [7:0] nb1 = { win1[64], win1[56], win1[48], win1[40],
                       win1[24], win1[16], win1[8],  win1[0] };
    wire [3:0] cnt1 = nb1[0] + nb1[1] + nb1[2] + nb1[3] +
                      nb1[4] + nb1[5] + nb1[6] + nb1[7];
    wire       c1   = win1[32];
    wire       o1   = c1 ? (cnt1 >= KEEP_MIN) : (cnt1 >= FILL_MIN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            out_edge2 <= 2'd0;
        end
        else begin
            out_valid <= win_valid;
            out_hs    <= win_hs;
            out_vs    <= win_vs;
            out_edge2 <= win_valid ? {o1, o0} : 2'd0;
        end
    end

endmodule
