`timescale 1ns/1ps
//======================================================================================================
// shape_ccl.v - streaming connected-component labelling of the HOLES of the dilated, pooled edge map.
//
//   p_*        pooled edge cells (1 = edge) in raster order, MAP_W x MAP_H (240 x 270) per frame
//   rows       3 pooled rows are kept; the middle one is dilated 3x3 (closes small outline gaps)
//   labelling  4-connected regions of "no edge" cells; one pooled row is processed in a few thousand
//              clocks (there are ~4400 clocks per pooled row), pixel by pixel with run accumulation
//   regions    NL-1 labels (id 0 = none, id NL-1 = overflow sink). Closed labels are recycled.
//   output     fin_valid/fin_rec : one record for every region that does NOT touch the map border and
//              whose area is within [MMIN, MMAX]  (record layout: see shape_classify.v)
//======================================================================================================
module shape_ccl #(
    parameter integer MAP_W = 240,
    parameter integer MAP_H = 270,
    parameter integer MMIN  = 600,
    parameter integer MMAX  = 38880,
    parameter integer BMIN  = 5400     // bounding-box area (4x4 cells) must be >= this (1/12 of the 240x270 crop)
)(
    input  wire         clk, rst_n,
    input  wire         p_valid, p_bit, p_frame_start,
    output reg          fin_valid,
    output reg  [331:0] fin_rec,
    output reg          frame_done,
    output reg  [15:0]  ovf_count, overrun_count
);
localparam NL = 32;
localparam [4:0] OVF = 5'd31;

// ---------------- record field positions ----------------
// bits [195:0]  : moments, bbox, touch flag (see shape_classify.v)
// bits [331:196]: eight directional extreme cells, 17 bits each = {y[8:0], x[7:0]}, in angular order
//                 k0 (1,0) k1 (1,1) k2 (0,1) k3 (-1,1) k4 (-1,0) k5 (-1,-1) k6 (0,-1) k7 (1,-1)   (image y points down)
//                 extreme of  p = dx*x + dy*y ;  ties keep the first cell in raster order
localparam integer P_M=0, W_M=16, P_SX=16, W_SX=24, P_SY=40, W_SY=25, P_SXX=65, W_SXX=32, P_SYY=97, W_SYY=32,
                   P_SXY=129, W_SXY=32, P_XMIN=161, P_XMAX=169, P_YMIN=177, P_YMAX=186, P_T=195;
localparam integer P_E = 196;
function [16:0] ext_init;
    input integer k;
    reg [7:0] x0; reg [8:0] y0;
    begin
        // minimal p for the direction, so any real cell replaces it
        x0 = (k==3 || k==4 || k==5) ? 8'd255 : 8'd0;
        y0 = (k==5 || k==6 || k==7) ? 9'd511 : 9'd0;
        ext_init = {y0, x0};
    end
endfunction
function signed [11:0] ext_p;                  // projection of cell (x,y) on direction k
    input integer k; input [7:0] x; input [8:0] y;
    reg signed [11:0] xs, ys;
    begin
        xs = $signed({4'd0, x}); ys = $signed({3'd0, y});
        case (k)
        0: ext_p = xs;          1: ext_p = xs + ys;   2: ext_p = ys;          3: ext_p = ys - xs;
        4: ext_p = -xs;         5: ext_p = -xs - ys;  6: ext_p = -ys;         default: ext_p = xs - ys;
        endcase
    end
endfunction
function [331:0] rec_init;
    input dummy;
    integer k; reg [331:0] r;
    begin
        r = 332'd0;
        r[P_XMIN +: 8] = 8'd255; r[P_YMIN +: 9] = 9'd511;
        for (k = 0; k < 8; k = k + 1) r[P_E + 17*k +: 17] = ext_init(k);
        rec_init = r;
    end
endfunction
localparam [331:0] REC_INIT = rec_init(1'b0);

// ---------------- pooled row collection ----------------
reg [MAP_W-1:0] rowbuf, r0, r1, r2;
reg [8:0] bitcnt, rows_in;
reg       go_req, flush_req, clr_req;
reg [8:0] go_y;
wire [MAP_W-1:0] rowbuf_n = {p_bit, rowbuf[MAP_W-1:1]};

function [MAP_W-1:0] h3;
    input [MAP_W-1:0] v;
    begin h3 = v | {v[MAP_W-2:0], 1'b0} | {1'b0, v[MAP_W-1:1]}; end
endfunction
wire [MAP_W-1:0] dil = h3(r0) | h3(r1) | h3(r2);     // dilated middle row (r1)

// ---------------- label state ----------------
reg [NL-1:0] act, seen, gone, aged;
reg [4:0]    rep [0:NL-1];
integer i;

// ---------------- RAMs ----------------
reg         lp_we;  reg [7:0] lp_waddr;  reg [4:0] lp_wdata;
wire [4:0]  lp_q;
reg  [7:0]  x;
simple_dual_port_ram #(.DATA_WIDTH(5), .ADDR_WIDTH(8), .OUTPUT_REG("FALSE")) u_lp (
    .wdata(lp_wdata), .waddr(lp_waddr), .raddr(x), .we(lp_we), .wclk(clk), .re(1'b1), .rclk(clk), .rdata(lp_q));

reg         st_we;  reg [4:0] st_waddr;  reg [331:0] st_wdata;
reg  [4:0]  st_ra;
wire [331:0] st_q;
simple_dual_port_ram #(.DATA_WIDTH(332), .ADDR_WIDTH(5), .OUTPUT_REG("FALSE")) u_st (
    .wdata(st_wdata), .waddr(st_waddr), .raddr(st_ra), .we(st_we), .wclk(clk), .re(1'b1), .rclk(clk), .rdata(st_q));

// ---------------- row engine ----------------
localparam S_IDLE=0, S_CLR=1, S_ROWINIT=2, S_FETCH=3, S_EVAL=4, S_FINDN=5, S_DEC=6, S_MRG1=7, S_MRG2=8, S_MRG3=9,
           S_ACC=10, S_ADV=11, S_FL1=12, S_FL2=13, S_FL3=14, S_FL4=15, S_ER0=16, S_ER1=17, S_ER2=18, S_ER3=19, S_ER4=20, S_ER5=21;
reg [4:0] st;
reg [4:0] after_flush;
reg [8:0] y;
reg [16:0] ysq;
reg [MAP_W-1:0] drow;
reg [4:0] run_lab, t, rn, mb_a, mb_b, el;
reg [7:0]  run_cnt, run_xmin, run_xmax;
reg [15:0] run_sx;
reg [23:0] run_sxx;
reg        run_touch;
reg [331:0] sa;
reg [15:0] p_sy;  reg [24:0] p_syy, p_sxy;
reg [7:0]  clr_cnt;
reg [331:0] er_rec;
reg [7:0] bw;  reg [8:0] bh;  reg [16:0] bprod;

wire bg = ~drow[0];
wire border_pix = (x == 0) || (x == MAP_W-1) || (y == 0) || (y == MAP_H-1);

// priority encoder: first free label in 1..30
reg [4:0] fl; reg fl_ok;
always @* begin
    fl = 5'd0; fl_ok = 1'b0;
    for (i = 30; i >= 1; i = i - 1) if (!act[i]) begin fl = i[4:0]; fl_ok = 1'b1; end
end

wire [4:0] mrg_a = (rn < run_lab) ? rn : run_lab;
wire [4:0] mrg_b = (rn < run_lab) ? run_lab : rn;

function [331:0] merge_rec;
    input [331:0] a, b;
    integer k; reg [7:0] ax, bx; reg [8:0] ay, by;
    begin
        merge_rec = 332'd0;
        merge_rec[P_M   +: W_M  ] = a[P_M   +: W_M  ] + b[P_M   +: W_M  ];
        merge_rec[P_SX  +: W_SX ] = a[P_SX  +: W_SX ] + b[P_SX  +: W_SX ];
        merge_rec[P_SY  +: W_SY ] = a[P_SY  +: W_SY ] + b[P_SY  +: W_SY ];
        merge_rec[P_SXX +: W_SXX] = a[P_SXX +: W_SXX] + b[P_SXX +: W_SXX];
        merge_rec[P_SYY +: W_SYY] = a[P_SYY +: W_SYY] + b[P_SYY +: W_SYY];
        merge_rec[P_SXY +: W_SXY] = a[P_SXY +: W_SXY] + b[P_SXY +: W_SXY];
        merge_rec[P_XMIN +: 8] = (a[P_XMIN +: 8] < b[P_XMIN +: 8]) ? a[P_XMIN +: 8] : b[P_XMIN +: 8];
        merge_rec[P_XMAX +: 8] = (a[P_XMAX +: 8] > b[P_XMAX +: 8]) ? a[P_XMAX +: 8] : b[P_XMAX +: 8];
        merge_rec[P_YMIN +: 9] = (a[P_YMIN +: 9] < b[P_YMIN +: 9]) ? a[P_YMIN +: 9] : b[P_YMIN +: 9];
        merge_rec[P_YMAX +: 9] = (a[P_YMAX +: 9] > b[P_YMAX +: 9]) ? a[P_YMAX +: 9] : b[P_YMAX +: 9];
        merge_rec[P_T] = a[P_T] | b[P_T];
        for (k = 0; k < 8; k = k + 1) begin
            ax = a[P_E + 17*k +: 8]; ay = a[P_E + 17*k + 8 +: 9];
            bx = b[P_E + 17*k +: 8]; by = b[P_E + 17*k + 8 +: 9];
            if (ext_p(k, bx, by) > ext_p(k, ax, ay)) merge_rec[P_E + 17*k +: 17] = {by, bx};
            else                                       merge_rec[P_E + 17*k +: 17] = {ay, ax};
        end
    end
endfunction

function [331:0] flush_rec;
    input [331:0] a;
    input [7:0] cnt, xmn, xmx;
    input [15:0] sxr;
    input [23:0] sxxr;
    input [15:0] psy;
    input [24:0] psyy, psxy;
    input [8:0] yy;
    input touch;
    integer k; reg [7:0] cx, ox; reg [8:0] oy;
    begin
        flush_rec = 332'd0;
        flush_rec[P_M   +: W_M  ] = a[P_M   +: W_M  ] + cnt;
        flush_rec[P_SX  +: W_SX ] = a[P_SX  +: W_SX ] + sxr;
        flush_rec[P_SY  +: W_SY ] = a[P_SY  +: W_SY ] + psy;
        flush_rec[P_SXX +: W_SXX] = a[P_SXX +: W_SXX] + sxxr;
        flush_rec[P_SYY +: W_SYY] = a[P_SYY +: W_SYY] + psyy;
        flush_rec[P_SXY +: W_SXY] = a[P_SXY +: W_SXY] + psxy;
        flush_rec[P_XMIN +: 8] = (a[P_XMIN +: 8] < xmn) ? a[P_XMIN +: 8] : xmn;
        flush_rec[P_XMAX +: 8] = (a[P_XMAX +: 8] > xmx) ? a[P_XMAX +: 8] : xmx;
        flush_rec[P_YMIN +: 9] = (a[P_YMIN +: 9] < yy) ? a[P_YMIN +: 9] : yy;
        flush_rec[P_YMAX +: 9] = (a[P_YMAX +: 9] > yy) ? a[P_YMAX +: 9] : yy;
        flush_rec[P_T] = a[P_T] | touch;
        for (k = 0; k < 8; k = k + 1) begin
            cx = (k==0 || k==1 || k==7) ? xmx : xmn;                 // dx > 0 -> right end of the run, else left end
            ox = a[P_E + 17*k +: 8]; oy = a[P_E + 17*k + 8 +: 9];
            if (ext_p(k, cx, yy) > ext_p(k, ox, oy)) flush_rec[P_E + 17*k +: 17] = {yy, cx};
            else                                      flush_rec[P_E + 17*k +: 17] = {oy, ox};
        end
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rowbuf<=0; r0<=0; r1<=0; r2<=0; bitcnt<=0; rows_in<=0; go_req<=0; flush_req<=0; clr_req<=0; go_y<=0;
        act<={1'b1,31'd0}; seen<=0; gone<=0; aged<=0;
        for (i=0;i<NL;i=i+1) rep[i] <= i[4:0];
        lp_we<=0; lp_waddr<=0; lp_wdata<=0; st_we<=0; st_waddr<=0; st_wdata<=0; st_ra<=0; x<=0;
        st<=S_IDLE; after_flush<=S_ADV; y<=0; ysq<=0; drow<=0; run_lab<=0; t<=0; rn<=0; mb_a<=0; mb_b<=0; el<=0;
        run_cnt<=0; run_xmin<=0; run_xmax<=0; run_sx<=0; run_sxx<=0; run_touch<=0; sa<=0; p_sy<=0; p_syy<=0; p_sxy<=0;
        clr_cnt<=0; er_rec<=0; bw<=0; bh<=0; bprod<=0; fin_valid<=0; fin_rec<=0; frame_done<=0; ovf_count<=0; overrun_count<=0;
    end else begin
        lp_we <= 1'b0; st_we <= 1'b0; fin_valid <= 1'b0; frame_done <= 1'b0;

        // ---------- pooled row collection ----------
        if (p_frame_start) begin bitcnt<=0; rows_in<=0; clr_req<=1'b1; go_req<=1'b0; flush_req<=1'b0; r0<=0; r1<=0; r2<=0; end
        else if (p_valid) begin
            rowbuf <= rowbuf_n;
            if (bitcnt == MAP_W-1) begin
                bitcnt <= 0; rows_in <= rows_in + 1'b1;
                r2 <= r1; r1 <= r0; r0 <= rowbuf_n;
                if (rows_in >= 1) begin
                    if (go_req || (st != S_IDLE)) overrun_count <= overrun_count + 1'b1;
                    go_req <= 1'b1; go_y <= rows_in - 1'b1;
                    if (rows_in == MAP_H-1) flush_req <= 1'b1;
                end
            end else bitcnt <= bitcnt + 1'b1;
        end

        // ---------- row engine ----------
        case (st)
        S_IDLE: begin
            if (clr_req) begin clr_req<=1'b0; clr_cnt<=8'd0; st<=S_CLR; end
            else if (go_req) begin go_req<=1'b0; y<=go_y; st<=S_ROWINIT; end
            else if (flush_req) begin
                flush_req<=1'b0; r2<=r1; r1<=r0; r0<={MAP_W{1'b0}}; y<=MAP_H-1; st<=S_ROWINIT;
            end
        end
        S_CLR: begin   // new frame: forget all labels, zero the previous-row label line
            lp_we<=1'b1; lp_waddr<=clr_cnt; lp_wdata<=5'd0; clr_cnt<=clr_cnt+1'b1;
            act<={1'b1,31'd0}; seen<=0; gone<=0; aged<=0;
            for (i=0;i<NL;i=i+1) rep[i] <= i[4:0];
            if (clr_cnt == MAP_W-1) st<=S_IDLE;
        end
        S_ROWINIT: begin
            x<=8'd0; drow<=dil; run_lab<=5'd0; run_cnt<=8'd0; ysq<=y*y; st<=S_FETCH;
        end
        S_FETCH: st <= S_EVAL;                       // lp_q (row above, column x) arrives next cycle
        S_EVAL: begin
            if (!bg) begin
                lp_we<=1'b1; lp_waddr<=x; lp_wdata<=5'd0;
                if (run_lab != 0) begin after_flush<=S_ADV; st<=S_FL1; end
                else st<=S_ADV;
            end else if (lp_q == 5'd0) begin rn<=5'd0; st<=S_DEC; end
            else begin t<=lp_q; st<=S_FINDN; end
        end
        S_FINDN: begin
            if (rep[t] == t) begin rn<=t; st<=S_DEC; end
            else t<=rep[t];
        end
        S_DEC: begin
            if (run_lab == 5'd0) begin
                run_cnt<=8'd0;
                if (rn == 5'd0) begin
                    if (fl_ok) begin
                        run_lab<=fl; act[fl]<=1'b1; rep[fl]<=fl; seen[fl]<=1'b1;
                        st_we<=1'b1; st_waddr<=fl; st_wdata<=REC_INIT;
                    end else begin run_lab<=OVF; ovf_count<=ovf_count+1'b1; end
                end else begin run_lab<=rn; seen[rn]<=1'b1; end
                st<=S_ACC;
            end else if (rn == 5'd0 || rn == run_lab) st<=S_ACC;
            else if (rn == OVF || run_lab == OVF) begin       // merge into the overflow sink: region is lost
                if (rn == OVF) begin rep[run_lab]<=OVF; gone[run_lab]<=1'b1; end
                else begin rep[rn]<=OVF; gone[rn]<=1'b1; end
                run_lab<=OVF; st<=S_ACC;
            end else begin
                mb_a<=mrg_a; mb_b<=mrg_b; st_ra<=mrg_a; st<=S_MRG1;
            end
        end
        S_MRG1: begin st_ra<=mb_b; st<=S_MRG2; end
        S_MRG2: begin sa<=st_q; st<=S_MRG3; end
        S_MRG3: begin
            st_we<=1'b1; st_waddr<=mb_a; st_wdata<=merge_rec(sa, st_q);
            rep[mb_b]<=mb_a; gone[mb_b]<=1'b1; seen[mb_a]<=1'b1; run_lab<=mb_a; st<=S_ACC;
        end
        S_ACC: begin
            run_cnt <= run_cnt + 1'b1;
            run_sx  <= ((run_cnt==0) ? 16'd0 : run_sx) + x;
            run_sxx <= ((run_cnt==0) ? 24'd0 : run_sxx) + x*x;
            if (run_cnt == 0) run_xmin <= x;
            run_xmax <= x;
            run_touch <= ((run_cnt==0) ? 1'b0 : run_touch) | border_pix;
            lp_we<=1'b1; lp_waddr<=x; lp_wdata<=run_lab;
            seen[run_lab] <= 1'b1;
            st<=S_ADV;
        end
        S_ADV: begin
            x <= x + 1'b1; drow <= {1'b0, drow[MAP_W-1:1]};
            if (x == MAP_W-1) begin
                if (run_lab != 0) begin after_flush<=S_ER0; st<=S_FL1; end
                else st<=S_ER0;
            end else st<=S_FETCH;
        end
        // ---- flush the run accumulator into the label statistics ----
        S_FL1: begin
            if (run_lab == OVF || run_cnt == 0) begin run_lab<=5'd0; st<=after_flush; end
            else begin st_ra<=run_lab; st<=S_FL2; end
        end
        S_FL2: st<=S_FL3;
        S_FL3: begin
            sa<=st_q; p_sy<=y*run_cnt; p_syy<=ysq*run_cnt; p_sxy<=y*run_sx; st<=S_FL4;
        end
        S_FL4: begin
            st_we<=1'b1; st_waddr<=run_lab;
            st_wdata<=flush_rec(sa, run_cnt, run_xmin, run_xmax, run_sx, run_sxx, p_sy, p_syy, p_sxy, y, run_touch);
            run_lab<=5'd0; run_cnt<=8'd0; st<=after_flush;
        end
        // ---- end of row: recycle labels, report closed regions ----
        S_ER0: begin el<=5'd1; st<=S_ER1; end
        S_ER1: begin
            if (el == OVF) begin
                seen <= 0;
                if (y == MAP_H-1) frame_done <= 1'b1;
                st<=S_IDLE;
            end else begin
                if (aged[el]) begin act[el]<=1'b0; aged[el]<=1'b0; end
                else if (gone[el]) begin aged[el]<=1'b1; gone[el]<=1'b0; end
                if (act[el] && rep[el]==el && !seen[el] && !aged[el]) begin st_ra<=el; st<=S_ER2; end
                else el<=el+1'b1;
            end
        end
        S_ER2: st<=S_ER3;
        S_ER3: begin
            er_rec <= st_q;
            bw <= st_q[P_XMAX +: 8] - st_q[P_XMIN +: 8] + 8'd1;
            bh <= st_q[P_YMAX +: 9] - st_q[P_YMIN +: 9] + 9'd1;
            st <= S_ER4;
        end
        S_ER4: begin bprod <= bw * bh; st <= S_ER5; end
        S_ER5: begin
            if (!er_rec[P_T] && er_rec[P_M +: W_M] >= MMIN && er_rec[P_M +: W_M] <= MMAX && bprod >= BMIN) begin
                fin_valid<=1'b1; fin_rec<=er_rec;
            end
            act[el]<=1'b0; el<=el+1'b1; st<=S_ER1;
        end
        default: st<=S_IDLE;
        endcase
    end
end
endmodule
