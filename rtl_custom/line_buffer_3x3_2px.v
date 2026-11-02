`timescale 1ns/1ps

module line_buffer_3x3_2px #(
    parameter PAIR_COUNT = 960,
    parameter MAX_LINES  = 1080
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire [15:0] in_gray2,

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [71:0] win0,
    output reg  [71:0] win1
);

localparam X_WIDTH = 10;
localparam Y_WIDTH = 11;

// 三块显式简单双端口RAM
reg [X_WIDTH-1:0] wr_addr;
reg [Y_WIDTH-1:0] line_y;

reg [1:0] wr_bank;
reg [1:0] center_bank;
reg [1:0] top_bank;

wire [15:0] mem0_q;
wire [15:0] mem1_q;
wire [15:0] mem2_q;

simple_dual_port_ram #(
    .DATA_WIDTH (16),
    .ADDR_WIDTH (10),
    .OUTPUT_REG ("FALSE"),
    .RAM_INIT_FILE("")
) u_mem0 (
    .wdata(in_gray2),
    .waddr(wr_addr),
    .raddr(wr_addr),

    .we   (in_valid && (wr_bank == 2'd0)),
    .wclk (clk),

    .re   (1'b1),
    .rclk (clk),
    .rdata(mem0_q)
);

simple_dual_port_ram #(
    .DATA_WIDTH (16),
    .ADDR_WIDTH (10),
    .OUTPUT_REG ("FALSE"),
    .RAM_INIT_FILE("")
) u_mem1 (
    .wdata(in_gray2),
    .waddr(wr_addr),
    .raddr(wr_addr),

    .we   (in_valid && (wr_bank == 2'd1)),
    .wclk (clk),

    .re   (1'b1),
    .rclk (clk),
    .rdata(mem1_q)
);

simple_dual_port_ram #(
    .DATA_WIDTH (16),
    .ADDR_WIDTH (10),
    .OUTPUT_REG ("FALSE"),
    .RAM_INIT_FILE("")
) u_mem2 (
    .wdata(in_gray2),
    .waddr(wr_addr),
    .raddr(wr_addr),

    .we   (in_valid && (wr_bank == 2'd2)),
    .wclk (clk),

    .re   (1'b1),
    .rclk (clk),
    .rdata(mem2_q)
);

// 行缓存地址和Bank切换
reg [1:0] top_bank_d1;
reg [1:0] center_bank_d1;

// 当前地址q和下一地址q+1的历史行数据
reg [15:0] top_q1;
reg [15:0] center_q1;

// 当前底行和下一对底行数据
reg [15:0] in_d1;
reg [15:0] in_d2;

// 坐标和控制信号流水
reg [X_WIDTH-1:0] x_d1;
reg [X_WIDTH-1:0] x_d2;
reg [Y_WIDTH-1:0] y_d1;
reg [Y_WIDTH-1:0] y_d2;

reg v_d1;
reg v_d2;
reg hs_d1;
reg hs_d2;
reg vs_d1;
reg vs_d2;

reg in_vs_d;

// 上一对像素的高8位，作为左邻居
reg [7:0] prev_top_hi;
reg [7:0] prev_center_hi;
reg [7:0] prev_bottom_hi;

// 选择经过一级延迟的Bank
wire [15:0] top_q_sel =
    (top_bank_d1 == 2'd0) ? mem0_q :
    (top_bank_d1 == 2'd1) ? mem1_q : mem2_q;

wire [15:0] center_q_sel =
    (center_bank_d1 == 2'd0) ? mem0_q :
    (center_bank_d1 == 2'd1) ? mem1_q : mem2_q;

// 当前q对，以及下一q+1对
wire [15:0] top_pair_cur =
    (y_d2 <= 11'd1) ? center_q1 : top_q1;

wire [15:0] top_pair_next =
    (y_d2 <= 11'd1) ? center_q_sel : top_q_sel;

wire [15:0] center_pair_cur = center_q1;
wire [15:0] center_pair_next = center_q_sel;

wire [15:0] bottom_pair_cur = in_d2;
wire [15:0] bottom_pair_next = in_d1;

wire first_pair = (x_d2 == 0);
wire last_pair  = (x_d2 == PAIR_COUNT - 1);

wire [7:0] top_left =
    first_pair ? top_pair_cur[7:0] : prev_top_hi;

wire [7:0] center_left =
    first_pair ? center_pair_cur[7:0] : prev_center_hi;

wire [7:0] bottom_left =
    first_pair ? bottom_pair_cur[7:0] : prev_bottom_hi;

wire [7:0] top_right =
    last_pair ? top_pair_cur[15:8] : top_pair_next[7:0];

wire [7:0] center_right =
    last_pair ? center_pair_cur[15:8] : center_pair_next[7:0];

wire [7:0] bottom_right =
    last_pair ? bottom_pair_cur[15:8] : bottom_pair_next[7:0];

// VS上升沿检测
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        in_vs_d <= 1'b0;
    else
        in_vs_d <= in_vs;
end

// RAM输出经过一级寄存，同时保留当前历史行q
always @(posedge clk) begin
    top_q1    <= top_q_sel;
    center_q1 <= center_q_sel;
end

// 主控制流水
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_addr     <= 10'd0;
        line_y      <= 11'd0;

        wr_bank     <= 2'd0;
        center_bank <= 2'd1;
        top_bank    <= 2'd2;

        top_bank_d1    <= 2'd2;
        center_bank_d1 <= 2'd1;

        in_d1 <= 16'd0;
        in_d2 <= 16'd0;

        x_d1 <= 10'd0;
        x_d2 <= 10'd0;
        y_d1 <= 11'd0;
        y_d2 <= 11'd0;

        v_d1  <= 1'b0;
        v_d2  <= 1'b0;
        hs_d1 <= 1'b0;
        hs_d2 <= 1'b0;
        vs_d1 <= 1'b0;
        vs_d2 <= 1'b0;

        prev_top_hi    <= 8'd0;
        prev_center_hi <= 8'd0;
        prev_bottom_hi <= 8'd0;

        out_valid <= 1'b0;
        out_hs    <= 1'b0;
        out_vs    <= 1'b0;
        win0      <= 72'd0;
        win1      <= 72'd0;
    end
    else if (in_vs && !in_vs_d) begin
        wr_addr     <= 10'd0;
        line_y      <= 11'd0;

        wr_bank     <= 2'd0;
        center_bank <= 2'd1;
        top_bank    <= 2'd2;

        top_bank_d1    <= 2'd2;
        center_bank_d1 <= 2'd1;

        in_d1 <= 16'd0;
        in_d2 <= 16'd0;

        x_d1 <= 10'd0;
        x_d2 <= 10'd0;
        y_d1 <= 11'd0;
        y_d2 <= 11'd0;

        v_d1  <= 1'b0;
        v_d2  <= 1'b0;
        hs_d1 <= 1'b0;
        hs_d2 <= 1'b0;
        vs_d1 <= 1'b0;
        vs_d2 <= 1'b0;

        prev_top_hi    <= 8'd0;
        prev_center_hi <= 8'd0;
        prev_bottom_hi <= 8'd0;

        out_valid <= 1'b0;
        out_hs    <= 1'b0;
        out_vs    <= 1'b0;
        win0      <= 72'd0;
        win1      <= 72'd0;
    end
    else begin
        // 写入当前底行，由三个RAM实例完成实际写操作

        if (in_valid) begin
            if (wr_addr == PAIR_COUNT - 1) begin
                wr_addr <= 10'd0;

                if (line_y == MAX_LINES - 1)
                    line_y <= 11'd0;
                else
                    line_y <= line_y + 11'd1;

                top_bank    <= center_bank;
                center_bank <= wr_bank;
                wr_bank     <= top_bank;
            end
            else begin
                wr_addr <= wr_addr + 10'd1;
            end
        end

        // Bank选择延迟一拍，和RAM输出对齐
        top_bank_d1    <= top_bank;
        center_bank_d1 <= center_bank;

        // 底行像素和坐标流水
        in_d1 <= in_gray2;
        in_d2 <= in_d1;

        x_d1 <= wr_addr;
        x_d2 <= x_d1;

        y_d1 <= line_y;
        y_d2 <= y_d1;

        v_d1 <= in_valid;
        v_d2 <= v_d1;

        hs_d1 <= in_hs;
        hs_d2 <= hs_d1;

        vs_d1 <= in_vs;
        vs_d2 <= vs_d1;

        out_valid <= v_d2 && (y_d2 != 0);
        out_hs    <= hs_d2;
        out_vs    <= vs_d2;

        win0 <= {
            top_left,
            top_pair_cur[7:0],
            top_pair_cur[15:8],

            center_left,
            center_pair_cur[7:0],
            center_pair_cur[15:8],

            bottom_left,
            bottom_pair_cur[7:0],
            bottom_pair_cur[15:8]
        };

        win1 <= {
            top_pair_cur[7:0],
            top_pair_cur[15:8],
            top_right,

            center_pair_cur[7:0],
            center_pair_cur[15:8],
            center_right,

            bottom_pair_cur[7:0],
            bottom_pair_cur[15:8],
            bottom_right
        };

        if (v_d2 && (y_d2 != 0)) begin
            prev_top_hi    <= top_pair_cur[15:8];
            prev_center_hi <= center_pair_cur[15:8];
            prev_bottom_hi <= bottom_pair_cur[15:8];
        end
    end
end

endmodule