`timescale 1ns/1ps
module tb_digit_capture;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,enable=1,start=0,ready=0,v=0,s=0;
reg [15:0] g=0;
wire we,b,done,busy;
wire [15:0] addr;
wire [7:0] threshold;
digit_capture_2px dut(.clk(clk),.rst_n(rst_n),.enable(enable),.start(start),.ready(ready),
    .in_valid(v),.in_vs(s),.in_gray2(g),.map_we(we),.map_addr(addr),.map_bit(b),
    .done(done),.busy(busy),.ink_threshold(threshold));
reg expected[0:64799];
reg expected_moved[0:64799];
reg [15:0] image[0:518399];
reg [15:0] image_moved[0:518399];
integer f,l,c,errors=0,nwrite=0,ndone=0;
always @(posedge clk) begin
    if(we) begin
        if((f!=1 && f!=3) || addr!==(nwrite%64800) || b!==(nwrite<64800 ? expected[nwrite%64800] : expected_moved[nwrite%64800])) begin
            if(errors<10) $display("FAIL capture f=%0d addr=%0d nwrite=%0d",f,addr,nwrite);
            errors=errors+1;
        end
        nwrite=nwrite+1;
    end
    if(done) ndone=ndone+1;
end
initial begin
    $readmemb("sim/digits/vectors/scene0.mem",expected);
    $readmemh("sim/digits/vectors/card_gray2.mem",image);
    $readmemh("sim/digits/vectors/card_moved_gray2.mem",image_moved);
    $readmemb("sim/digits/vectors/card_moved.mem",expected_moved);
    repeat(8) @(negedge clk); rst_n=1; start=1; @(negedge clk); start=0;
    for(f=0;f<4;f=f+1) begin
        ready=(f==1 || f==3);
        for(l=0;l<1125;l=l+1) begin
            for(c=0;c<1100;c=c+1) begin
                s=(l<3); v=(l>=20 && l<1100 && c<960); g=16'hffff;
                if(v && c>=240 && c<720) g=(f<2) ? image[(l-20)*480+c-240] : image_moved[(l-20)*480+c-240];
                @(negedge clk);
            end
        end
    end
    v=0; s=0; repeat(20) @(negedge clk);
    if(nwrite!=129600 || ndone!=2 || busy || threshold!=127) begin
        errors=errors+1; $display("FAIL counts writes=%0d done=%0d busy=%0d threshold=%0d",nwrite,ndone,busy,threshold);
    end
    // A fresh request canceled partway through settling must not submit a map.
    start=1; @(negedge clk); start=0; repeat(5) @(negedge clk);
    enable=0; @(negedge clk);
    if(busy || we || done) errors=errors+1;
    if(errors) $fatal(1,"capture errors=%0d",errors);
    $display("PASS: continuous live frames, busy backpressure, both 64800-cell moving maps and cancellation");
    $finish;
end
endmodule
