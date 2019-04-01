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

reg [7:0] cd_command_buffer [0:255];
reg [7:0] cd_command_buffer_pos = 0;

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
wire RST_signal = SCSI_RST;
wire ACK_signal = SCSI_ACK;
wire SEL_signal = SCSI_SEL;

localparam BUSY_BIT = 8'h80;
localparam REQ_BIT  = 8'h40;
localparam MSG_BIT  = 8'h20;
localparam CD_BIT   = 8'h10;
localparam IO_BIT   = 8'h08;

localparam PHASE_BUS_FREE    = 8'b00000000;
localparam PHASE_COMMAND     = 8'b00000001;
localparam PHASE_DATA_IN     = 8'b00000010;
localparam PHASE_DATA_OUT    = 8'b00000100;
localparam PHASE_STATUS      = 8'b00001000;
localparam PHASE_MESSAGE_IN  = 8'b00010000;
localparam PHASE_MESSAGE_OUT = 8'b00100000;

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

// Phase handling
reg [7:0] phase = 0;
reg [7:0] current_phase = 0;
reg bus_phase_changed = 0;

// Status sending
reg cd_status_sent = 0;

// Ack handling
reg clear_ack = 0;

// SCSI Command Handling
reg SCSI_think = 0;
reg SCSI_RST = 0;
reg SCSI_ACK = 0;
// @todo SCSI device selected is forced to one here
reg SCSI_SEL = 1;
reg SCSI_SEL_flipflop = 0;
reg SCSI_SEL_flipflop_latch = 0;

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
		phase                 <= 8'b0;
		current_phase         <= PHASE_BUS_FREE; 
		bus_phase_changed			<= 0;
	end else begin
		if (sel) begin
			SCSI_think <= 0;
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
									$display("Read 0x0. dout = 0x%h", {cdc_status[7:3] , 3'b000});
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
									bram_lock <= bram_lock ^ 2;
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
									cdc_status <= din;
									SCSI_SEL_flipflop_latch <= 1;
								end
					8'h01: begin
									//$display("Write to 0x1. 0x%h", din);
									cdc_databus <= din;
									SCSI_think <= 1;
								end
					8'h02: begin
									adpcm_control <= din;
									// Set ACK signal to contents of the interrupt registers 7th bit? A full command will have this bit high
									SCSI_ACK <= din[7];
									SCSI_think <= 1;
									irq2_assert <= din & bram_lock & 8'h7C; // RefreshIRQ2(); ... using din here
									//$display("Write to 0x2. irq2_assert will be: 0x%h", (adpcm_control & bram_lock & 8'h7C) != 0);
								end
					8'h03: begin
									bram_lock <= din;
								end
					8'h04: begin
									cd_reset <= din;
									// Set RST signal to contents of RST registers 2nd bit
									SCSI_RST <= din[1];
									SCSI_think <= 1;
									if (din[1]) begin // if (SCSI_RST)
										$display("CD RESET");
										bram_lock <= bram_lock & 8'h8F; // CdIoPorts[3] &= 0x8F;
										irq2_assert <= (adpcm_control & bram_lock & 8'h7C) != 0; // RefreshIRQ2();
										//$display("Write to 0x4. irq2_assert will be: 0x%h", (adpcm_control & bram_lock & 8'h7C) != 0);
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

		if (SCSI_think) begin
			//$display("SCSI_Think()");
			SCSI_think <= 0;
			case (current_phase)
					PHASE_BUS_FREE: begin
						if (SCSI_SEL) begin
							phase <= PHASE_COMMAND;
							bus_phase_changed <= 1;
						end
					end
					PHASE_COMMAND: begin
						$display ("SCSI_ACK is %b", SCSI_ACK);
						$display ("cd_command_buffer_pos is %h", cd_command_buffer_pos);
						if (REQ_signal && ACK_signal) begin
							$display ("phase_command - setting req false and adding command to buffer");
							// Databus is valid now, so we need to collect a command
							cd_command_buffer_pos <= cd_command_buffer_pos + 1;
							cd_command_buffer [cd_command_buffer_pos] <= cdc_databus;
							// Set the REQ low
							cdc_status[6] <= 0;
							// @todo sort Ack clearing out as soon as we get an ACK that is!
							//clear_ack <= 0;
						end
						if (!REQ_signal && !ACK_signal && cd_command_buffer_pos > 8'h0) begin
							// We got a command!!!!!!!
							//$display ("We got a command! $%h",  cd_command_buffer [cd_command_buffer_pos]);
							$display("We got a command");
							//$finish;
						end
					end
					PHASE_STATUS: begin
						if (REQ_signal && ACK_signal) begin
							// Set the REQ low
							cdc_status[6] <= 0;
							cd_status_sent <= 1;
						end
						if (!REQ_signal && !ACK_signal && cd_status_sent) begin
							// Status sent, so get ready to send the message!
							cd_status_sent <= 0;
							// @todo message_pending message goes on the buss
							//cd_bus.DB = cd.message_pending;
							phase <= PHASE_MESSAGE_IN;
							bus_phase_changed <= 1;
						end
					end
					PHASE_DATA_IN: begin
						//$display ("PHASE_DATA_IN TBC");
						// if (!REQ_signal && !ACK_signal) {
						// if (din.in_count == 0) // aaand we're done!
						// {
						//     CDIRQCallback(0x8000 | PCECD_Drive_IRQ_DATA_TRANSFER_READY);
						//     if (cd.data_transfer_done) {
						//         SendStatusAndMessage(STATUS_GOOD, 0x00);
						//         cd.data_transfer_done = FALSE;
						//         CDIRQCallback(PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
						//     }
						// } else {
						//     cd_bus.DB = din.ReadByte();
						//     SetREQ(TRUE);
						//}
						// }
						// if (REQ_signal && ACK_signal) {
						//puts("REQ and ACK true");
						//SetREQ(FALSE);
						// clear_cd_reg_bits(0x00, REQ_BIT);
					end
					PHASE_MESSAGE_IN: begin
						if (REQ_signal && ACK_signal) begin
							// Set the REQ low
							cdc_status[6] <= 0;
							cdc_status <= cdc_status & ~REQ_BIT;
							//CDMessageSent <= true;
						end
						//if (!REQ_signal && !ACK_signal && CDMessageSent) begin
							//CDMessageSent <= false;
							//change_phase <= PHASE_BUS_FREE;
							//bus_phase_changed <= 1;
						//end
					end
			endcase
		end // End SCSI_Think();

		if (clear_ack) begin
			$display("PCECD: Clearing ACK");
		end

		// This might live in a separate module that we instantiate here?
		if (bus_phase_changed) begin
			//$display("Phase Changed");
			if (current_phase != phase)
				case (phase)
					PHASE_BUS_FREE: begin
						//$display ("PHASE_BUS_FREE");
						cdc_status <= cdc_status & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
						bram_lock <= bram_lock & ~8'h20; // CDIRQ(IRQ_8000, PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
						current_phase <= PHASE_BUS_FREE;
					end
					PHASE_DATA_IN: begin
						//$display ("PHASE_DATA_IN");
						cdc_status <= cdc_status | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
						current_phase <= PHASE_DATA_IN;
					end
					PHASE_STATUS: begin
						//$display ("PHASE_STATUS");
						cdc_status <= cdc_status | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
						current_phase <= PHASE_STATUS;
					end
					PHASE_MESSAGE_IN: begin
						//$display ("PHASE_MESSAGE_IN");
						cdc_status <= cdc_status | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
						current_phase <= PHASE_MESSAGE_IN;
					end
					PHASE_COMMAND: begin
						//$display ("PHASE_COMMAND");
						cdc_status <= cdc_status | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
						current_phase <= PHASE_COMMAND;
					end
				endcase
				bus_phase_changed <= 0;
			end // End current_phase != phase
		end // End bus_phase_changed

		if (SCSI_SEL_flipflop_latch) begin
			if (SCSI_SEL_flipflop) begin
				//$display("**** LATCH LAST ******");
				// This one will get executed last
				SCSI_SEL <= 0;
				SCSI_think <= 1;
				// Reset the flip flop and latch
				SCSI_SEL_flipflop <= 0;
				SCSI_SEL_flipflop_latch <= 0;
			end else begin
				//$display("**** LATCH FIRST ******");
				// This one will get executed first
				SCSI_SEL <= 1;
				SCSI_think <= 1;
				SCSI_SEL_flipflop <= 1;
			end
		end
	end // End else
endmodule