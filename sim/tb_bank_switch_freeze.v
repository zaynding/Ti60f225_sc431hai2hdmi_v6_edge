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

    capture_saved(SAVED0_ADDR);
    capture_saved(SAVED1_ADDR);
    capture_saved(SAVED2_ADDR);
    capture_saved(SAVED3_ADDR);
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

    if (errors == 0) begin
        $display("PASS: bank_switch replay test passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
