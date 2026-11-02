`timescale 1ns/1ps

module rgb2gray_2px (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire [47:0] in_pixel2,

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [15:0] out_gray2
);

function [7:0] rgb_to_gray;
    input [7:0] r;
    input [7:0] g;
    input [7:0] b;
    reg   [15:0] sum;
    begin
        sum = r*8'd77 + g*8'd150 + b*8'd29;
        rgb_to_gray = sum[15:8];
    end
endfunction

wire [23:0] pixel0 = in_pixel2[23:0];
wire [23:0] pixel1 = in_pixel2[47:24];

wire [7:0] r0 = pixel0[7:0];
wire [7:0] g0 = pixel0[15:8];
wire [7:0] b0 = pixel0[23:16];

wire [7:0] r1 = pixel1[7:0];
wire [7:0] g1 = pixel1[15:8];
wire [7:0] b1 = pixel1[23:16];

wire [7:0] gray0 = rgb_to_gray(r0, g0, b0);
wire [7:0] gray1 = rgb_to_gray(r1, g1, b1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid <= 1'b0;
        out_hs    <= 1'b0;
        out_vs    <= 1'b0;
        out_gray2 <= 16'd0;
    end else begin
        out_valid <= in_valid;
        out_hs    <= in_hs;
        out_vs    <= in_vs;

        if (in_valid)
            out_gray2 <= {gray1, gray0};
        else
            out_gray2 <= 16'd0;
    end
end

endmodule