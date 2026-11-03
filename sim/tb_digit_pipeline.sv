`timescale 1ns/1ps
// Exercise the actual existing median/Canny/despeckle path with digit masks.
// Pixel oracle checks colour row alignment and both contour panels.
module tb_digit_pipeline;
localparam P=64,L=64,LC=256;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,v=0,h=0,s=0;
reg [15:0] g=0;
wire mv,mh,ms,ev,eh,es,dv,dh,ds,ov,oh,os;
wire [15:0] mg;
wire e0,e1,se0,se1;
wire [1:0] de;
wire [47:0] rgb;
median_switch_2px #(.PAIR_COUNT(P),.MAX_LINES(L)) median(.clk(clk),.rst_n(rst_n),.in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),.en(1'b1),
    .out_valid(mv),.out_hs(mh),.out_vs(ms),.out_gray2(mg));
edge_algo_2px #(.PAIR_COUNT(P),.MAX_LINES(L),.LINE_CYCLES(LC),.SOBEL_DELAY_BASE(14),.AUTO_MIN_TOTAL(10)) edgepath(
    .clk(clk),.rst_n(rst_n),.in_valid(mv),.in_hs(mh),.in_vs(ms),.in_gray2(mg),.algo(2'd1),.th_main(12'd160),.th_raw(12'd160),
    .out_valid(ev),.out_hs(eh),.out_vs(es),.edge0(e0),.edge1(e1),.s_edge0(se0),.s_edge1(se1),.auto_main(),.auto_raw());
despeckle_2px #(.PAIR_COUNT(P),.MAX_LINES(L),.KEEP_MIN(1),.FILL_MIN(9)) desp(.clk(clk),.rst_n(rst_n),
    .in_valid(ev),.in_hs(eh),.in_vs(es),.in_edge2({e1,e0}),.out_valid(dv),.out_hs(dh),.out_vs(ds),.out_edge2(de));
wire cv,ch,cs;
wire [1:0] contour;
digit_outline_2px #(.PAIR_COUNT(P),.LINE_COUNT(L),.LINE_CYCLES(LC),.CROP_X_PAIR(16)) outline(
    .clk(clk),.rst_n(rst_n),.enable(1'b1),.found(1'b1),.lhs_value(4'd7),.ink_threshold(8'd128),
    .box_x0({8'd10,8'd6,8'd2}),.box_x1({8'd11,8'd7,8'd3}),
    .box_y0({9'd4,9'd6,9'd4}),.box_y1({9'd9,9'd7,9'd9}),
    .in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),.out_valid(cv),.out_hs(ch),.out_vs(cs),.out_mask2(contour));
display_split_2px #(.PAIR_COUNT(P),.LINE_COUNT(L),.CROP_X_PAIR(16),.CROP_PAIRS(32),.BUF_LINES(8),.DIGIT_SUPPORT(1)) split(
    .clk(clk),.rst_n(rst_n),.show_red(1'b1),.show_color(1'b1),.show_edge(1'b1),
    .sup_en(1'b0),.sup_vis(3'd0),.sup_xmin(24'd0),.sup_xmax(24'd0),.sup_ymin(27'd0),.sup_ymax(27'd0),
    .cmp_mode(1'b0),.s_edge0(se0),.s_edge1(se1),.src_valid(v),.src_vs(s),.src_rgb2({{3{g[15:8]}},{3{g[7:0]}}}),
    .digit_mode(1'b1),.digit_valid(cv),.digit_vs(cs),.digit_mask2(contour),
    .in_valid(dv),.in_hs(dh),.in_vs(ds),.edge0(de[0]),.edge1(de[1]),.out_valid(ov),.out_hs(oh),.out_vs(os),.out_rgb2(rgb));
function ink;
    input integer x,y;
    begin ink=(x>=40 && x<=47 && y>=16 && y<=39) || (x>=56 && x<=63 && y>=24 && y<=31) || (x>=72 && x<=79 && y>=16 && y<=39); end
endfunction
function [7:0] gray;
    input integer x,y;
    begin gray=ink(x,y) ? 20 : 200+(x+y)%55; end
endfunction
reg [1:0] golden[0:P*L-1];
integer f,l,c,x=0,y=0,frame=-1,errors=0,checked=0,k,px,sx;
reg os_d=0;
reg [23:0] expected;
always @(posedge clk) begin
    os_d<=os;
    if(os && !os_d) begin x=0;y=0;frame=frame+1; end
    else if(ov) begin
        if(frame==2) for(k=0;k<2;k=k+1) begin
            px=2*x+k; sx=(px%64)+32;
            if(golden[y*P+sx/2][sx%2]) expected=24'h00ff00;
            else if(px<64) expected={3{gray(sx,y)}};
            else expected=0;
            if(rgb[24*k+:24]!==expected) begin
                if(errors<10) $display("FAIL real pipeline x=%0d y=%0d got=%h expected=%h",px,y,rgb[24*k+:24],expected);
                errors=errors+1;
            end
            checked=checked+1;
        end
        if(x==P-1) begin x=0;y=y+1;end else x=x+1;
    end
end
initial begin
    $readmemh("sim/build/digits/pipeline_expected.mem",golden);
    repeat(8) @(negedge clk);rst_n=1;
    for(f=0;f<3;f=f+1) for(l=0;l<L+40;l=l+1) for(c=0;c<LC;c=c+1) begin
        s=(l<3);h=(c>=LC-8);v=(l>=20 && l<20+L && c<P);
        g={gray(2*c+1,l-20),gray(2*c,l-20)};
        @(negedge clk);
    end
    v=0;s=0;h=0;repeat(10*LC) @(negedge clk);
    if(checked<7000) begin errors=errors+1;$display("FAIL insufficient output %0d",checked);end
    if(errors) $fatal(1,"real-pipeline errors=%0d",errors);
    $display("PASS: real median/Canny/despeckle path, %0d display pixels aligned with original colour and contour",checked);$finish;
end
endmodule
