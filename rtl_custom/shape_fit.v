`timescale 1ns/1ps
//======================================================================================================
// shape_fit.v - turn one classified region into the parameters of the ideal outline that fits it.
//
//   kind 1/2 (circle, ellipse): centre + covariance eigen-decomposition (second moments)
//            kind 3/4/5 (square, rectangle, triangle): the best polygon (4 / 3 vertices, maximum area) among the
//            eight directional extreme cells of the region, then every side is pushed outwards:
//            the region is the SHAPE ERODED by the dilated edge ring, so  d_i = K0 + K1*(|nx|+|ny|)  px
//            (calibrated in sim/shape/fitmodel.py: K0=6, K1=3, KE=7.5)
//
//   out_par (324 bits), interpreted by `kind`
//     polygon : line e (e = 0..3) at [59*e +: 59] = { c[26:0] (Q14 px), ny[15:0] (Q14), nx[15:0] (Q14) }
//               pixel (x,y) is on line e at   g_e = nx*x + ny*y - c  ==  0 ;  inside of the polygon  g_max < 0 ;
//               unused fourth line of a triangle has nx=ny=0 and c = +max  (never the maximum)
//     ellipse : [11:0] cx (Q2 px)  [24:12] cy (Q2 px)  [38:25] a (Q4 px, includes the offset)  [52:39] b (Q4 px)
//               [68:53] c (Q14, cos of major axis)  [84:69] s (Q14, sin)  [102:85] ia (Q20 = 1/a px)  [120:103] ib
//     polygon vertices (for the tracker's hold test): [236 + 22*k +: 22] = { y[10:0], x[10:0] } px, k = 0..3 (triangle: v3 = v2)
//   All of it sequential: one 64/32 divider, one square root, no multiplier except two small ones.
//======================================================================================================
module shape_fit #(
    parameter integer K0_Q4 = 96,         // 6.0 px  (Q4)
    parameter integer K1_Q4 = 48,         // 3.0 px
    parameter integer KE_Q4 = 120         // 7.5 px
)(
    input  wire         clk, rst_n,
    input  wire         in_valid,
    input  wire [2:0]   in_class,
    input  wire [331:0] in_rec,
    input  wire [31:0]  in_vxx, in_vyy, in_vxy,
    input  wire         in_vxy_neg,
    input  wire [63:0]  in_dd,
    output reg          out_valid,
    output reg  [2:0]   out_kind,
    output reg  [323:0] out_par,
    output reg  [7:0]   out_xmin, out_xmax,
    output reg  [8:0]   out_ymin, out_ymax,
    output reg  [31:0]  drop_count
);
// ---------------- latched inputs ----------------
reg [2:0]   kind;
reg [331:0] rec;
reg [31:0]  vxx, vyy, vxy; reg vxy_neg; reg [63:0] dd;
wire [15:0] M  = rec[15:0];
wire [23:0] sx = rec[39:16];
wire [24:0] sy = rec[64:40];

reg [4:0] st;
localparam S_IDLE=0,
           E0=1, E1=2, E2=3, E3=4, E4=5, E5=6, E6=7, E7=8, E8=9, E9=10, E10=11,
           P0=16, P1=17, P2=18, P3=19, P4=20, P5=21, P6=22, P7=23, P8=24;

// ---------------- arithmetic engines ----------------
reg         dv_start, sq_start;
reg  [63:0] dv_num;  reg [31:0] dv_den;
reg  [63:0] sq_in;
wire [63:0] dv_q;    wire dv_done;
wire [31:0] sq_r;    wire sq_done;
seq_div  u_div  (.clk(clk), .rst_n(rst_n), .start(dv_start), .num(dv_num), .den(dv_den), .quot(dv_q), .done(dv_done));
seq_sqrt u_sqrt (.clk(clk), .rst_n(rst_n), .start(sq_start), .x(sq_in), .root(sq_r), .done(sq_done));

// ---------------- ellipse registers ----------------
reg [31:0]  cxq8, cyq8, rr;
reg [31:0]  lam1, lam2, a16, b16;
reg [15:0]  c14, s14;
reg [31:0]  c2q15;
reg         diff_neg;
reg [31:0]  csq, ssq;
reg [31:0]  ia, ib;
wire [32:0] tsum   = {1'b0, vxx} + {1'b0, vyy};
wire [31:0] diff_a = (vxx >= vyy) ? (vxx - vyy) : (vyy - vxx);
wire [32:0] rr_ext = {1'b0, sq_r};
wire [31:0] lam1_n = (tsum + rr_ext) >> 1;                                   // valid while sq_done of E3
wire [31:0] lam2_n = (tsum > rr_ext) ? ((tsum - rr_ext) >> 1) : 32'd0;
wire [31:0] cx_t = (cxq8 >> 4) + 32'd8;
wire [31:0] cy_t = (cyq8 >> 4) + 32'd8;
wire [31:0] csq_n = diff_neg ? ((32'd32768 - dv_q[31:0]) >> 1) : ((32'd32768 + dv_q[31:0]) >> 1);

// ---------------- polygon registers ----------------
reg [3:0]  ti, tj, tk, tl;                     // tuple indices (0..7)
reg [3:0]  bi, bj, bk, bl;
reg signed [24:0] best_area;
reg [2:0]  nv;                                 // 3 or 4
reg [10:0] vx [0:3];  reg [10:0] vy [0:3];     // vertices, px
reg [2:0]  edge_i;
reg [58:0] line_q [0:3];
reg [15:0] nxq, nyq;
reg [31:0] len;

function [10:0] ext_x; input [3:0] k; input [331:0] r;     // px of the extreme cell k : 4*x + 2
    begin ext_x = {1'b0, r[196 + 17*k +: 8], 2'b00} + 11'd2; end
endfunction
function [10:0] ext_y; input [3:0] k; input [331:0] r;
    begin ext_y = {r[196 + 17*k + 8 +: 9], 2'b00} + 11'd2; end
endfunction

wire signed [11:0] xi = $signed({1'b0, ext_x(ti, rec)}), yi = $signed({1'b0, ext_y(ti, rec)});
wire signed [11:0] xj = $signed({1'b0, ext_x(tj, rec)}), yj = $signed({1'b0, ext_y(tj, rec)});
wire signed [11:0] xk = $signed({1'b0, ext_x(tk, rec)}), yk = $signed({1'b0, ext_y(tk, rec)});
wire signed [11:0] xl = $signed({1'b0, ext_x(tl, rec)}), yl = $signed({1'b0, ext_y(tl, rec)});
wire signed [24:0] area_tri  = (xj - xi) * (yk - yi) - (xk - xi) * (yj - yi);
wire signed [24:0] area_quad = (xk - xi) * (yl - yj) - (xl - xj) * (yk - yi);
wire signed [24:0] area_now  = (kind == 3'd5) ? area_tri : area_quad;

// next tuple (lexicographic combinations of 0..7)
reg [3:0] ni, nj, nk, nl; reg last_tuple;
always @* begin
    ni = ti; nj = tj; nk = tk; nl = tl; last_tuple = 1'b0;
    if (kind == 3'd5) begin
        if (tk < 4'd7) nk = tk + 1'b1;
        else if (tj < 4'd6) begin nj = tj + 1'b1; nk = nj + 1'b1; end
        else if (ti < 4'd5) begin ni = ti + 1'b1; nj = ni + 1'b1; nk = nj + 1'b1; end
        else last_tuple = 1'b1;
    end else begin
        if (tl < 4'd7) nl = tl + 1'b1;
        else if (tk < 4'd6) begin nk = tk + 1'b1; nl = nk + 1'b1; end
        else if (tj < 4'd5) begin nj = tj + 1'b1; nk = nj + 1'b1; nl = nk + 1'b1; end
        else if (ti < 4'd4) begin ni = ti + 1'b1; nj = ni + 1'b1; nk = nj + 1'b1; nl = nk + 1'b1; end
        else last_tuple = 1'b1;
    end
end

// current edge
wire [2:0] e_next = (edge_i + 1'b1 == nv) ? 3'd0 : edge_i + 1'b1;
wire signed [12:0] edx = $signed({2'b0, vx[e_next]}) - $signed({2'b0, vx[edge_i]});
wire signed [12:0] edy = $signed({2'b0, vy[e_next]}) - $signed({2'b0, vy[edge_i]});
wire [11:0] adx = edx[12] ? -edx[11:0] : edx[11:0];
wire [11:0] ady = edy[12] ? -edy[11:0] : edy[11:0];
wire [31:0] len2 = adx * adx + ady * ady;
wire [14:0] anx = (nxq[15] ? -nxq : nxq);
wire [14:0] any = (nyq[15] ? -nyq : nyq);
wire signed [31:0] off_q14 = (K0_Q4 << 10) + ((K1_Q4 * (anx + any)) >> 4);        // px*2^14
wire signed [31:0] dotv = $signed(nxq) * $signed({1'b0, vx[edge_i]}) + $signed(nyq) * $signed({1'b0, vy[edge_i]});
wire signed [31:0] c_full = dotv + off_q14;

integer q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st<=S_IDLE; out_valid<=0; out_kind<=0; out_par<=0; out_xmin<=0; out_xmax<=0; out_ymin<=0; out_ymax<=0; drop_count<=0; kind<=0; rec<=0; vxx<=0; vyy<=0; vxy<=0; vxy_neg<=0; dd<=0;
        dv_start<=0; sq_start<=0; dv_num<=0; dv_den<=1; sq_in<=0; cxq8<=0; cyq8<=0; rr<=0; lam1<=0; lam2<=0; a16<=0; b16<=0;
        c14<=0; s14<=0; c2q15<=0; diff_neg<=0; csq<=0; ssq<=0; ia<=0; ib<=0; ti<=0; tj<=0; tk<=0; tl<=0; bi<=0; bj<=0; bk<=0; bl<=0;
        best_area<=0; nv<=0; edge_i<=0; nxq<=0; nyq<=0; len<=0;
        for (q=0;q<4;q=q+1) begin vx[q]<=0; vy[q]<=0; line_q[q]<=0; end
    end else begin
        out_valid <= 1'b0; dv_start <= 1'b0; sq_start <= 1'b0;
        case (st)
        S_IDLE: if (in_valid && in_class != 3'd0) begin
            kind <= in_class; rec <= in_rec; vxx <= in_vxx; vyy <= in_vyy; vxy <= in_vxy; vxy_neg <= in_vxy_neg; dd <= in_dd;
            st <= (in_class <= 3'd2) ? E0 : P0;
        end
        // ================= ellipse / circle =================
        E0: begin dv_num <= {32'd0, sx, 8'd0}; dv_den <= {16'd0, M}; dv_start <= 1'b1; st <= E1; end
        E1: if (dv_done) begin cxq8 <= dv_q[31:0]; dv_num <= {31'd0, sy, 8'd0}; dv_den <= {16'd0, M}; dv_start <= 1'b1; st <= E2; end
        E2: if (dv_done) begin cyq8 <= dv_q[31:0]; sq_in <= dd; sq_start <= 1'b1; st <= E3; end
        E3: if (sq_done) begin
            rr <= sq_r;
            lam1 <= lam1_n; lam2 <= lam2_n;
            sq_in <= {26'd0, lam1_n, 6'd0}; sq_start <= 1'b1; st <= E4;
        end
        E4: if (sq_done) begin a16 <= sq_r; sq_in <= {26'd0, lam2, 6'd0}; sq_start <= 1'b1; st <= E5; end
        E5: if (sq_done) begin
            b16 <= sq_r; diff_neg <= (vxx < vyy);
            if (rr == 32'd0) begin c14 <= 16'd16384; s14 <= 16'd0; st <= E8; ia <= 0; end
            else begin dv_num <= {17'd0, diff_a, 15'd0}; dv_den <= rr; dv_start <= 1'b1; st <= E6; end
        end
        E6: if (dv_done) begin
            // dv_q = |Vxx-Vyy| / R in Q15  (0 .. 32768) = |cos 2theta|
            c2q15 <= dv_q[31:0];
            csq <= csq_n;                                  // cos^2 theta, Q15
            ssq <= 32'd32768 - csq_n;
            sq_in <= {19'd0, csq_n, 13'd0};
            sq_start <= 1'b1; st <= E7;
        end
        E7: if (sq_done) begin c14 <= sq_r[15:0]; sq_in <= {19'd0, ssq, 13'd0}; sq_start <= 1'b1; st <= 5'd30; end
        5'd30: if (sq_done) begin s14 <= vxy_neg ? -sq_r[15:0] : sq_r[15:0]; st <= E8; end
        E8: begin
            // circle: both axes are the mean
            if (kind == 3'd1) begin a16 <= (a16 + b16) >> 1; b16 <= (a16 + b16) >> 1; end
            st <= 5'd31;
        end
        5'd31: begin
            a16 <= a16 + KE_Q4; b16 <= b16 + KE_Q4; st <= E9;
        end
        E9: begin dv_num <= 64'd16777216; dv_den <= a16; dv_start <= 1'b1; st <= E10; end   // 2^24 / a16 = Q20 of 1/a_px
        E10: if (dv_done) begin
            ia <= dv_q[31:0]; dv_num <= 64'd16777216; dv_den <= b16; dv_start <= 1'b1; st <= 5'd29;
        end
        5'd29: if (dv_done) begin
            out_kind <= kind; out_xmin <= rec[168:161]; out_xmax <= rec[176:169]; out_ymin <= rec[185:177]; out_ymax <= rec[194:186];
            out_par <= {203'd0,
                        dv_q[17:0], ia[17:0], s14, c14, b16[13:0], a16[13:0],
                        cy_t[12:0], cx_t[11:0]};
            out_valid <= 1'b1; st <= S_IDLE;
        end
        // ================= polygon =================
        P0: begin
            nv <= (kind == 3'd5) ? 3'd3 : 3'd4; best_area <= -25'sd1;
            ti <= 0; tj <= 1; tk <= 2; tl <= 3; bi <= 0; bj <= 1; bk <= 2; bl <= 3; st <= P1;
        end
        P1: begin
            if (area_now > best_area) begin best_area <= area_now; bi <= ti; bj <= tj; bk <= tk; bl <= tl; end
            if (last_tuple) st <= P2;
            else begin ti <= ni; tj <= nj; tk <= nk; tl <= nl; end
        end
        P2: begin
            vx[0] <= ext_x(bi, rec); vy[0] <= ext_y(bi, rec);
            vx[1] <= ext_x(bj, rec); vy[1] <= ext_y(bj, rec);
            vx[2] <= ext_x(bk, rec); vy[2] <= ext_y(bk, rec);
            vx[3] <= (kind == 3'd5) ? ext_x(bk, rec) : ext_x(bl, rec); vy[3] <= (kind == 3'd5) ? ext_y(bk, rec) : ext_y(bl, rec);
            edge_i <= 3'd0; st <= P3;
        end
        P3: begin sq_in <= {24'd0, len2, 8'd0}; sq_start <= 1'b1; st <= P4; end        // sqrt(len2*256) = 16*L
        P4: if (sq_done) begin
            len <= (sq_r == 32'd0) ? 32'd1 : sq_r;
            dv_num <= {34'd0, ady, 18'd0}; dv_den <= (sq_r == 32'd0) ? 32'd1 : sq_r; dv_start <= 1'b1; st <= P5;
        end
        P5: if (dv_done) begin
            nxq <= edy[12] ? -dv_q[15:0] : dv_q[15:0];                     // nx =  dy / L
            dv_num <= {34'd0, adx, 18'd0}; dv_den <= len; dv_start <= 1'b1; st <= P6;
        end
        P6: if (dv_done) begin
            nyq <= edx[12] ? dv_q[15:0] : -dv_q[15:0];                     // ny = -dx / L
            st <= P7;
        end
        P7: begin
            line_q[edge_i] <= {c_full[26:0], nyq, nxq};
            if (edge_i + 1'b1 == nv) begin
                if (nv == 3'd3) line_q[3] <= {27'h3ffffff, 16'd0, 16'd0};
                st <= P8;
            end else begin edge_i <= edge_i + 1'b1; st <= P3; end
        end
        P8: begin
            out_kind <= kind; out_xmin <= rec[168:161]; out_xmax <= rec[176:169]; out_ymin <= rec[185:177]; out_ymax <= rec[194:186];
            out_par <= {vy[3], vx[3], vy[2], vx[2], vy[1], vx[1], vy[0], vx[0], line_q[3], line_q[2], line_q[1], line_q[0]};
            out_valid <= 1'b1; st <= S_IDLE;
        end
        default: st <= S_IDLE;
        endcase
        if (in_valid && st != S_IDLE && in_class != 3'd0) drop_count <= drop_count + 1'b1;
    end
end
endmodule
