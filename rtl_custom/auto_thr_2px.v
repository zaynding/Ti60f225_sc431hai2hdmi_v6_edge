`timescale 1ns/1ps
//======================================================================================================
// auto_thr_2px.v - per-frame automatic edge threshold from the gradient-magnitude distribution.
//
//   For 16 fixed levels L0..L15 the module counts, over one frame, how many pixels have magnitude > Lk
//   (two lanes per clock, no RAM).  After the frame it picks the lowest level whose count is at most
//   total/2^SHIFT (default 1/32 = 3.1 % "edge pixels") and holds it for the whole next frame.
//     * clean scene, few strong edges  -> a low (sensitive) level
//     * textured / noisy scene         -> a higher level that keeps the edge density bounded
//   MIN_IDX sets the floor (noise rejection; level 6 = 192, below that camera grain flickers).
//   The held threshold moves at most ONE level per frame and only after the same target was chosen on two
//   consecutive frames, so a noisy count can never make the edge map jump between thresholds frame to frame.
//======================================================================================================
module auto_thr_2px #(
    parameter integer MIN_IDX   = 6,
    parameter integer SHIFT     = 6,
    parameter integer MIN_TOTAL = 400000,
    parameter [11:0]  TH_INIT   = 12'd192
)(
    input  wire        clk, rst_n,
    input  wire        in_valid, in_vs,
    input  wire [11:0] mag0, mag1,
    output reg  [11:0] th
);
function [11:0] level;
    input [3:0] k;
    begin
        case (k)
        4'd0: level = 12'd64;  4'd1: level = 12'd80;  4'd2: level = 12'd96;  4'd3: level = 12'd112;
        4'd4: level = 12'd128; 4'd5: level = 12'd160; 4'd6: level = 12'd192; 4'd7: level = 12'd224;
        4'd8: level = 12'd256; 4'd9: level = 12'd288; 4'd10: level = 12'd320; 4'd11: level = 12'd384;
        4'd12: level = 12'd448; 4'd13: level = 12'd512; 4'd14: level = 12'd640; default: level = 12'd768;
        endcase
    end
endfunction

reg [21:0] cnt [0:15];
reg [22:0] total;
reg        vs_d, scanning, found;
reg [3:0]  cur_idx, cand_idx, tgt_idx;
reg        cand_ok;
reg [4:0]  k;
integer    i;
wire [22:0] limit = total >> SHIFT;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        total <= 0; vs_d <= 0; scanning <= 0; found <= 0; k <= 0; th <= TH_INIT;
        cur_idx <= 4'd7; cand_idx <= 4'd7; tgt_idx <= 4'd7; cand_ok <= 1'b0;
        for (i = 0; i < 16; i = i + 1) cnt[i] <= 22'd0;
    end else begin
        vs_d <= in_vs;
        if (cand_ok) begin
            cand_ok <= 1'b0;
            cand_idx <= tgt_idx;
            if (tgt_idx == cand_idx && tgt_idx != cur_idx) begin
                cur_idx <= (tgt_idx > cur_idx) ? cur_idx + 1'b1 : cur_idx - 1'b1;
                th <= level((tgt_idx > cur_idx) ? cur_idx + 1'b1 : cur_idx - 1'b1);
            end
        end
        if (!scanning) begin
            if (in_vs && !vs_d) begin scanning <= 1'b1; k <= 5'd0; found <= 1'b0; end
            else if (in_valid) begin
                total <= total + 23'd2;
                for (i = 0; i < 16; i = i + 1)
                    cnt[i] <= cnt[i] + (mag0 > level(i[3:0])) + (mag1 > level(i[3:0]));
            end
        end else begin
            if (k < 5'd16) begin
                if (!found && k >= MIN_IDX && {1'b0, cnt[k[3:0]]} <= limit) begin
                    found <= 1'b1; tgt_idx <= k[3:0];
                end
                k <= k + 1'b1;
            end else begin
                // k == 16: choose the target (15 if no level was sparse enough), then slew-limit it
                if (total >= MIN_TOTAL) begin
                    if (!found) tgt_idx <= 4'd15;
                    cand_ok <= 1'b1;
                end
                total <= 0; scanning <= 1'b0;
                for (i = 0; i < 16; i = i + 1) cnt[i] <= 22'd0;
            end
        end
    end
end
endmodule
