
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2021 Efinix Inc. All rights reserved.
//
// Description:
// Example top file for ti60f225 dev kit OOB design
//
// Language:  Verilog 2001
//Ti60f225_sc431hai2hdmi_v6：
//使用了最新版本的framebuffer_v3;
// ------------------------------------------------------------------------------

/////////////////////////////////////////////////////////////////////////////////
//`define SOFT_TAP 1
`include "ddr3_controller/ddr3_parameter.vh"
// `include "define.v"

module ti60f225_oob_top #(

	parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
	parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
	parameter                       RANKS              = `RANKS,
	parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
	parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
	parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
	parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
	parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
	parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
	parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
	parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
	parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
	parameter                       ODT_WIDTH          = `ODT_WIDTH,
	parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
	parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
	parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
	parameter                       DATA_WIDTH         = `DATA_WIDTH,
	parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
	parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
	parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
	parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,

   //Clocks 
	input	wire	i_arstn,
    input	wire	i_mipi_rx_pclk,
    input wire  vid_clk_dvi2,
    input wire hdmi_tx_slow_clk,
    input wire CLK_5M,
    input  wire CLK_25M,
	output  wire    pll_inst1_RSTN,
	input	wire	i_pll_locked,
	input 	wire  	pll_locked,
	output  wire    pll_inst4_RSTN,
	input   wire    pll_inst4_LOCKED,
	output  wire  	USER_PLL_RSTN,
    output 	wire 	DDR3_PLL_RSTN,
	input 	wire  	user_pll_locked,
    //CSI Interface
    input	 wire		io_cam_sda_IN,
    output wire   io_cam_sda_OUT,
    output wire		io_cam_sda_OE,

    output io_cam_scl_OUT,
    input io_cam_scl_IN,
    output io_cam_scl_OE,

    output	wire		o_cam_rst_p,
    
    input	wire		i_cam_ck_LP_P_IN,
    input	wire		i_cam_ck_LP_N_IN,
    output	wire		o_cam_ck_HS_TERM,
    output	wire		o_cam_ck_HS_ENA,
    input	wire		i_cam_ck_CLKOUT,
    
    input	wire	[7:0]			cam_d0_HS_IN,
    input	  wire		      cam_d0_LP_P_IN,
    input	  wire		      cam_d0_LP_N_IN,
    output	wire		      cam_d0_HS_TERM,
    output	wire		      cam_d0_HS_ENA,
    output	wire		      cam_d0_RST,
    output	wire		      cam_d0_FIFO_RD,
    input	  wire		      cam_d0_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d1_HS_IN,
    input	  wire		        cam_d1_LP_P_IN,
    input	  wire		        cam_d1_LP_N_IN,
    output	wire		        cam_d1_HS_TERM,
    output	wire		        cam_d1_HS_ENA,
    output	wire		        cam_d1_RST,
    output	wire		        cam_d1_FIFO_RD,
    input	  wire		        cam_d1_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d2_HS_IN,
    input	  wire		        cam_d2_LP_P_IN,
    input	  wire		        cam_d2_LP_N_IN,
    output	wire		        cam_d2_HS_TERM,
    output	wire		        cam_d2_HS_ENA,
    output	wire		        cam_d2_RST,
    output	wire		        cam_d2_FIFO_RD,
    input	  wire		        cam_d2_FIFO_EMPTY,  
   
    input 	wire	[7:0]			cam_d3_HS_IN,
    input	  wire		        cam_d3_LP_P_IN,
    input	  wire		        cam_d3_LP_N_IN,
    output	wire		        cam_d3_HS_TERM,
    output	wire		        cam_d3_HS_ENA,
    output	wire		        cam_d3_RST,
    output	wire		        cam_d3_FIFO_RD,
    input	  wire		        cam_d3_FIFO_EMPTY,

	
	input 					tx_cal_clk_90edge,
  	input 					rx_cal_clk,
  	input 					tx_cal_clk,
	input                              core_clk,     // CORE CLK @ 100MHz
	input                              sdram_clk,    // SDRAM CK @ 400MHz
	// PLL status flags  
	output [2:0]                       pll_shift,  
	output [4:0]                       pll_shift_sel,
	output                             pll_shift_ena,  
	// memory interface ports
	output                             ddr_ck_hi,
	output                             ddr_ck_lo,
	output                             ddr_reset_n,
	output [CKE_WIDTH-1:0]             ddr_cke,     
	output [ROW_WIDTH-1:0]             ddr_addr,
	output [BANK_WIDTH-1:0]            ddr_ba,
	output                             ddr_cas_n,
 
	output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
	output                             ddr_ras_n,
	output                             ddr_we_n,
	
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
	
	output [DQS_WIDTH-1:0]             ddr_dqs_oe,
	output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
	output [DQ_WIDTH-1:0]              ddr_dq_oe,  
	output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
	output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
	output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
	output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
	output [DM_WIDTH-1:0]              ddr_dm_hi,
	output [DM_WIDTH-1:0]              ddr_dm_lo,
	output [ODT_WIDTH-1:0]             ddr_odt,

       //LED
       input  [3:0] key_i,          // KEY0..KEY3, active low (3.3V, external pull-up)

       // MIPI DSI
       input	wire	                     i_mipi_tx_pclk		,
       output	wire	                     mipi_dp_clk_LP_P_OUT		,
       output	wire	                     mipi_dp_clk_LP_N_OUT		,
       output	wire	[7:0] 	              mipi_dp_clk_HS_OUT		,
       output	wire	                     mipi_dp_clk_HS_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OUT	,
       output	wire	                     mipi_dp_data2_LP_P_OUT	,
       output	wire	                     mipi_dp_data1_LP_P_OUT	,
       output	wire	                     mipi_dp_data0_LP_P_OUT	,
       output	wire	                     mipi_dp_data3_LP_N_OUT	,
       output	wire	                     mipi_dp_data2_LP_N_OUT	,
       output	wire	                     mipi_dp_data1_LP_N_OUT	,
       output	wire	                     mipi_dp_data0_LP_N_OUT	,
       output	wire	[7:0] 	              mipi_dp_data0_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data1_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data2_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data3_HS_OUT	       ,
       output	wire	                     mipi_dp_data3_HS_OE		,
       output	wire	                     mipi_dp_data2_HS_OE		,
       output	wire	                     mipi_dp_data1_HS_OE		,
       output	wire	                     mipi_dp_data0_HS_OE		,

       output	wire	                     mipi_dp_clk_RST		,
       output	wire	                     mipi_dp_data0_RST		,
       output	wire	                     mipi_dp_data1_RST		,
       output	wire	                     mipi_dp_data2_RST		,
       output	wire	                     mipi_dp_data3_RST		,
       output	wire	                     mipi_dp_clk_LP_P_OE		,
       output	wire	                     mipi_dp_clk_LP_N_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OE	,
       output	wire	                     mipi_dp_data3_LP_N_OE	,
       output	wire	                     mipi_dp_data2_LP_P_OE	,
       output	wire	                     mipi_dp_data2_LP_N_OE	,
       output	wire	                     mipi_dp_data1_LP_P_OE	,
       output	wire	                     mipi_dp_data1_LP_N_OE	,
       output	wire	                     mipi_dp_data0_LP_P_OE	,
       output	wire	                     mipi_dp_data0_LP_N_OE	,

       input  wire	                     mipi_dp_data0_LP_P_IN	,
       input  wire	                     mipi_dp_data0_LP_N_IN	,
       output	wire	                     LCD_RST_P			,
       output wire                        LCD_POWER			,

       // hdmi interface

    output tmds_tx_clk_TX_OE,
    output [9:0] tmds_tx_clk_TX_DATA,
    output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE,
    output [9:0] tmds_tx_data0_TX_DATA,
    output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE,
    output [9:0] tmds_tx_data1_TX_DATA,
    output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE,
    output [9:0] tmds_tx_data2_TX_DATA,
    output tmds_tx_data2_TX_RST


);

function integer log2;
	input	integer	val;
	integer	i;
	begin
		log2 = 0;
		for (i=0; 2**i<val; i=i+1)
			log2 = i+1;
	end
endfunction


//===============================================================================
//localparam
//===============================================================================
localparam WR_FIFO_DEPTH  = 1024;
localparam RD_FIFO_DEPTH  = 1024;

// localparam	MAX_HRES		= 12'd1920;
// localparam	MAX_VRES		= 12'd1080;
// localparam	HSP			= 8'd2;
// localparam	HBP			= 8'd88;
// localparam	HFP			= 8'd120;
// localparam	VSP			= 8'd2;
// localparam	VBP			= 8'd20;
// localparam	VFP			= 8'd20;

localparam MAX_HRES = 1920;
localparam HFP      = 88;
localparam HSP      = 44;
localparam HBP      = 148;

localparam MAX_VRES = 1080;
localparam VFP      = 4;
localparam VSP      = 5;
localparam VBP      = 36;
//===============================================================================
//signal
//===============================================================================
   
wire                              app_sr_active;
wire                              app_ref_ack;
wire                              app_zq_ack;
wire                              cal_done;

// Slave Interface Write Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
wire [7:0]                        s_axi_awlen;
wire [2:0]                        s_axi_awsize;
wire [1:0]                        s_axi_awburst;
wire [0:0]                        s_axi_awlock;
wire [3:0]                        s_axi_awcache;
wire [2:0]                        s_axi_awprot;
wire                              s_axi_awvalid;
wire                              s_axi_awready;
// Slave Interface Write Data Ports
wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
wire                              s_axi_wlast;
wire                              s_axi_wvalid;
wire                              s_axi_wready;
// Slave Interface Write Response Ports
wire                              s_axi_bready;
wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
wire [1:0]                        s_axi_bresp;
wire                              s_axi_bvalid;
// Slave Interface Read Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
wire [7:0]                        s_axi_arlen;
wire [2:0]                        s_axi_arsize;
wire [1:0]                        s_axi_arburst;
wire [0:0]                        s_axi_arlock;
wire [3:0]                        s_axi_arcache;
wire [2:0]                        s_axi_arprot;
wire                              s_axi_arvalid;
wire                              s_axi_arready;
// Slave Interface Read Data Ports
wire                              s_axi_rready;
wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
wire [1:0]                        s_axi_rresp;
wire                              s_axi_rlast;
wire                              s_axi_rvalid;

// Camera frame-buffer AXI master
wire [5:0]  fb0_awid;
wire [31:0] fb0_awaddr;
wire [7:0]  fb0_awlen;
wire [2:0]  fb0_awsize;
wire [1:0]  fb0_awburst;
wire [3:0]  fb0_awcache;
wire [2:0]  fb0_awprot;
wire        fb0_awlock;
wire        fb0_awvalid;
wire        fb0_awready;
wire [127:0] fb0_wdata;
wire [15:0]  fb0_wstrb;
wire         fb0_wlast;
wire         fb0_wvalid;
wire         fb0_wready;
wire [5:0]   fb0_bid;
wire [1:0]   fb0_bresp;
wire         fb0_bvalid;
wire         fb0_bready;
wire [5:0]   fb0_arid;
wire [31:0]  fb0_araddr;
wire [7:0]   fb0_arlen;
wire [2:0]   fb0_arsize;
wire [1:0]   fb0_arburst;
wire [3:0]   fb0_arcache;
wire [2:0]   fb0_arprot;
wire         fb0_arlock;
wire         fb0_arvalid;
wire         fb0_arready;
wire [5:0]   fb0_rid;
wire [127:0] fb0_rdata;
wire [1:0]   fb0_rresp;
wire         fb0_rlast;
wire         fb0_rvalid;
wire         fb0_rready;

// Full-frame display-cache AXI master
wire [5:0]  fb1_awid;
wire [31:0] fb1_awaddr;
wire [7:0]  fb1_awlen;
wire [2:0]  fb1_awsize;
wire [1:0]  fb1_awburst;
wire [3:0]  fb1_awcache;
wire [2:0]  fb1_awprot;
wire        fb1_awlock;
wire        fb1_awvalid;
wire        fb1_awready;
wire [127:0] fb1_wdata;
wire [15:0]  fb1_wstrb;
wire         fb1_wlast;
wire         fb1_wvalid;
wire         fb1_wready;
wire [5:0]   fb1_bid;
wire [1:0]   fb1_bresp;
wire         fb1_bvalid;
wire         fb1_bready;
wire [5:0]   fb1_arid;
wire [31:0]  fb1_araddr;
wire [7:0]   fb1_arlen;
wire [2:0]   fb1_arsize;
wire [1:0]   fb1_arburst;
wire [3:0]   fb1_arcache;
wire [2:0]   fb1_arprot;
wire         fb1_arlock;
wire         fb1_arvalid;
wire         fb1_arready;
wire [5:0]   fb1_rid;
wire [127:0] fb1_rdata;
wire [1:0]   fb1_rresp;
wire         fb1_rlast;
wire         fb1_rvalid;
wire         fb1_rready;

wire [5:0]   ic_awid;
wire [5:0]   ic_arid;
wire [1:0]   ic_awlock;
wire [1:0]   ic_arlock;




////////////////////////////////////////////////////////////////
// System & Debugger
wire    w_arstn;
// wire	w_sysclk_mcu_arstn;
// wire	w_sysclk_mcu_arst;
wire	w_mipi_rx_pclk_arstn;
wire	w_mipi_rx_pclk_arst;

wire		       w_mipi_rx_vs;
wire		       w_mipi_rx_hs;
wire	       w_mipi_rx_de;
wire	[63:0]			w_mipi_rx_data	;

wire					io_systemReset;



//===================================================================================================
//reset module
//===================================================================================================

assign w_arstn  		       = i_pll_locked & pll_locked & user_pll_locked;
assign pll_inst1_RSTN  		= i_arstn;
assign USER_PLL_RSTN      		= i_arstn;
assign mipi_dsi_tx_pll_RSTN 	= i_arstn;
assign DDR3_PLL_RSTN 		= i_arstn;
reset_ctrl
#(
	.NUM_RST		(2),
	.CYCLE			(1),
	.IN_RST_ACTIVE	(4'b00),
	.OUT_RST_ACTIVE	(4'b10)
)
inst_reset_ctrl
(
	.i_arst		({2{w_arstn}}),//({{4{i_pll_locked}},                  {2{i_arstn}}}),
	.i_clk			({2{i_mipi_rx_pclk}}),
	.o_srst		({w_mipi_rx_pclk_arst, w_mipi_rx_pclk_arstn})
);



reg [25:0] cnt = 'd0;
always @( posedge core_clk)
begin 
       cnt <= cnt + 1'b1;
end

//========================================================================================================
//MIPI RX
//========================================================================================================
wire i_mipi_clk ;
assign i_mipi_clk = core_clk;

		assign	cam_d0_RST		= 1'b0;
		assign	cam_d1_RST		= 1'b0;
		assign  cam_d2_RST = 1'b0;
    assign  cam_d3_RST = 1'b0;
	
wire [15:0] mipi_debug_out;
		

		csi_rx_controller inst_efx_csi2_rx
		(
              .reset_n			(i_arstn),
              .clk				(i_mipi_clk),
              .reset_byte_HS_n	(i_arstn),
              .clk_byte_HS		  (i_cam_ck_CLKOUT),
              .reset_pixel_n		(w_mipi_rx_pclk_arstn),
              .clk_pixel			  (i_mipi_rx_pclk),
              
              .Rx_LP_CLK_P		  (i_cam_ck_LP_P_IN),
              .Rx_LP_CLK_N		  (i_cam_ck_LP_N_IN),
              .Rx_HS_enable_C		(o_cam_ck_HS_ENA),
              .LVDS_termen_C		(o_cam_ck_HS_TERM),
              
              .Rx_LP_D_P			({cam_d3_LP_P_IN, cam_d2_LP_P_IN, cam_d1_LP_P_IN, cam_d0_LP_P_IN}),//(r_mipi_rx_data_LP_P_IN_2P),
              .Rx_LP_D_N			({cam_d3_LP_N_IN, cam_d2_LP_N_IN, cam_d1_LP_N_IN, cam_d0_LP_N_IN}),//(r_mipi_rx_data_LP_N_IN_2P),
              .Rx_HS_D_0			(cam_d0_HS_IN),//(r_mipi_rx_data_HS_IN_2P[0*8+:8]),
              .Rx_HS_D_1			(cam_d1_HS_IN),//(r_mipi_rx_data_HS_IN_2P[1*8+:8]),
              .Rx_HS_D_2			(cam_d2_HS_IN),
              .Rx_HS_D_3			(cam_d3_HS_IN),
              .Rx_HS_D_4			(),
              .Rx_HS_D_5			(),
              .Rx_HS_D_6			(),
              .Rx_HS_D_7			(),
              .Rx_HS_enable_D		({cam_d3_HS_ENA    ,cam_d2_HS_ENA    ,cam_d1_HS_ENA    ,cam_d0_HS_ENA    }),//( w_cam_d_HS_ENA),
              .LVDS_termen_D		({cam_d3_HS_TERM   ,cam_d2_HS_TERM   ,cam_d1_HS_TERM   ,cam_d0_HS_TERM   }),
              .fifo_rd_enable		({cam_d3_FIFO_RD   ,cam_d2_FIFO_RD   ,cam_d1_FIFO_RD   ,cam_d0_FIFO_RD   }),
              .fifo_rd_empty		({cam_d3_FIFO_EMPTY,cam_d2_FIFO_EMPTY,cam_d1_FIFO_EMPTY,cam_d0_FIFO_EMPTY}),
              .DLY_enable_D		       (),
              .DLY_inc_D			(),
              .u_dly_enable_D		(),
              .u_dly_inc_D		       (),
              
              .axi_clk			(1'b0),
              .axi_reset_n		       (1'b0),
              .axi_awaddr			(6'b0),
              .axi_awvalid		       (1'b0),
              .axi_awready		       (),
              .axi_wdata			(32'b0),
              .axi_wvalid			(1'b0),
              .axi_wready			(),
              
              .axi_bvalid			(),
              .axi_bready			(1'b0),
              .axi_araddr			(6'b0),
              .axi_arvalid		       (1'b0),
              .axi_arready		       (),
              .axi_rdata			(),
              .axi_rvalid			(),
              .axi_rready			(1'b1),
              
              .hsync_vc0			(w_mipi_rx_hs),
              .hsync_vc1			(),
              .hsync_vc2			(),
              .hsync_vc3			(),
              .vsync_vc0			(w_mipi_rx_vs),
              .vsync_vc1			(),
              .vsync_vc2			(),
              .vsync_vc3			(),
              .vc				(),
              .word_count			(),
              .shortpkt_data_field        (),
              .datatype			(),
              .pixel_per_clk		(),
              .pixel_data			(w_mipi_rx_data),
              .pixel_data_valid	       (w_mipi_rx_de),
              .irq				(),
              .mipi_debug_out(mipi_debug_out)
		);

//     wire		       w1_mipi_rx_vs;
// wire		       w1_mipi_rx_hs;
// wire	       w1_mipi_rx_de;
// wire	[39:0]			w1_mipi_rx_data	;
// sensor_clipper  sensor_clipper_inst (
//     .clk(i_mipi_rx_pclk),
//     .i_vs(w_mipi_rx_vs),
//     .i_hs(w_mipi_rx_hs),
//     .i_de(w_mipi_rx_de),
//     .i_dat(w_mipi_rx_data[39:0]),

//     .o_hs(w1_mipi_rx_hs),
//     .o_vs(w1_mipi_rx_vs),
//     .o_de(w1_mipi_rx_de),
//     .o_dat(w1_mipi_rx_data)
   
//   );


wire mdebug_pixel_fifo_full     = mipi_debug_out[0] ;
wire mdebug_pixel_fifo_empty    = mipi_debug_out[1] ;
wire mdebug_crc_error           = mipi_debug_out[2] ;
wire mdebug_ecc_1bit_error      = mipi_debug_out[3] ;
wire mdebug_ecc_2bit_error      = mipi_debug_out[4] ;
wire mdebug_undersize_pkt_error = mipi_debug_out[5] ;
wire mdebug_line_vc0_error      = mipi_debug_out[6] ;
wire mdebug_frame_vc0_error    = mipi_debug_out[10];   
wire mdebug_receive_error      = mipi_debug_out[14];


//========================================================================================================
//
//========================================================================================================
		

//*************** imx219 config********************/
// mipi_config_imx219_top u_config_imx219(
// 										.i_sys_clk(CLK_5M)    	,    /////48M 
// 										.sys_rstn(vid_rst_n )    ,
// 										.o_sen_rst_n(o_cam_rstn)  	,
										
										// .o_iic_sda_OE(io_cam_sda_OE) ,
										// .i_iic_sda(io_cam_sda_IN)   	,
										// .o_iic_sda(io_cam_sda_OUT)   	,
										// .o_iic_scl(io_cam_scl)    	
										// ); 	

wire scl_padoen_o;
wire sda_padoen_o;


reg [12:0] i2c_rst_cnt = '0;

always @( posedge CLK_5M or negedge w_arstn )
begin
    if( !w_arstn )
       i2c_rst_cnt <= 'd0;
    else 
       i2c_rst_cnt <= i2c_rst_cnt[12] ? i2c_rst_cnt : i2c_rst_cnt + 1'b1;
end
wire i2c_rst_n = i2c_rst_cnt[12];

i2c_master_ctrl_top u2_i2c_master_ctrl_top(
  /*i*/.clk			(CLK_5M		),
  /*i*/.rst_n			(i2c_rst_n		),
  /*i*/.scl_pad_i     (io_cam_scl_IN),//(1'b1),
  /*o*/.scl_pad_o     (io_cam_scl_OUT),
  /*o*/.scl_padoen_o  (scl_padoen_o),
  /*i*/.sda_pad_i     (io_cam_sda_IN),
  /*o*/.sda_pad_o     (io_cam_sda_OUT),
  /*o*/.sda_padoen_o  (sda_padoen_o)
  
  );
assign o_cam_rst_p = ~w_arstn;
assign io_cam_scl_OE = ~scl_padoen_o;
assign io_cam_sda_OE = ~sda_padoen_o;

//=====================================================================================
//frame buffer
//=====================================================================================
wire [7:0] 	ch0_r;
wire [7:0]    ch0_g;
wire [7:0]    ch0_b;
wire ch0_vs;
wire ch0_hs;
wire ch0_de;
wire [5:0]   fbm_awid;
wire [31:0]  fbm_awaddr;
wire [7:0]   fbm_awlen;
wire [2:0]   fbm_awsize;
wire [1:0]   fbm_awburst;
wire [2:0]   fbm_awprot;
wire [3:0]   fbm_awcache;
wire         fbm_awlock;
wire         fbm_awvalid;
wire         fbm_awready;
wire [127:0] fbm_wdata;
wire [15:0]  fbm_wstrb;
wire         fbm_wlast;
wire         fbm_wvalid;
wire         fbm_wready;
wire [5:0]   fbm_bid;
wire         fbm_bvalid;
wire         fbm_bready;

wire         ld_grant;
wire         ld_hold_req;
wire [3:0]   ld_preload_mask;
wire         ld_preload_tog;
wire [31:0]  ld_awaddr;
wire         ld_awvalid;
wire [127:0] ld_wdata;
wire         ld_wvalid;
wire frame_freeze;
wire [2:0] view_mode;
wire       snapshot_toggle;
wire       clear_saved_toggle;
wire [3:0] saved_valid;
// IMX219
  frame_buffer #(
.I_VID_WIDTH         (32),
.O_VID_WIDTH         (16),
.START_ADDR          (32'h00000        ),
.AXI_DATA_WIDTH      ( AXI_DATA_WIDTH	),
.AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH	),
.WR_FIFO_DEPTH	      ( 1024		),    
.RD_FIFO_DEPTH 	      ( 1024 	),
.BURST_LEN  	       (127),
.FB_NUM	            (3),
.MAX_VID_WIDTH	    (960) ,
.MAX_VID_HIGHT	    (1080) 


)checker0(
       .axi_clk		(core_clk 	        ),
       .rst_n			(vid_rst_n   ),
       .freeze          (frame_freeze       ),
       .view_mode        (view_mode          ),
       .snapshot_toggle (snapshot_toggle    ),
       .clear_saved_toggle(clear_saved_toggle),
       .saved_valid      (saved_valid         ),
       .ext_hold         (ld_hold_req        ),
       .preload_set      (ld_preload_mask    ),

/*i*/.i_clk			(i_mipi_rx_pclk      ),
/*i*/.i_vs			(w_mipi_rx_vs	),
/*i*/.i_de			(w_mipi_rx_de & w_mipi_rx_hs	),
/*i*/.vin 			({w_mipi_rx_data[39:32],w_mipi_rx_data[29:22],w_mipi_rx_data[19:12],w_mipi_rx_data[9:2]}	),
                     
/*i*/.o_clk			(vid_clk_dvi2),//(i_mipi_rx_pclk	),
/*i*/.o_hs    		(ch0_hs		),			
/*i*/.o_vs    		(ch0_vs		),			
/*i*/.o_de    		(ch0_de		),			
/*i*/.vout    		({ch0_g,ch0_b}	),//ch0_r,

/*i*/.H_FRONT_PORCH (HFP/2  		),//
/*i*/.H_SYNC 	 	    (HSP/2	 	),///2
/*i*/.H_VALID 	 	  (MAX_HRES/2     ),//		
/*i*/.H_BACK_PORCH	(HBP/2		),//		
/*i*/.V_FRONT_PORCH (VFP  		),//		
/*i*/.V_SYNC 	 	    (VSP 	 	),//		
/*i*/.V_VALID 	 	  (MAX_VRES     ),//		
/*i*/.V_BACK_PORCH	(VBP		),//		

       .awid			(fbm_awid),      
       .awaddr		(fbm_awaddr),
       .awlen			(fbm_awlen),
       .awsize		(fbm_awsize),
       .awburst		(fbm_awburst),
       .awprot    (fbm_awprot),
       .awcache   (fbm_awcache),
       .awlock		(fbm_awlock),
       .awvalid		(fbm_awvalid),
       .awready		(fbm_awready),

       .arid			(s_axi_arid	  ),
       .araddr		(s_axi_araddr	),
       .arlen			(s_axi_arlen	),
       .arsize		(s_axi_arsize	),
       .arburst 	(s_axi_arburst),

       .arprot    (s_axi_arprot ),
       .arcache   (s_axi_arcache),
       .arlock 		(s_axi_arlock	),
       .arvalid		(s_axi_arvalid),
       .arready		(s_axi_arready),

       .wdata			(fbm_wdata),
       .wstrb			(fbm_wstrb),
       .wlast			(fbm_wlast),
       .wvalid		(fbm_wvalid),
       .wready		(fbm_wready),


       .rid			  (s_axi_rid	),
       .rdata			(s_axi_rdata	),
       .rlast			(s_axi_rlast	),
       .rvalid 		(s_axi_rvalid	),
       .rready		(s_axi_rready	),
       .rresp			(s_axi_rresp	),

       .bid			  (fbm_bid),
       .bvalid		(fbm_bvalid),
       .bready	  (fbm_bready)
);

// ---- DDR write-channel mux: camera frame_buffer <-> JTAG demo loader -----------------------------------
// The loader only owns the channel while the camera write path has been frozen and has gone quiet.
assign s_axi_awid    = ld_grant ? {AXI_ID_WIDTH{1'b0}} : fbm_awid[AXI_ID_WIDTH-1:0];
assign s_axi_awaddr  = ld_grant ? ld_awaddr  : fbm_awaddr;
assign s_axi_awlen   = ld_grant ? 8'd0       : fbm_awlen;
assign s_axi_awsize  = ld_grant ? 3'd4       : fbm_awsize;
assign s_axi_awburst = ld_grant ? 2'b01      : fbm_awburst;
assign s_axi_awlock  = ld_grant ? 1'b0       : fbm_awlock;
assign s_axi_awcache = ld_grant ? 4'd3       : fbm_awcache;
assign s_axi_awprot  = ld_grant ? 3'd2       : fbm_awprot;
assign s_axi_awvalid = ld_grant ? ld_awvalid : fbm_awvalid;
assign s_axi_wdata   = ld_grant ? ld_wdata   : fbm_wdata;
assign s_axi_wstrb   = ld_grant ? {(AXI_DATA_WIDTH/8){1'b1}} : fbm_wstrb;
assign s_axi_wlast   = ld_grant ? 1'b1       : fbm_wlast;
assign s_axi_wvalid  = ld_grant ? ld_wvalid  : fbm_wvalid;
assign s_axi_bready  = ld_grant ? 1'b1       : fbm_bready;
assign fbm_awready   = s_axi_awready & ~ld_grant;
assign fbm_wready    = s_axi_wready  & ~ld_grant;
assign fbm_bid       = {{(6-AXI_ID_WIDTH){1'b0}}, s_axi_bid};
assign fbm_bvalid    = s_axi_bvalid  & ~ld_grant;
wire   fb_wr_busy    = fbm_awvalid | fbm_wvalid;

ddr3_top                 u_ddr3_top
(

.axi_clk                (core_clk            ),
.core_clk               (core_clk            ),
.sdram_clk              (sdram_clk           ),  
.rx_cal_clk             (rx_cal_clk          ),
.tx_cal_clk             (tx_cal_clk          ),
.tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
.rstn                   (w_arstn             ),      
.pll_shift              (pll_shift           ),
.pll_shift_sel          (pll_shift_sel       ),
.pll_shift_ena          (pll_shift_ena       ),       
///////////////DDR BUS
.ddr_ck_hi              (ddr_ck_hi           ),
.ddr_ck_lo              (ddr_ck_lo           ),
.ddr_cke                (ddr_cke             ),    
.ddr_reset_n            (ddr_reset_n         ),
.ddr_cs_n               (ddr_cs_n            ),
.ddr_ras_n              (ddr_ras_n           ),
.ddr_cas_n              (ddr_cas_n           ),
.ddr_we_n               (ddr_we_n            ),     
.ddr_addr               (ddr_addr            ),
.ddr_ba                 (ddr_ba              ),

.ddr_dqs_oe             (ddr_dqs_oe          ),
.ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
.ddr_dq_oe              (ddr_dq_oe           ),
.ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
.ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
.ddr_dq_in_hi           (ddr_dq_in_hi        ),
.ddr_dq_in_lo           (ddr_dq_in_lo        ),

.ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
.ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
.ddr_dq_out_hi          (ddr_dq_out_hi       ),
.ddr_dq_out_lo          (ddr_dq_out_lo       ),

.ddr_dm_hi              (ddr_dm_hi           ),
.ddr_dm_lo              (ddr_dm_lo           ),
.ddr_odt                (ddr_odt             ),

// Application interface ports
.app_sr_req                     (1'b0),
.app_ref_req                    (1'b0),
.app_zq_req                     (1'b0),
.app_sr_active                  (app_sr_active),
.app_ref_ack                    (app_ref_ack),
.app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
.s_axi_awid                     (s_axi_awid        ),
.s_axi_awaddr                   (s_axi_awaddr      ),
.s_axi_awlen                    (s_axi_awlen       ),
.s_axi_awsize                   (s_axi_awsize      ),
.s_axi_awburst                  (s_axi_awburst     ),
.s_axi_awlock                   (s_axi_awlock      ),
.s_axi_awcache                  (s_axi_awcache     ),
.s_axi_awprot                   (s_axi_awprot      ),
.s_axi_awqos                    (4'h0              ),
.s_axi_awvalid                  (s_axi_awvalid     ),
.s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
.s_axi_wdata                    (s_axi_wdata       ),
.s_axi_wstrb                    (s_axi_wstrb       ),
.s_axi_wlast                    (s_axi_wlast       ),
.s_axi_wvalid                   (s_axi_wvalid      ),
.s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
.s_axi_bid                      (s_axi_bid         ),
.s_axi_bresp                    (s_axi_bresp       ),
.s_axi_bvalid                   (s_axi_bvalid      ),
.s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
.s_axi_arid                     (s_axi_arid        ),
.s_axi_araddr                   (s_axi_araddr      ),
.s_axi_arlen                    (s_axi_arlen       ),
.s_axi_arsize                   (s_axi_arsize      ),
.s_axi_arburst                  (s_axi_arburst     ),
.s_axi_arlock                   (s_axi_arlock      ),
.s_axi_arcache                  (s_axi_arcache     ),
.s_axi_arprot                   (s_axi_arprot      ),
.s_axi_arqos                    (4'h0              ),
.s_axi_arvalid                  (s_axi_arvalid     ),
.s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
.s_axi_rid                      (s_axi_rid         ),
.s_axi_rdata                    (s_axi_rdata       ),
.s_axi_rresp                    (s_axi_rresp       ),
.s_axi_rlast                    (s_axi_rlast       ),
.s_axi_rvalid                   (s_axi_rvalid      ),
.s_axi_rready                   (s_axi_rready      ),
//DEBUG       
.wrlvl_dq_check                 (wrlvl_dq_check    ) ,
.rd_level_dqs_check             (rd_level_dqs_check) ,
.init_cur_state                 (init_cur_state    ) ,
.idelay_ld                      (idelay_ld         ) ,
.mpr_rdlvl_dly                  (mpr_rdlvl_dly     ) ,
.cal_done                       (cal_done          ) 
);

//***************************************************************************
// debayer
//***************************************************************************


wire        rgb_vs;
wire        rgb_hs;
wire        rgb_de;
wire        rgb_valid;
wire [47:0] rgb_datax2;
wire [15:0] r_gain = 16'd512;   // fixed WB gain (was VIO driven)
wire [15:0] g_gain = 16'd256;
wire [15:0] b_gain = 16'd517;

debayer_top_2to1 debayer_top
(
	.in_pclk		  (vid_clk_dvi2),//(i_mipi_rx_pclk ),
	.in_rstn		  (vid_rst_n	),
	
	.raw_vs_i		  (ch0_vs		      ),
	.raw_hs_i		  (ch0_hs		      ),
	.raw_de_i		  (ch0_de		      ),
	.raw_valid_i	(ch0_de	        ),
	.raw_datax4_i	({ch0_b,ch0_g}	),
	.r_gain       (|r_gain? r_gain:255 ),
  .g_gain       (|g_gain? g_gain:255 ),
  .b_gain       (|b_gain? b_gain:255 ),
	.rgb_vs_o		  (rgb_vs         ),
	.rgb_hs_o		  (rgb_hs         ),
	.rgb_de_o		  (rgb_de         ),
	.rgb_valid_o	(rgb_valid      ),
	.rgb_datax2_o (rgb_datax2     )//b,g,r,b,g,r
);

//***************************************************************************
// custom image processing chain  (steps 1-4: gray -> 3x3 window -> sobel -> threshold)
//   display source is FIXED to the despeckled binary edge (no runtime mode switching)
//***************************************************************************
wire [11:0] edge_threshold_12;
reg  [11:0] disp_threshold;     // latched at frame start (no tearing while pressing)
reg  [11:0] disp_threshold_raw; // threshold for the raw Sobel branch (compare mode)
wire [11:0] auto_th_main, auto_th_raw;
wire        ui_thr_auto;
wire [1:0]  ui_algo;

// ---- four-key UI: K1 threshold, K2 select, K3 change/confirm, K0 freeze (short) / capture (long) ----
wire k0_s, k0_l, k1_s, k1_l, k2_s, k2_l, k3_s, k3_l;
key_sl u_k0 (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .key_n(key_i[0]), .short_p(k0_s), .long_p(k0_l));
key_sl u_k1 (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .key_n(key_i[1]), .short_p(k1_s), .long_p(k1_l));
key_sl u_k2 (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .key_n(key_i[2]), .short_p(k2_s), .long_p(k2_l));
key_sl u_k3 (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .key_n(key_i[3]), .short_p(k3_s), .long_p(k3_l));

// saved_valid is produced in the DDR/AXI clock domain. It changes only after
// a complete frame, so a two-flop synchronizer is sufficient here.
reg [3:0] saved_valid_meta;
reg [3:0] saved_valid_sync;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
    if (!vid_rst_n) begin
        saved_valid_meta <= 4'b0000;
        saved_valid_sync <= 4'b0000;
    end else begin
        saved_valid_meta <= saved_valid;
        saved_valid_sync <= saved_valid_meta;
    end
end

// preload-finished toggle (core_clk) -> one pulse in the video clock domain
reg [2:0] pl_tog_s;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
    if (!vid_rst_n) pl_tog_s <= 3'b000;
    else            pl_tog_s <= {pl_tog_s[1:0], ld_preload_tog};
end
wire ui_ext_slot1 = pl_tog_s[2] ^ pl_tog_s[1];

wire [2:0] ui_sel, ui_thr_idx, ui_src_mode, ui_flash;
wire       ui_shape_on, ui_fps_on;
wire       ui_digit_active, ui_digit_start;
wire [1:0] ui_disp_mode;
ui_ctrl u_ui_ctrl (
    .clk(vid_clk_dvi2), .rst_n(vid_rst_n),
    .k0_s(k0_s), .k0_l(k0_l), .k1_s(k1_s), .k1_l(k1_l), .k2_s(k2_s), .k2_l(k2_l), .k3_s(k3_s), .k3_l(k3_l),
    .saved_valid(saved_valid_sync), .ext_slot1(ui_ext_slot1),
    .freeze(frame_freeze), .view_mode(view_mode), .snapshot_toggle(snapshot_toggle),
    .clear_saved_toggle(clear_saved_toggle),
    .digit_active(ui_digit_active), .digit_start(ui_digit_start),
    .sel(ui_sel), .thr_idx(ui_thr_idx), .thr12(edge_threshold_12),
    .shape_on(ui_shape_on), .fps_on(ui_fps_on), .algo(ui_algo), .thr_auto(ui_thr_auto), .disp_mode(ui_disp_mode), .src_mode(ui_src_mode), .flash(ui_flash)
);

// apply key changes only at the start of a frame
reg  vs_key_d;
wire vs_key_rise = rgb_vs & ~vs_key_d;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
    if (!vid_rst_n) begin
        vs_key_d      <= 1'b0;
        disp_threshold <= 12'd400;
        disp_threshold_raw <= 12'd400;
    end
    else begin
        vs_key_d <= rgb_vs;

        if (vs_key_rise) begin
            disp_threshold     <= ui_thr_auto ? auto_th_main : edge_threshold_12;
            disp_threshold_raw <= ui_thr_auto ? auto_th_raw  : edge_threshold_12;
        end
    end
end

wire [15:0] gray2;
wire        gray_valid, gray_hs, gray_vs;

rgb2gray_2px u_rgb2gray_2px (
    .clk        (vid_clk_dvi2),
    .rst_n      (vid_rst_n),
    .in_valid   (rgb_de),
    .in_hs      (rgb_hs),
    .in_vs      (rgb_vs),
    .in_pixel2  (rgb_datax2),
    .out_valid  (gray_valid),
    .out_hs     (gray_hs),
    .out_vs     (gray_vs),
    .out_gray2  (gray2)
);

// Long K1: continuous live nearest-glyph matching, without freezing the camera.
wire digit_map_we, digit_map_bit, digit_capture_done, digit_capture_busy;
wire [15:0] digit_map_addr;
wire [7:0] digit_ink_threshold;
wire digit_match_busy, digit_match_done, digit_found;
wire [4:0] digit_result;
wire [3:0] digit_lhs;
wire [23:0] digit_x0,digit_x1;
wire [26:0] digit_y0,digit_y1;
wire digit_mask_valid,digit_mask_hs,digit_mask_vs;
wire [1:0] digit_mask2;
digit_capture_2px u_digit_capture (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.enable(ui_digit_active),.start(ui_digit_start),.ready(!digit_match_busy),
    .in_valid(gray_valid),.in_vs(gray_vs),.in_gray2(gray2),
    .map_we(digit_map_we),.map_addr(digit_map_addr),.map_bit(digit_map_bit),
    .done(digit_capture_done),.busy(digit_capture_busy),.ink_threshold(digit_ink_threshold));
digit_match_7p2 u_digit_match (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.enable(ui_digit_active),.restart(ui_digit_start),.go(digit_capture_done),
    .map_we(digit_map_we),.map_waddr(digit_map_addr),.map_wbit(digit_map_bit),
    .busy(digit_match_busy),.done(digit_match_done),.found(digit_found),.result(digit_result),.lhs_value(digit_lhs),
    .box_x0(digit_x0),.box_x1(digit_x1),.box_y0(digit_y0),.box_y1(digit_y1));
wire digit_stable_found,digit_answer_ready;
wire [3:0] digit_stable_lhs;
wire [4:0] digit_stable_result;
wire [23:0] digit_stable_x0,digit_stable_x1;
wire [26:0] digit_stable_y0,digit_stable_y1;
reg digit_gray_vs_d;
digit_result_control u_digit_result_control (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.enable(ui_digit_active),.restart(ui_digit_start),
    .frame_start(gray_vs && !digit_gray_vs_d),.det_done(digit_match_done),.det_found(digit_found),
    .det_lhs(digit_lhs),.det_result(digit_result),.det_x0(digit_x0),.det_x1(digit_x1),.det_y0(digit_y0),.det_y1(digit_y1),
    .stable_found(digit_stable_found),.stable_lhs(digit_stable_lhs),.stable_result(digit_stable_result),
    .stable_x0(digit_stable_x0),.stable_x1(digit_stable_x1),.stable_y0(digit_stable_y0),.stable_y1(digit_stable_y1),.answer_ready(digit_answer_ready));
// Publish one coherent set of boxes for the complete displayed frame.
reg digit_vis_found;
reg [4:0] digit_vis_result;
reg [3:0] digit_vis_lhs;
reg [23:0] digit_vis_x0,digit_vis_x1;
reg [26:0] digit_vis_y0,digit_vis_y1;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
    if(!vid_rst_n) begin
        digit_gray_vs_d<=0;digit_vis_found<=0;digit_vis_result<=0;digit_vis_lhs<=0;
        digit_vis_x0<=0;digit_vis_x1<=0;digit_vis_y0<=0;digit_vis_y1<=0;
    end else begin
        digit_gray_vs_d<=gray_vs;
        if(gray_vs && !digit_gray_vs_d) begin
            digit_vis_found<=ui_digit_active && digit_stable_found;digit_vis_result<=digit_stable_result;digit_vis_lhs<=digit_stable_lhs;
            digit_vis_x0<=digit_stable_x0;digit_vis_x1<=digit_stable_x1;digit_vis_y0<=digit_stable_y0;digit_vis_y1<=digit_stable_y1;
        end
    end
end
digit_outline_2px u_digit_outline (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.enable(ui_digit_active),.found(digit_stable_found),.lhs_value(digit_stable_lhs),
    .ink_threshold(digit_ink_threshold),.box_x0(digit_stable_x0),.box_x1(digit_stable_x1),.box_y0(digit_stable_y0),.box_y1(digit_stable_y1),
    .in_valid(gray_valid),.in_hs(gray_hs),.in_vs(gray_vs),.in_gray2(gray2),
    .out_valid(digit_mask_valid),.out_hs(digit_mask_hs),.out_vs(digit_mask_vs),.out_mask2(digit_mask2));

wire [15:0] medg2;
wire        medg_valid, medg_hs, medg_vs;

median_switch_2px #(
    .PAIR_COUNT (960),
    .MAX_LINES  (1080)
) u_median_switch_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .in_valid  (gray_valid),
    .in_hs     (gray_hs),
    .in_vs     (gray_vs),
    .in_gray2  (gray2),
    .en        (1'b1),
    .out_valid (medg_valid),
    .out_hs    (medg_hs),
    .out_vs    (medg_vs),
    .out_gray2 (medg2)
);

// Sobel / Canny edge stage (Gaussian -> window -> Sobel -> {threshold | NMS -> double threshold + linking})
wire edge0, edge1, s_edge0, s_edge1;
wire edge_valid, edge_hs, edge_vs;

edge_algo_2px #(
    .PAIR_COUNT  (960),
    .MAX_LINES   (1080),
    .LINE_CYCLES (1100),
    .SOBEL_DELAY_BASE (14)
) u_edge_algo_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .in_valid  (medg_valid),
    .in_hs     (medg_hs),
    .in_vs     (medg_vs),
    .in_gray2  (medg2),
    .algo      (ui_algo),
    .th_main   (disp_threshold),
    .th_raw    (disp_threshold_raw),
    .out_valid (edge_valid),
    .out_hs    (edge_hs),
    .out_vs    (edge_vs),
    .edge0     (edge0),
    .edge1     (edge1),
    .s_edge0   (s_edge0),
    .s_edge1   (s_edge1),
    .auto_main (auto_th_main),
    .auto_raw  (auto_th_raw)
);

wire [1:0] desp_edge2;
wire       desp_valid, desp_hs, desp_vs;

despeckle_2px #(
    .PAIR_COUNT (960),
    .MAX_LINES  (1080),
    .KEEP_MIN   (1),     // 1 = only remove completely isolated pixels (keeps line ends)
    .FILL_MIN   (9)     // 9 = hole filling disabled: only remove isolated pixels
) u_despeckle_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .in_valid  (edge_valid),
    .in_hs     (edge_hs),
    .in_vs     (edge_vs),
    .in_edge2  ({edge1, edge0}),
    .out_valid (desp_valid),
    .out_hs    (desp_hs),
    .out_vs    (desp_vs),
    .out_edge2 (desp_edge2)
);

// same isolated-pixel removal on the raw Sobel branch (used by the left panel in compare mode)
wire [1:0] desp_s_edge2;
wire       desp_s_valid, desp_s_hs, desp_s_vs;
despeckle_2px #(
    .PAIR_COUNT (960),
    .MAX_LINES  (1080),
    .KEEP_MIN   (1),
    .FILL_MIN   (9)
) u_despeckle_s_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .in_valid  (edge_valid),
    .in_hs     (edge_hs),
    .in_vs     (edge_vs),
    .in_edge2  ({s_edge1, s_edge0}),
    .out_valid (desp_s_valid),
    .out_hs    (desp_s_hs),
    .out_vs    (desp_s_vs),
    .out_edge2 (desp_s_edge2)
);

// ---- left / right split screen ----
//  left  half (0..959)   : colour central crop with red edge overlay
//  right half (960..1919): binary edges of the SAME central crop
wire        split_valid, split_hs, split_vs;
wire [47:0] split_rgb2;

wire [2:0] st_vis;  wire [8:0] st_cls;  wire [23:0] st_x0, st_x1;  wire [26:0] st_y0, st_y1;  wire [971:0] st_par;

display_split_2px #(
    .PAIR_COUNT  (960),
    .LINE_COUNT  (1080),
    .CROP_X_PAIR (240),
    .CROP_PAIRS  (480),
    .BUF_LINES   (8),
    .DIGIT_SUPPORT (1)
) u_display_split_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .show_red  (ui_disp_mode != 2'd1),
    .show_color(ui_disp_mode != 2'd2),
    .show_edge (ui_disp_mode != 2'd1),
    .sup_en    (ui_shape_on && !ui_digit_active),
    .sup_vis   (st_vis),
    .sup_xmin  (st_x0), .sup_xmax(st_x1), .sup_ymin(st_y0), .sup_ymax(st_y1),
    .cmp_mode  (ui_algo == 2'd2),
    .s_edge0   (desp_s_edge2[0]),
    .s_edge1   (desp_s_edge2[1]),
    .src_valid (rgb_de),
    .src_vs    (rgb_vs),
    .src_rgb2  (rgb_datax2),
    .digit_mode(ui_digit_active), .digit_valid(digit_mask_valid), .digit_vs(digit_mask_vs), .digit_mask2(digit_mask2),
    .in_valid  (desp_valid),
    .in_hs     (desp_hs),
    .in_vs     (desp_vs),
    .edge0     (desp_edge2[0]),
    .edge1     (desp_edge2[1]),
    .out_valid (split_valid),
    .out_hs    (split_hs),
    .out_vs    (split_vs),
    .out_rgb2  (split_rgb2)
);

wire [47:0] disp_datax2;
wire        disp_de;
wire        disp_hs;
wire        disp_vs;

// ---- shape recognition (circle / ellipse / square / rectangle / triangle), tapped from the despeckled edge map ----
wire        shp_valid, shp_hs, shp_vs;
wire [47:0] shp_rgb2;
wire        sp_valid, sp_bit, sp_fs;
shape_pool u_shape_pool (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .in_valid(desp_valid), .in_vs(desp_vs),
    .in_edge2(desp_edge2), .p_valid(sp_valid), .p_bit(sp_bit), .p_frame_start(sp_fs));
wire        sf_valid, sf_done;  wire [331:0] sf_rec;  wire [15:0] sf_ovf, sf_overrun;
// shapes whose bounding box is smaller than 1/12 of the displayed crop (BMIN = 5400 of 64800 cells) are ignored
shape_ccl #(.MMIN(600), .BMIN(5400)) u_shape_ccl (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .p_valid(sp_valid), .p_bit(sp_bit),
    .p_frame_start(sp_fs), .fin_valid(sf_valid), .fin_rec(sf_rec), .frame_done(sf_done), .ovf_count(sf_ovf), .overrun_count(sf_overrun));
wire        sc_valid;  wire [2:0] sc_class;  wire [7:0] sc_x0, sc_x1;  wire [8:0] sc_y0, sc_y1;  wire [31:0] sc_i1, sc_drop;  wire sc_el;
wire [331:0] sc_rec;  wire [31:0] sc_vxx, sc_vyy, sc_vxy;  wire sc_vneg;  wire [63:0] sc_dd;
shape_classify u_shape_cls (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .in_valid(sf_valid), .in_rec(sf_rec), .out_valid(sc_valid),
    .out_class(sc_class), .out_xmin(sc_x0), .out_xmax(sc_x1), .out_ymin(sc_y0), .out_ymax(sc_y1), .out_i1(sc_i1),
    .out_elong(sc_el), .drop_count(sc_drop),
    .out_rec(sc_rec), .out_vxx(sc_vxx), .out_vyy(sc_vyy), .out_vxy(sc_vxy), .out_vxy_neg(sc_vneg), .out_dd(sc_dd));
// ideal-outline fit of the classified region (ellipse / rotated rectangle / triangle)
wire        sfit_valid;  wire [2:0] sfit_kind;  wire [323:0] sfit_par;  wire [7:0] sfit_x0, sfit_x1;  wire [8:0] sfit_y0, sfit_y1;  wire [31:0] sfit_drop;
shape_fit u_shape_fit (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .in_valid(sc_valid), .in_class(sc_class), .in_rec(sc_rec),
    .in_vxx(sc_vxx), .in_vyy(sc_vyy), .in_vxy(sc_vxy), .in_vxy_neg(sc_vneg), .in_dd(sc_dd),
    .out_valid(sfit_valid), .out_kind(sfit_kind), .out_par(sfit_par),
    .out_xmin(sfit_x0), .out_xmax(sfit_x1), .out_ymin(sfit_y0), .out_ymax(sfit_y1), .drop_count(sfit_drop));
shape_track #(.NT(3), .NP(3)) u_shape_trk (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .frame_start(sp_fs),
    .det_valid(sfit_valid), .det_class(sfit_kind), .det_xmin(sfit_x0), .det_xmax(sfit_x1),
    .det_ymin(sfit_y0), .det_ymax(sfit_y1), .det_par(sfit_par),
    .trk_vis(st_vis), .trk_cls(st_cls), .trk_xmin(st_x0), .trk_xmax(st_x1),
    .trk_ymin(st_y0), .trk_ymax(st_y1), .trk_par(st_par));
// Chinese class names above each shape (no bounding box: the fitted outline replaces it)
wire        nm_valid, nm_hs, nm_vs;  wire [47:0] nm_rgb2;
shape_overlay_2px #(.NT(3), .PAIR_COUNT(960)) u_shape_ovl (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .enable(ui_shape_on && !ui_digit_active), .show_box(1'b0),
    .in_valid(split_valid), .in_hs(split_hs), .in_vs(split_vs), .in_rgb2(split_rgb2),
    .trk_vis(st_vis), .trk_cls(st_cls), .trk_xmin(st_x0), .trk_xmax(st_x1), .trk_ymin(st_y0), .trk_ymax(st_y1),
    .out_valid(nm_valid), .out_hs(nm_hs), .out_vs(nm_vs), .out_rgb2(nm_rgb2));
shape_fit_draw_2px #(.NT(3)) u_shape_fit_draw (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .enable(ui_shape_on && !ui_digit_active),
    .in_valid(nm_valid), .in_hs(nm_hs), .in_vs(nm_vs), .in_rgb2(nm_rgb2),
    .trk_vis(st_vis), .trk_cls(st_cls), .trk_xmin(st_x0), .trk_xmax(st_x1), .trk_ymin(st_y0), .trk_ymax(st_y1), .trk_par(st_par),
    .out_valid(shp_valid), .out_hs(shp_hs), .out_vs(shp_vs), .out_rgb2(shp_rgb2));

wire digit_disp_valid,digit_disp_hs,digit_disp_vs;
wire [47:0] digit_disp_rgb2;
digit_result_overlay_2px u_digit_result_overlay (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.enable(ui_digit_active),
    .busy(digit_capture_busy || digit_match_busy),.found(digit_vis_found),.result(digit_vis_result),
    .lhs_value(digit_vis_lhs),.answer_ready(digit_answer_ready),
    .box_x0(digit_vis_x0),.box_x1(digit_vis_x1),.box_y0(digit_vis_y0),.box_y1(digit_vis_y1),
    .in_valid(shp_valid),.in_hs(shp_hs),.in_vs(shp_vs),.in_rgb2(shp_rgb2),
    .out_valid(digit_disp_valid),.out_hs(digit_disp_hs),.out_vs(digit_disp_vs),.out_rgb2(digit_disp_rgb2));

// ---- frame-rate meter: camera frames (toggle generated in the camera pixel-clock domain) and HDMI output frames ----
reg cam_vs_d = 1'b0, cam_tog = 1'b0;
always @(posedge i_mipi_rx_pclk) begin
    cam_vs_d <= w_mipi_rx_vs;
    if (w_mipi_rx_vs && !cam_vs_d) cam_tog <= ~cam_tog;
end
wire [6:0] fps_out_v, fps_cam_v;
fps_meter #(.CLK_HZ(74250000)) u_fps_meter (.clk(vid_clk_dvi2), .rst_n(vid_rst_n), .vs_out(disp_vs), .cam_tog(cam_tog),
    .fps_out(fps_out_v), .fps_cam(fps_cam_v));

wire        bar_valid, bar_hs, bar_vs;
wire [47:0] bar_rgb2;
menu_bar_2px #(.BAR_Y(960)) u_menu_bar (.clk(vid_clk_dvi2), .rst_n(vid_rst_n),
    .in_valid(digit_disp_valid), .in_hs(digit_disp_hs), .in_vs(digit_disp_vs), .in_rgb2(digit_disp_rgb2),
    .sel(ui_sel), .src_mode(ui_src_mode), .thr_idx(ui_thr_idx), .flash(ui_flash),
    .shape_on(ui_shape_on), .cmp_mode(ui_algo == 2'd2), .fps_on(ui_fps_on), .fps_out(fps_out_v), .fps_cam(fps_cam_v), .algo(ui_algo), .disp_mode(ui_disp_mode), .saved_valid(saved_valid_sync),
    .out_valid(bar_valid), .out_hs(bar_hs), .out_vs(bar_vs), .out_rgb2(bar_rgb2));

mode_overlay_2px #(
    .PAIR_COUNT (960),
    .LINE_COUNT (1080),
    .X0         (12),
    .Y0         (12),
    .BOX_W      (89),
    .BOX_H      (55)
) u_mode_overlay_2px (
    .clk       (vid_clk_dvi2),
    .rst_n     (vid_rst_n),
    .in_valid  (bar_valid),
    .in_hs     (bar_hs),
    .in_vs     (bar_vs),
    .in_rgb2   (bar_rgb2),
    .view_mode (view_mode),
    .out_valid (disp_de),
    .out_hs    (disp_hs),
    .out_vs    (disp_vs),
    .out_rgb2  (disp_datax2)
);

reg rgb_vs_r = 'd0;
always @( posedge hdmi_tx_slow_clk )
begin
  rgb_vs_r <= disp_vs;
end
assign pos_vs = {rgb_vs_r,disp_vs} == 2'b01;
reg vid_cnt = 'd0;
reg [7:0] hdmi_tx_rdata ;
reg [7:0] hdmi_tx_gdata ;
reg [7:0] hdmi_tx_bdata ;
reg hdmi_tx_vs;
reg hdmi_tx_hs;
reg hdmi_tx_de;
always @( posedge hdmi_tx_slow_clk )
begin
    if( pos_vs )
      vid_cnt <= 1'b1;
    else if( disp_de )
      vid_cnt <= ~vid_cnt ;

    if( vid_cnt )
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= disp_datax2[23:0];
    else 
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= disp_datax2[47:24];

  hdmi_tx_vs <= disp_vs;
  hdmi_tx_hs <= disp_hs;
  hdmi_tx_de <= disp_de;
end
//==============================================================================
// MIPI DSI
//==============================================================================
// signal 

reg		[25:0]	r_rst_cnt;

wire	[31:0]	w_axi_rdata;
wire			w_axi_awready;
wire			w_axi_wready;
wire			w_axi_arready;
wire			w_axi_rvalid;
wire			w_axi_bvalid;

wire	[6:0]	w_axi_awaddr;
wire			w_axi_awvalid;
wire	[31:0]	w_axi_wdata;
wire			w_axi_wvalid;
wire			w_axi_bready;
wire	[6:0]	w_axi_araddr;
wire			w_axi_arvalid;
wire			w_axi_rready;

wire			w_confdone;
assign w_confdone = 1'b1;

assign  LCD_POWER 			= i_arstn;
assign	LCD_RST_P	      = ~w_arstn;//~r_rst_cnt[23]; LCD复位先释放，然后再释放MIPI 的复位
assign	mipi_dp_clk_RST		= ~i_arstn;
assign	mipi_dp_data0_RST	= ~i_arstn;
assign	mipi_dp_data1_RST	= ~i_arstn;
assign	mipi_dp_data2_RST	= ~i_arstn;
assign	mipi_dp_data3_RST	= ~i_arstn;
////////////////////////////////////////////////////////////////
always@(posedge i_mipi_clk or  negedge w_arstn )
begin
  if ( !w_arstn ) begin
    r_rst_cnt	<= 'd0;
  end else 		
    r_rst_cnt	<= r_rst_cnt[25] ? r_rst_cnt :r_rst_cnt + 1'b1;
end

wire axi_rst_n = r_rst_cnt[25];

reg [26:0] dly_cnt = 'd0;

always @( posedge vid_clk_dvi2 or negedge w_arstn )
begin
  if( !w_arstn )
    dly_cnt <= 'd0;
  else if( w_confdone )
    dly_cnt <= dly_cnt[26] ? dly_cnt :(dly_cnt + 1'b1);
  else 
    dly_cnt <= 'd0;
end 

assign vid_rst_n = dly_cnt[26];




wire hs;
wire vs;
wire de;
wire [7:0] rgb_r;
wire [7:0] rgb_g;
wire [7:0] rgb_b;
  
  // color_bar_rgb #(
  // .HS_POLORY 		(1'b1		),
  // .VS_POLORY 		(1'b1		),
  // .H_FRONT_PORCH 	(HFP		),///2
  // .H_SYNC 		(HSP		),//
  // .H_VALID 		(MAX_HRES	),//
  // .H_BACK_PORCH 	(HBP		),//
  // .V_FRONT_PORCH 	(VFP		),
  // .V_SYNC 		(VSP		),
  // .V_VALID 		(MAX_VRES	),
  // .V_BACK_PORCH 	(VBP		),
  // .TEST_MODE 		(2'd2)
  // )u_color_bar_rgb1(
  // /*i*/.clk	(vid_clk_dvi2),//(vid_clk),
  // /*i*/.rst_n	(vid_rst_n),
  // /*o*/.hs	(hs),
  // /*o*/.vs	(vs),
  // /*o*/.de	(de),
  // // /*O*/.h_cnt (h_cnt),
  // // /*O*/.v_cnt (v_cnt),
  // /*o*/.rgb_r	(rgb_r),    //像素数据、红色分量
  // /*o*/.rgb_g	(rgb_g),    //像素数据、绿色分量
  // /*o*/.rgb_b (rgb_b)    //像素数据、蓝色分量
  
  // );

//=================================================================================
//hdmi tx ctrl 
//=================================================================================
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;

assign tmds_tx_data0_TX_OE = 1'b1;
assign tmds_tx_data1_TX_OE = 1'b1;
assign tmds_tx_data2_TX_OE = 1'b1;
assign tmds_tx_clk_TX_OE   = 1'b1;

assign tmds_tx_data0_TX_RST = 1'b0;
assign tmds_tx_data1_TX_RST = 1'b0;
assign tmds_tx_data2_TX_RST = 1'b0;
assign tmds_tx_clk_TX_RST   = 1'b0;

// 	  color_bar color_bar_m0(
// 	.clk(hdmi_tx_slow_clk),
// 	.rst(~vid_rst_n),
// 	.hs(video_hs),
// 	.vs(video_vs),
// 	.de(video_de),
// 	.rgb_r(video_r),
// 	.rgb_g(video_g),
// 	.rgb_b(video_b)
// );

wire [9:0] tmds_data0;
wire [9:0] tmds_data1;
wire [9:0] tmds_data2;
wire [9:0] tmds_clk ;
wire [7:0] gamma_rdata ;
wire [7:0] gamma_gdata ;
wire [7:0] gamma_bdata ;
wire gamma_valid;
wire gamma_hs;
wire gamma_vs;
wire gamma_sel = 1'b0;          // gamma path permanently OFF (no runtime timing switch)
wire [15:0] vio_r_gain_unused, vio_g_gain_unused, vio_b_gain_unused;
wire        vio_gamma_sel_unused;

wire [7:0] con_rdata ;
wire [7:0] con_gdata ;
wire [7:0] con_bdata ;
wire con_de;
wire con_hs;
wire con_vs;
wire con_sel;

wire [7:0] BRIGHT_SIG    ;
wire CONTRAST_SIG_G;
wire CONTRAST_SIG_R;
wire [7:0] CONTRAST_G    ;
wire CONTRAST_SIG_B;
wire [7:0] BRIGHT        ;
wire [7:0] CONTRAST_R    ;


wire CONTRAST_B    ;


gamma_correction
#(
	.DATA_WIDTH		(8),
	.GAMMA_CURVE	("./rtl/gamma_conrrection/2P2.mem")
)
inst_gamma_correction
(
	.i_pclk		(hdmi_tx_slow_clk),
	.i_rstn		(vid_rst_n),
	
	.i_red		(hdmi_tx_rdata),//(con_rdata  ),//
	.i_green	(hdmi_tx_gdata),//(con_gdata  ),//
	.i_blue		(hdmi_tx_bdata),//(con_bdata  ),//
  .i_valid	(hdmi_tx_de   ),//(con_de     ),//
  .i_hs     (hdmi_tx_hs   ),//(con_hs     ),//
  .i_vs     (hdmi_tx_vs   ),//(con_vs     ),//
	.o_blue		(gamma_bdata		),
  .o_green	(gamma_gdata	  ),
	.o_red		(gamma_rdata		),
	.o_valid	(gamma_valid	  ),
  .o_hs     (gamma_hs       ),
  .o_vs     (gamma_vs       )
);

dvi_encoder dvi_encoder_m0
(
	.pixelclk      		(hdmi_tx_slow_clk          ),// system clock
	.rst_p         		(~vid_rst_n      ),// reset
	.i_bdata      		(gamma_sel ? gamma_bdata	: hdmi_tx_rdata 	),//(hdmi_tx_rdata ),//(video_b            ),//(bdata_in	),   //
	.i_gdata     		  (gamma_sel ? gamma_gdata	: hdmi_tx_gdata   ),//(hdmi_tx_gdata ),//(video_g            ),//(gdata_in	),   //   
	.i_rdata       		(gamma_sel ? gamma_rdata	: hdmi_tx_bdata 	),//(hdmi_tx_bdata ),//(video_r            ),//(rdata_in	),   //   
  .i_de            	(gamma_sel ? gamma_valid	: hdmi_tx_de      ),//(hdmi_tx_de    ),//(video_de           ),//(rx_de		  ),   //
	.i_hs         		(gamma_sel ? gamma_hs	    : hdmi_tx_hs    ),//(video_hs           ),//(rx_hsync	),   //   
	.i_vs         		(gamma_sel ? gamma_vs	    : hdmi_tx_vs    ),//(video_vs           ),//(rx_vsync	),   //  
	
  .video_format     (video_format), //// 00 = RGB, 01 = YCbCr 4:2:2, 10 = YCbCr 4:4:4
  .video_VIC        (0),
	.audio_L			    (audio_L),
  .audio_R			    (audio_R),
  .audio_valid		  (audio_valid),
  .audio_N                (6144),     //(20'h01880),//     
  .audio_CTS              (148500),      //(20'h28488),//      
  .audio_sample_frequency (audio_samp_freq),    //(3'b000),// 
  .audio_word_length      ({audio_samp_word_len,audio_max_word_length}),//(4'b1011),//

	.tmds_data0    		(tmds_data0),
  .tmds_data1    		(tmds_data1),
  .tmds_data2    		(tmds_data2),
  .tmds_clk      	  (tmds_clk  )
);
assign tmds_tx_clk_TX_DATA   = ~tmds_clk;
assign tmds_tx_data0_TX_DATA = ~tmds_data0;
assign tmds_tx_data1_TX_DATA = ~tmds_data1;
assign tmds_tx_data2_TX_DATA = ~tmds_data2;

// Debug (LA/VIO) core removed to save block RAM; set DEBUG_CORE=1 and restore the <efx:debugger> section to re-enable.
localparam DEBUG_CORE = 0;
generate if (DEBUG_CORE) begin : g_dbg
    assign ld_grant = 1'b0; assign ld_hold_req = 1'b0; assign ld_preload_mask = 4'd0; assign ld_preload_tog = 1'b0;
    assign ld_awaddr = 32'd0; assign ld_awvalid = 1'b0; assign ld_wdata = 128'd0; assign ld_wvalid = 1'b0;
debug_edb_top debug_edb_top_inst (
    .bscan_CAPTURE      ( jtag_inst1_CAPTURE  ),
    .bscan_DRCK         ( jtag_inst1_DRCK     ),
    .bscan_RESET        ( jtag_inst1_RESET    ),
    .bscan_RUNTEST      ( jtag_inst1_RUNTEST  ),
    .bscan_SEL          ( jtag_inst1_SEL      ),
    .bscan_SHIFT        ( jtag_inst1_SHIFT    ),
    .bscan_TCK          ( jtag_inst1_TCK      ),
    .bscan_TDI          ( jtag_inst1_TDI      ),
    .bscan_TMS          ( jtag_inst1_TMS      ),
    .bscan_UPDATE       ( jtag_inst1_UPDATE   ),
    .bscan_TDO          ( jtag_inst1_TDO      ),
    .vio0_clk           ( vid_clk_dvi2        ),
    .vio0_r_gain        ( vio_r_gain_unused              ),
    .vio0_g_gain        ( vio_g_gain_unused              ),
    .vio0_b_gain        ( vio_b_gain_unused              ),

    .vio0_gamma_sel     (vio_gamma_sel_unused),
    .la0_clk            ( vid_clk_dvi2        ),
    .la0_ch0_g          ( ch0_g               ),
    .la0_ch0_b          ( ch0_b               ),
    .la0_ch0_de         ( ch0_de              ),
    .la0_cal_done       ( cal_done            )
);
end else begin : g_nodbg
    // JTAG USER1 is used to preload the two demo pictures into saved-frame slots 1 and 2 (tools/jtag_load_demo.py)
    wire jtag_tck_g;
    EFX_GBUFCE #(.CE_POLARITY(1'b1)) u_jtag_tck_gbuf (.CE(1'b1), .I(jtag_inst1_TCK), .O(jtag_tck_g));
    reg [1:0] ld_rst_s = 2'b00;
    always @(posedge core_clk or negedge vid_rst_n) begin
        if (!vid_rst_n) ld_rst_s <= 2'b00;
        else            ld_rst_s <= {ld_rst_s[0], cal_done};
    end
    wire ld_tdo;
    jtag_demo_loader u_jtag_demo_loader (
        .tck(jtag_tck_g), .tdi(jtag_inst1_TDI), .tdo(ld_tdo), .sel(jtag_inst1_SEL),
        .shift(jtag_inst1_SHIFT), .capture(jtag_inst1_CAPTURE), .update(jtag_inst1_UPDATE),
        .clk(core_clk), .rst_n(ld_rst_s[1]),
        .fb_busy(fb_wr_busy), .hold_req(ld_hold_req), .grant(ld_grant),
        .awaddr(ld_awaddr), .awvalid(ld_awvalid), .awready(s_axi_awready),
        .wdata(ld_wdata), .wvalid(ld_wvalid), .wready(s_axi_wready),
        .bvalid(s_axi_bvalid & ld_grant), .bresp(s_axi_bresp),
        .preload_mask(ld_preload_mask), .preload_tog(ld_preload_tog));
    assign jtag_inst1_TDO = ld_tdo;
end endgenerate

endmodule
