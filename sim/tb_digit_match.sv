`timescale 1ns/1ps
module tb_digit_match;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, enable=1, restart=0, go=0, we=0, bit_in=0;
reg [15:0] addr=0;
wire busy, done, found;
wire [4:0] result;
wire [3:0] lhs;
wire [23:0] x0,x1;
wire [26:0] y0,y1;
digit_match_7p2 dut(.clk(clk),.rst_n(rst_n),.enable(enable),.restart(restart),.go(go),
    .map_we(we),.map_waddr(addr),.map_wbit(bit_in),.busy(busy),.done(done),.found(found),
    .result(result),.lhs_value(lhs),.box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1));
reg bits [0:64799];
localparam NSCENE=24;
reg expected [0:NSCENE-1];
reg [23:0] ex0[0:NSCENE-1],ex1[0:NSCENE-1];
reg [26:0] ey0[0:NSCENE-1],ey1[0:NSCENE-1];
reg [3:0] elhs[0:NSCENE-1];
reg [4:0] eresult[0:NSCENE-1];
integer scene,i,cycles,errors=0,trace=0;
reg [511:0] filename;
integer result_file;
always @(negedge clk) begin
    if (dut.state==12 && trace)
        $display("glyph x=%0d..%0d y=%0d..%0d scores=%0d,%0d,%0d,%0d",
            dut.x0,dut.x1,dut.y0,dut.y1,dut.score7,dut.score_plus,dut.score2,dut.score5);
end
initial begin
    trace=$test$plusargs("trace");
    $readmemb("sim/digits/vectors/expected.mem",expected);
    $readmemh("sim/digits/vectors/expected_lhs.mem",elhs);$readmemh("sim/digits/vectors/expected_result.mem",eresult);
    $readmemh("sim/digits/vectors/expected_x0.mem",ex0);$readmemh("sim/digits/vectors/expected_x1.mem",ex1);
    $readmemh("sim/digits/vectors/expected_y0.mem",ey0);$readmemh("sim/digits/vectors/expected_y1.mem",ey1);
    result_file=$fopen("sim/build/digits/results.txt","w");
    repeat(5) @(negedge clk); rst_n=1;
    for (scene=0;scene<NSCENE;scene=scene+1) begin
        $sformat(filename,"sim/digits/vectors/scene%0d.mem",scene);
        $readmemb(filename,bits);
        restart=1; @(negedge clk); restart=0;
        for(i=0;i<64800;i=i+1) begin
            we=1; addr=i; bit_in=bits[i]; @(negedge clk);
        end
        we=0; go=1; @(negedge clk); go=0;
        cycles=0;
        while(!done && cycles<1000000) begin @(negedge clk); cycles=cycles+1; end
        if (!done || found!==expected[scene] || lhs!==elhs[scene] || result!==eresult[scene] || (found && (x0!==ex0[scene] || x1!==ex1[scene] || y0!==ey0[scene] || y1!==ey1[scene]))) begin
            errors=errors+1;
            $display("FAIL scene %0d expected=%0d found=%0d result=%0d cycles=%0d overflow=%0d labels=%0d",scene,expected[scene],found,result,cycles,dut.overflow,dut.next_label);
        end else $display("PASS scene %0d found=%0d cycles=%0d",scene,found,cycles);
        $fdisplay(result_file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            scene,found,result,cycles,x0[7:0],x1[7:0],y0[8:0],y1[8:0],
            x0[15:8],x1[15:8],y0[17:9],y1[17:9],x0[23:16],x1[23:16],y0[26:18],y1[26:18]);
        // Cancellation must clear a successful result, including a new go in flight.
        go=1; @(negedge clk); go=0; repeat(10) @(negedge clk);
        enable=0; @(negedge clk);
        if (busy || found || result) begin errors=errors+1; $display("FAIL cancel"); end
        enable=1; @(negedge clk);
    end
    $fclose(result_file);
    if(errors) $fatal(1,"digit matcher errors=%0d",errors);
    $display("PASS: all 24 assignment scenes, 7/5 classification, actual sums, exact boxes and cancellation"); $finish;
end
endmodule
