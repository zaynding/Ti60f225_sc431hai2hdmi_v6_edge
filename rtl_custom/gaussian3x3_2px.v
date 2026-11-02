`timescale 1ns/1ps
// Integer Gaussian approximation [1 2 1]'*[1 2 1]/16, replicated borders.
module gaussian3x3_2px #(
    parameter PAIR_COUNT=960, MAX_LINES=1080, LINE_CYCLES=1100
)(
    input wire clk,rst_n,in_valid,in_hs,in_vs,
    input wire [15:0] in_gray2,
    input wire en,                 // 0 = pass the centre pixel (same latency)
    output reg out_valid,out_hs,out_vs,
    output reg [15:0] out_gray2
);
wire v,h,s;
wire [71:0] w0,w1;
line_buffer_3x3_2px_p #(.PAIR_COUNT(PAIR_COUNT),.MAX_LINES(MAX_LINES),.LINE_CYCLES(LINE_CYCLES)) u_window (
    .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_hs(in_hs),.in_vs(in_vs),.in_gray2(in_gray2),
    .out_valid(v),.out_hs(h),.out_vs(s),.win0(w0),.win1(w1));
function [7:0] smooth;
    input [71:0] w;
    reg [11:0] sum;
    integer i;
    begin
        sum=0;
        for(i=0;i<9;i=i+1)
            if(i==4) sum=sum+({4'd0,w[i*8 +:8]}<<2);
            else if(i==1 || i==3 || i==5 || i==7) sum=sum+({4'd0,w[i*8 +:8]}<<1);
            else sum=sum+{4'd0,w[i*8 +:8]};
        smooth=sum[11:4];
    end
endfunction
always @(posedge clk or negedge rst_n)
    if(!rst_n) begin out_valid<=0; out_hs<=0; out_vs<=0; out_gray2<=0; end
    else begin out_valid<=v; out_hs<=h; out_vs<=s; out_gray2<= en ? {smooth(w1),smooth(w0)} : {w1[39:32],w0[39:32]}; end
endmodule
