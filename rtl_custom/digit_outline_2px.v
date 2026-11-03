`timescale 1ns/1ps
// Clean standard-glyph outlines. The camera grayscale is deliberately not used
// for drawing: a card-derived polygon span ROM is scaled to each matched box.
// Interpolated scanline endpoints preserve straight edges and smooth curves.
// One shared divider/multiplier pipeline prepares the next row in parallel with
// displaying the current row. Three small binary windows make a ~6 px outline.
module digit_outline_2px #(
    parameter integer PAIR_COUNT=960,LINE_COUNT=1080,LINE_CYCLES=1100,CROP_X_PAIR=240,
    parameter SPAN_FILE="digit_standard_spans.mem"
)(
    input wire clk,rst_n,enable,found,
    input wire [3:0] lhs_value,
    input wire [7:0] ink_threshold,
    input wire [23:0] box_x0,box_x1,
    input wire [26:0] box_y0,box_y1,
    input wire in_valid,in_hs,in_vs,
    input wire [15:0] in_gray2,
    output reg out_valid,out_hs,out_vs,
    output reg [1:0] out_mask2
);
localparam IDLE=0,CHAR=1,DIVIDE=2,ROM_WAIT=3,ROM_USE=4,
           MUL0=5,MUL1=6,SCALE=7,STORE=8,NEXT=9,READY=10;
reg [3:0] state;
reg vs_d,valid_d,show,five_l;
reg [9:0] xp;
reg [10:0] yp,prep_y;
reg [11:0] left[0:2],top[0:2],width[0:2],height[0:2];
reg [11:0] edges[0:11],next_edges[0:11];
reg [5:0] flags,next_flags;
reg [1:0] glyph,edge_index;
reg [25:0] numerator,quotient;
reg [11:0] denominator,remainder;
reg [4:0] div_count;
wire [12:0] trial={remainder,numerator[25]};
wire take=(trial>={1'b0,denominator});
wire [25:0] quotient_next={quotient[24:0],take};
reg [8:0] rom_addr;
reg [99:0] span_rom[0:511];
reg [99:0] rom_q,word_q;
initial $readmemh(SPAN_FILE,span_rom);
always @(posedge clk) rom_q<=span_rom[rom_addr];
reg [7:0] fraction;
wire [1:0] atlas_glyph=(glyph==0 && five_l) ? 2'd3 : glyph;
wire [11:0] edge_a=word_q[12*edge_index+:12];
wire [11:0] edge_b=word_q[50+12*edge_index+:12];
wire signed [12:0] delta=$signed({1'b0,edge_b})-$signed({1'b0,edge_a});
reg signed [21:0] interpolation_product;
reg [11:0] base_edge,interpolated;
reg [23:0] native_product;
integer k;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=IDLE;vs_d<=0;valid_d<=0;show<=0;five_l<=0;xp<=0;yp<=0;prep_y<=0;
        flags<=0;next_flags<=0;glyph<=0;edge_index<=0;
        numerator<=0;quotient<=0;denominator<=1;remainder<=0;div_count<=0;
        rom_addr<=0;word_q<=0;fraction<=0;interpolation_product<=0;base_edge<=0;interpolated<=0;native_product<=0;
        for(k=0;k<3;k=k+1) begin left[k]<=0;top[k]<=0;width[k]<=1;height[k]<=1;end
        for(k=0;k<12;k=k+1) begin edges[k]<=0;next_edges[k]<=0;end
    end else begin
        vs_d<=in_vs;valid_d<=in_valid;
        if(in_valid) begin
            if(xp==PAIR_COUNT-1) begin xp<=0;yp<=yp+1'b1;end
            else xp<=xp+1'b1;
        end
        case(state)
            IDLE:begin end
            CHAR:begin
                if(!show || prep_y<top[glyph] || {1'b0,prep_y}>=top[glyph]+height[glyph]) begin
                    next_flags[2*glyph+:2]<=0;state<=NEXT;
                end else begin
                    numerator<=(({15'd0,prep_y}-{14'd0,top[glyph]})*26'd2+26'd1)<<14;
                    denominator<=height[glyph];remainder<=0;quotient<=0;div_count<=25;state<=DIVIDE;
                end
            end
            DIVIDE:begin
                numerator<={numerator[24:0],1'b0};quotient<=quotient_next;
                remainder<=take ? trial-{1'b0,denominator} : trial;
                if(div_count==0) begin
                    rom_addr<={atlas_glyph,quotient_next[14:8]};fraction<=quotient_next[7:0];state<=ROM_WAIT;
                end else div_count<=div_count-1'b1;
            end
            ROM_WAIT:state<=ROM_USE;
            ROM_USE:begin
                // Do not interpolate across a split/merge of scanline intervals:
                // moving a collapsed endpoint across empty space creates dots.
                if(rom_q[49:48]!=rom_q[99:98]) begin
                    if(fraction[7]) begin word_q<={rom_q[99:50],rom_q[99:50]};next_flags[2*glyph+:2]<=rom_q[99:98];end
                    else begin word_q<={rom_q[49:0],rom_q[49:0]};next_flags[2*glyph+:2]<=rom_q[49:48];end
                end else begin word_q<=rom_q;next_flags[2*glyph+:2]<=rom_q[49:48];end
                edge_index<=0;state<=MUL0;
            end
            MUL0:begin interpolation_product<=delta*$signed({1'b0,fraction});base_edge<=edge_a;state<=MUL1;end
            MUL1:begin interpolated<=$signed({1'b0,base_edge})+(interpolation_product>>>8);state<=SCALE;end
            SCALE:begin native_product<=interpolated*width[glyph];state<=STORE;end
            STORE:begin
                next_edges[4*glyph+edge_index]<=left[glyph]+native_product[23:12];
                if(edge_index==3) state<=NEXT;else begin edge_index<=edge_index+1'b1;state<=MUL0;end
            end
            NEXT:begin
                if(glyph==2) state<=READY;else begin glyph<=glyph+1'b1;state<=CHAR;end
            end
            READY:if(!in_valid) begin
                for(k=0;k<12;k=k+1) edges[k]<=next_edges[k];
                flags<=next_flags;state<=IDLE;
            end
            default:state<=IDLE;
        endcase
        // Prepare row y+1 while the active row y is being displayed.
        if(in_valid && !valid_d && state==IDLE) begin prep_y<=yp+1'b1;glyph<=0;state<=CHAR;end
        if(in_vs && !vs_d) begin
            xp<=0;yp<=0;show<=enable && found;five_l<=(lhs_value==5);prep_y<=0;glyph<=0;state<=CHAR;
            for(k=0;k<3;k=k+1) begin
                left[k]<=2*CROP_X_PAIR+{2'd0,box_x0[8*k+:8],2'b0};
                top[k]<={1'b0,box_y0[9*k+:9],2'b0};
                width[k]<=({1'b0,box_x1[8*k+:8]}-{1'b0,box_x0[8*k+:8]}+9'd1)<<2;
                height[k]<=({1'b0,box_y1[9*k+:9]}-{1'b0,box_y0[9*k+:9]}+10'd1)<<2;
            end
        end
    end
end
wire [11:0] px0={1'b0,xp,1'b0},px1=px0+12'd1;
reg [1:0] ideal_ink;
always @* begin
    ideal_ink=0;
    for(integer j=0;j<3;j=j+1) if(show) begin
        if((flags[2*j] && px0>=edges[4*j] && px0<=edges[4*j+1]) ||
           (flags[2*j+1] && px0>=edges[4*j+2] && px0<=edges[4*j+3])) ideal_ink[0]=1;
        if((flags[2*j] && px1>=edges[4*j] && px1<=edges[4*j+1]) ||
           (flags[2*j+1] && px1>=edges[4*j+2] && px1<=edges[4*j+3])) ideal_ink[1]=1;
    end
end
wire v1,h1,s1,v2,h2,s2,v3,h3,s3;
wire [8:0] w10,w11,w20,w21,w30,w31;
line_buffer_3x3_2px_p #(.PAIR_COUNT(PAIR_COUNT),.MAX_LINES(LINE_COUNT),.LINE_CYCLES(LINE_CYCLES),.PIXEL_WIDTH(1)) u_gradient (
    .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_hs(in_hs),.in_vs(in_vs),.in_gray2(ideal_ink),
    .out_valid(v1),.out_hs(h1),.out_vs(s1),.win0(w10),.win1(w11));
reg gv,gh,gs,dv,dh,ds;
reg [1:0] gradient,dilated;
always @(posedge clk or negedge rst_n)
    if(!rst_n) begin gv<=0;gh<=0;gs<=0;gradient<=0;dv<=0;dh<=0;ds<=0;dilated<=0;end
    else begin
        gv<=v1;gh<=h1;gs<=s1;gradient<={(|w11)&&!(&w11),(|w10)&&!(&w10)};
        dv<=v2;dh<=h2;ds<=s2;dilated<={|w21,|w20};
    end
line_buffer_3x3_2px_p #(.PAIR_COUNT(PAIR_COUNT),.MAX_LINES(LINE_COUNT),.LINE_CYCLES(LINE_CYCLES),.PIXEL_WIDTH(1)) u_dilate1 (
    .clk(clk),.rst_n(rst_n),.in_valid(gv),.in_hs(gh),.in_vs(gs),.in_gray2(gradient),
    .out_valid(v2),.out_hs(h2),.out_vs(s2),.win0(w20),.win1(w21));
line_buffer_3x3_2px_p #(.PAIR_COUNT(PAIR_COUNT),.MAX_LINES(LINE_COUNT),.LINE_CYCLES(LINE_CYCLES),.PIXEL_WIDTH(1)) u_dilate2 (
    .clk(clk),.rst_n(rst_n),.in_valid(dv),.in_hs(dh),.in_vs(ds),.in_gray2(dilated),
    .out_valid(v3),.out_hs(h3),.out_vs(s3),.win0(w30),.win1(w31));
always @(posedge clk or negedge rst_n)
    if(!rst_n) begin out_valid<=0;out_hs<=0;out_vs<=0;out_mask2<=0;end
    else begin out_valid<=v3;out_hs<=h3;out_vs<=s3;out_mask2<=v3 ? {(|w31),(|w30)} : 2'b0;end
endmodule
