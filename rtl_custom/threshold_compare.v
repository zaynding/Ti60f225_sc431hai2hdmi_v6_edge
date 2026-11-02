`timescale 1ns/1ps

module threshold_compare #(
    parameter integer PAIR_COUNT = 960,
    parameter integer BLANK_PAIRS = 0
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       in_valid,
    input  wire       in_hs,
    input  wire       in_vs,

    input  wire [11:0] mag0,
    input  wire [11:0] mag1,
    input  wire [11:0] threshold,

    output reg        out_valid,
    output reg        out_hs,
    output reg        out_vs,
    output reg        edge0,
    output reg        edge1
);

    reg [9:0] x_cnt;
    reg [9:0] x_cnt_d1;
    reg       in_vs_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt    <= 10'd0;
            x_cnt_d1 <= 10'd0;
            in_vs_d  <= 1'b0;

            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            edge0     <= 1'b0;
            edge1     <= 1'b0;
        end
        else begin
            in_vs_d <= in_vs;

            if (in_vs && !in_vs_d) begin
                x_cnt    <= 10'd0;
                x_cnt_d1 <= 10'd0;
            end
            else begin
                if (in_valid) begin
                    if (x_cnt == PAIR_COUNT - 1)
                        x_cnt <= 10'd0;
                    else
                        x_cnt <= x_cnt + 10'd1;
                end

                x_cnt_d1 <= x_cnt;
            end

            out_valid <= in_valid;
            out_hs    <= in_hs;
            out_vs    <= in_vs;

            edge0 <= (mag0 > threshold) && (x_cnt_d1 >= BLANK_PAIRS);
            edge1 <= (mag1 > threshold) && (x_cnt_d1 >= BLANK_PAIRS);
        end
    end

endmodule
