

module bank_switch #(
		parameter FB_NUM = 2,
		parameter MAX_VID_WIDTH = 1920,
		parameter MAX_VID_HIGHT = 1080,
		parameter START_ADDR= 0,
		parameter VID_DATA_WIDTH= 16,
		parameter AXI_DATA_WIDTH = 256
		
)

(
input	wire		ddr_clk,//!时钟
input	wire		rst_n,//!复位，低电平有效
input	wire		freeze,//!hold the current read bank
input	wire	[2:0]	view_mode,//!0=live, 1..4=saved frame
input	wire			snapshot_toggle,//!toggle once when K3 is pressed

input	wire		wr_sw,//!写bank切换请求信号,电平有效
input	wire		rd_sw,//!读bank切换请求信号,电平有效

output	reg	[1:0]	wr_bank,
output	reg	[1:0]	rd_bank,
output	reg			rd_sw_ack,
output	reg			wr_sw_ack,
output	reg[31:0] 	rd_start_addr,
output	reg[31:0]	wr_start_addr,
output	reg	[3:0]	saved_valid




);                       
localparam AXI_BYTE_NUMBER = AXI_DATA_WIDTH/8  ;
localparam FRAME_LEN =   MAX_VID_WIDTH*MAX_VID_HIGHT*VID_DATA_WIDTH/8 + 32'h200;  

localparam FRAME_1ST_START_ADDR = START_ADDR;
localparam FRAME_2ND_START_ADDR = FRAME_LEN + START_ADDR ;

localparam FRAME_3RD_START_ADDR = FRAME_LEN+ FRAME_2ND_START_ADDR;

// The four saved frames use a separate DDR region. The live triple buffer
// occupies addresses below 16 MB, so this region is completely independent.
localparam [31:0] SAVED_BASE_ADDR = 32'h0200_0000;

function [31:0] saved_addr;
input [1:0] idx;
begin
    case (idx)
        2'd0: saved_addr = SAVED_BASE_ADDR;
        2'd1: saved_addr = SAVED_BASE_ADDR + FRAME_LEN;
        2'd2: saved_addr = SAVED_BASE_ADDR + (FRAME_LEN << 1);
        default: saved_addr = SAVED_BASE_ADDR + (FRAME_LEN << 1) + FRAME_LEN;
    endcase
