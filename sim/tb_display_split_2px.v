`timescale 1ns/1ps

module tb_display_split_2px;

    localparam integer PAIR_COUNT  = 32;
    localparam integer LINE_COUNT  = 8;
    localparam integer CROP_X_PAIR = 4;
    localparam integer CROP_PAIRS  = 8;
    localparam integer BUF_LINES   = 4;

    reg         clk;
    reg         rst_n;

    reg         src_valid;
    reg         src_vs;
    reg  [47:0] src_rgb2;

    reg         in_valid;
    reg         in_hs;
    reg         in_vs;
    reg         edge0;
    reg         edge1;

    wire        out_valid;
    wire        out_hs;
    wire        out_vs;
    wire [47:0] out_rgb2;

    integer errors;
    integer out_x;
    integer out_y;
    integer i;
    integer j;

    display_split_2px #(
        .PAIR_COUNT  (PAIR_COUNT),
        .LINE_COUNT  (LINE_COUNT),
        .CROP_X_PAIR (CROP_X_PAIR),
        .CROP_PAIRS  (CROP_PAIRS),
        .BUF_LINES   (BUF_LINES)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .show_red  (1'b1),
        .show_color(1'b1),
        .show_edge (1'b1),
        .cmp_mode  (1'b0),
        .s_edge0   (1'b0),
        .s_edge1   (1'b0),
        .src_valid (src_valid),
        .src_vs    (src_vs),
        .src_rgb2  (src_rgb2),
        .in_valid  (in_valid),
        .in_hs     (in_hs),
        .in_vs     (in_vs),
        .edge0     (edge0),
        .edge1     (edge1),
        .out_valid (out_valid),
        .out_hs    (out_hs),
        .out_vs    (out_vs),
        .out_rgb2  (out_rgb2)
    );

    always #5 clk = ~clk;

    function [23:0] color_pixel;
        input integer row;
        input integer pair;
        begin
            color_pixel = {8'h10 + row[7:0], 8'h20 + pair[7:0], 8'h30 + row[7:0]};
        end
    endfunction

    function [47:0] color_pair;
        input integer row;
        input integer pair;
        begin
            color_pair = {color_pixel(row, pair + 1), color_pixel(row, pair)};
        end
    endfunction

    function expected_edge0;
        input integer row;
        input integer pair;
        begin
            expected_edge0 = ((pair == 4) || (pair == 12) ||
                              ((row == 2) && (pair >= 6) && (pair <= 9)));
        end
    endfunction

    function expected_edge1;
        input integer row;
        input integer pair;
        begin
            expected_edge1 = ((pair == 5) || (pair == 13) ||
                              ((row == 3) && (pair >= 14) && (pair <= 17)));
        end
    endfunction

    function [47:0] expected_left_pair;
        input integer row;
        input integer x;
        reg [23:0] px0;
        reg [23:0] px1;
        integer source_pair;
        begin
            source_pair = x + CROP_X_PAIR;
            px0 = color_pixel(row, source_pair + 1);
            px1 = color_pixel(row, source_pair);

            if ((row > 0) && expected_edge0(row - 1, source_pair))
                px1 = 24'hFF0000;
            if ((row > 0) && expected_edge1(row - 1, source_pair))
                px0 = 24'hFF0000;

            expected_left_pair = {px0, px1};
        end
    endfunction

    task send_color_row;
        input integer row;
        begin
            for (i = 0; i < PAIR_COUNT; i = i + 1) begin
                @(negedge clk);
                src_valid = 1'b1;
                src_rgb2  = color_pair(row, i);
            end
        end
    endtask

    task send_edge_row;
        input integer row;
        begin
            for (i = 0; i < PAIR_COUNT; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_hs    = (i == 0);
                edge0    = expected_edge0(row, i);
                edge1    = expected_edge1(row, i);
            end
        end
    endtask

    initial begin
        clk        = 1'b0;
        rst_n      = 1'b0;
        src_valid  = 1'b0;
        src_vs     = 1'b0;
        src_rgb2   = 48'd0;
        in_valid   = 1'b0;
        in_hs      = 1'b0;
        in_vs      = 1'b0;
        edge0      = 1'b0;
        edge1      = 1'b0;
        errors     = 0;
        out_x      = 0;
        out_y      = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Fill the four colour line-buffer slots before edge processing starts.
        @(negedge clk);
        src_vs = 1'b1;
        @(negedge clk);
        src_vs = 1'b0;
        for (j = 0; j < BUF_LINES; j = j + 1)
            send_color_row(j);
        @(negedge clk);
        src_valid = 1'b0;

        // Process four edge rows. The captured colour rows must match by row number.
        @(negedge clk);
        in_vs = 1'b1;
        @(negedge clk);
        in_vs = 1'b0;
        for (j = 0; j < BUF_LINES; j = j + 1)
            send_edge_row(j);
        @(negedge clk);
        in_valid = 1'b0;
        in_hs    = 1'b0;
        edge0    = 1'b0;
        edge1    = 1'b0;

        repeat (8) @(posedge clk);
        if (errors == 0)
            $display("PASS: display_split_2px test passed");
        else
            $display("FAIL: display_split_2px test had %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            #1;
            if (out_hs) begin
                out_x = 0;
                out_y = out_y + 1;
            end
            else begin
                out_x = out_x + 1;
            end

            if (out_x < CROP_PAIRS) begin
                if (out_rgb2 !== expected_left_pair(out_y, out_x)) begin
                    $display("ERROR left row=%0d x=%0d expected=%h got=%h",
                             out_y, out_x,
                             expected_left_pair(out_y, out_x), out_rgb2);
                    errors = errors + 1;
                end
            end
            else if (out_x < (2 * CROP_PAIRS)) begin
                if (out_rgb2 !== {
                        (expected_edge1(out_y, out_x - CROP_PAIRS + CROP_X_PAIR) ?
                         24'hFFFFFF : 24'h000000),
                        (expected_edge0(out_y, out_x - CROP_PAIRS + CROP_X_PAIR) ?
                         24'hFFFFFF : 24'h000000)}) begin
                    $display("ERROR right row=%0d x=%0d got=%h",
                             out_y, out_x, out_rgb2);
                    errors = errors + 1;
                end
            end

        end
    end

endmodule
