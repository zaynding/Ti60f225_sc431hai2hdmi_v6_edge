`timescale 1ns/1ps
// Continuous live analysis; one bitmap is shared with the matcher.
// The display never freezes. Only complete frames are submitted for matching.
module digit_capture_2px #(
    parameter integer PAIR_COUNT=960, LINE_COUNT=1080,
    parameter integer CROP_X_PAIR=240, CROP_PAIRS=480,
    parameter integer SETTLE_FRAMES=0
)(
    input wire clk, rst_n, enable, start, ready,
    input wire in_valid, in_vs,
    input wire [15:0] in_gray2,
    output reg map_we,
    output reg [15:0] map_addr,
    output reg map_bit,
    output reg done,
    output wire busy,
    output reg [7:0] ink_threshold
);
localparam integer MW=CROP_PAIRS/2;
localparam S_IDLE=0, S_CAPTURE=2;
reg [1:0] state;
reg vs_d;
reg [9:0] xp;
reg [10:0] yp;
reg [15:0] wr_addr;
reg [8:0] pair_sum;
reg [7:0] frame_min, frame_max;
wire fs=in_vs && !vs_d;
wire inside_crop=(xp>=CROP_X_PAIR && xp<CROP_X_PAIR+CROP_PAIRS);
wire [9:0] xc=xp-CROP_X_PAIR;
wire [7:0] col=xc[8:1];
wire [8:0] gsum={1'b0,in_gray2[7:0]}+{1'b0,in_gray2[15:8]};
wire [9:0] four_sum={1'b0,pair_sum}+{1'b0,gsum};
wire [11:0] acc_q;
wire cell_end=in_valid && inside_crop && xc[0];
wire [11:0] block_sum=(yp[1:0]==0 ? 12'd0 : acc_q)+{2'b0,four_sum};
wire [7:0] average=block_sum[11:4];
wire [8:0] levels={1'b0,frame_min}+{1'b0,frame_max};
simple_dual_port_ram #(.DATA_WIDTH(12),.ADDR_WIDTH(8),.OUTPUT_REG("FALSE")) u_acc (
    .wdata(block_sum),.waddr(col),.we(cell_end),.wclk(clk),
    .raddr(col),.re(1'b1),.rclk(clk),.rdata(acc_q));
assign busy=(state!=S_IDLE);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state<=S_IDLE; vs_d<=0; xp<=0; yp<=0; wr_addr<=0;
        pair_sum<=0; frame_min<=255; frame_max<=0;
        map_we<=0; map_addr<=0; map_bit<=0; done<=0; ink_threshold<=128;
    end else begin
        vs_d<=in_vs; map_we<=0; done<=0;
        if (fs) begin
            xp<=0; yp<=0; frame_min<=255; frame_max<=0;
            // Discard incomplete data and start only if the shared map is free.
            if (enable && ready && !done) begin
                state<=S_CAPTURE; wr_addr<=0; ink_threshold<=levels[8:1];
            end else state<=S_IDLE;
        end else if (in_valid) begin
            if (xp==PAIR_COUNT-1) begin xp<=0; yp<=yp+1'b1; end
            else xp<=xp+1'b1;
            if (inside_crop) begin
                if (!xc[0]) pair_sum<=gsum;
                else if (yp[1:0]==3) begin
                    if (average<frame_min) frame_min<=average;
                    if (average>frame_max) frame_max<=average;
                    if (state==S_CAPTURE) begin
                        map_we<=1; map_addr<=wr_addr;
                        map_bit<=(average<ink_threshold);
                        wr_addr<=wr_addr+1'b1;
                        if (wr_addr==MW*(LINE_COUNT/4)-1) begin state<=S_IDLE; done<=1; end
                    end
                end
            end
        end
        if (!enable) begin state<=S_IDLE; map_we<=0; done<=0; end
        else if (start) begin state<=S_IDLE; map_we<=0; done<=0; end
    end
end
endmodule
