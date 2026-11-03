`timescale 1ns/1ps
// Shared result glyph ROM for 9/7. Both status and large answer honor the delay.
// Two-clock video pipeline, matching synchronous result-glyph ROM reads.
module digit_result_overlay_2px #(
    parameter integer PANEL_PAIRS=480, BAR_Y=960,
    parameter RESULT_FILE="digit_results.mem"
)(
    input wire clk,rst_n,enable,busy,found,answer_ready,
    input wire [3:0] lhs_value,
    input wire [4:0] result,
    input wire [23:0] box_x0,box_x1,
    input wire [26:0] box_y0,box_y1,
    input wire in_valid,in_hs,in_vs,
    input wire [47:0] in_rgb2,
    output reg out_valid,out_hs,out_vs,
    output reg [47:0] out_rgb2
);
reg vs_d,valid_d,mode_l,found_l,busy_l,ready_l;
reg [3:0] lhs_l;
reg [4:0] value_l;
reg [9:0] xp;
reg [10:0] yp;
reg [11:0] result_x,result_y;
wire [9:0] local_pair=xp>=PANEL_PAIRS ? xp-PANEL_PAIRS : xp;
wire [11:0] px0={1'b0,local_pair,1'b0},px1=px0+12'd1;
wire [11:0] expression_right={2'd0,box_x1[23:16],2'b0}+12'd20;
wire [8:0] top_cell=box_y0[8:0]<box_y0[26:18] ? box_y0[8:0] : box_y0[26:18];
wire [8:0] bottom_cell=box_y1[8:0]>box_y1[26:18] ? box_y1[8:0] : box_y1[26:18];
wire [11:0] expression_top={1'b0,top_cell,2'b0};
wire [11:0] expression_bottom={1'b0,bottom_cell,2'b0}+12'd20;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        vs_d<=0; valid_d<=0; xp<=0; yp<=0; mode_l<=0; found_l<=0; busy_l<=0; ready_l<=0;lhs_l<=0;value_l<=0;result_x<=0; result_y<=0;
    end else begin
        vs_d<=in_vs; valid_d<=in_valid;
        if(in_vs && !vs_d) begin
            xp<=0; yp<=0; mode_l<=enable; found_l<=enable && found; busy_l<=busy;
            ready_l<=answer_ready && (result==9 || result==7);lhs_l<=lhs_value;value_l<=result;
            if(expression_right+12'd144<=2*PANEL_PAIRS) begin
                result_x<=expression_right;
                result_y<=expression_top+12'd128<BAR_Y ? expression_top : BAR_Y-136;
            end else begin
                result_x<={2'd0,box_x0[7:0],2'b0};
                if(expression_bottom+12'd128<BAR_Y) result_y<=expression_bottom;
                else result_y<=expression_top>=144 ? expression_top-12'd144 : 12'd8;
            end
        end else if(in_valid) xp<=xp+1'b1;
        else if(valid_d) begin xp<=0; yp<=yp+1'b1; end
    end
end

function [34:0] letter;
    input [7:0] c;
    begin
        case(c)
            "S": letter=35'b01111_10000_10000_01110_00001_00001_11110;
            "C": letter=35'b01110_10001_10000_10000_10000_10001_01110;
            "A": letter=35'b01110_10001_10001_11111_10001_10001_10001;
            "N": letter=35'b10001_11001_11001_10101_10011_10011_10001;
            "O": letter=35'b01110_10001_10001_10001_10001_10001_01110;
            "M": letter=35'b10001_11011_10101_10101_10001_10001_10001;
            "T": letter=35'b11111_00100_00100_00100_00100_00100_00100;
            "H": letter=35'b10001_10001_10001_11111_10001_10001_10001;
            "K": letter=35'b10001_10010_10100_11000_10100_10010_10001;
            "7": letter=35'b11111_00001_00010_00100_01000_01000_01000;
            "5": letter=35'b11111_10000_10000_11110_00001_10001_01110;
            "+": letter=35'b00000_00100_00100_11111_00100_00100_00000;
            "2": letter=35'b01110_10001_00001_00010_00100_01000_11111;
            "=": letter=35'b00000_00000_11111_00000_11111_00000_00000;
            "9": letter=35'b01110_10001_10001_01111_00001_00010_01100;
            default: letter=0;
        endcase
    end
endfunction
function [7:0] status_char;
    input [2:0] i;
    input f,b;
    reg [63:0] word;
    begin
        word=b ? "SCAN    " : "NO MATCH";
        if(f) begin
            word="7+2     ";
            word[63:56]=(lhs_l==5) ? "5" : "7";
            if(ready_l) begin word[39:32]="=";word[31:24]=(value_l==7) ? "7" : "9";word[15:0]="OK";end
        end
        status_char=word[63-8*i-:8];
    end
endfunction
function text_pixel;
    input [11:0] x,y;
    reg [7:0] col,row;
    reg [34:0] glyph;
    begin
        text_pixel=0; col=(x-12)>>2; row=(y-76)>>2;
        glyph=letter(status_char(col/6,found_l,busy_l));
        if(x>=12 && x<204 && y>=76 && y<104 && (col%6)<5)
            text_pixel=glyph[34-5*row-(col%6)];
    end
endfunction
wire [11:0] dy={1'b0,yp}-result_y;
wire [11:0] dx0=px0-result_x,dx1=px1-result_x;
wire result_row=found_l && ready_l && yp>=result_y && yp<result_y+128;
wire plate0=mode_l && result_row && px0>=result_x && px0<result_x+144;
wire plate1=mode_l && result_row && px1>=result_x && px1<result_x+144;
wire eqrow=(dy>=42 && dy<50)||(dy>=78 && dy<86);
wire eq0=plate0 && eqrow && dx0>=4 && dx0<44;
wire eq1=plate1 && eqrow && dx1>=4 && dx1<44;
wire nine0=plate0 && dx0>=56 && dx0<144;
wire nine1=plate1 && dx1>=56 && dx1<144;
wire status0=mode_l && px0>=8 && px0<208 && yp>=72 && yp<108;
wire status1=mode_l && px1>=8 && px1<208 && yp>=72 && yp<108;
reg [43:0] nine_rom [0:127];
reg [43:0] nine_q;
initial $readmemh(RESULT_FILE,nine_rom);
always @(posedge clk) nine_q<=nine_rom[{value_l==7,dy[6:1]}];
reg a_valid,a_hs,a_vs,a_p0,a_p1,a_eq0,a_eq1,a_n0,a_n1,a_s0,a_s1,a_t0,a_t1;
reg [5:0] a_x0,a_x1;
reg [47:0] a_rgb;
reg [23:0] a_color;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        a_valid<=0; a_hs<=0; a_vs<=0; a_p0<=0; a_p1<=0; a_eq0<=0; a_eq1<=0;
        a_n0<=0; a_n1<=0; a_s0<=0; a_s1<=0; a_t0<=0; a_t1<=0;
        a_x0<=0; a_x1<=0; a_rgb<=0; a_color<=0;
        out_valid<=0; out_hs<=0; out_vs<=0; out_rgb2<=0;
    end else begin
        a_valid<=in_valid; a_hs<=in_hs; a_vs<=in_vs; a_rgb<=in_rgb2;
        a_p0<=plate0; a_p1<=plate1; a_eq0<=eq0; a_eq1<=eq1;
        a_n0<=nine0; a_n1<=nine1; a_x0<=(dx0-56)>>1; a_x1<=(dx1-56)>>1;
        a_s0<=status0; a_s1<=status1;
        a_t0<=text_pixel(px0,{1'b0,yp}); a_t1<=text_pixel(px1,{1'b0,yp});
        a_color<=found_l ? 24'h00FF00 : (busy_l ? 24'h00FFFF : 24'h0000FF);
        out_valid<=a_valid; out_hs<=a_hs; out_vs<=a_vs;
        out_rgb2[23:0]<=a_s0 ? (a_t0 ? a_color : 24'h202020) :
            ((a_eq0 || (a_n0 && nine_q[43-a_x0])) ? 24'h00FF00 : (a_p0 ? 24'h202020 : a_rgb[23:0]));
        out_rgb2[47:24]<=a_s1 ? (a_t1 ? a_color : 24'h202020) :
            ((a_eq1 || (a_n1 && nine_q[43-a_x1])) ? 24'h00FF00 : (a_p1 ? 24'h202020 : a_rgb[47:24]));
    end
end
endmodule
