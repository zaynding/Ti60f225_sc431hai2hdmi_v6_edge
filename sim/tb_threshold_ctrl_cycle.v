`timescale 1ns/1ps

module tb_threshold_ctrl_cycle;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg cycle_press = 1'b0;
wire [7:0] threshold;

integer errors = 0;

always #5 clk = ~clk;

threshold_ctrl #(
    .STEP     (8),
    .THR_MIN  (8),
    .THR_INIT (50)
) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .cycle_press (cycle_press),
    .threshold   (threshold)
);

task press_once;
    input [7:0] expected;
begin
    @(negedge clk);
    cycle_press = 1'b1;
    @(negedge clk);
    cycle_press = 1'b0;
    @(posedge clk);
    if (threshold !== expected) begin
        $display("ERROR: threshold expected %0d, got %0d", expected, threshold);
        errors = errors + 1;
    end
end
endtask

initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    if (threshold !== 8'd50) begin
        $display("ERROR: reset threshold expected 50, got %0d", threshold);
        errors = errors + 1;
    end

    press_once(8'd42);
    press_once(8'd34);
    press_once(8'd26);
    press_once(8'd18);
    press_once(8'd10);
    press_once(8'd8);
    press_once(8'd50);

    if (errors == 0)
        $display("PASS: threshold_ctrl cycle test passed");
    else
        $display("FAIL: %0d errors", errors);
    $finish;
end

endmodule
