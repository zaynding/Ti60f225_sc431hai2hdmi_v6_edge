`timescale 1ns/1ps
// Live nearest-template assignment of three distinct foreground components.
// No confidence, size, aspect, border, order, spacing or alignment rejection.
module digit_match_7p2 #(
    parameter integer MAP_W=240, MAP_H=270, NL=64,
    parameter TEMPLATE_FILE="digit_7p2_templates.mem"
)(
    input wire clk,rst_n,enable,restart,go,map_we,
    input wire [15:0] map_waddr,
    input wire map_wbit,
    output wire busy,
    output reg done,found,
    output reg [4:0] result,
    output reg [3:0] lhs_value,
    output reg [23:0] box_x0,box_x1,
    output reg [26:0] box_y0,box_y1
);
localparam IDLE=0,P_REQ=1,P_USE=2,F_LEFT=3,F_UP=4,F_JOIN=5,P_SAVE=6,
           C_LABEL=7,N_INIT=8,N_ADDR=9,N_REQ=10,N_USE=11,N_DONE=12,
           SEL_INIT=13,SEL=14,PUB=15,FETCH=16,
           BB_A_REQ=17,BB_A_USE=18,BB_B_REQ=19,BB_STORE=20,
           C_BOX_REQ=21,C_BOX_USE=22,FETCH_USE=23;
reg [4:0] state;
reg [15:0] mem_addr;
wire map_q;
simple_dual_port_ram #(.DATA_WIDTH(1),.ADDR_WIDTH(16),.OUTPUT_REG("FALSE")) u_map (
    .wdata(map_wbit),.waddr(map_waddr),.we(map_we),.wclk(clk),
    .raddr(mem_addr),.re(1'b1),.rclk(clk),.rdata(map_q));
reg [7:0] px;
reg [8:0] py;
reg [5:0] left_label,current_label,root_a,root_b,up_left,old_up;
reg [5:0] neighbors[0:2];
reg [1:0] neighbor_index;
wire [5:0] up_q,up_right_q;
simple_dual_port_ram #(.DATA_WIDTH(6),.ADDR_WIDTH(8),.OUTPUT_REG("FALSE")) u_labels (
    .wdata(current_label),.waddr(px),.we(state==P_SAVE),.wclk(clk),
    .raddr(px),.re(1'b1),.rclk(clk),.rdata(up_q));
simple_dual_port_ram #(.DATA_WIDTH(6),.ADDR_WIDTH(8),.OUTPUT_REG("FALSE")) u_labels_right (
    .wdata(current_label),.waddr(px),.we(state==P_SAVE),.wclk(clk),
    .raddr(px+8'd1),.re(1'b1),.rclk(clk),.rdata(up_right_q));
// Parent/bounds are initialized when labels are allocated. Old entries are
// unreachable after next_label resets, avoiding a large reset fanout.
reg [5:0] parent [0:NL-1];
reg [6:0] next_label,label_index;
reg overflow;
wire [5:0] master=(root_a==0) ? root_b : ((root_b==0 || root_a<root_b) ? root_a : root_b);
wire [5:0] slave=(master==root_a) ? root_b : root_a;
reg [5:0] merge_master,merge_slave,bb_ra;
reg [33:0] bb_a;
wire [33:0] bb_q;
wire [7:0] merged_x0=(merge_slave!=0 && bb_q[7:0]<bb_a[7:0]) ? bb_q[7:0] : bb_a[7:0];
wire [7:0] merged_x1=(merge_slave!=0 && bb_q[15:8]>bb_a[15:8]) ? bb_q[15:8] : bb_a[15:8];
wire [8:0] merged_y0=(merge_slave!=0 && bb_q[24:16]<bb_a[24:16]) ? bb_q[24:16] : bb_a[24:16];
wire [8:0] merged_y1=(merge_slave!=0 && bb_q[33:25]>bb_a[33:25]) ? bb_q[33:25] : bb_a[33:25];
wire [7:0] store_x0=px<merged_x0 ? px : merged_x0;
wire [7:0] store_x1=px>merged_x1 ? px : merged_x1;
wire [8:0] store_y0=py<merged_y0 ? py : merged_y0;
wire [8:0] store_y1=py>merged_y1 ? py : merged_y1;
wire allocating=(state==F_JOIN && master==0 && neighbor_index==2 && next_label<NL);
wire bb_we=allocating || state==BB_STORE;
wire [5:0] bb_wa=allocating ? next_label[5:0] : merge_master;
wire [33:0] bb_wdata=allocating ? {py,py,px,px} : {store_y1,store_y0,store_x1,store_x0};
simple_dual_port_ram #(.DATA_WIDTH(34),.ADDR_WIDTH(6),.OUTPUT_REG("FALSE")) u_bounds (
    .wdata(bb_wdata),.waddr(bb_wa),.we(bb_we),.wclk(clk),
    .raddr(bb_ra),.re(1'b1),.rclk(clk),.rdata(bb_q));

// Pixel-major packing: all four template bits at one normalized coordinate.
// 2048 x 4 fits one 10-Kbit RAM instead of wide, shallow row ROMs.
reg [3:0] templates [0:2047];
reg [3:0] template_q;
initial $readmemh(TEMPLATE_FILE,templates);
reg [5:0] ny;
reg [4:0] nx;
always @(posedge clk) template_q<=templates[{ny,nx}];
reg [7:0] x0,x1;
reg [8:0] y0,y1,cw;
reg [9:0] ch;
reg [14:0] xnum;
reg [16:0] ynum;
wire [8:0] sample_x={1'b0,x0}+xnum[14:6];
wire [9:0] sample_y={1'b0,y0}+ynum[16:7];
reg [11:0] score7,score_plus,score2,score5;
reg [3:0] best_lhs [0:2];
reg [3:0] selected_lhs;
reg [11:0] best_score [0:8];
reg [5:0] best_id [0:8];
reg [1:0] i7,ip,i2;
reg [13:0] total_best;
reg [5:0] selected [0:2];
wire [5:0] id7=best_id[i7],idp=best_id[3+ip],id2=best_id[6+i2];
wire [13:0] total={2'd0,best_score[i7]}+{2'd0,best_score[3+ip]}+{2'd0,best_score[6+i2]};
reg [1:0] fetch_index;
reg [23:0] next_x0,next_x1;
reg [26:0] next_y0,next_y1;
assign busy=(state!=IDLE);
integer j;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=IDLE;mem_addr<=0;px<=0;py<=0;left_label<=0;current_label<=0;root_a<=0;root_b<=0;
        up_left<=0;old_up<=0;neighbor_index<=0;merge_master<=0;merge_slave<=0;bb_ra<=0;bb_a<=0;
        next_label<=1;label_index<=1;overflow<=0;
        done<=0;found<=0;result<=0;lhs_value<=0;selected_lhs<=0;box_x0<=0;box_x1<=0;box_y0<=0;box_y1<=0;
        x0<=0;x1<=0;y0<=0;y1<=0;cw<=0;ch<=0;nx<=0;ny<=0;xnum<=0;ynum<=0;
        score7<=0;score_plus<=0;score2<=0;score5<=0;i7<=0;ip<=0;i2<=0;total_best<=14'h3fff;
        fetch_index<=0;next_x0<=0;next_x1<=0;next_y0<=0;next_y1<=0;
        for(j=0;j<9;j=j+1) begin best_score[j]<=4095;best_id[j]<=0;end
        for(j=0;j<3;j=j+1) selected[j]<=0;
        for(j=0;j<3;j=j+1) best_lhs[j]<=0;
        for(j=0;j<3;j=j+1) neighbors[j]<=0;
    end else begin
        done<=0;
        case(state)
            IDLE: begin end
            P_REQ:state<=P_USE;
            P_USE:begin
                old_up<=up_q;neighbor_index<=0;
                neighbors[0]<=(py==0 || px==0) ? 6'd0 : up_left;
                neighbors[1]<=(py==0) ? 6'd0 : up_q;
                neighbors[2]<=(py==0 || px==MAP_W-1) ? 6'd0 : up_right_q;
                if(!map_q) begin current_label<=0;state<=P_SAVE;end
                else begin root_a<=left_label;root_b<=(py==0 || px==0) ? 6'd0 : up_left;state<=F_LEFT;end
            end
            F_LEFT:begin
                if(root_a==0 || parent[root_a]==root_a) state<=F_UP;
                else root_a<=parent[root_a];
            end
            F_UP:begin
                if(root_b==0 || parent[root_b]==root_b) state<=F_JOIN;
                else root_b<=parent[root_b];
            end
            F_JOIN:begin
                if(master==0) begin
                    if(neighbor_index!=2) begin
                        root_a<=0;root_b<=neighbors[neighbor_index+1'b1];neighbor_index<=neighbor_index+1'b1;state<=F_LEFT;
                    end else begin
                        if(next_label<NL) begin
                            current_label<=next_label[5:0];parent[next_label[5:0]]<=next_label[5:0];
                            next_label<=next_label+1'b1;
                        end else begin current_label<=0;overflow<=1;end
                        state<=P_SAVE;
                    end
                end else begin
                    merge_master<=master;merge_slave<=slave;bb_ra<=master;state<=BB_A_REQ;
                end
            end
            BB_A_REQ:state<=BB_A_USE;
            BB_A_USE:begin bb_a<=bb_q;bb_ra<=merge_slave;state<=BB_B_REQ;end
            BB_B_REQ:state<=BB_STORE;
            BB_STORE:begin
                if(merge_slave!=0 && merge_slave!=merge_master) parent[merge_slave]<=merge_master;
                if(neighbor_index!=2) begin
                    root_a<=merge_master;root_b<=neighbors[neighbor_index+1'b1];neighbor_index<=neighbor_index+1'b1;state<=F_LEFT;
                end else begin current_label<=merge_master;state<=P_SAVE;end
            end
            P_SAVE:begin
                if(px==MAP_W-1) begin px<=0;py<=py+1'b1;left_label<=0;up_left<=0;end
                else begin px<=px+1'b1;left_label<=current_label;up_left<=old_up;end
                if(mem_addr==MAP_W*MAP_H-1) begin label_index<=1;state<=C_LABEL;end
                else begin mem_addr<=mem_addr+1'b1;state<=P_REQ;end
            end
            C_LABEL:begin
                if(label_index>=next_label) state<=SEL_INIT;
                else if(parent[label_index[5:0]]==label_index[5:0]) begin
                    bb_ra<=label_index[5:0];state<=C_BOX_REQ;
                end else label_index<=label_index+1'b1;
            end
            C_BOX_REQ:state<=C_BOX_USE;
            C_BOX_USE:begin
                x0<=bb_q[7:0];x1<=bb_q[15:8];y0<=bb_q[24:16];y1<=bb_q[33:25];
                cw<={1'b0,bb_q[15:8]}-{1'b0,bb_q[7:0]}+9'd1;
                ch<={1'b0,bb_q[33:25]}-{1'b0,bb_q[24:16]}+10'd1;state<=N_INIT;
            end
            N_INIT:begin
                nx<=0;ny<=0;xnum<={6'd0,cw};ynum<={7'd0,ch};
                score7<=0;score_plus<=0;score2<=0;score5<=0;state<=N_ADDR;
            end
            N_ADDR:begin mem_addr<=sample_y*MAP_W+sample_x;state<=N_REQ;end
            N_REQ:state<=N_USE;
            N_USE:begin
                score7<=score7+{11'd0,(map_q^template_q[0])};
                score_plus<=score_plus+{11'd0,(map_q^template_q[1])};
                score2<=score2+{11'd0,(map_q^template_q[2])};
                score5<=score5+{11'd0,(map_q^template_q[3])};
                if(nx==31) begin
                    nx<=0;xnum<={6'd0,cw};
                    if(ny==63) state<=N_DONE;
                    else begin ny<=ny+1'b1;ynum<=ynum+({7'd0,ch}<<1);state<=N_ADDR;end
                end else begin nx<=nx+1'b1;xnum<=xnum+({6'd0,cw}<<1);state<=N_ADDR;end
            end
            N_DONE:begin : rank_component
                reg [11:0] sc;
                reg [3:0] value;
                integer g,b;
                for(g=0;g<3;g=g+1) begin
                    value=(score5<score7) ? 4'd5 : 4'd7;
                    sc=(g==0) ? ((score5<score7) ? score5 : score7) : ((g==1) ? score_plus : score2);b=3*g;
                    if(sc<best_score[b]) begin
                        best_score[b+2]<=best_score[b+1];best_id[b+2]<=best_id[b+1];
                        best_score[b+1]<=best_score[b];best_id[b+1]<=best_id[b];
                        best_score[b]<=sc;best_id[b]<=label_index[5:0];
                        if(g==0) begin best_lhs[2]<=best_lhs[1];best_lhs[1]<=best_lhs[0];best_lhs[0]<=value;end
                    end else if(sc<best_score[b+1]) begin
                        best_score[b+2]<=best_score[b+1];best_id[b+2]<=best_id[b+1];
                        best_score[b+1]<=sc;best_id[b+1]<=label_index[5:0];
                        if(g==0) begin best_lhs[2]<=best_lhs[1];best_lhs[1]<=value;end
                    end else if(sc<best_score[b+2]) begin
                        best_score[b+2]<=sc;best_id[b+2]<=label_index[5:0];if(g==0) best_lhs[2]<=value;
                    end
                end
                label_index<=label_index+1'b1;state<=C_LABEL;
            end
            SEL_INIT:begin i7<=0;ip<=0;i2<=0;total_best<=14'h3fff;state<=SEL;end
            SEL:begin
                if(id7!=0 && idp!=0 && id2!=0 && id7!=idp && id7!=id2 && idp!=id2 && total<total_best) begin
                    total_best<=total;selected[0]<=id7;selected[1]<=idp;selected[2]<=id2;
                    selected_lhs<=best_lhs[i7];
                end
                if(i2!=2) i2<=i2+1'b1;
                else begin
                    i2<=0;
                    if(ip!=2) ip<=ip+1'b1;
                    else begin ip<=0;if(i7!=2) i7<=i7+1'b1;else state<=PUB;end
                end
            end
            PUB:begin
                if(total_best==14'h3fff) begin found<=0;result<=0;lhs_value<=0;done<=1;state<=IDLE;end
                else begin fetch_index<=0;bb_ra<=selected[0];state<=FETCH;end
            end
            FETCH:state<=FETCH_USE;
            FETCH_USE:begin
                next_x0[8*fetch_index+:8]<=bb_q[7:0];next_x1[8*fetch_index+:8]<=bb_q[15:8];
                next_y0[9*fetch_index+:9]<=bb_q[24:16];next_y1[9*fetch_index+:9]<=bb_q[33:25];
                if(fetch_index==2) begin
                    box_x0<={bb_q[7:0],next_x0[15:0]};box_x1<={bb_q[15:8],next_x1[15:0]};
                    box_y0<={bb_q[24:16],next_y0[17:0]};box_y1<={bb_q[33:25],next_y1[17:0]};
                    found<=1;lhs_value<=selected_lhs;
                    result<={1'b0,selected_lhs}+5'd2;done<=1;state<=IDLE;
                end else begin fetch_index<=fetch_index+1'b1;bb_ra<=selected[fetch_index+1'b1];state<=FETCH;end
            end
            default:state<=IDLE;
        endcase
        if(!enable || restart) begin state<=IDLE;done<=0;found<=0;result<=0;lhs_value<=0;end
        else if(go) begin
            // Keep the last completed result during analysis, preventing flicker.
            state<=P_REQ;mem_addr<=0;px<=0;py<=0;left_label<=0;up_left<=0;
            next_label<=1;label_index<=1;overflow<=0;
            for(j=0;j<9;j=j+1) begin best_score[j]<=4095;best_id[j]<=0;end
        end
    end
end
endmodule
