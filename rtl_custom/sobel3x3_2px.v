`timescale 1ns/1ps

// 单个3x3窗口的Sobel计算
module sobel3x3_lane (
    input  wire [71:0] win,
    output wire [7:0]  mag,
    output wire [11:0] magnitude,
    output wire [1:0] direction
);

    // 窗口排列：
    // { p00, p01, p02,
    //   p10, p11, p12,
    //   p20, p21, p22 }
    wire [7:0] p00 = win[71:64];
    wire [7:0] p01 = win[63:56];
    wire [7:0] p02 = win[55:48];

    wire [7:0] p10 = win[47:40];
    wire [7:0] p11 = win[39:32];
    wire [7:0] p12 = win[31:24];

    wire [7:0] p20 = win[23:16];
    wire [7:0] p21 = win[15:8];
    wire [7:0] p22 = win[7:0];

    // Gx = -p00 + p02
    //      -2*p10 + 2*p12
    //      -p20 + p22
    wire [10:0] gx =
          {3'b000, p02}
        + {2'b00, p12, 1'b0}
        + {3'b000, p22}
        - {3'b000, p00}
        - {2'b00, p10, 1'b0}
        - {3'b000, p20};

    // Gy = -p00 - 2*p01 - p02
    //      +p20 + 2*p21 + p22
    wire [10:0] gy =
          {3'b000, p20}
        + {2'b00, p21, 1'b0}
        + {3'b000, p22}
        - {3'b000, p00}
        - {2'b00, p01, 1'b0}
        - {3'b000, p02};

    // 取绝对值
    wire [10:0] abs_gx = gx[10] ? (11'd0 - gx) : gx;
    wire [10:0] abs_gy = gy[10] ? (11'd0 - gy) : gy;

    // 梯度幅值近似：|Gx| + |Gy|
    wire [11:0] mag_sum = {1'b0, abs_gx} + {1'b0, abs_gy};

    // 限制到8位，最大255
    assign mag = (mag_sum > 12'd255) ? 8'hFF : mag_sum[7:0];
    assign magnitude = mag_sum;

    wire [12:0] ax2 = {1'b0, abs_gx, 1'b0};
    wire [12:0] ay2 = {1'b0, abs_gy, 1'b0};
    wire [12:0] ax5 = {abs_gx, 2'b0} + {2'b0, abs_gx};
    wire [12:0] ay5 = {abs_gy, 2'b0} + {2'b0, abs_gy};
    // 0: horizontal, 1: down-right, 2: vertical, 3: down-left.
    assign direction = (ay5 < ax2) ? 2'd0 :
                       (ax5 < ay2) ? 2'd2 :
                       (gx[10] == gy[10]) ? 2'd1 : 2'd3;

endmodule


// 同时处理两个像素
module sobel3x3_2px (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,

    input  wire [71:0] win0,
    input  wire [71:0] win1,

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [7:0]  mag0,
    output reg  [7:0]  mag1,
    output reg  [11:0] magnitude0,
    output reg  [11:0] magnitude1,
    output reg  [1:0] direction0,
    output reg  [1:0] direction1
);

    wire [7:0] mag0_comb;
    wire [7:0] mag1_comb;
    wire [11:0] magnitude0_comb, magnitude1_comb;
    wire [1:0] direction0_comb, direction1_comb;

    sobel3x3_lane u_sobel_lane0 (
        .win(win0),
        .mag(mag0_comb), .magnitude(magnitude0_comb), .direction(direction0_comb)
    );

    sobel3x3_lane u_sobel_lane1 (
        .win(win1),
        .mag(mag1_comb), .magnitude(magnitude1_comb), .direction(direction1_comb)
    );

    // valid/hs/vs和幅值一起延迟一拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            mag0      <= 8'd0;
            mag1      <= 8'd0;
            magnitude0 <= 0;
            magnitude1 <= 0;
            direction0 <= 0;
            direction1 <= 0;
        end
        else begin
            out_valid <= in_valid;
            out_hs    <= in_hs;
            out_vs    <= in_vs;

            mag0 <= mag0_comb;
            mag1 <= mag1_comb;
            magnitude0 <= magnitude0_comb;
            magnitude1 <= magnitude1_comb;
            direction0 <= direction0_comb;
            direction1 <= direction1_comb;
        end
    end

endmodule
