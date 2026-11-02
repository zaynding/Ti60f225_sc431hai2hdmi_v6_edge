`timescale 1ns/1ps
//======================================================================================================
// menu_bar_2px.v - opaque menu bar over the bottom 120 lines (y >= BAR_Y) of the 1920x1080 picture.
//   5 columns of 384 pixels, three 32-pixel text rows (label / value / status), 16x16 glyphs at 2x.
//   Input and output: two pixels per clock, [23:0] = left pixel, colours {R,G,B}.   Delay: 4 clocks.
//======================================================================================================
module menu_bar_2px #(
    parameter integer BAR_Y = 960
)(
    input  wire        clk, rst_n,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [47:0] in_rgb2,
    input  wire [2:0]  sel, src_mode, thr_idx, flash,
    input  wire        shape_on, med_on,
    input  wire [1:0]  disp_mode,
    input  wire [3:0]  saved_valid,
    output wire        out_valid, out_hs, out_vs,
    output wire [47:0] out_rgb2
);
// ---------------- position counters ----------------
reg vs_d, valid_d;
reg [3:0] col, chr;  reg [2:0] item;  reg [10:0] yl;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin vs_d<=0; valid_d<=0; col<=0; chr<=0; item<=0; yl<=0; end
    else begin
        vs_d <= in_vs; valid_d <= in_valid;
        if (in_vs && !vs_d) begin col<=0; chr<=0; item<=0; yl<=0; end
        else if (in_valid) begin
            if (col == 4'd15) begin
                col <= 0;
                if (chr == 4'd11) begin chr <= 0; item <= item + 1'b1; end else chr <= chr + 1'b1;
            end else col <= col + 1'b1;
        end else if (valid_d) begin col<=0; chr<=0; item<=0; yl<=yl+1'b1; end
    end
end
wire [10:0] yo = yl - BAR_Y;
wire in_bar = (yl >= BAR_Y);
// text line: yo 8..39 -> 0, 48..79 -> 1, 88..119 -> 2
reg [1:0] line; reg line_ok; reg [5:0] ly;
always @* begin
    line = 0; line_ok = 0; ly = 0;
    if (yo >= 11'd8  && yo < 11'd40)  begin line = 0; line_ok = 1; ly = yo[5:0] - 6'd8;  end
    else if (yo >= 11'd48 && yo < 11'd80)  begin line = 1; line_ok = 1; ly = yo[6:0] - 7'd48; end
    else if (yo >= 11'd88 && yo < 11'd120) begin line = 2; line_ok = 1; ly = yo[6:0] - 7'd88; end
end
// ---------------- stage A ----------------
reg a_valid, a_hs, a_vs, a_bar, a_ok, a_hi, a_sep;
reg [47:0] a_rgb;
reg [2:0] a_item; reg [3:0] a_chr, a_col; reg [1:0] a_line; reg [4:0] a_ly;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin a_valid<=0; a_hs<=0; a_vs<=0; a_bar<=0; a_ok<=0; a_hi<=0; a_sep<=0; a_rgb<=0; a_item<=0; a_chr<=0; a_col<=0; a_line<=0; a_ly<=0; end
    else begin
        a_valid<=in_valid; a_hs<=in_hs; a_vs<=in_vs; a_rgb<=in_rgb2;
        a_bar<=in_bar; a_ok<=line_ok && (item < 3'd5); a_hi<=(item == sel); a_sep<=(yo < 11'd3);
        a_item<=item; a_chr<=chr; a_col<=col; a_line<=line; a_ly<=ly[4:1];      // glyph row = ly/2
    end
end
reg [2:0] val;
always @* case (a_item)
    3'd0: val = src_mode;
    3'd1: val = 3'd0;
    3'd2: val = {2'b00, shape_on};
    3'd3: val = {2'b00, med_on};
    default: val = {1'b0, disp_mode};
endcase
wire [5:0] glyph; wire dim;
menu_text_rom u_txt (.item(a_item), .line(a_line), .chr(a_chr), .val(val), .thr(thr_idx), .flash(flash), .valid(saved_valid),
    .glyph(glyph), .dim(dim));
// ---------------- stage B ----------------
reg b_valid, b_hs, b_vs, b_bar, b_ok, b_hi, b_sep, b_dim;
reg [47:0] b_rgb; reg [5:0] b_glyph; reg [3:0] b_col, b_ly; reg [1:0] b_line;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin b_valid<=0; b_hs<=0; b_vs<=0; b_bar<=0; b_ok<=0; b_hi<=0; b_sep<=0; b_dim<=0; b_rgb<=0; b_glyph<=0; b_col<=0; b_ly<=0; b_line<=0; end
    else begin
        b_valid<=a_valid; b_hs<=a_hs; b_vs<=a_vs; b_rgb<=a_rgb; b_bar<=a_bar; b_ok<=a_ok; b_hi<=a_hi; b_sep<=a_sep; b_dim<=dim;
        b_glyph<=glyph; b_col<=a_col; b_ly<=a_ly[3:0]; b_line<=a_line;
    end
end
wire [15:0] bits;
menu_font_rom u_font (.ch(b_glyph), .row(b_ly), .bits(bits));
// ---------------- stage C ----------------
reg c_valid, c_hs, c_vs, c_bar, c_hi, c_sep, c_px, c_dim;
reg [47:0] c_rgb; reg [1:0] c_line;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin c_valid<=0; c_hs<=0; c_vs<=0; c_bar<=0; c_hi<=0; c_sep<=0; c_px<=0; c_dim<=0; c_rgb<=0; c_line<=0; end
    else begin
        c_valid<=b_valid; c_hs<=b_hs; c_vs<=b_vs; c_rgb<=b_rgb; c_bar<=b_bar; c_hi<=b_hi; c_sep<=b_sep; c_dim<=b_dim; c_line<=b_line;
        c_px <= b_ok && bits[4'd15 - b_col];
    end
end
// ---------------- stage D : colour ----------------
reg d_valid, d_hs, d_vs; reg [47:0] d_rgb;
wire [23:0] bg   = c_hi ? 24'h104878 : 24'h101418;
wire [23:0] fg   = c_dim ? 24'h505050 : (c_line == 2'd0) ? 24'h80D0FF : (c_line == 2'd1) ? 24'hFFFFFF : 24'hC0C0C0;
wire [23:0] pix  = c_sep ? 24'h60A0FF : (c_px ? fg : bg);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin d_valid<=0; d_hs<=0; d_vs<=0; d_rgb<=0; end
    else begin
        d_valid<=c_valid; d_hs<=c_hs; d_vs<=c_vs;
        d_rgb <= c_bar ? {pix, pix} : c_rgb;
    end
end
assign out_valid = d_valid; assign out_hs = d_hs; assign out_vs = d_vs; assign out_rgb2 = d_rgb;
endmodule
