`timescale 1ns/1ps
// isolated white pixels in the 1-bit edge map must be removed, lines kept
module tb_despeckle_2px;
    localparam integer NP = 64;
    localparam integer NL = 16;
    reg clk=0, rstn=0; always #6.734 clk=~clk;
    reg in_valid=0, in_hs=0, in_vs=0; reg [1:0] in_edge2=0;
    wire out_valid, out_hs, out_vs; wire [1:0] out_edge2;

    despeckle_2px #(.PAIR_COUNT(NP), .MAX_LINES(NL)) dut (
        .clk(clk), .rst_n(rstn),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_edge2(in_edge2),
        .out_valid(out_valid), .out_hs(out_hs), .out_vs(out_vs), .out_edge2(out_edge2));

    reg got [0:NL-1][0:2*NP-1];
    integer oc=0, orow=-1;
    always @(posedge clk) begin
        if (out_vs) begin oc=0; orow=-1; end
        else if (out_valid) begin
            if (orow>=0 && orow<NL) begin
                got[orow][2*oc]   = out_edge2[0];
                got[orow][2*oc+1] = out_edge2[1];
            end
            if (oc==NP-1) begin oc=0; orow=orow+1; end else oc=oc+1;
        end
    end

    function px; input integer x; input integer y; reg v; begin
        v = 1'b0;
        if (y==5 && x>=4 && x<=60) v = 1'b1;      // horizontal line
        if (x==20 && y>=1 && y<=14) v = 1'b1;     // vertical line
        if (x==5  && y==9)  v = 1'b1;             // isolated
        if (x==40 && y==2)  v = 1'b1;             // isolated
        if (x==80 && y==12) v = 1'b1;             // isolated
        if (x==100 && y==6) v = 1'b1;             // isolated
        px = v;
    end endfunction

    function exp_px; input integer x; input integer y; reg v; begin
        v = 1'b0;
        if (y==5 && x>=5 && x<=59) v = 1'b1;      // line interior (endpoints may be trimmed)
        if (x==20 && y>=2 && y<=13) v = 1'b1;     // vertical line interior
        exp_px = v;
    end endfunction

    integer errors=0, checked=0, i,c,f,y,p;
    initial begin
        in_valid=0; in_hs=0; in_vs=0; in_edge2=0;
        rstn=0; repeat(10) @(posedge clk); rstn=1; @(posedge clk);
        for (f=0; f<6; f=f+1) begin
            @(negedge clk); in_vs=1'b1; repeat(8) @(posedge clk); in_vs=1'b0;
            for (y=0;y<NL;y=y+1) begin
                @(negedge clk); in_hs=1'b1;
                @(posedge clk); in_hs=1'b0;
                for (p=0;p<NP;p=p+1) begin
                    @(negedge clk); in_valid=1'b1;
                    in_edge2[0] = px(2*p,   y);
                    in_edge2[1] = px(2*p+1, y);
                    @(posedge clk);
                end
                @(negedge clk); in_valid=1'b0; repeat(4) @(posedge clk);
            end
            repeat(30) @(posedge clk);
        end
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
        if (errors==0) $display("PASS: isolated edge pixels removed, lines kept");
        else           $display("FAIL");
        $finish;
    end
    initial begin #4000000; $display("timeout"); $finish; end
endmodule
