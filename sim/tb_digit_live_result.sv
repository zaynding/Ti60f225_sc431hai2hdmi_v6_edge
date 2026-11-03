`timescale 1ns/1ps
// One enable event, four consecutive analyzed frames: acquire, move, lose,
// reacquire. Completed results remain stable throughout the following scan.
module tb_digit_live_result;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,enable=1,restart=0,go=0,we=0,bit_in=0;
reg [15:0] addr=0;
wire busy,done,found;
wire [4:0] result;
wire [3:0] lhs;
wire [23:0] x0,x1;
wire [26:0] y0,y1;
digit_match_7p2 dut(.clk(clk),.rst_n(rst_n),.enable(enable),.restart(restart),.go(go),
    .map_we(we),.map_waddr(addr),.map_wbit(bit_in),.busy(busy),.done(done),.found(found),
    .result(result),.lhs_value(lhs),.box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1));
reg original[0:64799],moved[0:64799];
integer f,i,n,errors=0;
reg old_found;
reg [23:0] old_x;
initial begin
    $readmemb("sim/digits/vectors/scene0.mem",original);
    $readmemb("sim/digits/vectors/card5_moved.mem",moved);
    repeat(5) @(negedge clk);rst_n=1;
    for(f=0;f<4;f=f+1) begin
        old_found=found;old_x=x0;
        for(i=0;i<64800;i=i+1) begin
            we=1;addr=i;bit_in=(f==1) ? moved[i] : ((f==2) ? 1'b0 : original[i]);
            @(negedge clk);
            if(busy || found!==old_found || x0!==old_x) errors=errors+1;
        end
        we=0;go=1;@(negedge clk);go=0;n=0;
        while(!done && n<1500000) begin
            @(negedge clk);n=n+1;
            if(!done && (found!==old_found || x0!==old_x)) errors=errors+1;
        end
        if(!done || found!==(f!=2) || result!==((f==2) ? 5'd0 : ((f==1) ? 5'd7 : 5'd9))) errors=errors+1;
        if(found && lhs!==((f==1) ? 4'd5 : 4'd7)) errors=errors+1;
        $display("live frame %0d found=%0d lhs=%0d result=%0d cycles=%0d",f,found,lhs,result,n);
        @(negedge clk);
    end
    if(errors) $fatal(1,"live result errors=%0d",errors);
    $display("PASS: real card 7+2 -> covered 5+2 -> loss -> 7+2, actual 9/7/9 sums without restart");$finish;
end
endmodule
