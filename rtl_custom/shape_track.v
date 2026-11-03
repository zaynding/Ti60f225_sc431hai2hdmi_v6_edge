`timescale 1ns/1ps
//======================================================================================================
// shape_track.v - temporal vote + fitted-outline hold for the per-frame detections.
//
//   det_*       : one pulse per classified region of the frame that just ended (class 1..5, bbox in cells, fit params)
//   frame_start : start of the next frame - detections gathered meanwhile are merged into the tracks here
//   A detection matches a track when the bbox centres are within TOL cells.  A match raises the track score (cap
//   SC_MAX); an unmatched track loses one point per frame.  A track is shown when score >= SHOW.  The class has its
//   own 0..3 confidence so that a borderline circle/ellipse does not flip every frame.
//   The fitted outline parameters are HELD while a new frame's fit is within a small tolerance of the stored one
//   (poly: every vertex within 3 px; ellipse: centre 2 px, axes 3 px, angle weighted by eccentricity), otherwise
//   they are replaced.  This keeps the drawn line perfectly still on a stationary object.
//   Timing: every detection is processed in short states (LOAD, CMP, SAME, APPLY) so no path is long.
//======================================================================================================
module shape_track #(
    parameter integer NT = 3,
    parameter integer NP = 3,
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
    input  wire [323:0] det_par,
    output wire [NT-1:0]   trk_vis,
    output wire [3*NT-1:0] trk_cls,
    output wire [8*NT-1:0] trk_xmin, trk_xmax,
    output wire [9*NT-1:0] trk_ymin, trk_ymax,
    output wire [324*NT-1:0] trk_par
);
// ---- pending detections of the running frame ----
reg [NP-1:0] p_v;
reg [2:0] p_c [0:NP-1];
reg [7:0] p_x0 [0:NP-1], p_x1 [0:NP-1];
reg [8:0] p_y0 [0:NP-1], p_y1 [0:NP-1];
reg [323:0] p_par [0:NP-1];
// ---- tracks ----
reg [NT-1:0] t_v, t_hit;
reg [2:0] t_c [0:NT-1];
reg [1:0] t_conf [0:NT-1];
reg [3:0] t_sc [0:NT-1];
reg [7:0] t_x0 [0:NT-1], t_x1 [0:NT-1];
reg [8:0] t_y0 [0:NT-1], t_y1 [0:NT-1];
reg [323:0] t_par [0:NT-1];

localparam S_IDLE=0, S_NEXT=1, S_LOAD=2, S_CMP=3, S_SAME=4, S_APPLY=5, S_AGE=6;
reg [2:0] st;
reg [3:0] d;
integer i;

// ---- registered copy of the pending detection being processed ----
reg [2:0] c_c; reg [7:0] c_x0, c_x1; reg [8:0] c_y0, c_y1; reg [323:0] c_par;
reg [9:0] c_dxs, c_dys;

// ---- match result ----
reg [1:0] mi, fi, vi; reg m_ok, f_ok; reg [3:0] vsc; reg same_r;

function [11:0] adf; input [11:0] a, b; begin adf = (a > b) ? (a - b) : (b - a); end endfunction
function [9:0] adiff; input [9:0] a, b; begin adiff = (a > b) ? (a - b) : (b - a); end endfunction
function same_par;
    input [2:0] kind; input [323:0] a, b;
    reg signed [15:0] ac, as_, bc, bs; reg [31:0] dang; integer ii, jj; reg okf, okr, found;
    reg [10:0] axv, ayv, bxv, byv;
    begin
        if (kind <= 3'd2) begin
            ac = a[68:53]; as_ = a[84:69]; bc = b[68:53]; bs = b[84:69];
            dang = (((ac > bc) ? (ac - bc) : (bc - ac)) + ((as_ > bs) ? (as_ - bs) : (bs - as_))) * (a[38:25] - a[52:39]);
            same_par = (adf({1'b0,a[11:0]}, {1'b0,b[11:0]}) <= 12'd8) && (adf({1'b0,a[24:12]}, {1'b0,b[24:12]}) <= 12'd8) &&
                       (adf({1'b0,a[38:25]}, {1'b0,b[38:25]}) <= 12'd48) && (adf({1'b0,a[52:39]}, {1'b0,b[52:39]}) <= 12'd48) &&
                       (kind == 3'd1 || dang <= 32'd786432);
        end else begin
            okf = 1'b1; okr = 1'b1;
            for (ii = 0; ii < 4; ii = ii + 1) begin
                found = 1'b0;
                for (jj = 0; jj < 4; jj = jj + 1) begin
                    axv = a[236 + 22*ii +: 11]; ayv = a[236 + 22*ii + 11 +: 11];
                    bxv = b[236 + 22*jj +: 11]; byv = b[236 + 22*jj + 11 +: 11];
                    if (adf({1'b0,axv}, {1'b0,bxv}) <= 12'd3 && adf({1'b0,ayv}, {1'b0,byv}) <= 12'd3) found = 1'b1;
                end
                if (!found) okf = 1'b0;
                found = 1'b0;
                for (jj = 0; jj < 4; jj = jj + 1) begin
                    axv = b[236 + 22*ii +: 11]; ayv = b[236 + 22*ii + 11 +: 11];
                    bxv = a[236 + 22*jj +: 11]; byv = a[236 + 22*jj + 11 +: 11];
                    if (adf({1'b0,axv}, {1'b0,bxv}) <= 12'd3 && adf({1'b0,ayv}, {1'b0,byv}) <= 12'd3) found = 1'b1;
                end
                if (!found) okr = 1'b0;
            end
            same_par = okf && okr;
        end
    end
endfunction

reg [9:0] txs, tys;
reg [NT-1:0] match_v;
always @* begin
    match_v = 0;
    for (i = 0; i < NT; i = i + 1) begin
        txs = {2'b0, t_x0[i]} + {2'b0, t_x1[i]};
        tys = {1'b0, t_y0[i]} + {1'b0, t_y1[i]};
        match_v[i] = t_v[i] && (adiff(c_dxs, txs) <= 2*TOL) && (adiff(c_dys, tys) <= 2*TOL);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_v<=0; t_v<=0; t_hit<=0; st<=S_IDLE; d<=0;
        c_c<=0; c_x0<=0; c_x1<=0; c_y0<=0; c_y1<=0; c_par<=0; c_dxs<=0; c_dys<=0; mi<=0; fi<=0; vi<=0; m_ok<=0; f_ok<=0; vsc<=0; same_r<=0;
        for (i=0;i<NP;i=i+1) begin p_c[i]<=0; p_x0[i]<=0; p_x1[i]<=0; p_y0[i]<=0; p_y1[i]<=0; p_par[i]<=0; end
        for (i=0;i<NT;i=i+1) begin t_c[i]<=0; t_conf[i]<=0; t_sc[i]<=0; t_x0[i]<=0; t_x1[i]<=0; t_y0[i]<=0; t_y1[i]<=0; t_par[i]<=0; end
    end else begin
        case (st)
        S_IDLE: begin
            if (frame_start) begin d<=0; t_hit<=0; st<=S_NEXT; end
            else if (det_valid) begin : store
                integer k; reg done;
                done = 0;
                for (k=0;k<NP;k=k+1) if (!done && !p_v[k]) begin
                    done = 1; p_v[k]<=1'b1; p_c[k]<=det_class; p_x0[k]<=det_xmin; p_x1[k]<=det_xmax; p_y0[k]<=det_ymin; p_y1[k]<=det_ymax; p_par[k]<=det_par;
                end
            end
        end
        S_NEXT: begin
            if (d == NP) st <= S_AGE;
            else if (!p_v[d]) d <= d + 1'b1;
            else st <= S_LOAD;
        end
        S_LOAD: begin
            c_c <= p_c[d]; c_x0 <= p_x0[d]; c_x1 <= p_x1[d]; c_y0 <= p_y0[d]; c_y1 <= p_y1[d]; c_par <= p_par[d];
            c_dxs <= {2'b0, p_x0[d]} + {2'b0, p_x1[d]}; c_dys <= {1'b0, p_y0[d]} + {1'b0, p_y1[d]};
            p_v[d] <= 1'b0; st <= S_CMP;
        end
        S_CMP: begin : cmp
            integer j; reg mfound, ffound; reg [1:0] mj, fj, vj; reg [3:0] vs;
            mfound = 0; ffound = 0; mj = 0; fj = 0; vj = 0; vs = 4'd15;
            for (j = NT-1; j >= 0; j = j - 1) begin
                if (match_v[j]) begin mfound = 1; mj = j[1:0]; end
                if (!t_v[j]) begin ffound = 1; fj = j[1:0]; end
                if (t_v[j] && t_sc[j] <= vs) begin vs = t_sc[j]; vj = j[1:0]; end
            end
            m_ok <= mfound; mi <= mj; f_ok <= ffound; fi <= fj; vi <= vj; vsc <= vs;
            st <= S_SAME;
        end
        S_SAME: begin
            same_r <= m_ok ? same_par(c_c, c_par, t_par[mi]) : 1'b0;
            st <= S_APPLY;
        end
        S_APPLY: begin
            if (m_ok) begin
                t_hit[mi] <= 1'b1;
                if (t_sc[mi] < SC_MAX) t_sc[mi] <= t_sc[mi] + 1'b1;
                if (t_c[mi] == c_c) begin
                    if (t_conf[mi] != 2'd3) t_conf[mi] <= t_conf[mi] + 1'b1;
                    if (!same_r) begin                                   // moved / resized: take the new fit
                        t_par[mi] <= c_par;
                        t_x0[mi] <= c_x0; t_x1[mi] <= c_x1; t_y0[mi] <= c_y0; t_y1[mi] <= c_y1;
                    end
                end else if (t_conf[mi] <= 2'd1) begin
                    t_c[mi] <= c_c; t_conf[mi] <= 2'd1; t_par[mi] <= c_par;
                    t_x0[mi] <= c_x0; t_x1[mi] <= c_x1; t_y0[mi] <= c_y0; t_y1[mi] <= c_y1;
                end else t_conf[mi] <= t_conf[mi] - 1'b1;
            end else if (f_ok) begin
                t_v[fi]<=1'b1; t_hit[fi]<=1'b1; t_c[fi]<=c_c; t_conf[fi]<=2'd1; t_sc[fi]<=4'd1;
                t_x0[fi]<=c_x0; t_x1[fi]<=c_x1; t_y0[fi]<=c_y0; t_y1[fi]<=c_y1; t_par[fi]<=c_par;
            end else if (!t_hit[vi] && vsc < 4'd3) begin
                t_hit[vi]<=1'b1; t_c[vi]<=c_c; t_conf[vi]<=2'd1; t_sc[vi]<=4'd1;
                t_x0[vi]<=c_x0; t_x1[vi]<=c_x1; t_y0[vi]<=c_y0; t_y1[vi]<=c_y1; t_par[vi]<=c_par;
            end
            d <= d + 1'b1; st <= S_NEXT;
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
    assign trk_par[324*g +: 324] = t_par[g];
end endgenerate
endmodule
