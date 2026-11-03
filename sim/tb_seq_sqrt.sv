`timescale 1ns/1ps
module tb_seq_sqrt;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg start=0; reg [63:0] x=0; wire [31:0] root; wire done;
seq_sqrt dut(.clk(clk),.rst_n(rst_n),.start(start),.x(x),.root(root),.done(done));
integer i, errs=0; reg [63:0] v; reg [31:0] expv;
function [31:0] ref_sqrt; input [63:0] a; reg [63:0] lo, hi, mid; integer k;
  begin lo=0; hi=64'h00000000ffffffff; for (k=0;k<34;k=k+1) begin mid = lo + ((hi-lo+64'd1)>>1); if (mid*mid <= a) lo=mid; else hi=mid-64'd1; end ref_sqrt = lo[31:0]; end
endfunction
initial begin
  repeat(4) @(negedge clk); rst_n=1; repeat(2) @(negedge clk);
  for (i=0;i<60;i=i+1) begin
    v = (i<10) ? i : (i<20) ? (64'd1 << (i+30)) + i : {$random,$random} >> (i%40);
    @(negedge clk); x=v; start=1; @(negedge clk); start=0;
    while (!done) @(negedge clk);
    expv = ref_sqrt(v);
    if (root !== expv) begin errs=errs+1; $display("MISMATCH %0d: sqrt(%0d)=%0d expected %0d", i, v, root, expv); end
  end
  if (errs==0) $display("PASS: seq_sqrt 60 vectors"); else $fatal(1,"seq_sqrt errors %0d",errs);
  $finish;
end
endmodule
