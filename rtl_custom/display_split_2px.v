`timescale 1ns/1ps
//======================================================================================================
// display_split_2px.v
//
// Left half  : central colour crop with red edges copied from the edge mask.
// Right half : the same central crop as a black/white edge image.
//
// The edge source arrives at the same time as the left colour stream, but the
// current edge row is not available when the first left pixels are emitted.
// A one-line central edge buffer therefore supplies the previous scan line for
// the red overlay.  The colour image is not moved horizontally, and no
// full-frame buffer is added.
//======================================================================================================
module display_split_2px #(
    parameter integer PAIR_COUNT  = 960,
    parameter integer LINE_COUNT  = 1080,
    parameter integer CROP_X_PAIR = 240,
    parameter integer CROP_PAIRS  = 480,
    parameter integer BUF_LINES   = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        show_red, show_color, show_edge,
    input  wire        cmp_mode,                 // 1: left panel = raw Sobel edges, right panel = main (Canny) edges
    input  wire        s_edge0, s_edge1,         // raw Sobel edges, aligned with edge0/edge1
    input  wire        src_valid,
    input  wire        src_vs,
    input  wire [47:0] src_rgb2,

    input  wire        in_valid,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire        edge0,
    input  wire        edge1,

    output reg         out_valid,
    output reg         out_hs,
    output reg         out_vs,
    output reg  [47:0] out_rgb2
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer PW    = clog2(PAIR_COUNT);
    localparam integer SW    = clog2(BUF_LINES);
    localparam integer CW    = clog2(CROP_PAIRS);          // colour line buffer holds only the displayed crop
    localparam integer DEPTH = BUF_LINES << CW;
    localparam [PW-1:0] CROP_X_START = CROP_X_PAIR;
    localparam [PW-1:0] CROP_X_END   = CROP_X_PAIR + CROP_PAIRS;

    // Full-width colour line buffer.  The colour stream is several lines ahead
    // of the edge stream because of the median and 3x3 processing stages.
    reg [47:0] cmem [0:DEPTH-1];

    // Central-crop edge line buffer, two pixels per word.
    reg [1:0] emask_mem [0:CROP_PAIRS-1];

    //=============================================================================================
    // Colour write port
    //=============================================================================================
    reg [SW-1:0] wr_slot;
    reg [PW-1:0] wr_pair;
    reg          src_vs_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slot <= {SW{1'b0}};
            wr_pair <= {PW{1'b0}};
            src_vs_d <= 1'b0;
        end
        else begin
            src_vs_d <= src_vs;
            if (src_vs & ~src_vs_d) begin
                wr_slot <= {SW{1'b0}};
                wr_pair <= {PW{1'b0}};
            end
            else if (src_valid) begin
                if (wr_pair == PAIR_COUNT-1) begin
                    wr_pair <= {PW{1'b0}};
                    wr_slot <= (wr_slot == BUF_LINES-1) ?
                               {SW{1'b0}} : (wr_slot + 1'b1);
                end
                else begin
                    wr_pair <= wr_pair + 1'b1;
                end
            end
        end
    end

    wire [PW-1:0] wr_off = wr_pair - CROP_X_START;
    always @(posedge clk) begin
        if (src_valid && wr_pair >= CROP_X_START && wr_pair < CROP_X_END)
            cmem[{wr_slot, wr_off[CW-1:0]}] <= src_rgb2;
    end

    //=============================================================================================
    // Input position and line tracking
    //=============================================================================================
    reg [PW-1:0] x_in;
    reg [SW-1:0] rd_slot;
    reg          in_vs_d;
    reg          in_hs_d;
    reg [10:0]   line_y;

    // Read central-crop colour for the left half only.
    wire         left_read     = in_valid && (x_in < CROP_PAIRS);
    wire [PW-1:0] color_raddr  = left_read ? x_in : {PW{1'b0}};
    wire [PW-1:0] emask_raddr  = left_read ? x_in : {PW{1'b0}};

    // Write the current edge row into the central-crop mask.  While writing
    // address x, the left side reads address x + CROP_X_PAIR, so the previous
    // scan line is still available in the buffer.
    wire         emask_we     = in_valid &&
                                (x_in >= CROP_X_START) &&
                                (x_in < CROP_X_END);
    wire [PW-1:0] emask_waddr = x_in - CROP_X_START;

    // Registered RAM outputs.  Both colour and mask use the same pipeline.
    reg cmp_l;                                   // compare mode, sampled at the start of every frame
    always @(posedge clk or negedge rst_n)
        if (!rst_n) cmp_l <= 1'b0;
        else if (in_vs & ~in_vs_d) cmp_l <= cmp_mode;
    reg [47:0] cmem_q;
    reg [1:0]  emask_q;

    always @(posedge clk) begin
        cmem_q  <= cmem[{rd_slot, color_raddr[CW-1:0]}];
        emask_q <= emask_mem[emask_raddr];
        if (emask_we)
            emask_mem[emask_waddr] <= cmp_l ? {s_edge1, s_edge0} : {edge1, edge0};
    end

    //=============================================================================================
    // Right-half edge crop delay: right output begins at pair CROP_PAIRS and
    // must show source pair CROP_X_PAIR first.
    //=============================================================================================
    reg [CROP_X_PAIR-1:0] e0_sr;
    reg [CROP_X_PAIR-1:0] e1_sr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e0_sr <= {CROP_X_PAIR{1'b0}};
            e1_sr <= {CROP_X_PAIR{1'b0}};
        end
        else if (in_hs & ~in_hs_d) begin
            e0_sr <= {CROP_X_PAIR{1'b0}};
            e1_sr <= {CROP_X_PAIR{1'b0}};
        end
        else if (in_valid) begin
            e0_sr <= {e0_sr[CROP_X_PAIR-2:0], edge0};
            e1_sr <= {e1_sr[CROP_X_PAIR-2:0], edge1};
        end
    end

    wire [1:0] edge_dly = {e1_sr[CROP_X_PAIR-1], e0_sr[CROP_X_PAIR-1]};

    //=============================================================================================
    // Output pipeline
    //=============================================================================================
    reg          pipe_valid;
    reg          pipe_hs;
    reg          pipe_vs;
    reg [PW-1:0] pipe_x;
    reg [10:0]   pipe_line;
    reg [1:0]    pipe_edge;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in      <= {PW{1'b0}};
            rd_slot   <= {SW{1'b0}};
            in_vs_d   <= 1'b0;
            in_hs_d   <= 1'b0;
            line_y    <= 11'd0;

            pipe_valid <= 1'b0;
            pipe_hs    <= 1'b0;
            pipe_vs    <= 1'b0;
            pipe_x     <= {PW{1'b0}};
            pipe_line  <= 11'd0;
            pipe_edge  <= 2'd0;

            out_valid <= 1'b0;
            out_hs    <= 1'b0;
            out_vs    <= 1'b0;
            out_rgb2  <= 48'd0;
        end
        else begin
            in_vs_d <= in_vs;
            in_hs_d <= in_hs;

            // Stage 1 flags and edge data.
            pipe_valid <= in_valid;
            pipe_hs    <= in_hs;
            pipe_vs    <= in_vs;
            pipe_x     <= x_in;
            pipe_line  <= line_y;
            pipe_edge  <= edge_dly;

            // Stage 2 output.  cmem_q/emask_q and stage-1 flags correspond to
            // the same pixel pair.
            out_valid <= pipe_valid;
            out_hs    <= pipe_hs;
            out_vs    <= pipe_vs;

            if (pipe_valid) begin
                if (pipe_x < CROP_PAIRS) begin
                    out_rgb2 <= cmp_l ? {
                        ((pipe_line != 11'd0) && emask_q[1] && show_edge) ? 24'hFFFFFF : 24'h000000,
                        ((pipe_line != 11'd0) && emask_q[0] && show_edge) ? 24'hFFFFFF : 24'h000000
                    } : {
                        ((pipe_line != 11'd0) && emask_q[1] && show_red) ?
                            24'hFF0000 : (show_color ? cmem_q[47:24] : 24'h202020),
                        ((pipe_line != 11'd0) && emask_q[0] && show_red) ?
                            24'hFF0000 : (show_color ? cmem_q[23:0] : 24'h202020)
                    };
                end
                else if (pipe_x < (2 * CROP_PAIRS)) begin
                    out_rgb2 <= {
                        (pipe_edge[1] && show_edge) ? 24'hFFFFFF : 24'h000000,
                        (pipe_edge[0] && show_edge) ? 24'hFFFFFF : 24'h000000
                    };
                end
                else begin
                    out_rgb2 <= 48'd0;
                end
            end

            if (in_vs & ~in_vs_d) begin
                x_in    <= {PW{1'b0}};
                rd_slot <= {SW{1'b0}};
                line_y  <= 11'd0;
            end
            else if (in_valid) begin
                if (x_in == PAIR_COUNT-1) begin
                    x_in    <= {PW{1'b0}};
                    rd_slot <= (rd_slot == BUF_LINES-1) ?
                               {SW{1'b0}} : (rd_slot + 1'b1);
                    line_y  <= line_y + 11'd1;
                end
                else begin
                    x_in <= x_in + 1'b1;
                end
            end
        end
    end

endmodule
