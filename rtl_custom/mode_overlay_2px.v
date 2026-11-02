`timescale 1ns/1ps
//======================================================================================================
// mode_overlay_2px.v
//   Draw a small OSD in the top-left corner of the 1080p display:
//     view_mode = 0 -> L
//     view_mode = 1 -> 1
//     view_mode = 2 -> 2
//     view_mode = 3 -> 3
//     view_mode = 4 -> 4
//   The OSD box is 89 x 55 pixels (golden ratio).
//
//   The input format is two 24-bit RGB pixels per clock:
//     in_rgb2[23:0]  = pixel 0
//     in_rgb2[47:24] = pixel 1
//======================================================================================================
module mode_overlay_2px #(
    parameter integer PAIR_COUNT = 960,
    parameter integer LINE_COUNT = 1080,
    parameter integer X0         = 12,
    parameter integer Y0         = 12,
    parameter integer BOX_W      = 89,
    parameter integer BOX_H      = 55
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire [47:0] in_rgb2,
    input  wire [2:0]  view_mode,

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [47:0] out_rgb2
);

    localparam integer PIXEL_SCALE = 5;
    localparam integer GLYPH_W     = 5 * PIXEL_SCALE; // 25
    localparam integer GLYPH_H     = 7 * PIXEL_SCALE; // 35
    localparam integer GLYPH_X0    = (BOX_W - GLYPH_W) / 2;
    localparam integer GLYPH_Y0    = (BOX_H - GLYPH_H) / 2;

    reg [9:0]  x_pair;
    reg [10:0] y_line;
    reg        in_vs_d;

    wire [10:0] px0 = {x_pair, 1'b0};
    wire [10:0] px1 = px0 + 1'b1;

    wire [10:0] local_x0_full = px0 - X0;
    wire [10:0] local_x1_full = px1 - X0;
    wire [10:0] local_y_full  = y_line - Y0;

    wire [7:0] local_x0 = local_x0_full[7:0];
    wire [7:0] local_x1 = local_x1_full[7:0];
    wire [7:0] local_y  = local_y_full[7:0];

    wire in_box0 = in_valid &&
                   (px0 >= X0) && (px0 < (X0 + BOX_W)) &&
                   (y_line >= Y0) && (y_line < (Y0 + BOX_H));
    wire in_box1 = in_valid &&
                   (px1 >= X0) && (px1 < (X0 + BOX_W)) &&
                   (y_line >= Y0) && (y_line < (Y0 + BOX_H));

    // Single-character OSD: L for live, then 1/2/3/4.
    wire [7:0] glyph_x0_w = local_x0 - GLYPH_X0;
    wire [7:0] glyph_x1_w = local_x1 - GLYPH_X0;
    wire [7:0] glyph_y_w  = local_y - GLYPH_Y0;

    wire glyph_area0 = in_box0 &&
                       (local_x0 >= GLYPH_X0) && (local_x0 < GLYPH_X0 + GLYPH_W) &&
                       (local_y >= GLYPH_Y0) && (local_y < GLYPH_Y0 + GLYPH_H);
    wire glyph_area1 = in_box1 &&
                       (local_x1 >= GLYPH_X0) && (local_x1 < GLYPH_X0 + GLYPH_W) &&
                       (local_y >= GLYPH_Y0) && (local_y < GLYPH_Y0 + GLYPH_H);

    wire [2:0] col0 = glyph_x0_w / PIXEL_SCALE;
    wire [2:0] col1 = glyph_x1_w / PIXEL_SCALE;
    wire [2:0] font_row = glyph_y_w / PIXEL_SCALE;
    wire [2:0] font_id = (view_mode == 3'd0) ? 3'd0 : (view_mode + 3'd3);
    wire [4:0] font_bits = font_row_bits(font_id, font_row);

    wire glyph_on0 = glyph_area0 && font_bits[4'd4 - col0];
    wire glyph_on1 = glyph_area1 && font_bits[4'd4 - col1];

    wire [23:0] out_pix0 = in_box0 ? (glyph_on0 ? 24'hFFFFFF : 24'h000000)
                                    : in_rgb2[23:0];
    wire [23:0] out_pix1 = in_box1 ? (glyph_on1 ? 24'hFFFFFF : 24'h000000)
                                    : in_rgb2[47:24];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            out_rgb2  <= 48'd0;
            x_pair    <= 10'd0;
            y_line    <= 11'd0;
            in_vs_d   <= 1'b0;
        end else begin
            in_vs_d <= in_vs;

            if (in_vs & ~in_vs_d) begin
                x_pair <= 10'd0;
                y_line <= 11'd0;
            end else if (in_valid) begin
                if (x_pair == PAIR_COUNT - 1) begin
                    x_pair <= 10'd0;
                    if (y_line == LINE_COUNT - 1)
                        y_line <= 11'd0;
                    else
                        y_line <= y_line + 1'b1;
                end else begin
                    x_pair <= x_pair + 1'b1;
                end
            end

            out_valid <= in_valid;
            out_hs    <= in_hs;
            out_vs    <= in_vs;
            out_rgb2  <= {out_pix1, out_pix0};
        end
    end

    // 5x7 bitmap font inside an 8x8 character cell. The remaining rows and
    // columns are the character spacing.
    function [4:0] font_row_bits;
        input [2:0] font_id;
        input [2:0] row;
    begin
        case (font_id)
            3'd0: begin // L
                case (row)
                    3'd0: font_row_bits = 5'h10;
                    3'd1: font_row_bits = 5'h10;
                    3'd2: font_row_bits = 5'h10;
                    3'd3: font_row_bits = 5'h10;
                    3'd4: font_row_bits = 5'h10;
                    3'd5: font_row_bits = 5'h10;
                    3'd6: font_row_bits = 5'h1F;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd1: begin // I
                case (row)
                    3'd0: font_row_bits = 5'h1F;
                    3'd1: font_row_bits = 5'h04;
                    3'd2: font_row_bits = 5'h04;
                    3'd3: font_row_bits = 5'h04;
                    3'd4: font_row_bits = 5'h04;
                    3'd5: font_row_bits = 5'h04;
                    3'd6: font_row_bits = 5'h1F;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd2: begin // V
                case (row)
                    3'd0: font_row_bits = 5'h11;
                    3'd1: font_row_bits = 5'h11;
                    3'd2: font_row_bits = 5'h11;
                    3'd3: font_row_bits = 5'h11;
                    3'd4: font_row_bits = 5'h11;
                    3'd5: font_row_bits = 5'h0A;
                    3'd6: font_row_bits = 5'h04;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd3: begin // E
                case (row)
                    3'd0: font_row_bits = 5'h1F;
                    3'd1: font_row_bits = 5'h10;
                    3'd2: font_row_bits = 5'h10;
                    3'd3: font_row_bits = 5'h1E;
                    3'd4: font_row_bits = 5'h10;
                    3'd5: font_row_bits = 5'h10;
                    3'd6: font_row_bits = 5'h1F;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd4: begin // 1
                case (row)
                    3'd0: font_row_bits = 5'h04;
                    3'd1: font_row_bits = 5'h0C;
                    3'd2: font_row_bits = 5'h04;
                    3'd3: font_row_bits = 5'h04;
                    3'd4: font_row_bits = 5'h04;
                    3'd5: font_row_bits = 5'h04;
                    3'd6: font_row_bits = 5'h0E;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd5: begin // 2
                case (row)
                    3'd0: font_row_bits = 5'h0E;
                    3'd1: font_row_bits = 5'h11;
                    3'd2: font_row_bits = 5'h01;
                    3'd3: font_row_bits = 5'h02;
                    3'd4: font_row_bits = 5'h04;
                    3'd5: font_row_bits = 5'h08;
                    3'd6: font_row_bits = 5'h1F;
                    default: font_row_bits = 5'h00;
                endcase
            end
            3'd6: begin // 3
                case (row)
                    3'd0: font_row_bits = 5'h0E;
                    3'd1: font_row_bits = 5'h11;
                    3'd2: font_row_bits = 5'h01;
                    3'd3: font_row_bits = 5'h06;
                    3'd4: font_row_bits = 5'h01;
                    3'd5: font_row_bits = 5'h11;
                    3'd6: font_row_bits = 5'h0E;
                    default: font_row_bits = 5'h00;
                endcase
            end
            default: begin // 4
                case (row)
                    3'd0: font_row_bits = 5'h02;
                    3'd1: font_row_bits = 5'h06;
                    3'd2: font_row_bits = 5'h0A;
                    3'd3: font_row_bits = 5'h12;
                    3'd4: font_row_bits = 5'h1F;
                    3'd5: font_row_bits = 5'h02;
                    3'd6: font_row_bits = 5'h02;
                    default: font_row_bits = 5'h00;
                endcase
            end
        endcase
    end
    endfunction

endmodule
