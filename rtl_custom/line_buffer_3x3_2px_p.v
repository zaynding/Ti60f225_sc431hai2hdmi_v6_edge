`timescale 1ns/1ps

module line_buffer_3x3_2px_p #(
    parameter PAIR_COUNT  = 960,
    parameter MAX_LINES   = 1080,
    parameter LINE_CYCLES = 1100,
    parameter PIXEL_WIDTH = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire [2*PIXEL_WIDTH-1:0] in_gray2,
    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [9*PIXEL_WIDTH-1:0] win0,
    output reg  [9*PIXEL_WIDTH-1:0] win1
);

localparam DATA_WIDTH = 2*PIXEL_WIDTH;
localparam ADDR_WIDTH = $clog2(LINE_CYCLES);
reg [ADDR_WIDTH-1:0] addr, addr_d;
reg filled, ready;
wire [DATA_WIDTH+2:0] row1_q;
wire [2*PIXEL_WIDTH-1:0] row2_q;
reg [DATA_WIDTH+2:0] center;
reg [2*PIXEL_WIDTH-1:0] bottom_d1, bottom_d2;

// 包括消隐在内延迟一整行，同步信号和像素使用相同的地址。
simple_dual_port_ram #(
    .DATA_WIDTH(DATA_WIDTH+3), .ADDR_WIDTH(ADDR_WIDTH), .OUTPUT_REG("FALSE")
) u_row1 (
    .wdata({in_valid, in_hs, in_vs, in_gray2}),
    .waddr(addr), .raddr(addr), .we(1'b1), .re(1'b1),
    .wclk(clk), .rclk(clk), .rdata(row1_q)
);

simple_dual_port_ram #(
    .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .OUTPUT_REG("FALSE")
) u_row2 (
    .wdata(row1_q[DATA_WIDTH-1:0]),
    .waddr(addr_d), .raddr(addr_d), .we(1'b1), .re(1'b1),
    .wclk(clk), .rclk(clk), .rdata(row2_q)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        addr   <= 0;
        addr_d <= 0;
        filled <= 0;
        ready  <= 0;
        center <= 0;
        bottom_d1 <= 0;
        bottom_d2 <= 0;
    end else begin
        addr <= (addr == LINE_CYCLES - 1) ? 0 : addr + 1'b1;
        addr_d <= addr;
        if (addr == LINE_CYCLES - 1)
            filled <= 1;
        ready <= filled;
        center <= ready ? row1_q : {(DATA_WIDTH+3){1'b0}};
        bottom_d1 <= in_gray2;
        bottom_d2 <= bottom_d1;
    end
end

reg [9:0] x;
reg [10:0] y;
wire [2*PIXEL_WIDTH-1:0] top = (y == 0) ? center[2*PIXEL_WIDTH-1:0] : row2_q;
wire [2*PIXEL_WIDTH-1:0] bottom = (y == MAX_LINES - 1) ? center[2*PIXEL_WIDTH-1:0] : bottom_d2;
reg [2*PIXEL_WIDTH-1:0] top_d, mid_d, bot_d;
reg [PIXEL_WIDTH-1:0] left_top, left_mid, left_bot;
reg first_pair, last_pair;
reg [2:0] control_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x <= 0;
        y <= 0;
        top_d <= 0;
        mid_d <= 0;
        bot_d <= 0;
        left_top <= 0;
        left_mid <= 0;
        left_bot <= 0;
        first_pair <= 0;
        last_pair <= 0;
        control_d <= 0;
        out_valid <= 0;
        out_hs <= 0;
        out_vs <= 0;
        win0 <= 0;
        win1 <= 0;
    end else begin
        if (center[DATA_WIDTH]) begin
            x <= 0;
            y <= 0;
        end else if (center[DATA_WIDTH+2]) begin
            if (x == PAIR_COUNT - 1) begin
                x <= 0;
                y <= (y == MAX_LINES - 1) ? 0 : y + 1'b1;
            end else
                x <= x + 1'b1;
        end

        top_d <= top;
        mid_d <= center[2*PIXEL_WIDTH-1:0];
        bot_d <= bottom;
        left_top <= top_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH];
        left_mid <= mid_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH];
        left_bot <= bot_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH];
        first_pair <= (x == 0);
        last_pair <= (x == PAIR_COUNT - 1);
        control_d <= center[DATA_WIDTH+2:DATA_WIDTH];

        out_valid <= control_d[2];
        out_hs <= control_d[1];
        out_vs <= control_d[0];
        // 第一列复制左边界，最后一列复制右边界。
        win0 <= {
            first_pair ? top_d[PIXEL_WIDTH-1:0] : left_top, top_d[PIXEL_WIDTH-1:0], top_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH],
            first_pair ? mid_d[PIXEL_WIDTH-1:0] : left_mid, mid_d[PIXEL_WIDTH-1:0], mid_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH],
            first_pair ? bot_d[PIXEL_WIDTH-1:0] : left_bot, bot_d[PIXEL_WIDTH-1:0], bot_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH]
        };
        win1 <= {
            top_d[PIXEL_WIDTH-1:0], top_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH], last_pair ? top_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH] : top[PIXEL_WIDTH-1:0],
            mid_d[PIXEL_WIDTH-1:0], mid_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH], last_pair ? mid_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH] : center[PIXEL_WIDTH-1:0],
            bot_d[PIXEL_WIDTH-1:0], bot_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH], last_pair ? bot_d[2*PIXEL_WIDTH-1:PIXEL_WIDTH] : bottom[PIXEL_WIDTH-1:0]
        };
    end
end

endmodule
