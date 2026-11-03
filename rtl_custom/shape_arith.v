`timescale 1ns/1ps
// Small sequential arithmetic helpers for the shape classifier (area-cheap, many cycles).

// 32x32 -> 64 unsigned shift-add multiplier, 32 clocks.
module seq_mul (
    input  wire        clk, rst_n, start,
    input  wire [31:0] a, b,
    output reg  [63:0] p,
    output reg         done
);
reg [63:0] acc, ma;
reg [31:0] mb;
reg [5:0]  cnt;
reg        busy;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin acc<=0; ma<=0; mb<=0; cnt<=0; busy<=0; done<=0; p<=0; end
    else begin
        done <= 1'b0;
        if (start && !busy) begin
            acc<=64'd0; ma<={32'd0,a}; mb<=b; cnt<=6'd0; busy<=1'b1;
        end else if (busy) begin
            if (mb[0]) acc <= acc + ma;
            ma <= ma << 1; mb <= mb >> 1; cnt <= cnt + 1'b1;
            if (cnt == 6'd31) begin busy<=1'b0; done<=1'b1; p <= mb[0] ? acc + ma : acc; end
        end
    end
end
endmodule

// 64 / 32 -> 64 unsigned restoring divider, 64 clocks.  Quotient truncates like Python //.
module seq_div (
    input  wire        clk, rst_n, start,
    input  wire [63:0] num,
    input  wire [31:0] den,
    output reg  [63:0] quot,
    output reg         done
);
reg [63:0] q;
reg [32:0] rem;
reg [31:0] d;
reg [6:0]  cnt;
reg        busy;
wire [32:0] shifted = {rem[31:0], q[63]};
wire        ge      = (shifted >= {1'b0, d});
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin q<=0; rem<=0; d<=0; cnt<=0; busy<=0; done<=0; quot<=0; end
    else begin
        done <= 1'b0;
        if (start && !busy) begin
            q<=num; rem<=33'd0; d<=den; cnt<=7'd0; busy<=1'b1;
        end else if (busy) begin
            rem <= ge ? shifted - {1'b0, d} : shifted;
            q   <= {q[62:0], ge};
            cnt <= cnt + 1'b1;
            if (cnt == 7'd63) begin busy<=1'b0; done<=1'b1; quot <= {q[62:0], ge}; end
        end
    end
end
endmodule

// 64 -> 32 unsigned integer square root (floor), digit-by-digit, 32 clocks.
module seq_sqrt (
    input  wire        clk, rst_n, start,
    input  wire [63:0] x,
    output reg  [31:0] root,
    output reg         done
);
reg [63:0] num;
reg [33:0] rem;
reg [31:0] r;
reg [5:0]  cnt;
reg        busy;
wire [33:0] rem_n = {rem[31:0], num[63:62]};
wire [33:0] trial = {r, 2'b01};
wire        ge    = (rem_n >= trial);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin num<=0; rem<=0; r<=0; cnt<=0; busy<=0; done<=0; root<=0; end
    else begin
        done <= 1'b0;
        if (start && !busy) begin num<=x; rem<=34'd0; r<=32'd0; cnt<=6'd0; busy<=1'b1; end
        else if (busy) begin
            rem <= ge ? (rem_n - trial) : rem_n;
            r   <= {r[30:0], ge};
            num <= {num[61:0], 2'b00};
            cnt <= cnt + 1'b1;
            if (cnt == 6'd31) begin busy<=1'b0; done<=1'b1; root <= {r[30:0], ge}; end
        end
    end
end
endmodule
