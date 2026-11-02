`timescale 1ns/1ps
//======================================================================================================
// shape_track.v - temporal vote for the per-frame detections (prevents flicker and one-frame false hits).
//
//   det_*       : one pulse per classified region of the frame that just ended (class 1..5, bbox in cells)
//   frame_start : start of the next frame - detections gathered meanwhile are merged into the tracks here
//   A detection matches a track when the bbox centres are within TOL cells.  A match raises the track
//   score (cap SC_MAX); an unmatched track loses one point per frame.  A track is shown when
//   score >= SHOW.  The class has its own 0..3 confidence so that a borderline circle/ellipse does not
//   flip every frame.
//======================================================================================================
module shape_track #(
    parameter integer NT = 4,
    parameter integer NP = 6,
    parameter integer TOL = 16,
    parameter integer SHOW = 4,
    parameter integer SC_MAX = 12
)(
    input  wire clk, rst_n,
    input  wire frame_start,
    input  wire det_valid,
    input  wire [2:0] det_class,
    input  wire [7:0] det_xmin, det_xmax,
    input  wire [8:0] det_ymin, det_ymax,
    output wire [NT-1:0]   trk_vis,
    output wire [3*NT-1:0] trk_cls,
    output wire [8*NT-1:0] trk_xmin, trk_xmax,
    output wire [9*NT-1:0] trk_ymin, trk_ymax
);
// ---- pending detections of the running frame ----
reg [NP-1:0] p_v;
reg [2:0] p_c [0:NP-1];
reg [7:0] p_x0 [0:NP-1], p_x1 [0:NP-1];
reg [8:0] p_y0 [0:NP-1], p_y1 [0:NP-1];
// ---- tracks ----
reg [NT-1:0] t_v, t_hit;
reg [2:0] t_c [0:NT-1];
reg [1:0] t_conf [0:NT-1];
reg [3:0] t_sc [0:NT-1];
reg [7:0] t_x0 [0:NT-1], t_x1 [0:NT-1];
reg [8:0] t_y0 [0:NT-1], t_y1 [0:NT-1];

localparam S_IDLE=0, S_DET=1, S_AGE=2;
reg [1:0] st;
reg [3:0] d;
integer i;

// combinational match for pending detection d
reg [NT-1:0] match;
reg [9:0] dxs, dys, txs, tys;
reg [3:0] mi; reg m_ok; reg [3:0] fi; reg f_ok; reg [3:0] vi; reg [3:0] vsc;
function [9:0] adiff; input [9:0] a, b; begin adiff = (a > b) ? (a - b) : (b - a); end endfunction
always @* begin
    dxs = {2'b0, p_x0[d]} + {2'b0, p_x1[d]};
    dys = {1'b0, p_y0[d]} + {1'b0, p_y1[d]};
    match = 0; mi = 0; m_ok = 0; fi = 0; f_ok = 0; vi = 0; vsc = 4'd15;
    for (i = NT-1; i >= 0; i = i - 1) begin
        txs = {2'b0, t_x0[i]} + {2'b0, t_x1[i]};
        tys = {1'b0, t_y0[i]} + {1'b0, t_y1[i]};
        if (t_v[i] && adiff(dxs, txs) <= 2*TOL && adiff(dys, tys) <= 2*TOL) begin match[i] = 1'b1; mi = i[3:0]; m_ok = 1'b1; end
        if (!t_v[i]) begin fi = i[3:0]; f_ok = 1'b1; end
        if (t_v[i] && t_sc[i] <= vsc) begin vsc = t_sc[i]; vi = i[3:0]; end    // weakest track (replacement victim)
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_v<=0; t_v<=0; t_hit<=0; st<=S_IDLE; d<=0;
        for (i=0;i<NP;i=i+1) begin p_c[i]<=0; p_x0[i]<=0; p_x1[i]<=0; p_y0[i]<=0; p_y1[i]<=0; end
        for (i=0;i<NT;i=i+1) begin t_c[i]<=0; t_conf[i]<=0; t_sc[i]<=0; t_x0[i]<=0; t_x1[i]<=0; t_y0[i]<=0; t_y1[i]<=0; end
    end else begin
        case (st)
        S_IDLE: begin
            if (frame_start) begin d<=0; t_hit<=0; st<=S_DET; end
            else if (det_valid) begin : store
                integer k; reg done;
                done = 0;
                for (k=0;k<NP;k=k+1) if (!done && !p_v[k]) begin
                    done = 1; p_v[k]<=1'b1; p_c[k]<=det_class; p_x0[k]<=det_xmin; p_x1[k]<=det_xmax; p_y0[k]<=det_ymin; p_y1[k]<=det_ymax;
                end
            end
        end
        S_DET: begin
            if (d == NP) st <= S_AGE;
            else begin
                if (p_v[d]) begin
                    p_v[d] <= 1'b0;
                    if (m_ok) begin
                        t_hit[mi] <= 1'b1;
                        t_x0[mi] <= ({1'b0,t_x0[mi]} + {1'b0,p_x0[d]}) >> 1; t_x1[mi] <= ({1'b0,t_x1[mi]} + {1'b0,p_x1[d]}) >> 1;
                        t_y0[mi] <= ({1'b0,t_y0[mi]} + {1'b0,p_y0[d]}) >> 1; t_y1[mi] <= ({1'b0,t_y1[mi]} + {1'b0,p_y1[d]}) >> 1;
                        if (t_sc[mi] < SC_MAX) t_sc[mi] <= t_sc[mi] + 1'b1;
                        if (t_c[mi] == p_c[d]) begin if (t_conf[mi] != 2'd3) t_conf[mi] <= t_conf[mi] + 1'b1; end
                        else if (t_conf[mi] <= 2'd1) begin t_c[mi] <= p_c[d]; t_conf[mi] <= 2'd1; end
                        else t_conf[mi] <= t_conf[mi] - 1'b1;
                    end else begin
                        // new track in a free slot, or replace the weakest unseen one
                        if (f_ok) begin
                            t_v[fi]<=1'b1; t_hit[fi]<=1'b1; t_c[fi]<=p_c[d]; t_conf[fi]<=2'd1; t_sc[fi]<=4'd1;
                            t_x0[fi]<=p_x0[d]; t_x1[fi]<=p_x1[d]; t_y0[fi]<=p_y0[d]; t_y1[fi]<=p_y1[d];
                        end else if (!t_hit[vi] && vsc < 4'd3) begin
                            t_hit[vi]<=1'b1; t_c[vi]<=p_c[d]; t_conf[vi]<=2'd1; t_sc[vi]<=4'd1;
                            t_x0[vi]<=p_x0[d]; t_x1[vi]<=p_x1[d]; t_y0[vi]<=p_y0[d]; t_y1[vi]<=p_y1[d];
                        end
                    end
                end
                d <= d + 1'b1;
            end
        end
        S_AGE: begin
            for (i=0;i<NT;i=i+1) if (t_v[i] && !t_hit[i]) begin
                if (t_sc[i] <= 4'd1) t_v[i] <= 1'b0; else t_sc[i] <= t_sc[i] - 1'b1;
            end
            st <= S_IDLE;
        end
        default: st <= S_IDLE;
        endcase
    end
end

genvar g;
generate for (g=0; g<NT; g=g+1) begin : g_out
    assign trk_vis[g] = t_v[g] && (t_sc[g] >= SHOW);
    assign trk_cls[3*g +: 3] = t_c[g];
    assign trk_xmin[8*g +: 8] = t_x0[g];  assign trk_xmax[8*g +: 8] = t_x1[g];
    assign trk_ymin[9*g +: 9] = t_y0[g];  assign trk_ymax[9*g +: 9] = t_y1[g];
end endgenerate
endmodule
