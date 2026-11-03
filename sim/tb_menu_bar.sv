`timescale 1ns/1ps
module tb_menu_bar;
reg clk=0, rst_n=0; always #6.734 clk=~clk;
reg v=0,h=0,s=0; reg [47:0] d=48'h808080808080;
wire ov,oh,os; wire [47:0] od;
menu_bar_2px dut(.clk(clk),.rst_n(rst_n),.in_valid(v),.in_hs(h),.in_vs(s),.in_rgb2(d),.sel(3'd2),.src_mode(3'd6),.thr_idx(3'd2),.flash(3'd2),
    .shape_on(1'b1),.cmp_mode(1'b1),.algo(2'd2),.disp_mode(2'd2),.saved_valid(4'b0101),.out_valid(ov),.out_hs(oh),.out_vs(os),.out_rgb2(od));
integer line, clkn, fd, ly=0, started=0;
reg ov_d=0;
always @(posedge clk) begin
    ov_d <= ov;
    if (ov && started) $fwrite(fd, "%012h ", od);
    if (!ov && ov_d && started) begin $fwrite(fd, "\n"); end
end
initial begin
    fd = $fopen("sim/build/menu/bar_out.txt", "w");
    repeat(5) @(negedge clk); rst_n = 1; repeat(5) @(negedge clk);
    for (line = 0; line < 1130; line = line + 1) begin
        for (clkn = 0; clkn < 1100; clkn = clkn + 1) begin
            s = (line < 5); h = (clkn >= 1004 && clkn < 1026);
            if (line >= 41 && line < 1121 && clkn < 960) begin v = 1; end else v = 0;
            if (line == 41 + 1) started = 1;
            @(negedge clk);
        end
    end
    repeat(20) @(negedge clk);
    $fclose(fd); $finish;
end
endmodule
