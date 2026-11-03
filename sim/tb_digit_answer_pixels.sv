`timescale 1ns/1ps
// Check the public video output: neither status text nor the large answer
// may leak 9/7 while answer_ready is low, including after covering 7 with 5.
module tb_digit_answer_pixels;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,v=0,s=0,ready=0;
reg [3:0] lhs=7;
reg [4:0] result=9;
wire ov,oh,os;
wire [47:0] rgb;
digit_result_overlay_2px dut(.clk(clk),.rst_n(rst_n),.enable(1'b1),.busy(1'b0),.found(1'b1),
    .answer_ready(ready),.lhs_value(lhs),.result(result),
    .box_x0({8'd80,8'd50,8'd20}),.box_x1({8'd100,8'd70,8'd40}),
    .box_y0({9'd20,9'd25,9'd20}),.box_y1({9'd60,9'd55,9'd60}),
    .in_valid(v),.in_hs(1'b0),.in_vs(s),.in_rgb2(48'hffffffffffff),
    .out_valid(ov),.out_hs(oh),.out_vs(os),.out_rgb2(rgb));
reg [43:0] glyphs[0:127];
integer frame_id=-1,x=0,y=0,f,l,c,k,px,dx,dy,bitx,row,bank,errors=0,checked=0;
reg os_d=0,hit;
reg [23:0] expected;
always @(posedge clk) begin
    os_d<=os;
    if(os && !os_d) begin frame_id=frame_id+1;x=0;y=0;end
    else if(ov) begin
        for(k=0;k<2;k=k+1) begin
            px=(2*x+k)%960;dx=px-420;dy=y-80;
            if(dx>=0 && dx<144 && dy>=0 && dy<128) begin
                expected=24'hffffff;
                if(frame_id%2==1) begin
                    expected=24'h202020;
                    hit=dx>=4 && dx<44 && ((dy>=42 && dy<50)||(dy>=78 && dy<86));
                    bank=(frame_id==3) ? 64 : 0;row=dy/2;bitx=(dx-56)/2;
                    if(dx>=56 && dx<144 && glyphs[bank+row][43-bitx]) hit=1;
                    if(hit) expected=24'h00ff00;
                end
                if(rgb[24*k+:24]!==expected) begin
                    if(errors<5) $display("FAIL answer frame=%0d x=%0d y=%0d got=%h expected=%h",frame_id,px,y,rgb[24*k+:24],expected);
                    errors=errors+1;
                end
                checked=checked+1;
            end
            if(frame_id%2==0 && px>=84 && px<128 && y>=76 && y<104 && rgb[24*k+:24]!==24'h202020)
                errors=errors+1;
        end
        if(x==959) begin x=0;y=y+1;end else x=x+1;
    end
end
initial begin
    $readmemh("digit_results.mem",glyphs);
    repeat(5) @(negedge clk);rst_n=1;
    for(f=0;f<4;f=f+1) begin
        ready=f%2;lhs=f<2 ? 7 : 5;result=f<2 ? 9 : 7;
        s=1;repeat(5) @(negedge clk);s=0;repeat(5) @(negedge clk);
        for(l=0;l<220;l=l+1) begin
            v=1;repeat(960) @(negedge clk);v=0;repeat(4) @(negedge clk);
        end
    end
    repeat(10) @(negedge clk);
    if(checked!=147456 || errors) $fatal(1,"answer pixel errors=%0d checked=%0d",errors,checked);
    $display("PASS: 147456 answer pixels, hidden status/results before ready, correct 9/7 ROM banks, old-answer removal");$finish;
end
endmodule
