`timescale 1ns/1ps

module tb_mode_overlay_2px;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_valid = 1'b0;
reg in_hs = 1'b0;
reg in_vs = 1'b0;
reg [47:0] in_rgb2 = 48'h123456_123456;
reg [2:0] view_mode = 3'd0;

wire out_valid;
wire out_hs;
wire out_vs;
wire [47:0] out_rgb2;

integer white_count = 0;
integer errors = 0;

always #5 clk = ~clk;

mode_overlay_2px #(
    .PAIR_COUNT (64),
    .LINE_COUNT (64),
    .X0         (0),
    .Y0         (0),
    .BOX_W      (89),
    .BOX_H      (55)
) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_hs     (in_hs),
    .in_vs     (in_vs),
    .in_rgb2   (in_rgb2),
    .view_mode (view_mode),
    .out_valid (out_valid),
    .out_hs    (out_hs),
    .out_vs    (out_vs),
    .out_rgb2  (out_rgb2)
);

// Count white text pixels over the golden-ratio OSD box.
always @(posedge clk) begin
    if (out_valid) begin
        if (out_rgb2[23:0] == 24'hFFFFFF)
            white_count = white_count + 1;
        if (out_rgb2[47:24] == 24'hFFFFFF)
            white_count = white_count + 1;
    end
end

task drive_frame;
    input [2:0] mode;
    integer line;
begin
    view_mode = mode;
    white_count = 0;

    @(negedge clk);
    in_vs = 1'b1;
    @(negedge clk);
    in_vs = 1'b0;

    repeat (2) @(posedge clk);
    in_hs = 1'b1;
    @(negedge clk);
    in_hs = 1'b0;

    for (line = 0; line < 55; line = line + 1) begin
        repeat (64) begin
            @(negedge clk);
            in_valid = 1'b1;
        end
        @(negedge clk);
        in_valid = 1'b0;
    end

    repeat (4) @(posedge clk);
end
endtask

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    drive_frame(3'd0);
    if (white_count != 275) begin
        $display("ERROR: L white pixel count expected 275, got %0d", white_count);
        errors = errors + 1;
    end

    drive_frame(3'd1);
    if (white_count != 250) begin
        $display("ERROR: digit 1 white pixel count expected 250, got %0d", white_count);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("PASS: mode_overlay_2px test passed");
    else
        $display("FAIL: %0d errors", errors);

    $finish;
end

endmodule
