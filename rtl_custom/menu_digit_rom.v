`timescale 1ns/1ps
// two 16x32 digit ROMs (tens / units), addr = {digit[3:0], row[4:0]} (digit 10 = blank); 1-clock read latency
module menu_digit_rom (
    input  wire        clk,
    input  wire [8:0]  addr_t, addr_u,
    output wire [15:0] bits_t, bits_u
);
simple_dual_port_ram #(.DATA_WIDTH(16), .ADDR_WIDTH(9), .OUTPUT_REG("FALSE"), .RAM_INIT_FILE("menu_digit16.mem")) u_t (
    .wdata(16'd0), .waddr(9'd0), .we(1'b0), .wclk(clk), .raddr(addr_t), .re(1'b1), .rclk(clk), .rdata(bits_t));
simple_dual_port_ram #(.DATA_WIDTH(16), .ADDR_WIDTH(9), .OUTPUT_REG("FALSE"), .RAM_INIT_FILE("menu_digit16.mem")) u_u (
    .wdata(16'd0), .waddr(9'd0), .we(1'b0), .wclk(clk), .raddr(addr_u), .re(1'b1), .rclk(clk), .rdata(bits_u));
endmodule
