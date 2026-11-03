module tb_bank_switch_freeze;

localparam [31:0] BANK0_ADDR = 32'h0000_0000;
localparam [31:0] BANK1_ADDR = 32'h003F_4A00;
localparam [31:0] BANK2_ADDR = 32'h007E_9400;
localparam [31:0] SAVED0_ADDR = 32'h0200_0000;
localparam [31:0] SAVED1_ADDR = 32'h023F_4A00;
localparam [31:0] SAVED2_ADDR = 32'h027E_9400;
localparam [31:0] SAVED3_ADDR = 32'h02BD_DE00;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg freeze = 1'b0;
reg [2:0] view_mode = 3'd0;
reg snapshot_toggle = 1'b0;
reg clear_saved_toggle = 1'b0;
reg [3:0] preload_set = 4'b0000;
reg wr_sw = 1'b0;
reg rd_sw = 1'b0;

wire [1:0]  wr_bank;
wire [1:0]  rd_bank;
wire        rd_sw_ack;
wire        wr_sw_ack;
wire [31:0] rd_start_addr;
wire [31:0] wr_start_addr;
wire [3:0]  saved_valid;

integer errors = 0;

bank_switch #(
    .FB_NUM         (3),
    .MAX_VID_WIDTH  (960),
    .MAX_VID_HIGHT  (1080),
    .START_ADDR     (32'h0000_0000),
    .VID_DATA_WIDTH (32),
    .AXI_DATA_WIDTH (128)
) dut (
    .ddr_clk       (clk),
    .rst_n         (rst_n),
    .freeze        (freeze),
    .view_mode     (view_mode),
    .snapshot_toggle(snapshot_toggle),
    .clear_saved_toggle(clear_saved_toggle),
    .preload_set   (preload_set),
    .wr_sw         (wr_sw),
    .rd_sw         (rd_sw),
    .wr_bank       (wr_bank),
    .rd_bank       (rd_bank),
    .rd_sw_ack     (rd_sw_ack),
    .wr_sw_ack     (wr_sw_ack),
    .rd_start_addr (rd_start_addr),
    .wr_start_addr (wr_start_addr),
    .saved_valid   (saved_valid)
);

always #5 clk = ~clk;

task pulse_wr_sw;
begin
    @(negedge clk);
    wr_sw = 1'b1;
    @(negedge clk);
    wr_sw = 1'b0;
    repeat (3) @(posedge clk);
end
endtask

task pulse_rd_sw;
begin
    @(negedge clk);
    rd_sw = 1'b1;
    @(negedge clk);
    rd_sw = 1'b0;
    repeat (3) @(posedge clk);
end
endtask

task check_addr;
    input [31:0] expected;
    input [255:0] label;
begin
    if (rd_start_addr !== expected) begin
        $display("ERROR: %0s expected %08h, got %08h",
                 label, expected, rd_start_addr);
        errors = errors + 1;
    end
end
endtask

task capture_saved;
    input [31:0] expected_addr;
begin
    @(negedge clk);
    snapshot_toggle = ~snapshot_toggle;
    repeat (3) @(posedge clk);

    // Complete the current live frame. This arms the snapshot for the next
    // frame and redirects the write address.
    pulse_wr_sw();
    repeat (2) @(posedge clk);
    if (wr_start_addr !== expected_addr) begin
        $display("ERROR: snapshot write address expected %08h, got %08h",
                 expected_addr, wr_start_addr);
        errors = errors + 1;
    end

    // Complete the snapshot frame.
    pulse_wr_sw();
    repeat (2) @(posedge clk);
