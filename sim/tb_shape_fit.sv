`timescale 1ns/1ps
// records -> shape_classify -> shape_fit ; dumps "kind par" for comparison with sim/shape/fitgold.py
module tb_shape_fit;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg [331:0] vin[0:127];
reg in_valid=0; reg [331:0] in_rec=0;
wire c_valid, c_el; wire [2:0] c_class; wire [31:0] c_i1, c_drop; wire [7:0] x0,x1; wire [8:0] y0,y1;
wire [331:0] c_rec; wire [31:0] vxx,vyy,vxy; wire vneg; wire [63:0] dd;
shape_classify cls(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_rec(in_rec),.out_valid(c_valid),.out_class(c_class),
  .out_xmin(x0),.out_xmax(x1),.out_ymin(y0),.out_ymax(y1),.out_i1(c_i1),.out_elong(c_el),.drop_count(c_drop),
  .out_rec(c_rec),.out_vxx(vxx),.out_vyy(vyy),.out_vxy(vxy),.out_vxy_neg(vneg),.out_dd(dd));
wire f_valid; wire [2:0] f_kind; wire [323:0] f_par; wire [31:0] f_drop;
shape_fit fit(.clk(clk),.rst_n(rst_n),.in_valid(c_valid),.in_class(c_class),.in_rec(c_rec),.in_vxx(vxx),.in_vyy(vyy),.in_vxy(vxy),
  .in_vxy_neg(vneg),.in_dd(dd),.out_valid(f_valid),.out_kind(f_kind),.out_par(f_par),.out_xmin(),.out_xmax(),.out_ymin(),.out_ymax(),.drop_count(f_drop));
integer i, n, fd, cycles;
initial begin
  $readmemh("sim/build/fit/fit_in.memh", vin);
  for (i=0;i<128;i=i+1) if (^vin[i] !== 1'bx) n=i+1;
  fd = $fopen("sim/build/fit/fit_out.txt","w");
  repeat(5) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
  for (i=0;i<n;i=i+1) begin
    @(negedge clk); in_valid=1; in_rec=vin[i]; @(negedge clk); in_valid=0;
    cycles=0;
    while (!f_valid && cycles < 20000) begin @(negedge clk); cycles=cycles+1; end
    if (!f_valid) $fatal(1, "record %0d: no fit result", i);
    $fwrite(fd, "%0d %0d %081h\n", f_kind, cycles, f_par);
  end
  $fclose(fd);
  $display("DONE tb_shape_fit %0d records, classify drops %0d, fit drops %0d", n, c_drop, f_drop);
  $finish;
end
endmodule
