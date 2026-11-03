`timescale 1ns/1ps
module tb_digit_result_control;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,enable=1,restart=0,fs=0,done=0,found=1;
reg [3:0] lhs=7;
wire stable,ready;
wire [3:0] stable_lhs;
wire [4:0] stable_result;
digit_result_control dut(.clk(clk),.rst_n(rst_n),.enable(enable),.restart(restart),.frame_start(fs),
    .det_done(done),.det_found(found),.det_lhs(lhs),.det_result({1'b0,lhs}+5'd2),
    .det_x0(24'd1),.det_x1(24'd2),.det_y0(27'd3),.det_y1(27'd4),
    .stable_found(stable),.stable_lhs(stable_lhs),.stable_result(stable_result),
    .stable_x0(),.stable_x1(),.stable_y0(),.stable_y1(),.answer_ready(ready));
integer errors=0,i;
task sample(input [3:0] value);
    begin lhs=value;done=1;@(negedge clk);done=0;@(negedge clk);end
endtask
task frame;
    begin fs=1;@(negedge clk);fs=0;@(negedge clk);end
endtask
task check_delay;
    begin
        frame();if(ready) errors=errors+1;
        for(i=1;i<=18;i=i+1) begin frame();if(ready!==(i==18)) errors=errors+1;end
    end
endtask
initial begin
    repeat(5) @(negedge clk);rst_n=1;
    sample(7);if(stable || ready) errors=errors+1;
    sample(7);if(!stable || stable_lhs!=7 || stable_result!=9 || ready) errors=errors+1;
    check_delay();
    // A changed digit withdraws the old 9 immediately. One sample is insufficient.
    sample(5);if(stable || ready) errors=errors+1;
    sample(7);if(stable || ready) errors=errors+1;
    sample(5);if(stable || ready) errors=errors+1;
    sample(5);if(!stable || stable_lhs!=5 || stable_result!=7 || ready) errors=errors+1;
    check_delay();
    sample(5);if(!ready) errors=errors+1; // movement/same identity does not reset delay
    sample(7);if(stable || ready) errors=errors+1;
    sample(7);if(!stable || stable_result!=9 || ready) errors=errors+1;
    check_delay();
    found=0;sample(7);if(stable || ready) errors=errors+1;
    enable=0;@(negedge clk);if(stable || ready) errors=errors+1;
    if(errors) $fatal(1,"result-control errors=%0d",errors);
    $display("PASS: 2-sample debounce, exact 18-frame answer delay, old-answer withdrawal, 9 -> 7 -> 9, loss/exit");$finish;
end
endmodule
