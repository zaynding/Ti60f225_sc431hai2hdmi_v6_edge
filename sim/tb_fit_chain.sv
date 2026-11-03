`timescale 1ns/1ps
// edge frames -> pool -> ccl -> classify -> fit -> track -> fitted outline drawn on a flat picture (last frame dumped)
module tb_fit_chain;
parameter SCENE = 0, NFRAME = 7;
reg clk=0, rst_n=0; always #6.734 clk=~clk;
reg in_valid=0, in_vs=0; reg [1:0] in_edge2=0;
wire p_valid,p_bit,p_fs;
shape_pool u_pool(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_vs(in_vs),.in_edge2(in_edge2),.p_valid(p_valid),.p_bit(p_bit),.p_frame_start(p_fs));
wire fin_valid, frame_done; wire [331:0] fin_rec; wire [15:0] ovf, overrun;
shape_ccl u_ccl(.clk(clk),.rst_n(rst_n),.p_valid(p_valid),.p_bit(p_bit),.p_frame_start(p_fs),.fin_valid(fin_valid),.fin_rec(fin_rec),
    .frame_done(frame_done),.ovf_count(ovf),.overrun_count(overrun));
wire c_valid, c_el; wire [2:0] c_class; wire [7:0] cx0,cx1; wire [8:0] cy0,cy1; wire [31:0] c_i1,c_drop;
wire [331:0] c_rec; wire [31:0] vxx,vyy,vxy; wire vneg; wire [63:0] dd;
shape_classify u_cls(.clk(clk),.rst_n(rst_n),.in_valid(fin_valid),.in_rec(fin_rec),.out_valid(c_valid),.out_class(c_class),
    .out_xmin(cx0),.out_xmax(cx1),.out_ymin(cy0),.out_ymax(cy1),.out_i1(c_i1),.out_elong(c_el),.drop_count(c_drop),
    .out_rec(c_rec),.out_vxx(vxx),.out_vyy(vyy),.out_vxy(vxy),.out_vxy_neg(vneg),.out_dd(dd));
wire f_valid; wire [2:0] f_kind; wire [323:0] f_par; wire [7:0] fx0,fx1; wire [8:0] fy0,fy1; wire [31:0] f_drop;
shape_fit u_fit(.clk(clk),.rst_n(rst_n),.in_valid(c_valid),.in_class(c_class),.in_rec(c_rec),.in_vxx(vxx),.in_vyy(vyy),.in_vxy(vxy),
    .in_vxy_neg(vneg),.in_dd(dd),.out_valid(f_valid),.out_kind(f_kind),.out_par(f_par),.out_xmin(fx0),.out_xmax(fx1),.out_ymin(fy0),.out_ymax(fy1),.drop_count(f_drop));
wire [2:0] t_vis; wire [8:0] t_cls; wire [23:0] t_x0,t_x1; wire [26:0] t_y0,t_y1; wire [971:0] t_par;
shape_track #(.NT(3),.NP(3)) u_trk(.clk(clk),.rst_n(rst_n),.frame_start(p_fs),.det_valid(f_valid),.det_class(f_kind),.det_xmin(fx0),.det_xmax(fx1),
    .det_ymin(fy0),.det_ymax(fy1),.det_par(f_par),.trk_vis(t_vis),.trk_cls(t_cls),.trk_xmin(t_x0),.trk_xmax(t_x1),.trk_ymin(t_y0),.trk_ymax(t_y1),.trk_par(t_par));
// picture: flat grey with the raw edge pixels in white (so that the fitted line can be compared with them)
reg [47:0] pic;
wire dv, dh, ds; wire [47:0] drgb;
reg v_d=0, s_d=0; reg [47:0] pic_d=0;
shape_fit_draw_2px #(.NT(3)) u_draw(.clk(clk),.rst_n(rst_n),.enable(1'b1),.in_valid(in_valid),.in_hs(1'b0),.in_vs(in_vs),.in_rgb2(pic),
    .trk_vis(t_vis),.trk_cls(t_cls),.trk_xmin(t_x0),.trk_xmax(t_x1),.trk_ymin(t_y0),.trk_ymax(t_y1),.trk_par(t_par),
    .out_valid(dv),.out_hs(dh),.out_vs(ds),.out_rgb2(drgb));
reg [1919:0] frame_mem [0:1079];
integer f, y, p, fd, frame_idx=0, line_idx=0;
reg dv_d=0, ds_d=0;
always @(posedge clk) begin
    dv_d <= dv; ds_d <= ds;
    if (ds && !ds_d) begin frame_idx <= frame_idx + 1; end
    if (dv && frame_idx == NFRAME) $fwrite(fd, "%012h ", drgb);
    if (!dv && dv_d && frame_idx == NFRAME) $fwrite(fd, "\n");
end
integer line_i;
task send_frame;
    begin
        @(negedge clk); in_vs = 1; repeat (5*1100) @(negedge clk); in_vs = 0; repeat (40*1100) @(negedge clk);
        for (y = 0; y < 1080; y = y + 1) begin
            for (p = 0; p < 1100; p = p + 1) begin
                if (p < 960) begin
                    in_valid = 1; in_edge2 = {frame_mem[y][2*p+1], frame_mem[y][2*p]};
                    pic = {in_edge2[1] ? 24'hFFFFFF : 24'h303030, in_edge2[0] ? 24'hFFFFFF : 24'h303030};
                end else begin in_valid = 0; pic = 0; end
                @(negedge clk);
            end
        end
        in_valid = 0;
    end
endtask
initial begin
    $readmemh($sformatf("sim/build/shape/frame%0d.memh", SCENE), frame_mem);
    fd = $fopen("sim/build/shape/fit_draw.txt", "w");
    repeat (10) @(negedge clk); rst_n = 1; repeat (10) @(negedge clk);
    for (f = 0; f < NFRAME + 1; f = f + 1) begin send_frame; repeat (60*1100) @(negedge clk); end
    repeat (20*1100) @(negedge clk);
    $fclose(fd);
    $display("DONE tb_fit_chain scene %0d: tracks visible %b classes %h, fit drops %0d", SCENE, t_vis, t_cls, f_drop);
    $finish;
end
endmodule
