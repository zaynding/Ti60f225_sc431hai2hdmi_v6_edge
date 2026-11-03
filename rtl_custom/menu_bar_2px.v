`timescale 1ns/1ps
//======================================================================================================
// menu_bar_2px.v - opaque menu bar over the bottom 120 lines (y >= BAR_Y) of the 1920x1080 picture.
//   6 columns of 320 pixels, three 32-pixel text rows (label / value / status), native 32x32 glyphs.
//   Number cells (frame rates) are two 16x32 digits taken from a small digit ROM.
//   Input and output: two pixels per clock, [23:0] = left pixel, colours {R,G,B}.   Delay: 4 clocks.
//======================================================================================================
module menu_bar_2px #(
    parameter integer BAR_Y = 960
)(
    input  wire        clk, rst_n,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [47:0] in_rgb2,
    input  wire [2:0]  sel, src_mode, thr_idx, flash,
    input  wire        shape_on, cmp_mode, fps_on,
    input  wire [6:0]  fps_out, fps_cam,
    input  wire [1:0]  algo,
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
                if (chr == 4'd9) begin chr <= 0; item <= item + 1'b1; end else chr <= chr + 1'b1;
            end else col <= col + 1'b1;
        end else if (valid_d) begin col<=0; chr<=0; item<=0; yl<=yl+1'b1; end
    end
end
wire [10:0] yo = yl - BAR_Y;
// compare-mode captions: "Sobel" over the left panel, "Canny" over the right panel (transparent background)
wire cap_row = cmp_mode && (yl >= 11'd8) && (yl < 11'd40);
wire [4:0] cap_ly = yl[4:0] - 5'd8;
reg cap_hit; reg [2:0] cap_item; reg [3:0] cap_chr;
always @* begin
    cap_hit = 1'b0; cap_item = 3'd0; cap_chr = 4'd0;
    if (cap_row && item == 3'd0 && chr >= 4'd1 && chr <= 4'd3) begin cap_hit = 1'b1; cap_item = 3'd6; cap_chr = chr - 4'd1; end
    else if (cap_row && item == 3'd3 && chr >= 4'd1 && chr <= 4'd3) begin cap_hit = 1'b1; cap_item = 3'd7; cap_chr = chr - 4'd1; end
end
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
reg a_valid, a_hs, a_vs, a_bar, a_ok, a_hi, a_sep, a_cap;
reg [47:0] a_rgb;
reg [2:0] a_item; reg [3:0] a_chr, a_col; reg [1:0] a_line; reg [4:0] a_ly;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin a_valid<=0; a_hs<=0; a_vs<=0; a_bar<=0; a_ok<=0; a_hi<=0; a_sep<=0; a_cap<=0; a_rgb<=0; a_item<=0; a_chr<=0; a_col<=0; a_line<=0; a_ly<=0; end
    else begin
        a_valid<=in_valid; a_hs<=in_hs; a_vs<=in_vs; a_rgb<=in_rgb2;
        a_bar<=in_bar; a_ok<=cap_hit || (line_ok && (item < 3'd6)); a_hi<=(item == sel); a_sep<=(yo < 11'd3); a_cap<=cap_hit;
        a_item<=cap_hit ? cap_item : item; a_chr<=cap_hit ? cap_chr : chr; a_col<=col; a_line<=cap_hit ? 2'd0 : line; a_ly<=cap_hit ? cap_ly : ly[4:0];
    end
end
reg [2:0] val;
always @* case (a_item)
    3'd0: val = src_mode;
    3'd1: val = 3'd0;
    3'd2: val = {2'b00, shape_on};
    3'd3: val = {1'b0, algo};
    3'd5: val = {2'b00, fps_on};
    default: val = {1'b0, disp_mode};
endcase
wire [5:0] glyph; wire dim; wire [1:0] num_sel;
menu_text_rom u_txt (.item(a_item), .line(a_line), .chr(a_chr), .val(val), .thr(thr_idx), .flash(flash), .valid(saved_valid), .fps_on(fps_on),
    .glyph(glyph), .dim(dim), .num_sel(num_sel));
// number cell: tens (blank when 0) and units digit of the selected frame rate
wire [6:0] num_v   = (num_sel == 2'd1) ? fps_out : fps_cam;
wire [3:0] num_t   = (num_v >= 7'd90) ? 4'd9 : (num_v >= 7'd80) ? 4'd8 : (num_v >= 7'd70) ? 4'd7 : (num_v >= 7'd60) ? 4'd6 :
                     (num_v >= 7'd50) ? 4'd5 : (num_v >= 7'd40) ? 4'd4 : (num_v >= 7'd30) ? 4'd3 : (num_v >= 7'd20) ? 4'd2 :
                     (num_v >= 7'd10) ? 4'd1 : 4'd0;
wire [6:0] num_u7  = num_v - {num_t, 3'b000} - {num_t, 1'b0};          // num_v - 10*tens
wire [3:0] dig_t   = (num_t == 4'd0) ? 4'd10 : num_t;                  // 10 = blank digit
wire [3:0] dig_u   = num_u7[3:0];
wire       a_num   = (num_sel != 2'd0);
// ---------------- stage B (font RAM read data arrives here) ----------------
reg b_valid, b_hs, b_vs, b_bar, b_ok, b_hi, b_sep, b_dim, b_cap, b_num;
reg [47:0] b_rgb; reg [3:0] b_col; reg [1:0] b_line;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin b_valid<=0; b_hs<=0; b_vs<=0; b_bar<=0; b_ok<=0; b_hi<=0; b_sep<=0; b_dim<=0; b_cap<=0; b_num<=0; b_rgb<=0; b_col<=0; b_line<=0; end
    else begin
        b_valid<=a_valid; b_hs<=a_hs; b_vs<=a_vs; b_rgb<=a_rgb; b_bar<=a_bar; b_ok<=a_ok; b_hi<=a_hi; b_sep<=a_sep; b_dim<=dim; b_cap<=a_cap; b_num<=a_num;
        b_col<=a_col; b_line<=a_line;
    end
end
wire [31:0] bits_g;
menu_font_rom u_font (.clk(clk), .addr({glyph, a_ly}), .bits(bits_g));
wire [15:0] bits_t, bits_u;
menu_digit_rom u_dig (.clk(clk), .addr_t({dig_t, a_ly}), .addr_u({dig_u, a_ly}), .bits_t(bits_t), .bits_u(bits_u));
wire [31:0] bits = b_num ? {bits_t, bits_u} : bits_g;
// ---------------- stage C ----------------
reg c_valid, c_hs, c_vs, c_bar, c_hi, c_sep, c_px0, c_px1, c_dim, c_cap;
reg [47:0] c_rgb; reg [1:0] c_line;
wire [4:0] bx = {b_col, 1'b0};
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin c_valid<=0; c_hs<=0; c_vs<=0; c_bar<=0; c_hi<=0; c_sep<=0; c_px0<=0; c_px1<=0; c_dim<=0; c_cap<=0; c_rgb<=0; c_line<=0; end
    else begin
        c_valid<=b_valid; c_hs<=b_hs; c_vs<=b_vs; c_rgb<=b_rgb; c_bar<=b_bar; c_hi<=b_hi; c_sep<=b_sep; c_dim<=b_dim; c_cap<=b_cap; c_line<=b_line;
        c_px0 <= b_ok && bits[5'd31 - bx];
        c_px1 <= b_ok && bits[5'd30 - bx];
    end
end
// ---------------- stage D : colour ----------------
reg d_valid, d_hs, d_vs; reg [47:0] d_rgb;
wire [23:0] bg   = c_hi ? 24'h104878 : 24'h101418;
wire [23:0] fg   = c_dim ? 24'h505050 : (c_line == 2'd0) ? 24'h80D0FF : (c_line == 2'd1) ? 24'hFFFFFF : 24'hC0C0C0;
wire [23:0] pix0 = c_sep ? 24'h60A0FF : (c_px0 ? fg : bg);
wire [23:0] pix1 = c_sep ? 24'h60A0FF : (c_px1 ? fg : bg);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin d_valid<=0; d_hs<=0; d_vs<=0; d_rgb<=0; end
    else begin
        d_valid<=c_valid; d_hs<=c_hs; d_vs<=c_vs;
        d_rgb <= c_bar ? {pix1, pix0} : c_cap ? { c_px1 ? fg : c_rgb[47:24], c_px0 ? fg : c_rgb[23:0] } : c_rgb;
    end
end
assign out_valid = d_valid; assign out_hs = d_hs; assign out_vs = d_vs; assign out_rgb2 = d_rgb;
endmodule
