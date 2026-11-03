`timescale 1ns/1ps
module tb_fps_meter;
parameter CLK_HZ = 100000;         // 1 "second" = 100000 clocks so the test is short
reg clk=0, cclk=0, rst_n=0; always #5 clk=~clk; always #7 cclk=~cclk;
reg vs=0; reg tog=0; wire [6:0] fo, fc;
fps_meter #(.CLK_HZ(CLK_HZ)) dut(.clk(clk),.rst_n(rst_n),.vs_out(vs),.cam_tog(tog),.fps_out(fo),.fps_cam(fc));
integer i, errs=0, p_out, p_cam;
// output VS: one pulse every 1666 clocks (about 60 per "second"); camera: one toggle every 2381 camera clocks (about 30)
always @(posedge clk) begin : gen_out
  integer c; 
end
integer co=0; always @(posedge clk) begin co<=co+1; vs <= ((co % 1666) < 40); end
integer cc=0; always @(posedge cclk) begin cc<=cc+1; if (cc % 2381 == 0) tog <= ~tog; end
initial begin
  repeat(4) @(negedge clk); rst_n=1;
  repeat(3*CLK_HZ) @(negedge clk);
  $display("fps_out=%0d fps_cam=%0d", fo, fc);
  if (fo < 59 || fo > 61) begin errs=errs+1; $display("FAIL out"); end
  if (fc < 28 || fc > 31) begin errs=errs+1; $display("FAIL cam"); end
  if (errs==0) $display("PASS: fps_meter output %0d, camera %0d", fo, fc);
  $finish;
end
endmodule
