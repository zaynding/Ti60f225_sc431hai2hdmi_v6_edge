`timescale 1ns/1ps
// Replays the exact byte stream written by `tools/jtag_load_demo.py --emit-test scan_write.bin`
// (HOLD scan, WRITE scan, DONE scan) into jtag_demo_loader and checks the DDR writes against demo_raw/frame1.raw.
module tb_jtag_file_scan;
parameter RAWFILE = "frame1.raw";
reg tck = 0, tdi = 0, sel = 0, shift = 0, capture = 0, update = 0;
wire tdo;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
always #16 tck = ~tck;
wire hold_req, grant, awvalid, wvalid; wire [31:0] awaddr; wire [127:0] wdata;
reg awready = 0, wready = 0, bvalid = 0;
wire [3:0] preload_mask; wire preload_tog;
jtag_demo_loader #(.QUIET_CYCLES(100), .WD_CYCLES(100000)) dut (
    .tck(tck), .tdi(tdi), .tdo(tdo), .sel(sel), .shift(shift), .capture(capture), .update(update),
    .clk(clk), .rst_n(rst_n), .fb_busy(1'b0), .hold_req(hold_req), .grant(grant),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata), .wvalid(wvalid), .wready(wready),
    .bvalid(bvalid), .bresp(2'b00), .preload_mask(preload_mask), .preload_tog(preload_tog));

reg [31:0] ma [0:15]; reg [127:0] md [0:15]; integer nm = 0;
reg ga = 0, gw = 0; reg [31:0] aq; reg [127:0] wq;
always @(posedge clk) begin
    bvalid <= 0; awready <= awvalid & ~ga; wready <= wvalid & ~gw;
    if (awvalid & awready) begin ga <= 1; aq <= awaddr; end
    if (wvalid & wready)   begin gw <= 1; wq <= wdata;  end
    if (ga & gw) begin ma[nm] = aq; md[nm] = wq; nm = nm + 1; ga <= 0; gw <= 0; bvalid <= 1; end
end

reg [7:0] scan [0:4095]; reg [7:0] raw [0:4095];
integer fd, nbytes, nraw, i, b, errors = 0;
task shift_bytes; input integer n;
    integer ii, bb;
    begin
        @(negedge tck); sel = 1; capture = 1; shift = 0;
        @(negedge tck); capture = 0; shift = 1;
        for (ii = 0; ii < n; ii = ii + 1)
            for (bb = 0; bb < 8; bb = bb + 1) begin tdi = scan[ii][bb]; @(negedge tck); end
        shift = 0; update = 1; @(negedge tck); update = 0; sel = 0;
        repeat (3) @(negedge tck);
    end
endtask
task hdr_only; input [7:0] c; input [23:0] n;
    reg [63:0] h; integer bb;
    begin
        h = {32'd0, n, c};
        for (bb = 0; bb < 8; bb = bb + 1) scan[bb] = h[8*bb +: 8];
        shift_bytes(8);
    end
endtask
initial begin
    fd = $fopen("scan_write.bin", "rb"); nbytes = $fread(scan, fd); $fclose(fd);
    fd = $fopen(RAWFILE, "rb"); nraw = $fread(raw, fd); $fclose(fd);
    repeat (8) @(posedge clk); rst_n = 1; repeat (10) @(posedge clk);
    // the write scan has to be shifted from scan[] but HOLD must come first -> stash it
    begin : stash
        reg [7:0] keep [0:4095]; integer q;
        for (q = 0; q < nbytes; q = q + 1) keep[q] = scan[q];
        hdr_only(8'd1, 24'd0);
        repeat (400) @(posedge clk);
        if (!grant) begin $display("ERROR: no grant"); errors = errors + 1; end
        for (q = 0; q < nbytes; q = q + 1) scan[q] = keep[q];
    end
    shift_bytes(nbytes);
    repeat (300) @(posedge clk);
    hdr_only(8'd3, 24'd3);
    repeat (300) @(posedge clk);
    if (nm !== 3) begin $display("ERROR: %0d writes", nm); errors = errors + 1; end
    for (i = 0; i < 3; i = i + 1) begin : cmp
        reg [127:0] e;
        for (b = 0; b < 16; b = b + 1) e[8*b +: 8] = raw[16*i + b];
        if (ma[i] !== 32'h0200_0000 + 16*i) begin $display("ERROR: addr %0d %h", i, ma[i]); errors = errors + 1; end
        if (md[i] !== e) begin $display("ERROR: data %0d %h vs %h", i, md[i], e); errors = errors + 1; end
    end
    if (preload_mask !== 4'b0011) begin $display("ERROR: mask %b", preload_mask); errors = errors + 1; end
    if (errors == 0) $display("PASS: script scan bytes accepted by jtag_demo_loader");
    else $display("FAIL: %0d errors", errors);
    $finish;
end
endmodule
