`timescale 1ns/1ps
module tb_flicker;
parameter PAIRS=100, LINES=80, LC=120, NF=8, ALGO=1, TH=400, SIG=0;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg v=0,h=0,s=0; reg [15:0] g=0;
wire ov,oh,os,e0,e1,se0,se1; wire [11:0] am, ar;
edge_algo_2px #(.PAIR_COUNT(PAIRS),.MAX_LINES(LINES),.LINE_CYCLES(LC),.SOBEL_DELAY_BASE(14),.AUTO_MIN_TOTAL(5000)) dut(.clk(clk),.rst_n(rst_n),
    .in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),.algo(ALGO[1:0]),.th_main(TH[11:0]),.th_raw(TH[11:0]),
    .out_valid(ov),.out_hs(oh),.out_vs(os),.edge0(e0),.edge1(e1),.s_edge0(se0),.s_edge1(se1),.auto_main(am),.auto_raw(ar));
reg [15:0] img[0:PAIRS*LINES*NF-1];
reg [0:0] cur [0:2*PAIRS*LINES-1], prev [0:2*PAIRS*LINES-1];
integer f,l,c, outf=-1, idx, diff, uni, tot_diff=0, tot_uni=0, edges=0;
reg os_d=0, ov_d=0;
always @(posedge clk) begin
    os_d<=os;
    if (os && !os_d) begin
        if (outf >= 2) begin tot_diff = tot_diff + diff; tot_uni = tot_uni + uni; end
        outf = outf + 1; idx = 0; diff = 0; uni = 0;
        for (c=0;c<2*PAIRS*LINES;c=c+1) begin prev[c] = cur[c]; cur[c] = 0; end
    end
    if (ov && outf>=0 && idx < 2*PAIRS*LINES-1) begin
        cur[idx] = e0; cur[idx+1] = e1;
        if (outf>=1) begin diff = diff + (e0 ^ prev[idx]) + (e1 ^ prev[idx+1]); uni = uni + (e0 | prev[idx]) + (e1 | prev[idx+1]); end
        idx = idx + 2;
    end
end
initial begin
    $readmemh("sim/build/algo/noisy.memh", img);
    repeat(5) @(negedge clk); rst_n=1; repeat(5) @(negedge clk);
    for (f=0; f<NF; f=f+1)
        for (l=0; l<LINES+30; l=l+1)
            for (c=0; c<LC; c=c+1) begin
                s=(l<3); h=(c>=LC-10);
                if (l>=15 && l<15+LINES && c<PAIRS) begin v=1; g=img[f*PAIRS*LINES+(l-15)*PAIRS+c]; end else begin v=0; g=0; end
                @(negedge clk);
            end
    repeat(4*LC) @(negedge clk);
    $display("RESULT algo=%0d th=%0d sig=%0d: frame-to-frame changed %0d of %0d edge pixels (%0d%%)  auto_main=%0d", ALGO, TH, SIG, tot_diff, tot_uni, (tot_uni==0)?0:(100*tot_diff/tot_uni), am);
    $finish;
end
endmodule
