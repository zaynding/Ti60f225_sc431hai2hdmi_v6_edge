`timescale 1ns/1ps
// Keys -> ui_ctrl, and the menu bar rendered into a PNG-able text dump.
module tb_ui_menu;
reg clk=0, rst_n=0; always #6.734 clk=~clk;
reg [3:0] key_n = 4'hF;
wire [3:0] sp, lp;
genvar g;
generate for (g=0; g<4; g=g+1) begin : k
    key_sl #(.DEBOUNCE_CYCLES(20), .LONG_CYCLES(400)) u (.clk(clk), .rst_n(rst_n), .key_n(key_n[g]), .short_p(sp[g]), .long_p(lp[g]));
end endgenerate
reg [3:0] valid = 4'b0000;
wire freeze, snap, shape_on, thr_auto, fps_on; wire [1:0] algo; wire [2:0] view, sel, thr, src, flash; wire [11:0] thr12; wire [1:0] disp;
ui_ctrl #(.ROT_CYCLES(300)) u_ui (.clk(clk), .rst_n(rst_n), .k0_s(sp[0]), .k0_l(lp[0]), .k1_s(sp[1]), .k1_l(lp[1]), .k2_s(sp[2]), .k2_l(lp[2]),
    .k3_s(sp[3]), .k3_l(lp[3]), .saved_valid(valid), .freeze(freeze), .view_mode(view), .snapshot_toggle(snap), .sel(sel), .thr_idx(thr),
    .thr12(thr12), .shape_on(shape_on), .fps_on(fps_on), .algo(algo), .thr_auto(thr_auto), .disp_mode(disp), .src_mode(src), .flash(flash));
task press(input integer k, input integer len);
    begin key_n[k] = 0; repeat(len) @(negedge clk); key_n[k] = 1; repeat(60) @(negedge clk); end
endtask
integer errs = 0;
task check(input cond, input [255:0] msg); begin if (!cond) begin errs = errs + 1; $display("FAIL: %0s", msg); end end endtask
reg snap0;
initial begin
    repeat(5) @(negedge clk); rst_n = 1; repeat(5) @(negedge clk);
    // K1: 6 steps and wrap
    repeat(3) press(1, 60); check(thr == 5 && thr12 == 64 && !thr_auto, "thr step 5");
    press(1, 60); check(thr == 6 && thr_auto, "thr auto");
    press(1, 60); check(thr == 0 && thr12 == 320 && !thr_auto, "thr wrap");
    press(1, 60); press(1, 700); check(thr == 2, "thr long reset");
    // K0: freeze toggle
    press(0, 60); check(freeze && src == 1, "freeze on"); press(0, 60); check(!freeze && src == 0, "live");
    // K2 select, K3 change
    press(2, 60); check(sel == 1, "sel 1"); press(2, 60); check(sel == 2, "sel 2");
    press(3, 60); check(!shape_on, "shape off"); press(3, 700); check(shape_on, "shape default");
    press(2, 60); check(algo == 1, "algo default canny"); press(3, 60); check(algo == 2, "algo compare"); press(3, 60); check(algo == 0, "algo sobel"); press(3, 60); check(algo == 1, "algo canny"); press(3, 60); press(3, 700); check(algo == 1, "algo default");
    press(2, 60); press(3, 60); check(disp == 1, "disp 1"); press(3, 60); check(disp == 2, "disp 2"); press(3, 60); check(disp == 0, "disp 0");
    press(2, 700); check(sel == 3, "sel back");
    // capture: K0 long
    snap0 = snap; press(0, 700); check(snap != snap0, "capture toggled");
    valid = 4'b0101; repeat(10) @(negedge clk); check(flash == 1, "flash slot");
    // frame-rate option: item 5
    while (sel != 5) press(2, 60);
    check(!fps_on, "fps default off"); press(3, 60); check(fps_on, "fps on"); press(3, 60); check(!fps_on, "fps off"); press(3, 60); press(3, 700); check(!fps_on, "fps default");
    press(2, 60); check(sel == 0, "sel wraps after item 5");
    // frame source cycle: sel 0 -> K3: live -> freeze -> slot1 -> slot3 -> rotate
    press(2, 60); press(2, 60); press(2, 60); check(sel == 3, "three steps from item 0");
    while (sel != 0) press(2, 60);
    press(3, 60); check(src == 1, "src freeze"); press(3, 60); check(src == 2 && view == 1, "src slot1");
    press(3, 60); check(src == 4 && view == 3, "src slot3 (slot2 invalid)"); press(3, 60); check(src == 6, "src rotate");
    repeat(350) @(negedge clk); check(view == 1 || view == 3 || view == 0, "rotate view");
    repeat(350) @(negedge clk); repeat(350) @(negedge clk);
    press(3, 60); check(src == 0, "back to live");
    if (errs == 0) $display("PASS: key short/long press, thresholds, freeze, menu select, item change, capture, slot skip, rotation");
    else $fatal(1, "ui errors %0d", errs);
    $finish;
end
endmodule