end
endtask

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    check_addr(BANK1_ADDR, "reset read bank");

    // Demo loader fills slots 1 and 2 from outside: they become valid and later captures continue after them.
    preload_set = 4'b0011;
    repeat (3) @(posedge clk);
    if (saved_valid !== 4'b0011) begin
        $display("ERROR: preload saved_valid expected 0011, got %04b", saved_valid);
        errors = errors + 1;
    end
    view_mode = 3'd2;
    repeat (2) @(posedge clk);
    check_addr(SAVED1_ADDR, "preloaded frame 2 read address");
    view_mode = 3'd0;
    repeat (2) @(posedge clk);
    capture_saved(SAVED2_ADDR);
    capture_saved(SAVED3_ADDR);
    capture_saved(SAVED0_ADDR);
    capture_saved(SAVED1_ADDR);
    if (saved_valid !== 4'b1111) begin
        $display("ERROR: saved_valid expected 1111, got %04b", saved_valid);
        errors = errors + 1;
    end

    // K2 mode selection: each saved mode must select its own DDR region.
    view_mode = 3'd1;
    repeat (2) @(posedge clk);
    check_addr(SAVED0_ADDR, "saved frame 1 read address");
    view_mode = 3'd2;
    repeat (2) @(posedge clk);
    check_addr(SAVED1_ADDR, "saved frame 2 read address");
    view_mode = 3'd3;
    repeat (2) @(posedge clk);
    check_addr(SAVED2_ADDR, "saved frame 3 read address");
    view_mode = 3'd4;
    repeat (2) @(posedge clk);
    check_addr(SAVED3_ADDR, "saved frame 4 read address");

    // Return to LIVE.
    view_mode = 3'd0;
    repeat (2) @(posedge clk);
    check_addr(BANK1_ADDR, "return to live read address");

    // Invalidate only 3/4 even while selected; next capture starts at 3.
    view_mode = 3'd4;
    @(negedge clk); clear_saved_toggle = ~clear_saved_toggle;
    repeat (8) @(negedge clk);
    if (saved_valid !== 4'b0011) $fatal(1, "clear must preserve slots 1/2 only");
    check_addr(BANK1_ADDR, "deleted source falls back to live");
    capture_saved(SAVED2_ADDR);
    if (saved_valid !== 4'b0111) $fatal(1, "next capture must refill slot 3");
    capture_saved(SAVED3_ADDR);
    if (saved_valid !== 4'b1111) $fatal(1, "second capture must refill slot 4");

    // Clear while a slot-3 write is active: don't redirect mid-frame or
    // revalidate it at completion. Low slots remain usable throughout.
    @(negedge clk); clear_saved_toggle = ~clear_saved_toggle;
    repeat (8) @(negedge clk);
    @(negedge clk); snapshot_toggle = ~snapshot_toggle;
    repeat (8) @(negedge clk);
    pulse_wr_sw();
    repeat (3) @(negedge clk);
    if (wr_start_addr !== SAVED2_ADDR) $fatal(1, "slot 3 write not active");
    @(negedge clk); clear_saved_toggle = ~clear_saved_toggle;
    repeat (8) @(negedge clk);
    if (wr_start_addr !== SAVED2_ADDR) $fatal(1, "clear redirected an active write");
    pulse_wr_sw();
    repeat (3) @(negedge clk);
    if (saved_valid !== 4'b0011) $fatal(1, "active write resurrected a deleted slot");
    capture_saved(SAVED2_ADDR);
    if (saved_valid !== 4'b0111) $fatal(1, "clear failed to rearm slot 3");

    // Cancel a queued snapshot before a live-frame boundary.
    @(negedge clk); snapshot_toggle = ~snapshot_toggle;
    repeat (8) @(negedge clk);
    @(negedge clk); clear_saved_toggle = ~clear_saved_toggle;
    repeat (8) @(negedge clk);
    pulse_wr_sw();
    repeat (3) @(negedge clk);
    if (dut.three_fb.snap_active || saved_valid !== 4'b0011)
        $fatal(1, "clear failed to cancel queued capture");
    capture_saved(SAVED2_ADDR);

    // Clear arriving on the exact completion cycle must also win.
    @(negedge clk); snapshot_toggle = ~snapshot_toggle;
    repeat (8) @(negedge clk);
    pulse_wr_sw();
    repeat (3) @(negedge clk);
    if (wr_start_addr !== SAVED3_ADDR) $fatal(1, "slot 4 write not active");
    @(negedge clk); clear_saved_toggle = ~clear_saved_toggle;
    repeat (2) @(negedge clk);
    wr_sw = 1;
    @(negedge clk); wr_sw = 0;
    repeat (8) @(negedge clk);
    if (saved_valid !== 4'b0011 || dut.three_fb.clear_pending)
        $fatal(1, "simultaneous clear/completion left a valid slot or stuck pending");
    capture_saved(SAVED2_ADDR);

    if (errors == 0) begin
        $display("PASS: bank_switch replay test passed");
    end else begin
        $fatal(1, "FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
