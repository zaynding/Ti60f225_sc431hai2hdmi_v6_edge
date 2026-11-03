`timescale 1ns/1ps
// Feeds a demo RAW mosaic (raster order, 1 byte/pixel, as written by tools/gen_demo_raw.py *.stream)
// through the real gain + debayer chain and dumps the RGB it produces, so the mosaic layout / white
// balance pre-compensation can be checked against the source photo.
module tb_debayer_demo;
parameter STREAM = "frame1.stream";
parameter OUTF   = "debayer_out.txt";
parameter LINES  = 1080;
localparam PAIRS = 960;

reg clk = 0;
reg rstn = 0;
always #5 clk = ~clk;

reg [7:0] mem [0:PAIRS*2*LINES-1];
reg vs = 0, hs = 0, de = 0;
reg [15:0] data = 0;

wire        o_vs, o_hs, o_de, o_valid;
wire [47:0] o_rgb2;

debayer_top_2to1 dut (
    .in_pclk(clk), .in_rstn(rstn),
    .raw_vs_i(vs), .raw_hs_i(hs), .raw_de_i(de), .raw_valid_i(de), .raw_datax4_i(data),
    .r_gain(16'd512), .g_gain(16'd256), .b_gain(16'd517),
    .rgb_vs_o(o_vs), .rgb_hs_o(o_hs), .rgb_de_o(o_de), .rgb_valid_o(o_valid),
    .rgb_bout(), .rgb_gout(), .rgb_rout(), .rgb_datax2_o(o_rgb2));

integer fd, fo, y, x, n;
integer rd;
initial begin
    fd = $fopen(STREAM, "rb");
    if (fd == 0) begin $display("cannot open %0s", STREAM); $finish; end
    rd = $fread(mem, fd);
    $fclose(fd);
    fo = $fopen(OUTF, "w");
    repeat (10) @(posedge clk);
    rstn = 1;
    repeat (10) @(posedge clk);
    // frame start: VS high then low
    vs = 1; repeat (20) @(posedge clk);
    vs = 0; repeat (40) @(posedge clk);
    for (y = 0; y < LINES + 2; y = y + 1) begin
        de = 1; hs = 1;
        for (x = 0; x < PAIRS; x = x + 1) begin
            n = (y < LINES ? y : LINES - 1) * PAIRS * 2 + x * 2;
            // {high=second (odd x) pixel, low=first (even x) pixel}
            data <= {mem[n + 1], mem[n]};
            @(posedge clk);
        end
        de = 0; hs = 0; data <= 0;
        repeat (80) @(posedge clk);
    end
    repeat (200) @(posedge clk);
    $fclose(fo);
    $display("done");
    $finish;
end

// dump every valid output pair: b_hi g_hi r_hi b_lo g_lo r_lo, one line per pair, '-' marks a new line
reg ov_d = 0;
always @(posedge clk) begin
    ov_d <= o_valid & o_de;
    if (o_valid & o_de) begin
        if (!ov_d) $fwrite(fo, "L\n");
        $fwrite(fo, "%012x\n", o_rgb2);
    end
end
endmodule
