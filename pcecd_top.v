module pcecd_top(
	input            reset,
	input            clk,
	// cpu register interface
	input            sel,
	input  [7:0]     addr,
	input            wr,
	input            rd,
	output reg [7:0] dout,
	input      [7:0] din,
	output           irq2_assert
);

//TODO: add hps "channel" to read/write from save ram

//wire [7:0] gp_ram_do,adpcm_ram_do,save_ram_do;

//- 64K general purpose RAM for the CD software to use
// generic_spram #(16,8) gp_ram(
// 	.clk(clk),
// 	.rst(reset),
// 	.ce(1'b1),
// 	.we(),
// 	.oe(1'b1),
// 	.addr(),
// 	.di(din),
// 	.dout(gp_ram_do)
// );

//- 64K ADPCM RAM for sample storage
// generic_spram #(16,8) adpcm_ram(
// 	.clk(clk),
// 	.rst(reset),
// 	.ce(1'b1),
// 	.we(),
// 	.oe(1'b1),
// 	.addr(),
// 	.di(din),
// 	.dout(adpcm_ram_do)
// );

 //- 2K battery backed RAM for save game data and high scores
// generic_tpram #(11,8) save_ram(
// 	.clk_a(clk),
// 	.rst_a(reset),
// 	.ce_a(1'b1),
// 	.we_a(),
// 	.oe_a(1'b1),
// 	.addr_a(),
// 	.di_a(din),
// 	.do_a(save_ram_do),
// 	.clk_b(clk),
// 	.rst_b(reset),
// 	.ce_b(1'b1),
// 	.we_b(),
// 	.oe_b(1'b1),
// 	.addr_b(),
// 	.di_b(),
// 	.do_b()
// );

//TODO: check if registers are needed (things are probably bound to some logic with the cd drive), placeholders for now
reg [7:0] cdc_status;             // $1800 - CDC status

// CD Interface Register 0x00 - CDC status
	// x--- ---- busy signal
	// -x-- ---- request signal
	// --x- ---- msg bit
	// ---x ---- cd signal
	// ---- x--- i/o signal

// Signals under our(the "target") control.
wire BSY_signal = cdc_status[7];
wire REQ_signal = cdc_status[6];
wire MSG_signal = cdc_status[5];
wire CD_signal = cdc_status[4];
wire IO_signal = cdc_status[3];

// Signals under the control of the initiator(not us!)
// wire RST_signal = cdc_status[0];
// wire ACK_signal = cdc_status[1];
// wire SEL_signal = cdc_status[2];
reg [0:0] SCSI_RST = 0;
reg [0:0] SCSI_ACK = 0;
reg [0:0] SCSI_SEL = 0;

reg [7:0] cdc_databus;            // $1801 - CDC command / status / data //TODO: this will probably change to a wire connected to the pcecd_drive module
reg [7:0] adpcm_control;          // $1802 - ADPCM / CD control

reg [7:0] bram_lock;              // $1803 - BRAM lock / CD status
reg bram_enabled;

reg [7:0] cd_reset;               // $1804 - CD reset
reg [7:0] convert_pcm;            // $1805 - Convert PCM data / PCM data
reg [7:0] pcm_data;               // $1806 - PCM data
reg [7:0] bram_unlock;            // $1807 - BRAM unlock / CD status
reg [7:0] adpcm_address_low;      // $1808 - ADPCM address (LSB) / CD data
reg [7:0] adpcm_address_high;     // $1809 - ADPCM address (MSB)
reg [7:0] adpcm_ram_data;         // $180A - ADPCM RAM data port
reg [7:0] adpcm_dma_control;      // $180B - ADPCM DMA control
reg [7:0] adpcm_status;           // $180C - ADPCM status
reg [7:0] adpcm_address_control;  // $180D - ADPCM address control
reg [7:0] adpcm_playback_rate;    // $180E - ADPCM playback rate
reg [7:0] adpcm_fade_timer;       // $180F - ADPCM and CD audio fade timer

