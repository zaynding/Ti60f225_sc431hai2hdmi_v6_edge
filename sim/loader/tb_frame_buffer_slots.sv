`timescale 1ns/1ps
// Exercise the real frame_buffer -> ddr_buffer -> bank_switch hierarchy.
// The old bank_switch-only test supplied the geometry directly and missed
// the missing parameter forwarding in frame_buffer.
module tb_frame_buffer_slots;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
reg [2:0] view_mode = 0;
reg [3:0] preload_set = 0;
reg read_start = 0;
reg clear_saved_toggle = 0;
wire [3:0] saved_valid;
wire [31:0] araddr;
wire [7:0] arlen;
wire arvalid, rready;
reg rvalid = 0, rlast = 0;
reg [8:0] beats_left = 0;
integer errors = 0, requests = 0, words = 0;
reg [31:0] expected_addr;
localparam integer FRAME_WORDS = 1920 * 1080 / 16;
localparam [31:0] SLOT_PITCH = 960 * 1080 * 32 / 8 + 512;

// Match checker0 in ti60f225_oob_top.v, including its 960-wide geometry.
frame_buffer #(
    .I_VID_WIDTH(32), .O_VID_WIDTH(16), .AXI_DATA_WIDTH(128),
    .AXI_ADDR_WIDTH(32), .START_ADDR(0), .BURST_LEN(127),
    .FB_NUM(3), .MAX_VID_WIDTH(960), .MAX_VID_HIGHT(1080)
) dut (
    .axi_clk(clk), .rst_n(rst_n), .i_clk(clk), .o_clk(clk),
    .freeze(1'b0), .view_mode(view_mode), .snapshot_toggle(1'b0),
    .clear_saved_toggle(clear_saved_toggle),
    .ext_hold(1'b1), .preload_set(preload_set), .saved_valid(saved_valid),
    .i_vs(1'b0), .i_de(1'b0), .vin(32'd0),
    .H_FRONT_PORCH(13'd44), .H_SYNC(13'd22), .H_VALID(13'd960), .H_BACK_PORCH(13'd74),
    .V_FRONT_PORCH(13'd4), .V_SYNC(13'd5), .V_VALID(13'd1080), .V_BACK_PORCH(13'd36),
    .awready(1'b0), .wready(1'b0), .bid(6'd0), .bvalid(1'b0),
    .araddr(araddr), .arlen(arlen), .arvalid(arvalid), .arready(1'b1),
    .rid(6'd0), .rdata(128'd0), .rlast(rlast), .rvalid(rvalid), .rready(rready), .rresp(2'b00)
);

// AXI read responder: validate every burst in a complete frame, including
// the non-4K-aligned second slot and the final partial burst.
always @(posedge clk) begin
    if (arvalid) begin
        if (araddr !== expected_addr) begin
            if (errors < 8) $display("ERROR: slot %0d burst %0d addr %08h expected %08h",
                                    view_mode, requests, araddr, expected_addr);
            errors = errors + 1;
        end
        if (({1'b0, araddr[11:0]} + (arlen + 1) * 16) > 4096) begin
            $display("ERROR: burst crosses 4K boundary"); errors = errors + 1;
        end
        expected_addr = expected_addr + (arlen + 1) * 16;
        requests = requests + 1;
        beats_left <= {1'b0, arlen} + 1;
        rvalid <= 1;
        rlast <= (arlen == 0);
    end else if (rvalid && rready) begin
        words = words + 1;
        beats_left <= beats_left - 1;
        rlast <= (beats_left == 2);
        if (beats_left == 1) begin rvalid <= 0; rlast <= 0; end
    end
end

integer slot;
initial begin
    // Supply a known RAW frame length without needing a camera. Drain the
    // read FIFO directly; this test checks DDR addressing, not HDMI timing.
    force dut.ddr_frame_len = FRAME_WORDS;
    force dut.fifo_rd_period = read_start;
    force dut.rd_fifo_rden = ~dut.rd_fifo_rdempty;
    repeat (8) @(negedge clk);
    rst_n = 1;
    repeat (50) @(negedge clk);
    preload_set = 4'b1111;
    repeat (10) @(negedge clk);
    if (saved_valid !== 4'b1111) $fatal(1, "preload slots not valid");

    for (slot = 1; slot <= 4; slot = slot + 1) begin
        view_mode = slot;
        expected_addr = 32'h0200_0000 + (slot - 1) * SLOT_PITCH;
        requests = 0; words = 0;
        repeat (20) @(negedge clk);
        read_start = 1;
        wait (words == FRAME_WORDS);
        repeat (20) @(negedge clk);
        if (words != FRAME_WORDS || rvalid) $fatal(1, "incorrect frame length");
        $display("slot %0d: checked %0d words in %0d bursts", slot, words, requests);
        read_start = 0;
        repeat (50) @(negedge clk);
    end
    // Exercise the new control through the full wrapper hierarchy and its CDC.
    clear_saved_toggle = ~clear_saved_toggle;
    repeat (12) @(negedge clk);
    if (saved_valid !== 4'b0011) $fatal(1, "clear lost in frame_buffer hierarchy");
    view_mode = 1;
    repeat (12) @(negedge clk);
    if (dut.u_ddr_buffer.rd_start_addr !== 32'h0200_0000)
        $fatal(1, "clear damaged retained slot 1 address");
    if (errors) $fatal(1, "FAIL: %0d slot address errors", errors);
    $display("PASS: frame_buffer hierarchy reads all four complete saved frames at loader addresses");
    $finish;
end
initial begin #20000000; $fatal(1, "FAIL: timeout"); end
endmodule
