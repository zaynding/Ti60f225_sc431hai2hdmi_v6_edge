`timescale 1ns/1ps
//======================================================================================================
// shape_pool.v - 4x4 OR pooling of the 1-bit edge stream (2 pixels / clock) inside the displayed crop.
//
//   Input  : despeckled edge pair stream (same one that feeds the display), valid only on active video.
//   Window : pairs [CROP_X_PAIR, CROP_X_PAIR+CROP_PAIRS)   (= 2*CROP_PAIRS pixels wide)
//   Output : one pooled cell per p_valid, raster order, MAP_W = CROP_PAIRS/2 cells per row.
//            A pooled row is produced every 4th video line (while that line is running).
//   A 240-bit rotating register holds the cell accumulators, so no RAM is needed.
//======================================================================================================
module shape_pool #(
    parameter integer CROP_X_PAIR = 240,
    parameter integer CROP_PAIRS  = 480
)(
    input  wire       clk, rst_n,
    input  wire       in_valid, in_vs,
    input  wire [1:0] in_edge2,           // {edge1, edge0}; edge0 is the left pixel
    output reg        p_valid, p_bit,
    output reg        p_frame_start
);
localparam integer MAP_W = CROP_PAIRS / 2;
reg        vs_d, valid_d, tmp;
reg [9:0]  xp;
reg [1:0]  ry;
reg [MAP_W-1:0] acc;
wire [9:0] xc = xp - CROP_X_PAIR;
wire       in_crop = (xp >= CROP_X_PAIR) && (xp < CROP_X_PAIR + CROP_PAIRS);
wire       cellbit = tmp | in_edge2[0] | in_edge2[1];
wire       newbit  = (ry == 2'd0) ? cellbit : (acc[0] | cellbit);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vs_d<=0; valid_d<=0; tmp<=0; xp<=0; ry<=0; acc<=0; p_valid<=0; p_bit<=0; p_frame_start<=0;
    end else begin
        vs_d <= in_vs; valid_d <= in_valid;
        p_valid <= 1'b0; p_frame_start <= 1'b0;
        if (in_vs && !vs_d) begin
            p_frame_start <= 1'b1; ry <= 2'd0; xp <= 10'd0;
        end else if (in_valid) begin
            xp <= xp + 1'b1;
            if (in_crop) begin
                if (!xc[0]) tmp <= in_edge2[0] | in_edge2[1];
                else begin
                    acc <= {newbit, acc[MAP_W-1:1]};
                    if (ry == 2'd3) begin p_valid <= 1'b1; p_bit <= newbit; end
                end
            end
        end else if (valid_d) begin
            xp <= 10'd0; ry <= ry + 1'b1;     // end of a video line
        end
    end
end
endmodule