//TODO: a pcecd_drive module should be probably added
always_ff @(posedge clk) begin
	if (reset) begin
		cdc_status            <= 8'b0;
		cdc_databus           <= 8'b0;
		adpcm_control         <= 8'b0;
		bram_lock             <= 8'b0;
		bram_enabled          <= 1'b1;
		cd_reset              <= 8'b0;
		convert_pcm           <= 8'b0;
		pcm_data              <= 8'b0;
		bram_unlock           <= 8'b0;
		adpcm_address_low     <= 8'b0;
		adpcm_address_high    <= 8'b0;
		adpcm_ram_data        <= 8'b0;
		adpcm_dma_control     <= 8'b0;
		adpcm_status          <= 8'b0;
		adpcm_address_control <= 8'b0;
		adpcm_playback_rate   <= 8'b0;
		adpcm_fade_timer      <= 8'b0;
	end else begin
		if (sel) begin
			if (rd) begin
				case (addr)
					// Super System Card registers $18Cx range
					8'hC1: dout <= 8'haa;
					8'hC2: dout <= 8'h55;
					8'hC3: dout <= 8'h00;
					8'hC5: dout <= 8'haa;
					8'hC6: dout <= 8'h55;
					8'hC7: dout <= 8'h03;
					// $1800 - CDC status
					8'h00: begin
									dout <= {cdc_status[7:3] , 3'b000};
								end
					8'h01: begin
									dout <= cdc_databus;
								end
					8'h02: begin
									$display("Read 0x2. dout = 0x%h", adpcm_control);
									dout <= adpcm_control;
								end
					8'h03: begin
									$display("Read 0x3. dout = 0x%h", bram_lock);
									dout <= bram_lock;
									$display("bram_enabled = 0x%h", 1'b0);
									bram_enabled <= 1'b0;
								end
					8'h04: begin
									$display("Read 0x4. dout = 0x%h", cd_reset);
									dout <= cd_reset;
								end
					8'h05: begin
									dout <= convert_pcm;
								end
					8'h06: begin
									dout <= pcm_data;
								end
					8'h07: begin
									dout <= bram_unlock;
								end
					8'h08: begin
									dout <= adpcm_address_low;
								end
					8'h09: begin
									dout <= adpcm_address_high;
								end
					8'h0A: begin
									dout <= adpcm_ram_data;
								end
					8'h0B: begin
									dout <= adpcm_dma_control;
								end
					8'h0C: begin
									dout <= adpcm_status;
								end
					8'h0D: begin
									dout <= adpcm_address_control;
								end
					8'h0E: begin
									dout <= adpcm_playback_rate;
								end
					8'h0F: begin
									dout <= adpcm_fade_timer;
								end
					default: dout <= 8'hFF;
				endcase

			end else if (wr) begin
				case (addr)
					// $1800 - CDC status
					8'h00: begin
									// We will need to latch this
									cdc_status <= din;
									SCSI_SEL <= 1; // Set SEL high
									// SCSI.Think();
									SCSI_SEL <= 0; // Set SEL low
									// SCSI.Think();
								end
					8'h01: begin
									cdc_databus <= din;
									// SCSI.Think();
								end
					8'h02: begin
									adpcm_control <= din;
									SCSI_ACK <= (din & 8'h80) != 0;
									// SCSI.Think();
									irq2_assert <= (din & bram_lock & 8'h7C) != 0; // RefreshIRQ2(); ... using din here
									$display("Write to 0x2. irq2_assert will be: 0x%h", (adpcm_control & bram_lock & 8'h7C) != 0);
								end
					8'h03: begin
									bram_lock <= din;
								end
					8'h04: begin
									cd_reset <= din;
									SCSI_RST <= (din & 8'h2) != 0;
									// SCSI.Think();
									if ((din & 8'h02) != 0) begin // if (SCSI_RST)
										bram_lock <= bram_lock & 8'h8F;
										irq2_assert <= (adpcm_control & bram_lock & 8'h7C) != 0; // RefreshIRQ2();
										$display("Write to 0x4. irq2_assert will be: 0x%h", (adpcm_control & bram_lock & 8'h7C) != 0);
									end
								end
					8'h05: begin
									convert_pcm <= din;
								end
					8'h06: begin
									pcm_data <= din;
								end
					8'h07: begin
									bram_unlock <= din;
								end
					8'h08: begin
									adpcm_address_low <= din;
								end
					8'h09: begin
									adpcm_address_high <= din;
								end
					8'h0A: begin
									adpcm_ram_data <= din;
								end
					8'h0B: begin
									adpcm_dma_control <= din;
								end
					8'h0C: begin
									adpcm_status <= din;
								end
					8'h0D: begin
									adpcm_address_control <= din;
								end
					8'h0E: begin
									adpcm_playback_rate <= din;
								end
					8'h0F: begin
									adpcm_fade_timer <= din;
								end
				endcase
			end
		end
		// logic , state machine etc.. comes here
	end
end

endmodule