`timescale 1ns/1ps
// Measures main-chain vs raw-Sobel latency, then checks alignment and the three modes.
module tb_edge_algo;
parameter PAIRS=100, LINES=80, LC=120, BASE=14, NF=7;
parameter IMG="sim/build/algo/img.memh", AUTO=400000;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg v=0,h=0,s=0; reg [15:0] g=0; reg [1:0] algo=0;
wire ov,oh,os,e0,e1,se0,se1; wire [11:0] am, ar;
edge_algo_2px #(.PAIR_COUNT(PAIRS),.MAX_LINES(LINES),.LINE_CYCLES(LC),.SOBEL_DELAY_BASE(BASE),.AUTO_MIN_TOTAL(AUTO)) dut(.clk(clk),.rst_n(rst_n),
    .in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),.algo(algo),.th_main(12'd160),.th_raw(12'd160),
    .out_valid(ov),.out_hs(oh),.out_vs(os),.edge0(e0),.edge1(e1),.s_edge0(se0),.s_edge1(se1),.auto_main(am),.auto_raw(ar));
reg [15:0] img[0:PAIRS*LINES-1];
integer f,l,c, outf=-1;
integer nedge[0:NF], nsedge[0:NF], mism[0:NF], nval[0:NF];
integer t_main=0, t_raw=0, clkcnt=0;
reg os_d=0, rs_d=0;
initial begin for (f=0;f<=NF;f=f+1) begin nedge[f]=0; nsedge[f]=0; mism[f]=0; nval[f]=0; end end
always @(posedge clk) begin
    clkcnt <= clkcnt + 1;
    os_d <= os; rs_d <= dut.rts;
    if (dut.rts && !rs_d && t_raw==0) t_raw = clkcnt;
    if (os && !os_d) begin outf = outf + 1; if (t_main==0) t_main = clkcnt; end
    if (ov && outf>=0 && outf<NF) begin
        nval[outf] = nval[outf] + 1;
        nedge[outf] = nedge[outf] + e0 + e1; nsedge[outf] = nsedge[outf] + se0 + se1;
        if (e0 !== se0 || e1 !== se1) mism[outf] = mism[outf] + 1;
    end
end
initial begin
    $readmemh(IMG, img);
    repeat(5) @(negedge clk); rst_n=1; repeat(5) @(negedge clk);
    for (f=0; f<NF; f=f+1) begin
        algo = (f==0||f==1) ? 2'd0 : (f==2||f==3) ? 2'd1 : (f==4||f==5) ? 2'd2 : 2'd1;
        for (l=0; l<LINES+30; l=l+1)
            for (c=0; c<LC; c=c+1) begin
                s = (l<3); h = (c>=LC-10);
                if (l>=15 && l<15+LINES && c<PAIRS) begin v=1; g=img[(l-15)*PAIRS+c]; end else begin v=0; g=0; end
                @(negedge clk);
            end
    end
    repeat(8*LC) @(negedge clk);
    $display("auto thresholds: main %0d raw %0d", am, ar);
    $display("latency main - raw = %0d clocks (LC=%0d  => base = %0d)", t_main - t_raw, LC, (t_main - t_raw) - 3*LC);
    for (f=0; f<NF; f=f+1) $display("frame %0d algo=%0d: valid %0d  main-edges %0d  raw-sobel-edges %0d  main!=raw %0d", f,
        (f==0||f==1)?0:(f==2||f==3)?1:(f==4||f==5)?2:1, nval[f], nedge[f], nsedge[f], mism[f]);
    $finish;
end
endmodule
