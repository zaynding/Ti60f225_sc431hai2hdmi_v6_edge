`timescale 1ns/1ps
// 32x32 glyph ROM held in one block-RAM (initialised from menu_font32.mem in the project root).
// Glyph order: see sim/menu/gen_menu.py.  addr = {glyph[5:0], row[4:0]}; 1-clock read latency.
module menu_font_rom (
    input  wire        clk,
    input  wire [10:0] addr,
    output wire [31:0] bits
);
simple_dual_port_ram #(.DATA_WIDTH(32), .ADDR_WIDTH(11), .OUTPUT_REG("FALSE"), .RAM_INIT_FILE("menu_font32.mem")) u_rom (
    .wdata(32'd0), .waddr(11'd0), .we(1'b0), .wclk(clk), .raddr(addr), .re(1'b1), .rclk(clk), .rdata(bits));
endmodule
