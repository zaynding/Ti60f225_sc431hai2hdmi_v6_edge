`timescale 1ns/1ps
//======================================================================================================
// shape_fit_draw_2px.v - draw the ideal fitted outline of every confirmed shape on BOTH panels
//                        (left colour crop, right edge crop), about 3 px wide, in the shape's class colour.
//
//   Both panels show the same 960x1080 crop, so one set of panel coordinates serves both.
//   For every pixel pair only the first confirmed track whose (margin-expanded) bounding box contains it is
//   evaluated, so a single arithmetic pipeline (2 pixels per clock) serves all tracks.
//     polygon : g_e = nx_e*x + ny_e*y - c_e,  on the line when  -T <= max_e g_e <= +T      (T = 1.5 px, Q14)
//               (the second pixel of the pair re-uses the products: g(x+1) = g(x) + nx)
//     ellipse : q = (u/a)^2 + (v/b)^2 in the rotated frame;  on the line when |q-1| < 3*(1/b)  (band 3..4.7 px)
//               (the second pixel of the pair is u+c, v-s)
//   Pipeline: s1 select -> s2 fetch parameters -> 7 arithmetic stages (polygon is padded to the same depth) ->
//   merge.  The picture and the sync signals are delayed by LAT clocks to match.
//======================================================================================================
module shape_fit_draw_2px #(
    parameter integer NT = 3,
    parameter integer PANEL_PAIRS = 480,
    parameter integer MARGIN = 80          // the tip of a sharp corner of the hole lies far (up to ~60 px) inside the real shape
)(
    input  wire        clk, rst_n,
    input  wire        enable,
    input  wire        in_valid, in_hs, in_vs,
    input  wire [47:0] in_rgb2,
    input  wire [NT-1:0]     trk_vis,
    input  wire [3*NT-1:0]   trk_cls,
    input  wire [8*NT-1:0]   trk_xmin, trk_xmax,
    input  wire [9*NT-1:0]   trk_ymin, trk_ymax,
    input  wire [324*NT-1:0] trk_par,
    output wire        out_valid, out_hs, out_vs,
    output wire [47:0] out_rgb2
);
localparam integer LAT = 10;

// ---------------- position counters ----------------
reg vs_d, valid_d;
reg [9:0]  xp;
reg [10:0] yl;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin vs_d<=0; valid_d<=0; xp<=0; yl<=0; end
    else begin
        vs_d <= in_vs; valid_d <= in_valid;
        if (in_vs && !vs_d) begin xp<=0; yl<=0; end
        else if (in_valid) xp <= xp + 1'b1;
        else if (valid_d) begin xp<=0; yl<=yl+1'b1; end
    end
end
wire        right_panel = (xp >= PANEL_PAIRS);
wire [9:0]  xpr = right_panel ? (xp - PANEL_PAIRS) : xp;
wire [10:0] xr0 = {xpr, 1'b0};
wire [10:0] xr1 = {xpr, 1'b1};
wire [10:0] yy  = yl;

// ---------------- per-track pixel boxes (registered) ----------------
reg [11:0] bxl [0:NT-1], bxh [0:NT-1], byl [0:NT-1], byh [0:NT-1];
reg        tact [0:NT-1];
integer k;
always @(posedge clk) begin
    for (k = 0; k < NT; k = k + 1) begin : geo
        reg [11:0] x0, x1, y0, y1;
        x0 = {2'b0, trk_xmin[8*k +: 8], 2'b0};  x1 = {2'b0, trk_xmax[8*k +: 8], 2'b0} + 12'd4;
        y0 = {1'b0, trk_ymin[9*k +: 9], 2'b0};  y1 = {1'b0, trk_ymax[9*k +: 9], 2'b0} + 12'd4;
        bxl[k] <= (x0 > MARGIN) ? (x0 - MARGIN) : 12'd0;   bxh[k] <= x1 + MARGIN;
        byl[k] <= (y0 > MARGIN) ? (y0 - MARGIN) : 12'd0;   byh[k] <= y1 + MARGIN;
        tact[k] <= trk_vis[k] && enable && (trk_cls[3*k +: 3] != 3'd0);
    end
end

// ---------------- stage 1 : choose the track for this pixel pair ----------------
reg        s1_sel_v;  reg [1:0] s1_sel;
reg        s1_in0, s1_in1;
reg [10:0] s1_x0, s1_y;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin s1_sel_v<=0; s1_sel<=0; s1_in0<=0; s1_in1<=0; s1_x0<=0; s1_y<=0; end
    else begin : sel
        integer j; reg found; reg [1:0] idx; reg a0, a1;
        found = 0; idx = 0;
        for (j = 0; j < NT; j = j + 1) begin
            a0 = tact[j] && (xr0 >= bxl[j]) && (xr0 <= bxh[j]) && (yy >= byl[j]) && (yy <= byh[j]);
            a1 = tact[j] && (xr1 >= bxl[j]) && (xr1 <= bxh[j]) && (yy >= byl[j]) && (yy <= byh[j]);
            if (!found && (a0 || a1)) begin found = 1; idx = j[1:0]; end
        end
        a0 = found && (xr0 >= bxl[idx]) && (xr0 <= bxh[idx]) && (yy >= byl[idx]) && (yy <= byh[idx]);
        a1 = found && (xr1 >= bxl[idx]) && (xr1 <= bxh[idx]) && (yy >= byl[idx]) && (yy <= byh[idx]);
        s1_sel_v <= found; s1_sel <= idx; s1_in0 <= a0; s1_in1 <= a1; s1_x0 <= xr0; s1_y <= yy;
    end
end

// ---------------- stage 2 : fetch the parameters of the chosen track ----------------
reg [2:0]  s2_cls;  reg s2_v, s2_in0, s2_in1;
reg [10:0] s2_x0, s2_y;
reg [323:0] s2_par;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin s2_cls<=0; s2_v<=0; s2_in0<=0; s2_in1<=0; s2_x0<=0; s2_y<=0; s2_par<=0; end
    else begin
        s2_v <= s1_sel_v; s2_in0 <= s1_in0; s2_in1 <= s1_in1; s2_x0 <= s1_x0; s2_y <= s1_y;
        s2_cls <= trk_cls[3*s1_sel +: 3];
        s2_par <= trk_par[324*s1_sel +: 324];
    end
end
wire s2_ell = (s2_cls <= 3'd2);

// ================= polygon branch (3 stages: mult, sum, band) =================
reg signed [27:0] pnx [0:3];                 // nx*x0
reg signed [27:0] pny [0:3];                 // ny*y
reg signed [26:0] pc  [0:3];
reg signed [15:0] pnxv [0:3];
reg p3_v, p3_in0, p3_in1; reg [2:0] p3_cls;
integer e;
always @(posedge clk) begin
    for (e = 0; e < 4; e = e + 1) begin
        pnx[e]  <= $signed(s2_par[59*e +: 16])      * $signed({1'b0, s2_x0});
        pny[e]  <= $signed(s2_par[59*e + 16 +: 16]) * $signed({1'b0, s2_y});
        pc[e]   <= $signed(s2_par[59*e + 32 +: 27]);
        pnxv[e] <= $signed(s2_par[59*e +: 16]);
    end
    p3_v <= s2_v; p3_in0 <= s2_in0; p3_in1 <= s2_in1; p3_cls <= s2_cls;
end
reg signed [30:0] pg0 [0:3];
reg signed [30:0] pg1 [0:3];
reg p4_v, p4_in0, p4_in1; reg [2:0] p4_cls;
always @(posedge clk) begin
    for (e = 0; e < 4; e = e + 1) begin
        pg0[e] <= pnx[e] + pny[e] - pc[e];
        pg1[e] <= pnx[e] + pny[e] - pc[e] + pnxv[e];      // pixel x0+1
    end
    p4_v <= p3_v; p4_in0 <= p3_in0; p4_in1 <= p3_in1; p4_cls <= p3_cls;
end
localparam signed [30:0] TBAND = 31'sd24576;           // 1.5 px in Q14
function signed [30:0] max4; input signed [30:0] a, b, c, d;
    reg signed [30:0] m1, m2; begin m1 = (a > b) ? a : b; m2 = (c > d) ? c : d; max4 = (m1 > m2) ? m1 : m2; end
endfunction
wire signed [30:0] gm0 = max4(pg0[0], pg0[1], pg0[2], pg0[3]);
wire signed [30:0] gm1 = max4(pg1[0], pg1[1], pg1[2], pg1[3]);
reg ph0, ph1; reg [2:0] p5_cls;
always @(posedge clk) begin
    ph0 <= p4_v && p4_in0 && (gm0 >= -TBAND) && (gm0 <= TBAND);
    ph1 <= p4_v && p4_in1 && (gm1 >= -TBAND) && (gm1 <= TBAND);
    p5_cls <= p4_cls;
end
// pad the polygon result to the ellipse depth (4 more registers)
reg [3:0] ph0_sr, ph1_sr; reg [11:0] pcls_sr;
always @(posedge clk) begin
    ph0_sr <= {ph0_sr[2:0], ph0}; ph1_sr <= {ph1_sr[2:0], ph1}; pcls_sr <= {pcls_sr[8:0], p5_cls};
end
wire poly_hit0 = ph0_sr[3], poly_hit1 = ph1_sr[3];
wire [2:0] poly_cls = pcls_sr[11:9];

// ================= ellipse branch (7 stages, ends at the same time as the polygon branch) =================
wire [11:0] ecx = s2_par[11:0];   wire [12:0] ecy = s2_par[24:12];
wire signed [15:0] ec = s2_par[68:53], es = s2_par[84:69];
wire [17:0] eia = s2_par[102:85], eib = s2_par[120:103];
// E3 : offsets from the centre (Q2 px)
reg signed [14:0] edx0, edy; reg e3_v, e3_in0, e3_in1; reg [2:0] e3_cls; reg [17:0] e3_ia, e3_ib; reg signed [15:0] e3_c, e3_s;
always @(posedge clk) begin
    edx0 <= $signed({1'b0, s2_x0, 2'b00}) - $signed({3'b0, ecx});
    edy  <= $signed({1'b0, s2_y,  2'b00}) - $signed({2'b0, ecy});
    e3_v <= s2_v; e3_in0 <= s2_in0; e3_in1 <= s2_in1; e3_cls <= s2_cls; e3_ia <= eia; e3_ib <= eib; e3_c <= ec; e3_s <= es;
end
// E4 : rotation products (pixel 0 only)
reg signed [30:0] m_cdx, m_sdx, m_cdy, m_sdy;
reg e4_v, e4_in0, e4_in1; reg [2:0] e4_cls; reg [17:0] e4_ia, e4_ib; reg signed [15:0] e4_c, e4_s;
always @(posedge clk) begin
    m_cdx <= e3_c * edx0;  m_sdx <= e3_s * edx0;
    m_cdy <= e3_c * edy;   m_sdy <= e3_s * edy;
    e4_v <= e3_v; e4_in0 <= e3_in0; e4_in1 <= e3_in1; e4_cls <= e3_cls; e4_ia <= e3_ia; e4_ib <= e3_ib; e4_c <= e3_c; e4_s <= e3_s;
end
// E5 : u, v in Q4 px for both pixels  (u = c*dx + s*dy, v = c*dy - s*dx;  Q2 * Q14 = Q16 -> >>12 = Q4)
reg signed [15:0] u4 [0:1], v4 [0:1];
reg e5_v, e5_in0, e5_in1; reg [2:0] e5_cls; reg [17:0] e5_ia, e5_ib;
always @(posedge clk) begin
    u4[0] <= (m_cdx + m_sdy) >>> 12;                              v4[0] <= (m_cdy - m_sdx) >>> 12;
    u4[1] <= (m_cdx + m_sdy + (e4_c <<< 2)) >>> 12;               v4[1] <= (m_cdy - m_sdx - (e4_s <<< 2)) >>> 12;
    e5_v <= e4_v; e5_in0 <= e4_in0; e5_in1 <= e4_in1; e5_cls <= e4_cls; e5_ia <= e4_ia; e5_ib <= e4_ib;
end
// E6 : |u|/a, |v|/b  (Q4 * Q20 = Q24 -> >>12 = Q12)
reg [15:0] ua [0:1], vb [0:1];
reg e6_v, e6_in0, e6_in1; reg [2:0] e6_cls; reg [17:0] e6_ib;
// NOTE: the products are formed in explicit 40-bit wires - a Verilog multiplier assigned to a 16-bit target is
// evaluated at the widest OPERAND width only (18 bits here) and would overflow before the shift.
wire [15:0] au0 = u4[0][15] ? -u4[0] : u4[0];   wire [15:0] au1 = u4[1][15] ? -u4[1] : u4[1];
wire [15:0] av0 = v4[0][15] ? -v4[0] : v4[0];   wire [15:0] av1 = v4[1][15] ? -v4[1] : v4[1];
wire [39:0] pa0 = au0 * e5_ia;  wire [39:0] pa1 = au1 * e5_ia;
wire [39:0] pb0 = av0 * e5_ib;  wire [39:0] pb1 = av1 * e5_ib;
always @(posedge clk) begin
    ua[0] <= pa0[27:12];  ua[1] <= pa1[27:12];
    vb[0] <= pb0[27:12];  vb[1] <= pb1[27:12];
    e6_v <= e5_v; e6_in0 <= e5_in0; e6_in1 <= e5_in1; e6_cls <= e5_cls; e6_ib <= e5_ib;
end
// E7 : squares (Q12*Q12 = Q24); band half-width in q = 2 * (1.5 px) * (1/b) = 3*ib*16 = 48*ib  (ib is Q20)
reg [31:0] sqa [0:1], sqb [0:1];
reg e7_v, e7_in0, e7_in1; reg [2:0] e7_cls; reg [23:0] e7_thr;
always @(posedge clk) begin
    sqa[0] <= ua[0][13:0] * ua[0][13:0];  sqa[1] <= ua[1][13:0] * ua[1][13:0];
    sqb[0] <= vb[0][13:0] * vb[0][13:0];  sqb[1] <= vb[1][13:0] * vb[1][13:0];
    e7_v <= e6_v; e7_in0 <= e6_in0; e7_in1 <= e6_in1; e7_cls <= e6_cls;
    e7_thr <= {e6_ib[17:0], 5'b0} + {e6_ib[17:0], 4'b0};
end
// E8 : q = (u/a)^2 + (v/b)^2 (Q24)
reg [33:0] q [0:1]; reg [23:0] e8_thr;
reg e8_v, e8_in0, e8_in1; reg [2:0] e8_cls;
always @(posedge clk) begin
    q[0] <= sqa[0] + sqb[0];  q[1] <= sqa[1] + sqb[1];
    e8_thr <= e7_thr;
    e8_v <= e7_v; e8_in0 <= e7_in0; e8_in1 <= e7_in1; e8_cls <= e7_cls;
end
// E9 : |q - 1| < thr
reg eh0, eh1; reg [2:0] e9_cls;
localparam [33:0] ONE = 34'd16777216;                      // 1.0 in Q24
always @(posedge clk) begin
    eh0 <= e8_v && e8_in0 && (((q[0] > ONE) ? (q[0] - ONE) : (ONE - q[0])) < {10'd0, e8_thr});
    eh1 <= e8_v && e8_in1 && (((q[1] > ONE) ? (q[1] - ONE) : (ONE - q[1])) < {10'd0, e8_thr});
    e9_cls <= e8_cls;
end

// ---------------- merge, delay the picture ----------------
function [23:0] class_color;
    input [2:0] c;
    begin
        case (c)
        3'd1: class_color = 24'h00FF00;   // circle    green
        3'd2: class_color = 24'hFFFF00;   // ellipse   yellow
        3'd3: class_color = 24'h00FFFF;   // square    cyan
        3'd4: class_color = 24'hFF00FF;   // rectangle magenta
        3'd5: class_color = 24'hFF8000;   // triangle  orange
        default: class_color = 24'hFFFFFF;
        endcase
    end
endfunction
reg [51:0] pipe [0:LAT-1];                  // {valid, hs, vs, rgb2}
integer d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) for (d = 0; d < LAT; d = d + 1) pipe[d] <= 52'd0;
    else begin
        pipe[0] <= {in_valid, in_hs, in_vs, in_rgb2};
        for (d = 1; d < LAT; d = d + 1) pipe[d] <= pipe[d-1];
    end
end
// kind of the selected track, aligned with eh*/poly_hit* (s2 is t+2, eh is registered at t+9)
reg [6:0] ell_sr;
always @(posedge clk) ell_sr <= {ell_sr[5:0], s2_ell && s2_v};
wire s_ell_d = ell_sr[6];
reg h0, h1; reg [2:0] hc;
always @(posedge clk) begin
    h0 <= (s_ell_d ? eh0 : poly_hit0);  h1 <= (s_ell_d ? eh1 : poly_hit1);
    hc <= (s_ell_d ? e9_cls : poly_cls);
end
reg [51:0] outq;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) outq <= 52'd0;
    else begin
        outq <= pipe[LAT-1];
        if (h0) outq[23:0]  <= class_color(hc);
        if (h1) outq[47:24] <= class_color(hc);
    end
end
assign {out_valid, out_hs, out_vs, out_rgb2} = outq;
endmodule