end
endfunction


	
	generate 
	if( FB_NUM == 1 ) begin : one_fb 
		always @( posedge ddr_clk or negedge rst_n ) 
		begin 
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;
				wr_sw_ack <= 1'b0;
				rd_sw_ack <= 1'b0;     
				rd_start_addr <= FRAME_1ST_START_ADDR; 
				wr_start_addr <= FRAME_1ST_START_ADDR; 
			end else begin 
				wr_bank <= 2'b00;
				rd_bank <= 2'b00;
				wr_sw_ack <= wr_sw;
				rd_sw_ack <= rd_sw;   
				rd_start_addr <= FRAME_1ST_START_ADDR;
				wr_start_addr <= FRAME_1ST_START_ADDR;
			end 
		end 

	end else if( FB_NUM == 2 ) begin :tow_fb
		reg			bank_sw_en = 1'b0;
		reg			bank_sw_en_d1 = 1'b0;
		wire		pos_bank_sw_en;
		always @( posedge ddr_clk )
		begin
			bank_sw_en <= wr_sw & rd_sw;
			bank_sw_en_d1 <= bank_sw_en;
		end
		assign pos_bank_sw_en = {bank_sw_en_d1,bank_sw_en} == 2'b01;
		
		always @( posedge ddr_clk or negedge rst_n)
		begin
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;      
				wr_start_addr <= FRAME_1ST_START_ADDR; 
				rd_start_addr <= FRAME_2ND_START_ADDR; 
			end else if( pos_bank_sw_en ) begin//必须两个bank同时切换
				wr_bank[0] <= ~wr_bank[0];
				rd_bank[0] <= wr_bank[0];
				rd_bank[1] <= 1'b0;
				wr_bank[1] <= 1'b0;      
				wr_start_addr <= wr_bank[0] ? FRAME_1ST_START_ADDR : FRAME_2ND_START_ADDR;
				rd_start_addr <= wr_bank[0] ? FRAME_2ND_START_ADDR : FRAME_1ST_START_ADDR; 
			end
		end
		
		always @( posedge ddr_clk )
		begin
			wr_sw_ack	 <= pos_bank_sw_en;
			rd_sw_ack	 <= pos_bank_sw_en;
		end
		
		
	end else if( FB_NUM == 3 ) begin :three_fb
		reg	[1:0] 	dirt_bank = 2'b10;
		reg			dirt_en = 1'b1;
		reg	[1:0]	clean_bank = 2'b00;
		reg			clean_en = 1'b0;
		wire		pos_wr_sw_en;
		wire		pos_rd_sw_en;
		reg			wr_sw_d1 = 1'b0;
		reg			rd_sw_d1 = 1'b0;

		reg [31:0] live_wr_start_addr = FRAME_1ST_START_ADDR;
		reg [31:0] live_rd_start_addr = FRAME_2ND_START_ADDR;
		reg [1:0]  snap_wr_slot = 2'd0;
		reg        snap_pending = 1'b0;
		reg        snap_active = 1'b0;
		reg        snap_tog_d0 = 1'b0;
		reg        snap_tog_d1 = 1'b0;
		reg        snap_tog_d2 = 1'b0;
		wire       snap_req_pulse;
		wire [1:0] view_idx = view_mode[1:0] - 2'd1;

		always @( posedge ddr_clk or negedge rst_n )
		begin
			if( !rst_n ) begin
				wr_sw_d1 <= 1'b0;
				rd_sw_d1 <= 1'b0;
				snap_tog_d0 <= 1'b0;
				snap_tog_d1 <= 1'b0;
				snap_tog_d2 <= 1'b0;
			end else begin
				wr_sw_d1 <= wr_sw;
				rd_sw_d1 <= rd_sw;
				snap_tog_d0 <= snapshot_toggle;
				snap_tog_d1 <= snap_tog_d0;
				snap_tog_d2 <= snap_tog_d1;
			end
		end
		assign pos_wr_sw_en = {wr_sw_d1,wr_sw} == 2'b01;
		assign pos_rd_sw_en = {rd_sw_d1,rd_sw} == 2'b01;
		assign snap_req_pulse = snap_tog_d1 ^ snap_tog_d2;

		always @( posedge ddr_clk )
		begin
			wr_sw_ack <= pos_wr_sw_en;
			rd_sw_ack <= pos_rd_sw_en;
		end

		// Select which address the read engine uses for the next frame.
		always @( posedge ddr_clk or negedge rst_n )
		begin
			if( !rst_n )
				rd_start_addr <= FRAME_2ND_START_ADDR;
			else if( (view_mode != 3'd0) && saved_valid[view_idx] )
				rd_start_addr <= saved_addr(view_idx);
			else
				rd_start_addr <= live_rd_start_addr;
		end

		// During a snapshot the write engine is redirected to the selected
		// saved-frame address for exactly one complete frame.
		always @( posedge ddr_clk or negedge rst_n )
		begin
			if( !rst_n )
				wr_start_addr <= FRAME_1ST_START_ADDR;
			else if( snap_active )
				wr_start_addr <= saved_addr(snap_wr_slot);
			else
				wr_start_addr <= live_wr_start_addr;
		end

		always @( posedge ddr_clk or negedge rst_n )
		begin
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;
				dirt_bank <= 2'b10;
				dirt_en <= 1'b1;
				clean_en <= 1'b0;
				clean_bank <= 2'b00;
				live_wr_start_addr <= FRAME_1ST_START_ADDR;
				live_rd_start_addr <= FRAME_2ND_START_ADDR;
				saved_valid <= 4'b0000;
				snap_wr_slot <= 2'd0;
				snap_pending <= 1'b0;
				snap_active <= 1'b0;
			end else begin
				if( snap_req_pulse && !snap_active && !snap_pending )
					snap_pending <= 1'b1;

				if( pos_wr_sw_en ) begin
					if( snap_active ) begin
						// The saved frame is complete. Keep the live
						// triple-buffer state untouched.
						saved_valid[snap_wr_slot] <= 1'b1;
						snap_wr_slot <= snap_wr_slot + 1'b1;
						snap_active <= 1'b0;
					end else begin
						// A normal live frame completed. Update the live
						// three-bank rotation as before.
						if( dirt_en ) begin
							wr_bank <= dirt_bank;
							live_wr_start_addr <= (dirt_bank == 2'b00) ? FRAME_1ST_START_ADDR :
							                      (dirt_bank == 2'b01) ? FRAME_2ND_START_ADDR :
							                                             FRAME_3RD_START_ADDR;
							clean_bank <= wr_bank;
							clean_en <= 1'b1;
							dirt_en <= 1'b0;
						end else begin
							wr_bank <= wr_bank;
							clean_en <= clean_en;
						end

						// If K3 was pressed, the next frame is written to
						// the dedicated saved-frame region.
						if( snap_pending ) begin
							snap_pending <= 1'b0;
							snap_active <= 1'b1;
						end
					end
				end else if( pos_rd_sw_en && !freeze ) begin
					// Keep the live read rotation running even while the
					// display is showing a saved frame.
					if( clean_en ) begin
						rd_bank <= clean_bank;
						live_rd_start_addr <= (clean_bank == 2'b00) ? FRAME_1ST_START_ADDR :
						                      (clean_bank == 2'b01) ? FRAME_2ND_START_ADDR :
						                                             FRAME_3RD_START_ADDR;
						dirt_bank <= rd_bank;
						dirt_en <= 1'b1;
						clean_en <= 1'b0;
					end else begin
						rd_bank <= rd_bank;
						dirt_en <= dirt_en;
					end
					clean_en <= 1'b0;
				end
			end
		end
						
	end
	endgenerate


endmodule
