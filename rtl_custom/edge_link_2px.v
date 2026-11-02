`timescale 1ns/1ps
module edge_link_2px #(
    parameter PAIR_COUNT=960, MAX_LINES=1080, LINE_CYCLES=1100
)(
    input wire clk,rst_n,in_valid,in_hs,in_vs,
    input wire [11:0] mag0,mag1,threshold,
    input wire [1:0] dir0,dir1,
    input wire en,                 // 0 = plain single threshold (strong bit), same latency
    output reg out_valid,out_hs,out_vs,edge0,edge1
);
wire v,h,s;
wire [35:0] w0,w1;
line_buffer_3x3_2px_p #(.PAIR_COUNT(PAIR_COUNT),.MAX_LINES(MAX_LINES),
    .LINE_CYCLES(LINE_CYCLES),.PIXEL_WIDTH(4)) u_window (
    .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_hs(in_hs),.in_vs(in_vs),
    .in_gray2({dir1,(mag1>(threshold>>1)),(mag1>threshold),
               dir0,(mag0>(threshold>>1)),(mag0>threshold)}),
    .out_valid(v),.out_hs(h),.out_vs(s),.win0(w0),.win1(w1));
function bridge;
    input [3:0] a,b;
    input [1:0] direction;
    begin bridge=a[0] && b[0] && a[3:2]==direction && b[3:2]==direction; end
endfunction
function weak_line;
    input [3:0] a,b;
    input [1:0] direction;
    begin weak_line=a[1] && b[1] && a[3:2]==direction && b[3:2]==direction; end
endfunction
function connected;
    input [35:0] w;
    input en;
    reg neighbor,continuous;
    integer i;
    begin
        neighbor=0;
        for(i=0;i<9;i=i+1) if(i!=4) neighbor=neighbor | w[i*4];
        case(w[19:18])
            0: continuous=weak_line(w[7*4 +:4],w[1*4 +:4],0);
            1: continuous=weak_line(w[6*4 +:4],w[2*4 +:4],1);
            2: continuous=weak_line(w[5*4 +:4],w[3*4 +:4],2);
            3: continuous=weak_line(w[8*4 +:4],w[0*4 +:4],3);
        endcase
        connected=!en ? w[16] : (w[16] || (w[17] && (neighbor || continuous)) ||
            bridge(w[7*4 +:4],w[1*4 +:4],0) ||
            bridge(w[6*4 +:4],w[2*4 +:4],1) ||
            bridge(w[5*4 +:4],w[3*4 +:4],2) ||
            bridge(w[8*4 +:4],w[0*4 +:4],3));
    end
endfunction
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin out_valid<=0; out_hs<=0; out_vs<=0; edge0<=0; edge1<=0; end
    else begin
        out_valid<=v; out_hs<=h; out_vs<=s;
        edge0<=v && connected(w0,en); edge1<=v && connected(w1,en);
    end
end
endmodule
