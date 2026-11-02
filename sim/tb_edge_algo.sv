`timescale 1ns/1ps
module tb_edge_algo;
localparam PAIRS=100, LINES=80, LC=120, NF=6;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg v=0,h=0,s=0; reg [15:0] g=0; reg algo=0;
wire ov,oh,os,e0,e1;
edge_algo_2px #(.PAIR_COUNT(PAIRS),.MAX_LINES(LINES),.LINE_CYCLES(LC)) dut(.clk(clk),.rst_n(rst_n),.in_valid(v),.in_hs(h),.in_vs(s),.in_gray2(g),
    .algo(algo),.threshold(12'd160),.out_valid(ov),.out_hs(oh),.out_vs(os),.edge0(e0),.edge1(e1));
reg [15:0] img[0:PAIRS*LINES-1];
integer f,l,c, fd, outf=-1, outl=0, nvalid[0:NF], nedge[0:NF], nlines[0:NF];
reg os_d=0, ov_d=0;
initial begin for (f=0;f<=NF;f=f+1) begin nvalid[f]=0; nedge[f]=0; nlines[f]=0; end end
always @(posedge clk) begin
    os_d<=os; ov_d<=ov;
    if (os && !os_d) begin outf = outf + 1; end
    if (ov && outf>=0 && outf<NF) begin
        nvalid[outf] = nvalid[outf] + 1; nedge[outf] = nedge[outf] + e0 + e1;
        $fwrite(fd, "%0d %0d %0d\n", outf, e0, e1);
    end
    if (!ov && ov_d && outf>=0) nlines[outf] = nlines[outf] + 1;
end
initial begin
    $readmemh("sim/build/algo/img.memh", img);
    fd = $fopen("sim/build/algo/out.txt","w");
    repeat(5) @(negedge clk); rst_n=1; repeat(5) @(negedge clk);
    for (f=0; f<NF; f=f+1) begin
        algo = (f==2 || f==3 || f==5) ? 1'b1 : 1'b0;
        for (l=0; l<LINES+30; l=l+1)
            for (c=0; c<LC; c=c+1) begin
                s = (l<3);
                h = (c>=LC-10);
                if (l>=15 && l<15+LINES && c<PAIRS) begin v=1; g=img[(l-15)*PAIRS+c]; end else begin v=0; g=0; end
                @(negedge clk);
            end
    end
    repeat(8*LC) @(negedge clk);
    $fclose(fd);
    for (f=0; f<NF; f=f+1) $display("frame %0d: valid pairs %0d lines %0d edge pixels %0d", f, nvalid[f], nlines[f], nedge[f]);
    $finish;
end
endmodule
