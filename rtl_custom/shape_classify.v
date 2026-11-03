`timescale 1ns/1ps
//======================================================================================================
// shape_classify.v - classify one connected hole region from its accumulated moments.
//
// Record (REC_W = 196 bits, LSB first):
//   [15:0] M   [39:16] sx   [64:40] sy   [96:65] sxx   [128:97] syy   [160:129] sxy
//   [168:161] xmin [176:169] xmax [185:177] ymin [194:186] ymax   [195] touch
//
// Invariant used (all arithmetic exact integers, see sim/shape/shape_int.py):
//   Cxx = M*sxx - sx^2   Cyy = M*syy - sy^2   Cxy = M*sxy - sx*sy
//   V** = (C** << 8) / M^2            (variance * 256)
//   I1  = ((Vxx*Vyy - Vxy^2) << 8) / M^2          = det(cov)/M^2 * 2^24
//         circle/ellipse 1/(16 pi^2)=0.00633, square/rect 1/144=0.00694, triangle 1/108=0.00926
//   elongated  <=>  64*((Vxx-Vyy)^2 + 4*Vxy^2) > (Vxx+Vyy)^2
// class: 1 circle 2 ellipse 3 square 4 rect 5 triangle 0 unknown
//======================================================================================================
module shape_classify #(
    parameter [31:0] I_CIRC_LO = 32'd100663,   // 0.00600 * 2^24
    parameter [31:0] I_CIRC_HI = 32'd112071,   // 0.00668
    parameter [31:0] I_QUAD_LO = 32'd113413,   // 0.00676
    parameter [31:0] I_QUAD_HI = 32'd127506,   // 0.00760
    parameter [31:0] I_TRI_LO  = 32'd142606,   // 0.00850
    parameter [31:0] I_TRI_HI  = 32'd167772    // 0.01000
)(
    input  wire         clk, rst_n,
    input  wire         in_valid,
    input  wire [331:0] in_rec,
    output reg          out_valid,
    output reg  [2:0]   out_class,
    output reg  [7:0]   out_xmin, out_xmax,
    output reg  [8:0]   out_ymin, out_ymax,
    output reg  [31:0]  out_i1,
    output reg          out_elong,
    output reg  [31:0]  drop_count,
    // geometry passed on to shape_fit (variances are cells^2 * 256)
    output reg  [331:0] out_rec,
    output reg  [31:0]  out_vxx, out_vyy, out_vxy,
    output reg          out_vxy_neg,
    output reg  [63:0]  out_dd
);
// ---- 2-entry input FIFO (registers) ----
reg [331:0] fifo [0:1];
reg [1:0] wp, rp;
wire fifo_empty = (wp == rp);
wire fifo_full  = (wp[0] == rp[0]) && (wp[1] != rp[1]);

// ---- working registers ----
reg [331:0] rec;
wire [15:0] M   = rec[15:0];
wire [23:0] sx  = rec[39:16];
wire [24:0] sy  = rec[64:40];
wire [31:0] sxx = rec[96:65];
wire [31:0] syy = rec[128:97];
wire [31:0] sxy = rec[160:129];
reg [31:0] mm;
reg [63:0] t1;
reg [63:0] cxx, cyy, cxy_abs;
reg cxy_neg;
reg [31:0] vxx, vyy, vxy;
reg [63:0] m1, m2, det, tt, i1;

reg  mul_start, div_start;
reg  [31:0] mul_a, mul_b;
reg  [63:0] div_num; reg [31:0] div_den;
wire [63:0] mul_p, div_q;
wire mul_done, div_done;
seq_mul u_mul (.clk(clk),.rst_n(rst_n),.start(mul_start),.a(mul_a),.b(mul_b),.p(mul_p),.done(mul_done));
seq_div u_div (.clk(clk),.rst_n(rst_n),.start(div_start),.num(div_num),.den(div_den),.quot(div_q),.done(div_done));

localparam S_IDLE=0, S_MM=1, S_T1=2, S_T2=3, S_T3=4, S_T4=5, S_T5=6, S_T6=7,
           S_D1=8, S_D2=9, S_D3=10, S_M1=11, S_M2=12, S_D4=13, S_M3=14, S_M4=15, S_FIN=16;
reg [4:0] st;
reg       issued;      // operation launched in this state

wire [31:0] vdiff = (vxx >= vyy) ? (vxx - vyy) : (vyy - vxx);
wire [31:0] vsum  = vxx + vyy;
wire [63:0] dd    = m1 + {m2[61:0], 2'b00};            // (Vxx-Vyy)^2 + 4*Vxy^2
wire        elong = ((dd << 6) > tt);
wire [31:0] i1_32 = i1[31:0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wp<=0; rp<=0; st<=S_IDLE; issued<=0; rec<=0; mul_start<=0; div_start<=0; mul_a<=0; mul_b<=0;
        div_num<=0; div_den<=1; out_valid<=0; out_class<=0; out_xmin<=0; out_xmax<=0; out_ymin<=0; out_ymax<=0;
        out_i1<=0; out_elong<=0; drop_count<=0; mm<=0; t1<=0; cxx<=0; cyy<=0; cxy_abs<=0;
        vxx<=0; vyy<=0; vxy<=0; m1<=0; m2<=0; det<=0; tt<=0; i1<=0;
        out_rec<=0; out_vxx<=0; out_vyy<=0; out_vxy<=0; out_vxy_neg<=0; out_dd<=0; cxy_neg<=0;
    end else begin
        out_valid <= 1'b0; mul_start <= 1'b0; div_start <= 1'b0;
        // FIFO write
        if (in_valid) begin
            if (fifo_full) drop_count <= drop_count + 1'b1;
            else begin fifo[wp[0]] <= in_rec; wp <= wp + 1'b1; end
        end
        case (st)
        S_IDLE: if (!fifo_empty) begin rec <= fifo[rp[0]]; rp <= rp + 1'b1; st <= S_MM; issued <= 0; end
        // mm = M*M
        S_MM: if (!issued) begin mul_a<={16'd0,M}; mul_b<={16'd0,M}; mul_start<=1; issued<=1; end
              else if (mul_done) begin mm <= mul_p[31:0]; st<=S_T1; issued<=0; end
        S_T1: if (!issued) begin mul_a<={16'd0,M}; mul_b<=sxx; mul_start<=1; issued<=1; end
              else if (mul_done) begin t1 <= mul_p; st<=S_T2; issued<=0; end
        S_T2: if (!issued) begin mul_a<={8'd0,sx}; mul_b<={8'd0,sx}; mul_start<=1; issued<=1; end
              else if (mul_done) begin cxx <= t1 - mul_p; st<=S_T3; issued<=0; end
        S_T3: if (!issued) begin mul_a<={16'd0,M}; mul_b<=syy; mul_start<=1; issued<=1; end
              else if (mul_done) begin t1 <= mul_p; st<=S_T4; issued<=0; end
        S_T4: if (!issued) begin mul_a<={7'd0,sy}; mul_b<={7'd0,sy}; mul_start<=1; issued<=1; end
              else if (mul_done) begin cyy <= t1 - mul_p; st<=S_T5; issued<=0; end
        S_T5: if (!issued) begin mul_a<={16'd0,M}; mul_b<=sxy; mul_start<=1; issued<=1; end
              else if (mul_done) begin t1 <= mul_p; st<=S_T6; issued<=0; end
        S_T6: if (!issued) begin mul_a<={8'd0,sx}; mul_b<={7'd0,sy}; mul_start<=1; issued<=1; end
              else if (mul_done) begin
                  cxy_abs <= (t1 >= mul_p) ? (t1 - mul_p) : (mul_p - t1);
                  cxy_neg <= (t1 < mul_p);
                  st<=S_D1; issued<=0; end
        S_D1: if (!issued) begin div_num<={cxx[55:0],8'd0}; div_den<=mm; div_start<=1; issued<=1; end
              else if (div_done) begin vxx <= div_q[31:0]; st<=S_D2; issued<=0; end
        S_D2: if (!issued) begin div_num<={cyy[55:0],8'd0}; div_den<=mm; div_start<=1; issued<=1; end
              else if (div_done) begin vyy <= div_q[31:0]; st<=S_D3; issued<=0; end
        S_D3: if (!issued) begin div_num<={cxy_abs[55:0],8'd0}; div_den<=mm; div_start<=1; issued<=1; end
              else if (div_done) begin vxy <= div_q[31:0]; st<=S_M1; issued<=0; end
        // m1 = Vxx*Vyy ; m2 = Vxy^2 ; det = m1 - m2   (sign of Vxy is irrelevant for det and D)
        S_M1: if (!issued) begin mul_a<=vxx; mul_b<=vyy; mul_start<=1; issued<=1; end
              else if (mul_done) begin m1 <= mul_p; st<=S_M2; issued<=0; end
        S_M2: if (!issued) begin mul_a<=vxy; mul_b<=vxy; mul_start<=1; issued<=1; end
              else if (mul_done) begin m2 <= mul_p; det <= (m1 >= mul_p) ? (m1 - mul_p) : 64'd0; st<=S_D4; issued<=0; end
        S_D4: if (!issued) begin div_num<={det[55:0],8'd0}; div_den<=mm; div_start<=1; issued<=1; end
              else if (div_done) begin i1 <= div_q; st<=S_M3; issued<=0; end
        // tt = (Vxx+Vyy)^2 ; m1 = (Vxx-Vyy)^2
        S_M3: if (!issued) begin mul_a<=vsum; mul_b<=vsum; mul_start<=1; issued<=1; end
              else if (mul_done) begin tt <= mul_p; st<=S_M4; issued<=0; end
        S_M4: if (!issued) begin mul_a<=vdiff; mul_b<=vdiff; mul_start<=1; issued<=1; end
              else if (mul_done) begin m1 <= mul_p; st<=S_FIN; issued<=0; end
        S_FIN: begin
            out_i1   <= i1_32;
            out_rec <= rec; out_vxx <= vxx; out_vyy <= vyy; out_vxy <= vxy; out_vxy_neg <= cxy_neg; out_dd <= dd;
            out_elong<= elong;
            out_xmin <= rec[168:161]; out_xmax <= rec[176:169]; out_ymin <= rec[185:177]; out_ymax <= rec[194:186];
            if (i1_32 >= I_CIRC_LO && i1_32 <= I_CIRC_HI)       out_class <= elong ? 3'd2 : 3'd1;
            else if (i1_32 >= I_QUAD_LO && i1_32 <= I_QUAD_HI)  out_class <= elong ? 3'd4 : 3'd3;
            else if (i1_32 >= I_TRI_LO && i1_32 <= I_TRI_HI)    out_class <= 3'd5;
            else                                                out_class <= 3'd0;
            out_valid <= 1'b1; st <= S_IDLE;
        end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
