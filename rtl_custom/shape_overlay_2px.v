`timescale 1ns/1ps
//======================================================================================================
// shape_overlay_2px.v - draw a coloured box and the Chinese shape name for every visible track on BOTH
//                       panels (left colour crop, right edge crop) of the 1920x1080 split display.
//
//   Input  : the finished display stream (2 pixels per clock, RGB888 pairs, [23:0] = left pixel)
//   Panels : pair 0..479 = left panel, pair 480..959 = right panel; both show the same 960x1080 crop,
//            so a track at map cell (cx,cy) is at panel pixel (4*cx, 4*cy).
//   Delay  : 2 clocks
//   Colour constants use the same {R,G,B} convention as display_split_2px (24'hFF0000 is red on screen).
//======================================================================================================
module shape_overlay_2px #(
    parameter integer NT = 4,
    parameter integer PAIR_COUNT = 960,
    parameter integer PANEL_PAIRS = 480
)(
    input  wire        clk, rst_n,
    input  wire        enable,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [47:0] in_rgb2,
    input  wire [NT-1:0]   trk_vis,
    input  wire [3*NT-1:0] trk_cls,
    input  wire [8*NT-1:0] trk_xmin, trk_xmax,
    input  wire [9*NT-1:0] trk_ymin, trk_ymax,
    output reg         out_valid, out_hs, out_vs,
    output reg  [47:0] out_rgb2
);
// ---------------- position counters (same convention as the other 2px modules) ----------------
reg vs_d, valid_d;
reg [9:0]  xp;
reg [10:0] yl;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin vs_d<=0; valid_d<=0; xp<=0; yl<=0; end
    else begin
        vs_d <= in_vs; valid_d <= in_valid;
        if (in_vs && !vs_d) begin xp<=0; yl<=0; end
        else if (in_valid) xp <= xp + 1'b1;
        else if (valid_d) begin xp<=0; yl<=yl+1'b1; end
    end
end
wire        right_panel = (xp >= PANEL_PAIRS);
wire [9:0]  xpr  = right_panel ? (xp - PANEL_PAIRS) : xp;      // pair index inside the panel
wire [10:0] xr0  = {xpr, 1'b0};                                // panel pixel of the left pixel
wire [10:0] xr1  = {xpr, 1'b1};
wire [10:0] yy   = yl;

// ---------------- per-track screen geometry (registered; constant during a frame) ----------------
reg [10:0] bx0 [0:NT-1], bx1 [0:NT-1], by0 [0:NT-1], by1 [0:NT-1], tx [0:NT-1], ty [0:NT-1];
reg [6:0]  tw [0:NT-1];
reg [2:0]  tc [0:NT-1];
reg        tv [0:NT-1];
integer i;
always @(posedge clk) begin
    for (i = 0; i < NT; i = i + 1) begin : geom
        reg [8:0]  x0, x1; reg [9:0] y0, y1;
        reg [10:0] ax0, ax1, ay0, ay1, sx, sy;
        reg [2:0]  c;
        c  = trk_cls[3*i +: 3];
        x0 = trk_xmin[8*i +: 8]; x1 = trk_xmax[8*i +: 8];
        y0 = trk_ymin[9*i +: 9]; y1 = trk_ymax[9*i +: 9];
        ax0 = (x0 > 2) ? ({x0 - 9'd2, 2'b00}) : 11'd0;
        ax1 = ({x1 + 9'd3, 2'b00}) - 11'd1;  if (ax1 > 11'd959) ax1 = 11'd959;
        ay0 = (y0 > 2) ? ({y0 - 10'd2, 2'b00}) : 11'd0;
        ay1 = ({y1 + 10'd3, 2'b00}) - 11'd1; if (ay1 > 11'd1079) ay1 = 11'd1079;
        tw[i] <= (c == 3'd1 || c == 3'd4) ? 7'd64 : 7'd96;
        sx = ax0;  if (ax0 + ((c == 3'd1 || c == 3'd4) ? 11'd64 : 11'd96) > 11'd960) sx = 11'd960 - ((c == 3'd1 || c == 3'd4) ? 11'd64 : 11'd96);
        sy = (ay0 >= 11'd36) ? (ay0 - 11'd36) : (ay1 + 11'd4);
        bx0[i] <= ax0; bx1[i] <= ax1; by0[i] <= ay0; by1[i] <= ay1; tx[i] <= sx; ty[i] <= sy;
        tc[i] <= c; tv[i] <= trk_vis[i] && enable && (c != 3'd0);
    end
end

// ---------------- stage 1: choose what covers each of the two pixels ----------------
// kind: 0 none, 1 box border, 2 text cell
reg        s1_valid, s1_hs, s1_vs;
reg [47:0] s1_rgb;
reg [1:0]  s1_kind0, s1_kind1;
reg [2:0]  s1_cls0, s1_cls1;
reg [3:0]  s1_gid0, s1_gid1;       // glyph id (0..7), 8 = blank
reg [3:0]  s1_row0, s1_row1;
reg [3:0]  s1_col0, s1_col1;

function [3:0] label_gid;
    input [2:0] cls; input [1:0] ci;
    begin
        label_gid = 4'd8;
        case (cls)
        3'd1: label_gid = (ci == 0) ? 4'd0 : (ci == 1) ? 4'd1 : 4'd8;            // yuan xing
        3'd2: label_gid = (ci == 0) ? 4'd2 : (ci == 1) ? 4'd0 : 4'd1;            // tuo yuan xing
        3'd3: label_gid = (ci == 0) ? 4'd3 : (ci == 1) ? 4'd4 : 4'd1;            // zheng fang xing
        3'd4: label_gid = (ci == 0) ? 4'd5 : (ci == 1) ? 4'd1 : 4'd8;            // ju xing
        3'd5: label_gid = (ci == 0) ? 4'd6 : (ci == 1) ? 4'd7 : 4'd1;            // san jiao xing
        default: label_gid = 4'd8;
        endcase
    end
endfunction

task eval_pixel;
    input [10:0] xr; input [10:0] y;
    output [1:0] kind; output [2:0] cls; output [3:0] gid, row, col;
    integer k;
    reg done_t, done_b;
    reg [10:0] u; reg [10:0] v;
    reg in_txt, on_box, in_in;
    begin
        kind = 2'd0; cls = 3'd0; gid = 4'd8; row = 4'd0; col = 4'd0; done_t = 0; done_b = 0;
        for (k = 0; k < NT; k = k + 1) if (tv[k]) begin
            in_txt = (xr >= tx[k]) && (xr < tx[k] + tw[k]) && (y >= ty[k]) && (y < ty[k] + 11'd32);
            if (in_txt && !done_t) begin
                done_t = 1; kind = 2'd2; cls = tc[k];
                u = (xr - tx[k]) >> 1; v = (y - ty[k]) >> 1;
                gid = label_gid(tc[k], u[5:4]); col = u[3:0]; row = v[3:0];
            end
            on_box = (xr >= bx0[k]) && (xr <= bx1[k]) && (y >= by0[k]) && (y <= by1[k]);
            in_in  = (xr >= bx0[k] + 11'd3) && (xr + 11'd3 <= bx1[k]) && (y >= by0[k] + 11'd3) && (y + 11'd3 <= by1[k]);
            if (on_box && !in_in && !done_b && !done_t) begin done_b = 1; kind = 2'd1; cls = tc[k]; end
        end
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid<=0; s1_hs<=0; s1_vs<=0; s1_rgb<=0; s1_kind0<=0; s1_kind1<=0; s1_cls0<=0; s1_cls1<=0;
        s1_gid0<=8; s1_gid1<=8; s1_row0<=0; s1_row1<=0; s1_col0<=0; s1_col1<=0;
    end else begin
        s1_valid<=in_valid; s1_hs<=in_hs; s1_vs<=in_vs; s1_rgb<=in_rgb2;
        eval_pixel(xr0, yy, s1_kind0, s1_cls0, s1_gid0, s1_row0, s1_col0);
        eval_pixel(xr1, yy, s1_kind1, s1_cls1, s1_gid1, s1_row1, s1_col1);
    end
end

// ---------------- stage 2: glyph lookup and colour ----------------
wire [15:0] bits0, bits1;
shape_font_rom u_f0 (.ch(s1_gid0[2:0]), .row(s1_row0), .bits(bits0));
shape_font_rom u_f1 (.ch(s1_gid1[2:0]), .row(s1_row1), .bits(bits1));

function [23:0] class_color;
    input [2:0] c;
    begin
        case (c)
        3'd1: class_color = 24'h00FF00;   // circle    green
        3'd2: class_color = 24'hFFFF00;   // ellipse   yellow
        3'd3: class_color = 24'h00FFFF;   // square    cyan
        3'd4: class_color = 24'hFF00FF;   // rectangle magenta
        3'd5: class_color = 24'hFF8000;   // triangle  orange
        default: class_color = 24'hFFFFFF;
        endcase
    end
endfunction

function [23:0] pix;
    input [1:0] kind; input [2:0] cls; input [3:0] gid, col; input [15:0] bits; input [23:0] base;
    begin
        pix = base;
        if (kind == 2'd1) pix = class_color(cls);
        else if (kind == 2'd2) pix = (gid != 4'd8 && bits[15 - col]) ? class_color(cls) : 24'h000000;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin out_valid<=0; out_hs<=0; out_vs<=0; out_rgb2<=0; end
    else begin
        out_valid<=s1_valid; out_hs<=s1_hs; out_vs<=s1_vs;
        out_rgb2 <= { pix(s1_kind1, s1_cls1, s1_gid1, s1_col1, bits1, s1_rgb[47:24]),
                      pix(s1_kind0, s1_cls0, s1_gid0, s1_col0, bits0, s1_rgb[23:0]) };
    end
end
endmodule
