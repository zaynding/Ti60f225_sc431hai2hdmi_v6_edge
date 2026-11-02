`timescale 1ns/1ps
// edge frame -> shape_pool -> shape_ccl -> shape_classify  vs the Python golden (sim/shape/shape_int.py)
module tb_shape_chain;
parameter NSCENE = 6;
reg clk=0, rst_n=0; always #6.734 clk=~clk;
reg in_valid=0, in_vs=0; reg [1:0] in_edge2=0;
wire p_valid,p_bit,p_fs;
shape_pool u_pool(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_vs(in_vs),.in_edge2(in_edge2),.p_valid(p_valid),.p_bit(p_bit),.p_frame_start(p_fs));
wire fin_valid, frame_done; wire [195:0] fin_rec; wire [15:0] ovf, overrun;
shape_ccl u_ccl(.clk(clk),.rst_n(rst_n),.p_valid(p_valid),.p_bit(p_bit),.p_frame_start(p_fs),.fin_valid(fin_valid),.fin_rec(fin_rec),
    .frame_done(frame_done),.ovf_count(ovf),.overrun_count(overrun));
wire c_valid; wire [2:0] c_class; wire [7:0] cx0,cx1; wire [8:0] cy0,cy1; wire [31:0] c_i1,drops; wire c_el;
shape_classify u_cls(.clk(clk),.rst_n(rst_n),.in_valid(fin_valid),.in_rec(fin_rec),.out_valid(c_valid),.out_class(c_class),
    .out_xmin(cx0),.out_xmax(cx1),.out_ymin(cy0),.out_ymax(cy1),.out_i1(c_i1),.out_elong(c_el),.drop_count(drops));

reg [1919:0] frame_mem [0:1079];
reg [195:0] exp_rec [0:15];
reg [3:0]   exp_cls [0:15];
reg [195:0] got_rec [0:15];
integer n_exp, n_got, n_cls_ok, k, y, p, m, found, errs=0, cls_got[0:7], cls_exp[0:7];
reg [195:0] t;
always @(posedge clk) if (fin_valid) begin if (n_got < 16) got_rec[n_got] <= fin_rec; n_got <= n_got + 1; end
always @(posedge clk) if (c_valid) cls_got[c_class] = cls_got[c_class] + 1;

task send_frame;
    begin
        // vsync (5 lines) with no valid pixels, then 1080 lines of 1100 clocks, then 60 blank lines
        @(negedge clk); in_vs = 1; repeat (5*1100) @(negedge clk); in_vs = 0; repeat (40*1100) @(negedge clk);
        for (y = 0; y < 1080; y = y + 1) begin
            for (p = 0; p < 1100; p = p + 1) begin
                if (p < 960) begin in_valid = 1; in_edge2 = {frame_mem[y][2*p+1], frame_mem[y][2*p]}; end
                else in_valid = 0;
                @(negedge clk);
            end
        end
        in_valid = 0;
    end
endtask

initial begin
    for (k = 0; k < 8; k = k + 1) begin cls_got[k] = 0; cls_exp[k] = 0; end
    n_got = 0;
    repeat (10) @(negedge clk); rst_n = 1; repeat (10) @(negedge clk);
    for (k = 0; k < NSCENE; k = k + 1) begin
        n_got = 0; for (m = 0; m < 8; m = m + 1) begin cls_got[m] = 0; cls_exp[m] = 0; end
        $readmemh($sformatf("sim/build/shape/frame%0d.memh", k), frame_mem);
        for (m = 0; m < 16; m = m + 1) begin exp_rec[m] = {196{1'bx}}; exp_cls[m] = 4'hx; end
        $readmemh($sformatf("sim/build/shape/exp%0d.memh", k), exp_rec);
        $readmemh($sformatf("sim/build/shape/cls%0d.memh", k), exp_cls);
        n_exp = 0; for (m = 0; m < 16; m = m + 1) if (^exp_rec[m] !== 1'bx) begin n_exp = m + 1; cls_exp[exp_cls[m]] = cls_exp[exp_cls[m]] + 1; end
        send_frame;
        repeat (60*1100) @(negedge clk);      // let the last rows, flush and classification finish
        if (n_got != n_exp) begin errs = errs + 1; $display("scene %0d: %0d regions, expected %0d (ovf %0d overrun %0d)", k, n_got, n_exp, ovf, overrun); end
        for (m = 0; m < n_exp; m = m + 1) begin
            found = 0;
            for (y = 0; y < n_got; y = y + 1) if (got_rec[y] === exp_rec[m]) found = 1;
            if (!found) begin errs = errs + 1; $display("scene %0d: expected region %0d not found: %h", k, m, exp_rec[m]); end
        end
        for (m = 0; m < 8; m = m + 1) if (cls_got[m] != cls_exp[m]) begin errs = errs + 1; $display("scene %0d class %0d: got %0d expected %0d", k, m, cls_got[m], cls_exp[m]); end
        $display("scene %0d done: regions %0d/%0d ovf %0d overrun %0d", k, n_got, n_exp, ovf, overrun);
    end
    if (errs == 0) $display("PASS: shape_pool + shape_ccl + shape_classify match the Python golden on %0d full 1080p edge frames", NSCENE);
    else $fatal(1, "shape chain: %0d errors", errs);
    $finish;
end
endmodule
