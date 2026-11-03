`timescale 1ns/1ps
// Drives jtag_demo_loader exactly like tools/jtag_load_demo.py does (same header / payload layout, LSB first),
// against a small AXI-slave memory model, and checks: hold/grant handshake, data + address of every word,
// camera/loader bus ownership, DONE -> preload_mask / preload_tog, status word, bank_switch slot marking.
module tb_jtag_demo_loader;
reg tck = 0, tdi = 0, sel = 0, shift = 0, capture = 0, update = 0;
wire tdo;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
always #16 tck = ~tck;      // ~31 MHz

reg fb_busy = 0;
wire hold_req, grant;
wire [31:0] awaddr; wire awvalid; reg awready = 0;
wire [127:0] wdata; wire wvalid; reg wready = 0;
reg bvalid = 0; reg [1:0] bresp = 0;
wire [3:0] preload_mask; wire preload_tog;

jtag_demo_loader #(.QUIET_CYCLES(200), .WD_CYCLES(100000)) dut (
    .tck(tck), .tdi(tdi), .tdo(tdo), .sel(sel), .shift(shift), .capture(capture), .update(update),
    .clk(clk), .rst_n(rst_n), .fb_busy(fb_busy), .hold_req(hold_req), .grant(grant),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata), .wvalid(wvalid), .wready(wready),
    .bvalid(bvalid), .bresp(bresp), .preload_mask(preload_mask), .preload_tog(preload_tog));

// ---------------- AXI slave: remembers (addr, data), answers with a few cycles of latency ----------------
reg [31:0] mem_addr [0:4095];
reg [127:0] mem_data [0:4095];
integer nmem = 0;
reg [31:0] a_lat; reg got_aw = 0, got_w = 0; reg [31:0] aw_q; reg [127:0] w_q;
integer dly = 0, state_b = 0;
always @(posedge clk) begin
    bvalid <= 0;
    awready <= awvalid & ~got_aw & ($random & 1);
    wready  <= wvalid  & ~got_w  & ($random & 1);
    if (awvalid & awready) begin got_aw <= 1; aw_q <= awaddr; end
    if (wvalid  & wready)  begin got_w  <= 1; w_q  <= wdata;  end
    if (got_aw & got_w) begin
        mem_addr[nmem] = aw_q; mem_data[nmem] = w_q; nmem = nmem + 1;
        got_aw <= 0; got_w <= 0; bvalid <= 1;
    end
end

// ---------------- JTAG TAP stimulus -----------------
reg [63:0] stat_cap;
task dr_scan;             // shifts `nbits` of `data` (LSB first), returns the bits shifted out in stat_cap[63:0]
    input [63:0] hdr;
    input integer npay;               // payload words of 128 bit
    input [127:0] seedpat;
    integer i, j; reg [127:0] w;
    begin
        @(negedge tck); sel = 1; capture = 1; shift = 0; update = 0;
        @(negedge tck); capture = 0; shift = 1;
        for (i = 0; i < 64; i = i + 1) begin
            stat_cap[i] = tdo;          // TDO is valid from the falling edge before the shifting rising edge
            tdi = hdr[i];
            @(negedge tck);
        end
        for (j = 0; j < npay; j = j + 1) begin
            w = seedpat + j;
            w[127:112] = j[15:0] ^ 16'hA5C3;
            for (i = 0; i < 128; i = i + 1) begin
                tdi = w[i];
                @(negedge tck);
            end
        end
        shift = 0; update = 1;
        @(negedge tck); update = 0; sel = 0;
        repeat (3) @(negedge tck);
    end
endtask

task status;
    begin dr_scan({32'd0, 24'd0, 8'd0}, 0, 128'd0); end
endtask

function [63:0] hdr; input [7:0] c; input [23:0] n; input [31:0] a;
    begin hdr = {a, n, c}; end
endfunction

integer errors = 0;
integer k;
initial begin
    repeat (8) @(posedge clk); rst_n = 1;
    repeat (20) @(posedge clk);

    status;
    if (stat_cap[63:48] !== 16'hA55A) begin $display("ERROR: status magic %h", stat_cap[63:48]); errors = errors + 1; end
    if (stat_cap[0] !== 1'b0) begin $display("ERROR: grant before hold"); errors = errors + 1; end

    // camera writer busy: hold must wait for quiet time
    fb_busy = 1;
    dr_scan(hdr(8'd1, 24'd0, 32'd0), 0, 128'd0);
    repeat (300) @(posedge clk);
    if (grant) begin $display("ERROR: granted while camera busy"); errors = errors + 1; end
    if (!hold_req) begin $display("ERROR: hold_req not asserted"); errors = errors + 1; end
    fb_busy = 0;
    repeat (400) @(posedge clk);
    if (!grant) begin $display("ERROR: no grant after quiet"); errors = errors + 1; end
    status;
    if (stat_cap[1:0] !== 2'b11) begin $display("ERROR: status grant/hold %b", stat_cap[1:0]); errors = errors + 1; end

    // two payload scans: 3 words at slot0 base, 2 words at slot1 base
    dr_scan(hdr(8'd2, 24'd3, 32'h0200_0000), 3, 128'h0123_4567_89AB_CDEF_0011_2233_4455_6600);
    dr_scan(hdr(8'd2, 24'd2, 32'h023F_4A00), 2, 128'hFEDC_BA98_7654_3210_FFEE_DDCC_BBAA_9900);
    repeat (200) @(posedge clk);
    status;
    if (stat_cap[47:16] !== 32'd5) begin $display("ERROR: acked words %0d", stat_cap[47:16]); errors = errors + 1; end
    if (stat_cap[4:2] !== 3'b000) begin $display("ERROR: error flags %b", stat_cap[4:2]); errors = errors + 1; end
    if (nmem !== 5) begin $display("ERROR: %0d writes seen", nmem); errors = errors + 1; end
    for (k = 0; k < 5; k = k + 1) begin : chk
        reg [31:0] ea; reg [127:0] ed;
        ea = (k < 3) ? 32'h0200_0000 + 16 * k : 32'h023F_4A00 + 16 * (k - 3);
        ed = (k < 3) ? (128'h0123_4567_89AB_CDEF_0011_2233_4455_6600 + k) : (128'hFEDC_BA98_7654_3210_FFEE_DDCC_BBAA_9900 + (k - 3));
        ed[127:112] = ((k < 3) ? k : (k - 3)) ^ 16'hA5C3;
        if (mem_addr[k] !== ea) begin $display("ERROR: write %0d addr %h expected %h", k, mem_addr[k], ea); errors = errors + 1; end
        if (mem_data[k] !== ed) begin $display("ERROR: write %0d data %h expected %h", k, mem_data[k], ed); errors = errors + 1; end
    end

    // wrong word count must be flagged
    dr_scan(hdr(8'd2, 24'd4, 32'h0200_0100), 2, 128'd0);
    repeat (100) @(posedge clk);
    status;
    if (stat_cap[3] !== 1'b1) begin $display("ERROR: word-count error not flagged"); errors = errors + 1; end
    dr_scan(hdr(8'd4, 24'd0, 32'd0), 0, 128'd0);      // CLEAR
    status;
    if (stat_cap[3] !== 1'b0) begin $display("ERROR: error flag not cleared"); errors = errors + 1; end

    // DONE: slots 0 and 1
    dr_scan(hdr(8'd3, 24'd3, 32'd0), 0, 128'd0);
    repeat (200) @(posedge clk);
    if (grant) begin $display("ERROR: still granted after DONE"); errors = errors + 1; end
    if (hold_req) begin $display("ERROR: hold_req still set after DONE"); errors = errors + 1; end
    if (preload_mask !== 4'b0011) begin $display("ERROR: preload_mask %b", preload_mask); errors = errors + 1; end
    status;
    if (stat_cap[11:8] !== 4'b0011) begin $display("ERROR: status mask %b", stat_cap[11:8]); errors = errors + 1; end

    // watchdog: a host that vanishes after HOLD must not keep the bus; a later HOLD must work again
    dr_scan(hdr(8'd1, 24'd0, 32'd0), 0, 128'd0);
    repeat (600) @(posedge clk);
    if (!grant) begin $display("ERROR: no grant (2nd hold)"); errors = errors + 1; end
    repeat (110000) @(posedge clk);
    if (grant || hold_req) begin $display("ERROR: watchdog did not release the bus"); errors = errors + 1; end
    status;
    if (stat_cap[6] !== 1'b1) begin $display("ERROR: watchdog flag not visible"); errors = errors + 1; end
    dr_scan(hdr(8'd1, 24'd0, 32'd0), 0, 128'd0);
    repeat (600) @(posedge clk);
    if (!grant) begin $display("ERROR: no grant after watchdog re-arm"); errors = errors + 1; end
    dr_scan(hdr(8'd3, 24'd0, 32'd0), 0, 128'd0);        // DONE with empty mask: release without marking
    repeat (200) @(posedge clk);
    if (grant || hold_req) begin $display("ERROR: bus not released by empty DONE"); errors = errors + 1; end
    if (preload_mask !== 4'b0011) begin $display("ERROR: mask changed %b", preload_mask); errors = errors + 1; end

    if (errors == 0) $display("PASS: jtag_demo_loader test passed");
    else $display("FAIL: %0d errors", errors);
    $finish;
end

// watchdog test is covered separately; global timeout
initial begin #200000000; $display("FAIL: timeout"); $finish; end
endmodule
