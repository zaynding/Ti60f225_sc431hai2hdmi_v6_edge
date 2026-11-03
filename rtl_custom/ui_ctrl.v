`timescale 1ns/1ps
//======================================================================================================
// ui_ctrl.v - four-key user interface state machine (all in the video clock domain)
//
//   K1 short: next threshold step (6 manual steps, then AUTO)   long: step 1
//   K2 short: next menu item                    long: previous item
//   K3 short: change the highlighted item       long: clear saved frames 3/4 (any menu item)
//   K0 short: freeze / back to live             long: capture a snapshot
//   menu items: 0 frame source (live/freeze/slot1..4/rotate)  1 capture  2 shape on/off  3 median on/off
//               4 display mode (split / original / edges)  5 frame-rate read-out on/off
//======================================================================================================
module ui_ctrl #(
    parameter integer ROT_CYCLES = 148500000        // 2 s @ 74.25 MHz
)(
    input  wire clk, rst_n,
    input  wire k0_s, k0_l, k1_s, k1_l, k2_s, k2_l, k3_s, k3_l,
    input  wire [3:0] saved_valid,                   // already synchronised to clk
    input  wire       ext_slot1,                     // one-clk pulse: demo frames loaded -> show slot 1
    output wire       freeze,
    output wire [2:0] view_mode,
    output reg        snapshot_toggle,
    output reg        clear_saved_toggle,
    output reg  [2:0] sel,
    output reg  [2:0] thr_idx,
    output reg  [11:0] thr12,
    output reg        shape_on, fps_on,
    output reg  [1:0] algo,                          // 0 Sobel, 1 Canny, 2 side-by-side compare
    output wire       thr_auto,
    output reg  [1:0] disp_mode,
    output reg  [2:0] src_mode,
    output reg  [2:0] flash
);
reg [2:0] rot_idx;
reg [27:0] rot_cnt;
reg [27:0] flash_cnt;
reg [3:0] valid_d;

always @* case (thr_idx)     // descending = more edges; 160 is the default (far enough below typical edge strength AND above grain)
    3'd0: thr12 = 12'd320; 3'd1: thr12 = 12'd240; 3'd2: thr12 = 12'd160;
    3'd3: thr12 = 12'd120; 3'd4: thr12 = 12'd90;  default: thr12 = 12'd64;   // idx 6 (auto) keeps 64 as the manual fallback
endcase

assign thr_auto  = (thr_idx == 3'd6);
assign freeze    = (src_mode == 3'd1);
assign view_mode = (src_mode >= 3'd2 && src_mode <= 3'd5) ? (src_mode - 3'd1) : (src_mode == 3'd6) ? rot_idx : 3'd0;

// next source mode: live -> freeze -> valid slots -> rotate -> live
function [2:0] next_src; input [2:0] cur; input [3:0] v;
    integer k; reg found; reg [2:0] c;
    begin
        next_src = 3'd0; found = 1'b0;
        for (k = 1; k <= 7; k = k + 1) begin
            c = (cur + k) % 7;
            if (!found && (c < 3'd2 || c == 3'd6 || v[c-2])) begin next_src = c; found = 1'b1; end
        end
    end
endfunction
// next rotation index (0 live, 1..4 slots) among valid ones
function [2:0] next_rot; input [2:0] cur; input [3:0] v;
    integer k; reg found; reg [2:0] c;
    begin
        next_rot = 3'd0; found = 1'b0;
        for (k = 1; k <= 5; k = k + 1) begin
            c = (cur + k) % 5;
            if (!found && (c == 3'd0 || v[c-1])) begin next_rot = c; found = 1'b1; end
        end
    end
endfunction

wire [3:0] new_slot = saved_valid & ~valid_d;
wire cap_req = k0_l || (k3_s && sel == 3'd1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        snapshot_toggle<=0; clear_saved_toggle<=0; sel<=0; thr_idx<=3'd2; shape_on<=1; fps_on<=0; algo<=2'd1; disp_mode<=0; src_mode<=0; flash<=0;
        rot_idx<=0; rot_cnt<=0; flash_cnt<=0; valid_d<=0;
    end else begin
        valid_d <= saved_valid;
        if (k1_s) thr_idx <= (thr_idx == 3'd6) ? 3'd0 : thr_idx + 1'b1;   // 0..5 manual steps, 6 = automatic
        if (k1_l) thr_idx <= 3'd2;
        if (k2_s) sel <= (sel == 3'd5) ? 3'd0 : sel + 1'b1;
        if (k2_l) sel <= (sel == 3'd0) ? 3'd5 : sel - 1'b1;
        if (k0_s) src_mode <= (src_mode == 3'd0) ? 3'd1 : 3'd0;
        if (cap_req) snapshot_toggle <= ~snapshot_toggle;
        if (ext_slot1) src_mode <= 3'd2;                              // later assignments of the same cycle (K3) still win
        if (k3_s) case (sel)
            3'd0: src_mode  <= next_src(src_mode, saved_valid);
            3'd2: shape_on  <= ~shape_on;
            3'd3: algo <= (algo == 2'd2) ? 2'd0 : algo + 1'b1;
            3'd4: disp_mode <= (disp_mode == 2'd2) ? 2'd0 : disp_mode + 1'b1;
            3'd5: fps_on    <= ~fps_on;
            default: begin end
        endcase
        // rotation timer
        if (src_mode != 3'd6) begin rot_cnt <= 0; rot_idx <= 0; end
        else if (rot_cnt == ROT_CYCLES - 1) begin rot_cnt <= 0; rot_idx <= next_rot(rot_idx, saved_valid); end
        else rot_cnt <= rot_cnt + 1'b1;
        // "saved" flash message (2 s)
        if (new_slot != 4'd0) begin
            flash <= new_slot[0] ? 3'd1 : new_slot[1] ? 3'd2 : new_slot[2] ? 3'd3 : 3'd4; flash_cnt <= 0;
        end else if (flash != 3'd0) begin
            if (flash_cnt == ROT_CYCLES - 1) begin flash <= 3'd0; flash_cnt <= 0; end
            else flash_cnt <= flash_cnt + 1'b1;
        end
        // A long confirmation press is global, independent of menu selection.
        // Leave a deleted source immediately; rotation can continue on 0/1/2.
        if (k3_l) begin
            clear_saved_toggle <= ~clear_saved_toggle;
            if (src_mode == 3'd4 || src_mode == 3'd5)
                src_mode <= saved_valid[0] ? 3'd2 : saved_valid[1] ? 3'd3 : 3'd0;
            if (rot_idx >= 3'd3) rot_idx <= 3'd0;
            flash <= 0;
            flash_cnt <= 0;
        end
    end
end
endmodule
