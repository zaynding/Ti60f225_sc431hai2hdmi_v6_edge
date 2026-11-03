`timescale 1ns/1ps
// one region record -> shape_classify -> shape_fit -> shape_fit_draw_2px (single confirmed track); dumps one frame
module tb_draw_ell;
parameter IDX = 0;
reg clk=0, rst_n=0; always #6.734 clk=~clk;
reg [331:0] vin[0:127];
reg in_valid=0; reg [331:0] in_rec=0;
wire c_valid, c_el; wire [2:0] c_class; wire [31:0] c_i1, c_drop; wire [7:0] x0,x1; wire [8:0] y0,y1;
wire [331:0] c_rec; wire [31:0] vxx,vyy,vxy; wire vneg; wire [63:0] dd;
shape_classify cls(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_rec(in_rec),.out_valid(c_valid),.out_class(c_class),
  .out_xmin(x0),.out_xmax(x1),.out_ymin(y0),.out_ymax(y1),.out_i1(c_i1),.out_elong(c_el),.drop_count(c_drop),
  .out_rec(c_rec),.out_vxx(vxx),.out_vyy(vyy),.out_vxy(vxy),.out_vxy_neg(vneg),.out_dd(dd));
wire f_valid; wire [2:0] f_kind; wire [323:0] f_par; wire [7:0] fx0,fx1; wire [8:0] fy0,fy1; wire [31:0] f_drop;
shape_fit fit(.clk(clk),.rst_n(rst_n),.in_valid(c_valid),.in_class(c_class),.in_rec(c_rec),.in_vxx(vxx),.in_vyy(vyy),.in_vxy(vxy),
  .in_vxy_neg(vneg),.in_dd(dd),.out_valid(f_valid),.out_kind(f_kind),.out_par(f_par),.out_xmin(fx0),.out_xmax(fx1),.out_ymin(fy0),.out_ymax(fy1),.drop_count(f_drop));
reg [323:0] par_r=0; reg [2:0] kind_r=0; reg [7:0] rx0=0, rx1=0; reg [8:0] ry0=0, ry1=0; reg vis=0;
always @(posedge clk) if (f_valid) begin par_r<=f_par; kind_r<=f_kind; rx0<=fx0; rx1<=fx1; ry0<=fy0; ry1<=fy1; vis<=1; end
reg dv_in=0, vs_in=0; reg [47:0] pic=0;
wire dv, dh, ds; wire [47:0] drgb;
shape_fit_draw_2px #(.NT(1)) draw(.clk(clk),.rst_n(rst_n),.enable(1'b1),.in_valid(dv_in),.in_hs(1'b0),.in_vs(vs_in),.in_rgb2(pic),
  .trk_vis(vis),.trk_cls(kind_r),.trk_xmin(rx0),.trk_xmax(rx1),.trk_ymin(ry0),.trk_ymax(ry1),.trk_par(par_r),
  .out_valid(dv),.out_hs(dh),.out_vs(ds),.out_rgb2(drgb));
integer n, i, y, p, fd, cycles; reg dv_d=0;
always @(posedge clk) begin
  dv_d <= dv;
  if (dv) $fwrite(fd, "%012h ", drgb);
  if (!dv && dv_d) $fwrite(fd, "\n");
end
initial begin
  $readmemh("sim/build/fit/fit_in.memh", vin);
  for (i=0;i<128;i=i+1) if (^vin[i] !== 1'bx) n=i+1;
  fd = $fopen("sim/build/fit/draw_out.txt","w");
  repeat(5) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
  @(negedge clk); in_valid=1; in_rec=vin[IDX]; @(negedge clk); in_valid=0;
  cycles=0; while (!f_valid && cycles < 20000) begin @(negedge clk); cycles=cycles+1; end
  repeat (50) @(negedge clk);
  $display("record %0d: class %0d kind %0d", IDX, c_class, kind_r);
  vs_in = 1; repeat (5*1100) @(negedge clk); vs_in = 0; repeat (20*1100) @(negedge clk);
  for (y = 0; y < 1080; y = y + 1) for (p = 0; p < 1100; p = p + 1) begin
    dv_in = (p < 960); pic = 48'h303030303030; @(negedge clk);
  end
  dv_in = 0; repeat (40) @(negedge clk);
  $fclose(fd); $finish;
end
endmodule
