`timescale 1ns/1ps
// salt-pepper impulses must be removed, 1-px lines must survive
module tb_median_switch_2px;
    localparam integer NP = 64;      // pixel pairs per line
    localparam integer NL = 16;      // lines
    reg clk=0, rstn=0; always #6.734 clk=~clk;
    reg in_valid=0, in_hs=0, in_vs=0; reg [15:0] in_gray2=0;
    wire out_valid, out_hs, out_vs; wire [15:0] out_gray2;

    median_switch_2px #(.PAIR_COUNT(NP), .MAX_LINES(NL)) dut (
        .clk(clk), .rst_n(rstn),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_gray2(in_gray2),
        .out_valid(out_valid), .out_hs(out_hs), .out_vs(out_vs), .out_gray2(out_gray2));

    integer got [0:NL-1][0:2*NP-1];
    integer oc=0, orow=-1;
    always @(posedge clk) begin
        if (out_vs) begin oc=0; orow=-1; end
        else if (out_valid) begin
            if (orow>=0 && orow<NL) begin
                got[orow][2*oc]   = out_gray2[7:0];
                got[orow][2*oc+1] = out_gray2[15:8];
            end
            if (oc==NP-1) begin oc=0; orow=orow+1; end else oc=oc+1;
        end
    end

    function integer px; input integer x; input integer y; integer v; begin
        v = 100;                                            // background
        if (x==30)            v = 255;                      // 1-px vertical line
        if (y==7 && x>=40 && x<=60) v = 255;                // 1-px horizontal line
        if (x>=90 && x<=92)   v = 200;                      // 3-px bar
        if (x==10 && y==5)    v = 255;                      // salt impulse
        if (x==11 && y==5)    v = 0;                        // pepper impulse
        if (x==70 && y==8)    v = 255;                      // salt impulse
        if (x==75 && y==9)    v = 0;                        // pepper impulse
        px = v;
    end endfunction

    function integer exp_px; input integer x; input integer y; integer v; begin
        v = 100;
        if (x==30)            v = 255;
        if (y==7 && x>=40 && x<=60) v = 255;
        if (x>=90 && x<=92)   v = 200;
        exp_px = v;                                         // impulses -> background
    end endfunction

    integer errors=0, checked=0, i,c,f,y,p;
    initial begin
        in_valid=0; in_hs=0; in_vs=0; in_gray2=0;
        rstn=0; repeat(10) @(posedge clk); rstn=1; @(posedge clk);
        for (f=0; f<6; f=f+1) begin
            @(negedge clk); in_vs=1'b1; repeat(8) @(posedge clk); in_vs=1'b0;
            for (y=0;y<NL;y=y+1) begin
                @(negedge clk); in_hs=1'b1;
                @(posedge clk); in_hs=1'b0;
                for (p=0;p<NP;p=p+1) begin
                    @(negedge clk); in_valid=1'b1;
                    in_gray2[7:0]  = px(2*p,   y);
                    in_gray2[15:8] = px(2*p+1, y);
                    @(posedge clk);
                end
                @(negedge clk); in_valid=1'b0; repeat(4) @(posedge clk);
            end
            repeat(30) @(posedge clk);
        end
        // compare interior
        for (i=2; i<NL-2; i=i+1)
            for (c=2; c<2*NP-2; c=c+1) begin
                checked = checked + 1;
                if (got[i][c] !== exp_px(c,i+1)) begin
                    errors = errors + 1;
                    if (errors <= 12)
                        $display("ERR x=%0d y=%0d exp=%0d got=%0d", c, i, exp_px(c,i+1), got[i][c]);
                end
            end
        $display("checked=%0d errors=%0d", checked, errors);
        if (errors==0) $display("PASS: impulses removed, 1-px lines preserved");
        else           $display("FAIL");
        $finish;
    end
    initial begin #4000000; $display("timeout"); $finish; end
endmodule
