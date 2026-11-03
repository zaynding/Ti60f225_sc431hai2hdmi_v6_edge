`timescale 1ns/1ps
//======================================================================================================
// jtag_demo_loader.v - fills the saved-frame slots in DDR from the PC over the on-chip JTAG USER1 TAP.
//
//   PC (tools/jtag_load_demo.py)  --JTAG USER1-->  [TCK domain shifter]  --toggle CDC-->  [core_clk AXI writer]
//
// Every JTAG DR scan is   64-bit header  +  optional payload  (all LSB first, byte 0 first):
//     header[7:0]   cmd      0 STATUS  (nothing, just read the status that is shifted out)
//                            1 HOLD    (freeze camera writes, then take over the DDR write channel)
//                            2 WRITE   (payload = nwords x 128 bit, stored from byte address `addr`)
//                            3 DONE    (mark slots in nwords[3:0], give the DDR write channel back)
//                            4 CLEAR   (clear sticky error flags)
//     header[31:8]  nwords   (WRITE: payload word count, checked;  DONE: slot mask)
//     header[63:32] addr     (WRITE: byte address of the first word, 16-byte aligned)
// The 64 bits shifted out while the header is shifted in are the status word:
//     [0] grant  [1] hold  [2] overrun  [3] word-count error  [4] bresp error  [5] writer busy  [6] watchdog
//     [11:8] loaded-slot mask  [47:16] words acknowledged by DDR  [63:48] 0xA55A
//
// A 128-bit word needs >=128 TCK cycles to shift in, the DDR side needs a few dozen clk cycles to write
// it, so no FIFO is needed; an overrun flag catches a host that is faster than the DDR (it cannot be).
//======================================================================================================
module jtag_demo_loader #(
    parameter integer QUIET_CYCLES = 2000000,      // camera write channel must be idle this long (20 ms @ 100 MHz)
    parameter integer WD_CYCLES    = 1000000000    // 10 s without a host word: give everything back
)(
    // JTAG USER TAP (BSCAN style, all synchronous to tck)
    input  wire         tck,
    input  wire         tdi,
    output wire         tdo,
    input  wire         sel,
    input  wire         shift,
    input  wire         capture,
    input  wire         update,
    // DDR AXI clock domain
    input  wire         clk,
    input  wire         rst_n,
    input  wire         fb_busy,        // camera frame-buffer still drives the write channel
    output wire         hold_req,       // freeze camera capture
    output reg          grant,          // loader owns the write channel
    output reg  [31:0]  awaddr,
    output reg          awvalid,
    input  wire         awready,
    output reg  [127:0] wdata,
    output reg          wvalid,
    input  wire         wready,
    input  wire         bvalid,
    input  wire [1:0]   bresp,
    output reg  [3:0]   preload_mask,   // sticky: slots that now hold demo frames
    output reg          preload_tog     // toggles every time preload_mask is updated
);
localparam [7:0] CMD_STATUS = 8'd0, CMD_HOLD = 8'd1, CMD_WRITE = 8'd2, CMD_DONE = 8'd3, CMD_CLEAR = 8'd4;

//------------------------------------------------------------------------------------------------
// TCK domain
//------------------------------------------------------------------------------------------------
reg  [63:0]  hsr     = 64'd0;
reg  [127:0] sr      = 128'd0;
reg  [7:0]   bc      = 8'd0;
reg          phase   = 1'b0;           // 0: header, 1: payload
reg  [7:0]   cmd     = 8'd0;
reg  [23:0]  nwords  = 24'd0;
reg  [23:0]  wrcv    = 24'd0;
reg  [31:0]  waddr   = 32'd0;
reg          wtog    = 1'b0;
reg  [127:0] whold   = 128'd0;
reg  [31:0]  waddr_h = 32'd0;
reg          hold_en = 1'b0;
reg          done_tog = 1'b0;
reg  [3:0]   done_mask = 4'd0;
reg          clr_tog = 1'b0;
reg          cnt_err = 1'b0;
reg  [63:0]  st_sr   = 64'd0;
wire [63:0]  status_core;               // core_clk domain, quasi static
reg  [63:0]  st_s1 = 64'd0, st_s2 = 64'd0;

wire [63:0]  hnext = {tdi, hsr[63:1]};
assign tdo = st_sr[0];

wire [63:0] status_tck = {st_s2[63:48], st_s2[47:16], st_s2[15:8], 1'b0, st_s2[6:4], cnt_err, st_s2[2:0]};

always @(posedge tck) begin
    st_s1 <= status_core;
    st_s2 <= st_s1;
    if (sel & capture) begin
        st_sr <= status_tck;
        bc    <= 8'd0;
        phase <= 1'b0;
        wrcv  <= 24'd0;
    end else if (sel & shift) begin
        st_sr <= {1'b0, st_sr[63:1]};
        if (!phase) begin
            hsr <= hnext;
            if (bc == 8'd63) begin
                bc     <= 8'd0;
                phase  <= 1'b1;
                cmd    <= hnext[7:0];
                nwords <= hnext[31:8];
                waddr  <= {hnext[63:36], 4'b0000};
            end else
                bc <= bc + 8'd1;
        end else begin
            sr <= {tdi, sr[127:1]};
            if (bc == 8'd127) begin
                bc <= 8'd0;
                if (cmd == CMD_WRITE) begin
                    whold   <= {tdi, sr[127:1]};
                    waddr_h <= waddr;
                    waddr   <= waddr + 32'd16;
                    wtog    <= ~wtog;
                    wrcv    <= wrcv + 24'd1;
                end
            end else
                bc <= bc + 8'd1;
        end
    end else if (sel & update) begin
        if (phase) begin
            case (cmd)
                CMD_HOLD:  begin hold_en <= 1'b1; clr_tog <= ~clr_tog; cnt_err <= 1'b0; end
                CMD_WRITE: if (bc != 8'd0 || wrcv != nwords) cnt_err <= 1'b1;
                CMD_DONE:  begin hold_en <= 1'b0; done_mask <= nwords[3:0]; done_tog <= ~done_tog; end
                CMD_CLEAR: begin clr_tog <= ~clr_tog; cnt_err <= 1'b0; end
                default: ;
            endcase
        end
    end
end

//------------------------------------------------------------------------------------------------
// core_clk domain
//------------------------------------------------------------------------------------------------
reg [1:0] hold_s;
reg [2:0] wtog_s, done_s, clr_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin hold_s <= 2'b00; wtog_s <= 3'b000; done_s <= 3'b000; clr_s <= 3'b000; end
    else begin
        hold_s <= {hold_s[0], hold_en};
        wtog_s <= {wtog_s[1:0], wtog};
        done_s <= {done_s[1:0], done_tog};
        clr_s  <= {clr_s[1:0],  clr_tog};
    end
end
wire wnew       = wtog_s[2] ^ wtog_s[1];
wire done_event = done_s[2] ^ done_s[1];
wire clr_event  = clr_s[2]  ^ clr_s[1];

localparam [1:0] S_IDLE = 2'd0, S_QUIET = 2'd1, S_GRANT = 2'd2;
reg [1:0]  state;
reg [31:0] q_cnt;
reg [31:0] wd_cnt;
reg        wd_exp;
reg        busy;
reg        ovf, bresp_err;
reg [31:0] wcnt;
reg        done_pend;
reg [3:0]  mask_pend;

wire hold_eff = hold_s[1] & ~wd_exp;
assign hold_req = hold_eff | (state != S_IDLE);

assign status_core = {16'hA55A, wcnt, 4'd0, preload_mask, 1'b0, wd_exp, busy, bresp_err, 1'b0, ovf, hold_eff, grant};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE; q_cnt <= 32'd0; wd_cnt <= 32'd0; wd_exp <= 1'b0; grant <= 1'b0;
        busy <= 1'b0; ovf <= 1'b0; bresp_err <= 1'b0; wcnt <= 32'd0;
        awvalid <= 1'b0; wvalid <= 1'b0; awaddr <= 32'd0; wdata <= 128'd0;
        preload_mask <= 4'd0; preload_tog <= 1'b0; done_pend <= 1'b0; mask_pend <= 4'd0;
    end else begin
        // ---- host watchdog -------------------------------------------------------------------
        if (!hold_s[1]) begin wd_cnt <= 32'd0; wd_exp <= 1'b0; end
        else if (wnew)  wd_cnt <= 32'd0;
        else if (wd_cnt == WD_CYCLES) wd_exp <= 1'b1;
        else wd_cnt <= wd_cnt + 32'd1;

        if (clr_event) begin ovf <= 1'b0; bresp_err <= 1'b0; wcnt <= 32'd0; wd_cnt <= 32'd0; wd_exp <= 1'b0; end   // HOLD/CLEAR re-arm the watchdog
        if (done_event) begin done_pend <= 1'b1; mask_pend <= done_mask; end

        // ---- DDR single-beat writer ---------------------------------------------------------
        if (awvalid & awready) awvalid <= 1'b0;
        if (wvalid  & wready)  wvalid  <= 1'b0;
        if (busy & bvalid) begin
            busy <= 1'b0;
            wcnt <= wcnt + 32'd1;
            if (bresp != 2'b00) bresp_err <= 1'b1;
        end
        if (wnew) begin
            if (grant && !busy) begin
                awaddr  <= waddr_h;
                wdata   <= whold;
                awvalid <= 1'b1;
                wvalid  <= 1'b1;
                busy    <= 1'b1;
            end else
                ovf <= 1'b1;
        end

        // ---- bus ownership ------------------------------------------------------------------
        case (state)
            S_IDLE: begin
                q_cnt <= 32'd0;
                if (hold_eff) state <= S_QUIET;
                else if (done_pend) begin
                    preload_mask <= preload_mask | mask_pend;
                    if (|mask_pend) preload_tog <= ~preload_tog;        // DONE with an empty mask only releases the bus
                    done_pend <= 1'b0;
                end
            end
            S_QUIET: begin
                if (!hold_eff) state <= S_IDLE;
                else if (fb_busy) q_cnt <= 32'd0;
                else if (q_cnt == QUIET_CYCLES) begin grant <= 1'b1; state <= S_GRANT; end
                else q_cnt <= q_cnt + 32'd1;
            end
            S_GRANT: begin
                if (!hold_eff && !busy && !awvalid && !wvalid && !wnew) begin
                    grant <= 1'b0;
                    state <= S_IDLE;
                end
            end
            default: state <= S_IDLE;
        endcase
    end
end
endmodule
