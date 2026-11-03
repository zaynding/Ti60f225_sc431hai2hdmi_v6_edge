`timescale 1ns/1ps
// End-to-end live video: K1 -> repeated moving frames -> nearest assignment ->
// clean standard contours and a moving '=9', without any UI freeze.
// The pre-existing edge branch is represented by a control-only delay here;
// tb_digit_pipeline separately exercises its real stages at a smaller size.
module tb_digit_video;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,v=0,h=0,s=0,key1=1,k0=0;
reg [15:0] g=16'hffff;
wire sp,lp,enable,start,freeze;
key_sl #(.DEBOUNCE_CYCLES(4),.LONG_CYCLES(20)) key(.clk(clk),.rst_n(rst_n),.key_n(key1),.short_p(sp),.long_p(lp));
ui_ctrl ui(.clk(clk),.rst_n(rst_n),.k0_s(k0),.k0_l(1'b0),.k1_s(sp),.k1_l(lp),
    .k2_s(1'b0),.k2_l(1'b0),.k3_s(1'b0),.k3_l(1'b0),.saved_valid(4'b0),.ext_slot1(1'b0),
    .freeze(freeze),.digit_active(enable),.digit_start(start),.view_mode(),.snapshot_toggle(),.clear_saved_toggle(),
    .sel(),.thr_idx(),.thr12(),.shape_on(),.fps_on(),.algo(),.thr_auto(),.disp_mode(),.src_mode(),.flash());
wire we,bit_in,cap_done,cap_busy,match_busy,match_done,found;
wire [15:0] addr;
wire [7:0] threshold;
wire [4:0] result;
wire [3:0] lhs;
wire [23:0] x0,x1;
wire [26:0] y0,y1;
digit_capture_2px cap(.clk(clk),.rst_n(rst_n),.enable(enable),.start(start),.ready(!match_busy),
    .in_valid(v),.in_vs(s),.in_gray2(g),.map_we(we),.map_addr(addr),.map_bit(bit_in),
    .done(cap_done),.busy(cap_busy),.ink_threshold(threshold));
digit_match_7p2 matcher(.clk(clk),.rst_n(rst_n),.enable(enable),.restart(start),.go(cap_done),
    .map_we(we),.map_waddr(addr),.map_wbit(bit_in),.busy(match_busy),.done(match_done),.found(found),
    .result(result),.lhs_value(lhs),.box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1));
wire stable_found,answer_ready;
wire [3:0] stable_lhs;
wire [4:0] stable_result;
wire [23:0] stable_x0,stable_x1;
wire [26:0] stable_y0,stable_y1;
reg input_vs_d=0;
always @(posedge clk) input_vs_d<=s;
// The default 18-frame delay is checked separately at full length. Shorten
// only the pixel fixture to one frame so it need not render 20+ HD frames.
digit_result_control #(.RESULT_DELAY_FRAMES(1)) control(.clk(clk),.rst_n(rst_n),.enable(enable),.restart(start),
    .frame_start(s && !input_vs_d),.det_done(match_done),.det_found(found),.det_lhs(lhs),.det_result(result),
    .det_x0(x0),.det_x1(x1),.det_y0(y0),.det_y1(y1),.stable_found(stable_found),.stable_lhs(stable_lhs),.stable_result(stable_result),
    .stable_x0(stable_x0),.stable_x1(stable_x1),.stable_y0(stable_y0),.stable_y1(stable_y1),.answer_ready(answer_ready));
wire mv,mh,ms;
wire [1:0] mask;
digit_outline_2px outline(.clk(clk),.rst_n(rst_n),.enable(enable),.found(stable_found),.lhs_value(stable_lhs),.ink_threshold(threshold),
    .box_x0(stable_x0),.box_x1(stable_x1),.box_y0(stable_y0),.box_y1(stable_y1),.in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),
    .out_valid(mv),.out_hs(mh),.out_vs(ms),.out_mask2(mask));
localparam DELAY=4460;
reg [2:0] delay [0:DELAY-1];
integer ptr=0;
reg [2:0] delayed=0;
always @(posedge clk) begin
    delay[ptr]<={v,h,s}; delayed<=delay[ptr];
    if(ptr==DELAY-1) ptr<=0; else ptr<=ptr+1;
end
wire sv,sh,ss;
wire [47:0] rgb;
wire [47:0] source={{3{g[15:8]}},{3{g[7:0]}}};
display_split_2px #(.DIGIT_SUPPORT(1)) split(.clk(clk),.rst_n(rst_n),
    .show_red(1'b1),.show_color(1'b1),.show_edge(1'b1),.sup_en(1'b0),.sup_vis(3'b0),
    .sup_xmin(24'd0),.sup_xmax(24'd0),.sup_ymin(27'd0),.sup_ymax(27'd0),.cmp_mode(1'b0),
    .s_edge0(1'b0),.s_edge1(1'b0),.src_valid(v),.src_vs(s),.src_rgb2(source),
    .digit_mode(enable),.digit_valid(mv),.digit_vs(ms),.digit_mask2(mask),
    .in_valid(delayed[2]),.in_hs(delayed[1]),.in_vs(delayed[0]),.edge0(1'b0),.edge1(1'b0),
    .out_valid(sv),.out_hs(sh),.out_vs(ss),.out_rgb2(rgb));
wire ov,oh,os;
wire [47:0] orgb;
reg vis_found=0,vs_d=0;
reg [4:0] vis_result=0;
reg [3:0] vis_lhs=0;
reg [23:0] vis_x0=0,vis_x1=0;
reg [26:0] vis_y0=0,vis_y1=0;
always @(posedge clk) begin
    vs_d<=s;
    if(s && !vs_d) begin vis_found<=stable_found;vis_result<=stable_result;vis_lhs<=stable_lhs;
        vis_x0<=stable_x0;vis_x1<=stable_x1;vis_y0<=stable_y0;vis_y1<=stable_y1;end
end
digit_result_overlay_2px overlay(.clk(clk),.rst_n(rst_n),.enable(enable),.busy(cap_busy||match_busy),.found(vis_found),
    .result(vis_result),.box_x0(vis_x0),.box_x1(vis_x1),.box_y0(vis_y0),.box_y1(vis_y1),
    .lhs_value(vis_lhs),.answer_ready(answer_ready),
    .in_valid(sv),.in_hs(sh),.in_vs(ss),.in_rgb2(rgb),.out_valid(ov),.out_hs(oh),.out_vs(os),.out_rgb2(orgb));
reg [15:0] image[0:518399];
reg [15:0] image_moved[0:518399];
reg [1:0] golden[0:1036799];
integer f,l,c,j,errors=0,starts=0,fdone=0;
integer mx=0,my=0,mframe=-1,ox=0,oy=0,oframe=-1,mask_checked=0,pixels_written=0;
reg ms_d=0,os_d=0;
integer video;
always @(posedge clk) begin
    if(start) starts=starts+1;
    if(match_done) fdone=fdone+1;
    if(freeze || (we && match_busy)) begin $display("FAIL live freeze/shared-memory overlap");errors=errors+1;end
    ms_d<=ms; os_d<=os;
    if(ms && !ms_d) begin mx=0; my=0; mframe=mframe+1; end
    else if(mv) begin
        if(mframe==7) begin
            if(mask!==golden[my*960+mx]) begin
                if(errors<10) $display("FAIL contour xpair=%0d y=%0d got=%b expected=%b",mx,my,mask,golden[my*960+mx]);
                errors=errors+1;
            end
            mask_checked=mask_checked+1;
        end
        if(mx==959) begin mx=0; my=my+1; end else mx=mx+1;
    end
    if(os && !os_d) begin ox=0; oy=0; oframe=oframe+1; end
    else if(ov) begin
        if(oframe==7) begin
            $fdisplay(video,"%012h",orgb); pixels_written=pixels_written+2;
        end
        if(ox==959) begin ox=0; oy=oy+1; end else ox=ox+1;
    end
end
initial begin
    for(j=0;j<DELAY;j=j+1) delay[j]=0;
    $readmemh("sim/digits/vectors/card_gray2.mem",image);
    $readmemh("sim/digits/vectors/card5_moved_gray2.mem",image_moved);
    $readmemh("sim/build/digits/outline_expected.mem",golden);
    video=$fopen("sim/build/digits/video.hex","w");
    repeat(10) @(negedge clk); rst_n=1; key1=0;
    repeat(100) @(negedge clk); key1=1;
    for(f=0;f<8;f=f+1) begin
        for(l=0;l<1125;l=l+1) begin
            for(c=0;c<1100;c=c+1) begin
                s=(l<3); h=(c>=1080); v=(l>=20 && l<1100 && c<960); g=16'hffff;
                if(v && c>=240 && c<720) g=(f<2) ? image[(l-20)*480+c-240] : image_moved[(l-20)*480+c-240];
                @(negedge clk);
            end
        end
    end
    s=0; h=0; v=0; repeat(450000) @(negedge clk);
    $fclose(video);
    if(freeze || !found || lhs!=5 || result!=7 || !answer_ready || starts!=1 || fdone<3 || mask_checked!=1036800 || pixels_written!=2073600) begin
        $display("FAIL state freeze=%0d found=%0d result=%0d starts=%0d done=%0d checked=%0d pixels=%0d",
            freeze,found,result,starts,fdone,mask_checked,pixels_written); errors=errors+1;
    end
    k0=1; @(negedge clk); k0=0; repeat(4) @(negedge clk);
    if(enable || freeze || found) begin errors=errors+1; $display("FAIL K0 exit"); end
    if(errors) $fatal(1,"digit video errors=%0d",errors);
    $display("PASS: real 7 covered by 5 in moving 1080p video, 1036800 standard-mask pairs, delayed 5+2=7, K0 exit"); $finish;
end
endmodule
