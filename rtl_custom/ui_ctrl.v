`timescale 1ns/1ps
//======================================================================================================
// ui_ctrl.v - four-key user interface state machine (all in the video clock domain)
//
//   K1 short: next threshold step (6 steps)     long: step 1
//   K2 short: next menu item                    long: previous item
//   K3 short: change the highlighted item       long: reset that item to its default
//   K0 short: freeze / back to live             long: capture a snapshot
//   menu items: 0 frame source (live/freeze/slot1..4/rotate)  1 capture  2 shape on/off  3 median on/off
//               4 display mode (split / original / edges)
//======================================================================================================
module ui_ctrl #(
    parameter integer ROT_CYCLES = 148500000        // 2 s @ 74.25 MHz
)(
    input  wire clk, rst_n,
    input  wire k0_s, k0_l, k1_s, k1_l, k2_s, k2_l, k3_s, k3_l,
    input  wire [3:0] saved_valid,                   // already synchronised to clk
    output wire       freeze,
    output wire [2:0] view_mode,
    output reg        snapshot_toggle,
    output reg  [2:0] sel,
    output reg  [2:0] thr_idx,
    output reg  [11:0] thr12,
    output reg        shape_on, med_on,
    output reg  [1:0] disp_mode,
    output reg  [2:0] src_mode,
    output reg  [2:0] flash
);
reg [2:0] rot_idx;
reg [27:0] rot_cnt;
reg [27:0] flash_cnt;
reg [3:0] valid_d;

always @* case (thr_idx)
    3'd0: thr12 = 12'd400; 3'd1: thr12 = 12'd320; 3'd2: thr12 = 12'd240;
    3'd3: thr12 = 12'd160; 3'd4: thr12 = 12'd104; default: thr12 = 12'd64;
endcase

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
        snapshot_toggle<=0; sel<=0; thr_idx<=0; shape_on<=1; med_on<=1; disp_mode<=0; src_mode<=0; flash<=0;
        rot_idx<=0; rot_cnt<=0; flash_cnt<=0; valid_d<=0;
    end else begin
        valid_d <= saved_valid;
        if (k1_s) thr_idx <= (thr_idx == 3'd5) ? 3'd0 : thr_idx + 1'b1;
        if (k1_l) thr_idx <= 3'd0;
        if (k2_s) sel <= (sel == 3'd4) ? 3'd0 : sel + 1'b1;
        if (k2_l) sel <= (sel == 3'd0) ? 3'd4 : sel - 1'b1;
        if (k0_s) src_mode <= (src_mode == 3'd0) ? 3'd1 : 3'd0;
        if (cap_req) snapshot_toggle <= ~snapshot_toggle;
        if (k3_s) case (sel)
            3'd0: src_mode  <= next_src(src_mode, saved_valid);
            3'd2: shape_on  <= ~shape_on;
            3'd3: med_on    <= ~med_on;
            3'd4: disp_mode <= (disp_mode == 2'd2) ? 2'd0 : disp_mode + 1'b1;
            default: begin end
        endcase
        if (k3_l) case (sel)
            3'd0: src_mode <= 3'd0;
            3'd2: shape_on <= 1'b1;
            3'd3: med_on   <= 1'b1;
            3'd4: disp_mode <= 2'd0;
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
    end
end
endmodule
