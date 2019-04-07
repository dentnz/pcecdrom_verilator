module pcecd_top(
	input             RESET,
	input             CLOCK,
	
	// cpu register interface
	input             CS_N,
	input             WR_N,
	input             RD_N,
	input      [20:0] ADDR,
	
	input       [7:0] DIN,
	output reg  [7:0] DOUT,
	
	output            irq2_assert,
	
	input             img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	
	output reg [31:0] sd_lba,
	output reg        sd_rd,       // only single sd_rd can be active at any given time
	//output reg      sd_wr,       // only single sd_wr can be active at any given time
	input             sd_ack,

	input       [7:0] sd_buff_addr,	// 256 WORDS!
	input      [15:0] sd_buff_din,	// 16-bit wide. Because the HPS uses that for ROM loading and save game stuff.
	input             sd_buff_wr,
	
	output     [15:0] cd_audio_l,
	output     [15:0] cd_audio_r
);

// CD Data buffer...
//reg [7:0] data_buffer [0:8191];
reg [12:0] data_buffer_pos;
reg [12:0] data_buffer_size;

wire [12:0] data_buffer_addr = data_buffer_pos;
wire [7:0] data_buffer_din = (!data_buffer_addr[0]) ? sd_buff_din[7:0] : sd_buff_din[15:8];

wire data_buffer_wr = (sd_buff_wr && data_buffer_wr_ena) | data_buffer_wr_force;
reg data_buffer_wr_ena;
reg data_buffer_wr_force;

wire [7:0] data_buffer_dout;

cd_data_buffer	cd_data_buffer_inst (
	.clock ( CLOCK ),

	.address ( data_buffer_addr ),
	.data ( data_buffer_din ),
	.wren ( data_buffer_wr ),
	
	.q ( data_buffer_dout )
);

// Using this rather than the main data buffer for DIR info for now. ElectronAsh.
reg [7:0] dir_buffer [0:15];
reg dir_data_out;

// CD Audio FIFO...
reg cdda_play = 1;

reg [9:0] audio_clk_div = 0;
always @(posedge CLOCK) begin
	if (audio_clk_div==486) audio_clk_div <= 0;	// 88,200 Hz, for stereo.
	else audio_clk_div <= audio_clk_div + 1;
end

wire audio_fifo_reset = RESET;
wire audio_fifo_full;
wire audio_fifo_wr = !audio_fifo_full && sd_ack && sd_buff_wr && cdda_play;
wire audio_fifo_empty;
wire audio_fifo_rd = !audio_fifo_empty && (audio_clk_div==0) && cdda_play;

cd_audio_fifo	cd_audio_fifo_inst (
	.aclr ( audio_fifo_reset ),

	.wrclk ( CLOCK ),
	.wrreq ( audio_fifo_wr ),
	.wrfull ( audio_fifo_full ),
	.data ( sd_buff_din ),
	
	.rdclk ( CLOCK ),
	.rdreq ( audio_clk_en ),
	.rdempty ( audio_fifo_empty ),
	.q ( cd_audio_l )
);

//TODO: add hps "channel" to read/write from save ram

reg [7:0] cd_command_buffer [0:15]/*synthesis noprune*/;
reg [3:0] cd_command_buffer_pos = 0;

// Clock stuff
reg [4:0] clock_divider;
always @(posedge CLOCK) clock_divider <= clock_divider + 1;
(*keep*)wire slow_clock = clock_divider==0;

//wire [7:0] gp_ram_do,adpcm_ram_do,save_ram_do;

//- 64K general purpose RAM for the CD software to use
// generic_spram #(16,8) gp_ram(
// 	.clk(CLOCK),
// 	.rst(RESET),
// 	.ce(1'b1),
// 	.we(),
// 	.oe(1'b1),
// 	.addr(),
// 	.di(DIN),
// 	.dout(gp_ram_do)
// );

//- 64K ADPCM RAM for sample storage
// generic_spram #(16,8) adpcm_ram(
// 	.clk(CLOCK),
// 	.rst(RESET),
// 	.ce(1'b1),
// 	.we(),
// 	.oe(1'b1),
// 	.addr(),
// 	.di(DIN),
// 	.dout(adpcm_ram_do)
// );

 //- 2K battery backed RAM for save game data and high scores
// generic_tpram #(11,8) save_ram(
// 	.clk_a(CLOCK),
// 	.rst_a(RESET),
// 	.ce_a(1'b1),
// 	.we_a(),
// 	.oe_a(1'b1),
// 	.addr_a(),
// 	.di_a(DIN),
// 	.do_a(save_ram_do),
// 	.clk_b(CLOCK),
// 	.rst_b(RESET),
// 	.ce_b(1'b1),
// 	.we_b(),
// 	.oe_b(1'b1),
// 	.addr_b(),
// 	.di_b(),
// 	.do_b()
// );

//TODO: check if registers are needed (things are probably bound to some logic with the cd drive), placeholders for now
//wire [7:0] cdc_status = {SCSI_BSY, SCSI_REQ, SCSI_MSG, SCSI_CD, SCSI_IO, SCSI_BIT2, SCSI_BIT1, SCSI_BIT0};             // $1800 - CDC status
wire [7:0] cdc_status = {SCSI_BSY, SCSI_REQ, SCSI_MSG, SCSI_CD, SCSI_IO, 3'b001};             // $1800 - CDC status

always_comb begin
	case (ADDR[7:0])
		// Super System Card registers $18Cx range
		8'hC1: DOUT <= 8'haa;
		8'hC2: DOUT <= 8'h55;
		8'hC3: DOUT <= 8'h00;
		8'hC5: DOUT <= 8'haa;
		8'hC6: DOUT <= 8'h55;
		8'hC7: DOUT <= 8'h03;

		8'h00: DOUT <= cdc_status;
		8'h01: DOUT <= cdc_databus;
		8'h02: DOUT <= adpcm_control;		// Or INT_MASK.
		8'h03: DOUT <= bram_lock;
		8'h04: DOUT <= cd_reset;
		8'h05: DOUT <= convert_pcm;
		8'h06: DOUT <= pcm_data;
		8'h07: DOUT <= bram_unlock;
		8'h08: DOUT <= adpcm_address_low;
		8'h09: DOUT <= adpcm_address_high;
		8'h0A: DOUT <= adpcm_ram_data;
		8'h0B: DOUT <= adpcm_dma_control;
		8'h0C: DOUT <= adpcm_status;
		8'h0D: DOUT <= adpcm_address_control;
		8'h0E: DOUT <= adpcm_playback_rate;
		8'h0F: DOUT <= adpcm_fade_timer;
		default: DOUT <= 8'hFF;
	endcase
end

// CD Interface Register 0x00 - CDC status
	// x--- ---- busy signal
	// -x-- ---- request signal
	// --x- ---- msg bit
	// ---x ---- cd signal
	// ---- x--- i/o signal
localparam BUSY_BIT = 8'h80;
localparam REQ_BIT  = 8'h40;
localparam MSG_BIT  = 8'h20;
localparam CD_BIT   = 8'h10;
localparam IO_BIT   = 8'h08;

localparam PHASE_BUS_FREE    = 8'b00000001;
localparam PHASE_COMMAND     = 8'b00000010;
localparam PHASE_DATA_IN     = 8'b00000100;
localparam PHASE_DATA_OUT    = 8'b00001000;
localparam PHASE_STATUS      = 8'b00010000;
localparam PHASE_MESSAGE_IN  = 8'b00100000;
localparam PHASE_MESSAGE_OUT = 8'b01000000;

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
reg [7:0] phase;
reg [7:0] old_phase;

// Status sending
reg cd_status_sent = 0;
reg cd_message_sent = 0;
reg [2:0] read_state;

// SCSI Command Handling
reg SCSI_RST = 0;
reg SCSI_ACK = 0;
reg SCSI_SEL = 0;

reg SCSI_BSY;
reg SCSI_REQ;
reg SCSI_MSG;
reg SCSI_CD;
reg SCSI_IO;
reg SCSI_BIT2;
reg SCSI_BIT1;
reg SCSI_BIT0;
// ^ Bits [2:0] are probably drive SCSI ID bits.
// The PCE often writes 0x81 (b10000001) to both CDC_STAT and CDC_CMD.
//
// I think it's quite possible that whenever CDC_STAT gets written, that IS the whole SCSI ID
// (of both the PCE (7) and CD drive (0).
//
// (from Io_cd13.PDF)...
//
// "Selection: In this state, the initiator selects a target unit and gets the target to carry out a given function,
// such as reading or writing data. The initator outputs the OR-value of its SCSI-ID and the target's SCSI-ID onto the DATA bus
// (for example, if the initiator is 2 (0000 0100) and the target is 5 (0010 0000) then the OR-ed ID on the bus wil be 0010 0100.)
// The target then determines that it's ID is on the data bus, and sets the BUSY line active."
//
// In short, we can ignore that, and assume that one CD drive is on the bus.
// It looks like the PCE maybe writes the the value 0x81 to both CDC_STAT and CDC_CMD as a kind of double-check.
// And the CD drive ignores that "Command" anyway, since it's not in SELection at that point.
//
// Which is why MAME, bizhawk, and other emulators don't need to have the 0x81 in command parsing table.
// Those emulators just set the SCSI_SEL bit whenever CDC_STAT gets written to (and they also clear the CD transfer IRQ flags).
//

reg [3:0] packet_bytecount;
reg [3:0] status_state;
reg [3:0] message_state;
reg [3:0] command_state;
reg [3:0] data_state;
reg message_after_status = 0;
reg old_ack;
reg [31:0] sd_sector_count;

// READ command parsing stuff... ;)
reg [20:0] frame/*synthesis noprune*/;
reg [7:0] frame_count/*synthesis noprune*/;
reg parse_command;

reg RD_N_1;
reg RD_N_2;

reg WR_N_1;
reg WR_N_2;

(*keep*)wire CDR_RD_N_FALLING = (!RD_N_1 && RD_N_2);
(*keep*)wire CDR_WR_N_FALLING = (!WR_N_1 && WR_N_2);

//TODO: a pcecd_drive module should be probably added
always_ff @(posedge CLOCK) begin
	if (RESET) begin
		SCSI_BSY  <= 1'b0;
		SCSI_REQ  <= 1'b0;
		SCSI_MSG  <= 1'b0;
		SCSI_CD   <= 1'b0;
		SCSI_IO   <= 1'b0;
		SCSI_BIT2 <= 1'b0;
		SCSI_BIT1 <= 1'b0;
		SCSI_BIT0 <= 1'b0;
		SCSI_SEL <= 0;

		status_state <= 0;
		message_state <= 0;
		command_state <= 0;
		data_state <= 0;

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

		phase         <= PHASE_BUS_FREE;

		cd_command_buffer_pos <= 4'd0;

		cd_command_buffer[0] <= 8'h00;
		cd_command_buffer[1] <= 8'h11;
		cd_command_buffer[2] <= 8'h22;
		cd_command_buffer[3] <= 8'h33;
		cd_command_buffer[4] <= 8'h44;
		cd_command_buffer[5] <= 8'h55;
		cd_command_buffer[6] <= 8'h66;
		cd_command_buffer[7] <= 8'h77;
		cd_command_buffer[8] <= 8'h88;
		cd_command_buffer[9] <= 8'h99;
		cd_command_buffer[10] <= 8'hAA;
		cd_command_buffer[11] <= 8'hBB;
		cd_command_buffer[12] <= 8'hCC;
		cd_command_buffer[13] <= 8'hDD;
		cd_command_buffer[14] <= 8'hEE;
		cd_command_buffer[15] <= 8'hFF;

		message_after_status <= 1'b0;

		data_buffer_size <= 4'd0;
		data_buffer_pos <= 0;
		data_buffer_wr_ena <= 0;
		data_buffer_wr_force = 0;

		dir_data_out <= 0;

		read_state <= 0;

		parse_command <= 0;

		sd_rd <= 1'b0;
		//sd_wr <= 1'b0;

		old_phase <= ~phase;	// ElectronAsh. (force a phase update after reset).
	end else begin
		old_phase <= phase;

		RD_N_1 <= RD_N;
		RD_N_2 <= RD_N_1;

		WR_N_1 <= WR_N;
		WR_N_2 <= WR_N_1;

		//sd_rd <= 1'b0;
		//sd_wr <= 1'b0;
		
		old_ack <= sd_ack;

		case (cd_command_buffer[0])
			8'h00: packet_bytecount <= 6;		// Command = 0x00 TEST_UNIT_READY (6)
			8'h08: packet_bytecount <= 6;		// Command = 0x08 READ (6)
			8'hD8: packet_bytecount <= 10;	// Command = 0xD8 NEC_SET_AUDIO_START_POS (10)
			8'hD9: packet_bytecount <= 10;	// Command = 0xD9 NEC_SET_AUDIO_STOP_POS (10)
			8'hDA: packet_bytecount <= 10;	// Command = 0xDA NEC_PAUSE (10)
			8'hDD: packet_bytecount <= 10;	// Command = 0xDD NEC_GET_SUBQ (10)
			8'hDE: packet_bytecount <= 10;	// Command = 0xDE NEC_GET_DIR_INFO (10)
			8'hFF: packet_bytecount <= 1;		// Command = 0xFF END_OF_LIST (1)
			8'h81: packet_bytecount <= 1;		// Command = 0x81 RESET CMD BUFFER (1), maybe?
		endcase

		begin
			if (!CS_N & CDR_RD_N_FALLING) begin
				case (ADDR[7:0])
					// Super System Card registers $18Cx range
					//8'hC1: DOUT <= 8'haa;
					//8'hC2: DOUT <= 8'h55;
					//8'hC3: DOUT <= 8'h00;
					//8'hC5: DOUT <= 8'haa;
					//8'hC6: DOUT <= 8'h55;
					//8'hC7: DOUT <= 8'h03;

					8'h00: begin	// 0x1800 CDC_STAT
						//DOUT <= cdc_status;
						$display("Read 0x0. dout = 0x%h", cdc_status);
					end
					8'h01: begin	// 0x1801 CDC_CMD
						//DOUT <= cdc_databus;
					end
					8'h02: begin	// 0x1802 INT_MASK
						$display("Read 0x2. dout = 0x%h", adpcm_control);
						//DOUT <= adpcm_control;
					end
					8'h03: begin	// 0x1803 BRAM_LOCK
						$display("Read 0x3. dout = 0x%h", bram_lock);
						//DOUT <= bram_lock;
						bram_lock <= bram_lock ^ 2;
						$display("bram_enabled = 0x%h", 1'b0);
						bram_enabled <= 1'b0;
					end
					8'h04: begin	// 0x1804 CD_RESET
						$display("Read 0x4. dout = 0x%h", cd_reset);
						//DOUT <= cd_reset;
					end
					8'h05: begin	// 0x1805
						//DOUT <= convert_pcm;
					end
					8'h06: begin	// 0x1806
						//DOUT <= pcm_data;
					end
					8'h07: begin	// 0x1807
						//DOUT <= bram_unlock;
					end
					8'h08: begin	// 0x1808
						//DOUT <= adpcm_address_low;
					end
					8'h09: begin	// 0x1809
						//DOUT <= adpcm_address_high;
					end
					8'h0A: begin	// 0x180A
						//DOUT <= adpcm_ram_data;
					end
					8'h0B: begin	// 0x180B
						//DOUT <= adpcm_dma_control;
					end
					8'h0C: begin	// 0x180C
						//DOUT <= adpcm_status;
					end
					8'h0D: begin	// 0x180D
						//DOUT <= adpcm_address_control;
					end
					8'h0E: begin	// 0x180E
						//DOUT <= adpcm_playback_rate;
					end
					8'h0F: begin	// 0x180F
						//DOUT <= adpcm_fade_timer;
					end
					default:; //DOUT <= 8'hFF;
				endcase
			end

			if (!CS_N & CDR_WR_N_FALLING) begin
				case (ADDR[7:0])
					8'h00: begin	// 0x1800 CDC_STAT
						// The MAME code normally assumes there is only ONE drive on the bus.
						// So no real point checking to see if the ID matches before setting SCSI_SEL.
						// But we could add a check for seeing 0x81 written to CDC_STAT (or CDC_CMD?) later on.

						if (DIN==8'h81) begin		// Selection "command", AFAIK. (bitwise OR of the PCE and drive SCSI IDs).
							SCSI_BIT2 <= DIN[2];		// Lower three bits are probably the drive's SCSI ID.
							SCSI_BIT1 <= DIN[1];		// Which will normally be set to 0b00000001 (bit 0 set == SCSI ID 0).
							SCSI_BIT0 <= DIN[0];
							SCSI_SEL <= 1;				// Select!
							status_state <= 0;
							message_state <= 0;
							command_state <= 0;
							data_state <= 0;
							cd_command_buffer_pos <= 0;
							parse_command <= 0;
							phase <= PHASE_COMMAND;	// ElectronAsh.
						end
					end
					8'h01: begin	// 0x1801 CDC_CMD
						cdc_databus <= DIN;
						if (DIN==8'h81) begin			// Deselect "command", AFAIK. (bitwise OR of the PCE and drive SCSI IDs).
							SCSI_BIT2 <= 0;
							SCSI_BIT1 <= 0;
							SCSI_BIT0 <= 0;
							SCSI_SEL <= 0;					// Deselect!
							phase <= PHASE_BUS_FREE;	// ElectronAsh.
						end
					end
					8'h02: begin	// 0x1802 INT_MASK
						adpcm_control <= DIN;
						// Set ACK signal to contents of the interrupt registers 7th bit? A full command will have this bit high
						SCSI_ACK <= DIN[7];
						//SCSI_think <= 1;
						irq2_assert <= (DIN & bram_lock & 8'h7C) != 0; // RefreshIRQ2(); ... using din here
					end
					8'h03: begin	// 0x1803 BRAM_LOCK
						bram_lock <= DIN;
					end
					8'h04: begin	// 0x1804 CD_RESET
						cd_reset <= DIN;
						// Set RST signal to contents of RST registers 2nd bit
						SCSI_RST <= (DIN & 8'h02) != 0;
						//SCSI_think <= 1;
						status_state <= 0;
						message_state <= 0;
						command_state <= 0;
						data_state <= 0;
						message_after_status <= 1'b0;
						data_buffer_size <= 4'd0;
						data_buffer_pos <= 0;
						dir_data_out <= 0;
						read_state <= 0;
						parse_command <= 0;
						if ((DIN & 8'h02) != 0) begin // if (SCSI_RST)
							SCSI_SEL <= 0;					// Deselect.
							phase <= PHASE_BUS_FREE;
							cd_command_buffer_pos <= 4'd0;
							data_buffer_wr_ena <= 0;
							data_buffer_wr_force = 0;
							bram_lock <= bram_lock & 8'h8F; // CdIoPorts[3] &= 0x8F;
							irq2_assert <= (adpcm_control & bram_lock & 8'h7C) != 0; // RefreshIRQ2();
						end
					end
					8'h05: begin	// 0x1805
						convert_pcm <= DIN;
					end
					8'h06: begin	// 0x1806
						pcm_data <= DIN;
					end
					8'h07: begin	// 0x1807
						bram_unlock <= DIN;
					end
					8'h08: begin	// 0x1808
						adpcm_address_low <= DIN;
					end
					8'h09: begin	// 0x1809
						adpcm_address_high <= DIN;
					end
					8'h0A: begin	// 0x180A
						adpcm_ram_data <= DIN;
					end
					8'h0B: begin	// 0x180B
						adpcm_dma_control <= DIN;
					end
					8'h0C: begin	// 0x180C
						adpcm_status <= DIN;
					end
					8'h0D: begin	// 0x180D
						adpcm_address_control <= DIN;
					end
					8'h0E: begin	// 0x180E
						adpcm_playback_rate <= DIN;
					end
					8'h0F: begin	// 0x180F
						adpcm_fade_timer <= DIN;
					end
				endcase
			end // end wr

			if (SCSI_RST) begin
				$display("Performing reset");
				SCSI_BSY  <= 1'b0;
				SCSI_REQ  <= 1'b0;
				SCSI_MSG  <= 1'b0;
				SCSI_CD   <= 1'b0;
				SCSI_IO   <= 1'b0;
				SCSI_BIT2 <= 1'b0;
				SCSI_BIT1 <= 1'b0;
				SCSI_BIT0 <= 1'b0;

				SCSI_ACK <= 1'b0;
				SCSI_RST <= 1'b0;

				SCSI_SEL <= 1'b0;

				cd_command_buffer_pos <= 4'd0;
				
				// @todo Clear the command buffer
				// @todo Stop all reads
				// @todo Stop all audio
			end

			// Phase Changes stuff
			if (!SCSI_RST) begin
				if (phase!=old_phase) begin
					case (phase)
						PHASE_BUS_FREE: begin
							$display ("PHASE_BUS_FREE");
							//cdc_status <= cdc_status & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
							SCSI_BSY <= 0;	// Clear BUSY_BIT.
							SCSI_REQ <= 0;	// Clear REQ_BIT.
							SCSI_MSG <= 0;	// Clear MSG_BIT.
							SCSI_CD  <= 0;	// Clear CD_BIT.
							SCSI_IO  <= 0;	// Clear IO_BIT.
							SCSI_BIT2 <= 0;	// Deselection seems to clear the lower bits (SCSI ID?) as well. ElectronAsh.
							SCSI_BIT1 <= 0;
							SCSI_BIT0 <= 0;
							bram_lock <= bram_lock & ~8'h20; // CDIRQ(IRQ_8000, PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
							cdc_databus <= 8'h00;	// Returning 0x00 for the "status" byte atm.
							cd_command_buffer_pos <= 0;
						end
						PHASE_COMMAND: begin	
							$display ("PHASE_COMMAND");
							//cdc_status <= cdc_status | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
							SCSI_BSY <= 1;	// Set BUSY_BIT.
							SCSI_REQ <= 1;	// Set REQ_BIT.
							SCSI_MSG <= 0;	// Clear MSG_BIT.
							SCSI_CD  <= 1;	// Set CD_BIT.
							SCSI_IO  <= 0;	// Clear IO_BIT.
						end
						PHASE_STATUS: begin
							$display ("PHASE_STATUS");
							//cdc_status <= cdc_status | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
							SCSI_BSY <= 1;	// Set BUSY_BIT.
							SCSI_REQ <= 1;	// Set REQ_BIT.
							SCSI_MSG <= 0;	// Clear MSG_BIT.
							SCSI_CD  <= 1;	// Set CD_BIT.
							SCSI_IO  <= 1;	// Set IO_BIT.
						end
						PHASE_DATA_IN: begin
							$display ("PHASE_DATA_IN");
							//cdc_status <= cdc_status | BUSY_BIT |  REQ_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT;
							SCSI_BSY <= 1;	// Set BUSY_BIT.
							SCSI_REQ <= 1;	// Set REQ_BIT.
							SCSI_MSG <= 0;	// Clear MSG_BIT.
							SCSI_CD <= 0;	// Clear CD_BIT.
							SCSI_IO <= 1;	// Set IO_BIT.
						end
						PHASE_MESSAGE_IN: begin
							$display ("PHASE_MESSAGE_IN");
							//cdc_status <= cdc_status | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
							SCSI_BSY <= 1;	// Set BUSY_BIT. [7]
							SCSI_REQ <= 1;	// Set REQ_BIT. [6]
							SCSI_MSG <= 1;	// Set MSG_BIT. [5]
							SCSI_CD <= 1;	// Set CD_BIT.  [4]
							SCSI_IO <= 1;	// Set IO_BIT.  [3]
						end
					endcase
				end // end old phase check;
			end // End phase changes

			if (slow_clock) begin
				if (SCSI_SEL && phase==PHASE_COMMAND && !parse_command) begin
					case (command_state)
					0: if (SCSI_ACK) begin
						SCSI_REQ <= 1'b0;					// Clear the REQ.
						command_state <= command_state + 1;
					end
					
					1: if (!SCSI_ACK) begin
						//SCSI_REQ <= 1'b1;
						command_state <= command_state + 1;
					end
					
					2: begin	// PCE should have written to CDC_CMD at this point!
						cd_command_buffer[cd_command_buffer_pos] <= cdc_databus;	// Grab the packet byte!
						cd_command_buffer_pos <= cd_command_buffer_pos + 1;
						command_state <= command_state + 1;
					end
					
					3: begin
						if (cd_command_buffer_pos < packet_bytecount) begin	// More bytes left to grab...
							SCSI_REQ <= 1;
							command_state <= 0;
						end
						else begin						// Else...
							SCSI_REQ <= 0;				// Stop REQuesting bytes!
							cd_command_buffer_pos <= 0;
							read_state <= 0;
							parse_command <= 1;
							//cdc_databus <= 8'h00;	// Returning 0x00 for the "status" byte atm.
							//phase <= PHASE_STATUS;	// TESTING! ElectronAsh.
						end
					end
					default:;
					endcase
				end
				
				if (SCSI_SEL && phase==PHASE_STATUS) begin
					case (status_state)
					0: if (SCSI_ACK) begin
						//cdc_databus <= cd_command_buffer[cd_command_buffer_pos];
						SCSI_REQ <= 1'b0;					// Clear the REQ.
						status_state <= status_state + 1;
					end
					
					1: if (!SCSI_ACK) begin
						//SCSI_REQ <= 1'b1;
						status_state <= status_state + 1;
					end
					
					2: /*if (!CS_N && CDR_RD_N_FALLING && ADDR[7:0]==8'h00)*/ begin	// Wait for PCE to read from CDC_STAT.
						cd_command_buffer_pos <= 0;
						cdc_databus <= 8'h00;		// Returning 0x00 for the "message" byte atm.
						phase <= PHASE_MESSAGE_IN;	// TESTING! ElectronAsh.
					end

					default:;
					endcase
				end
				
				if (SCSI_SEL && phase==PHASE_MESSAGE_IN) begin
					case (message_state)
					0: if (SCSI_ACK) begin
						//cdc_databus <= cd_command_buffer[cd_command_buffer_pos];
						SCSI_REQ <= 1'b0;					// Clear the REQ.
						message_state <= message_state + 1;
					end
					
					1: if (!SCSI_ACK) begin
						message_state <= message_state + 1;
					end
					
					2: begin
						cd_command_buffer_pos <= 0;
						phase <= PHASE_BUS_FREE;
					end
					
					default:;
					endcase
				end
				
				if (SCSI_SEL && phase==PHASE_DATA_IN) begin
					if (dir_data_out) cdc_databus <= dir_buffer[data_buffer_pos[3:0]];
					else cdc_databus <= data_buffer_dout;
					
					case (data_state)
					0: if (SCSI_ACK) begin
						SCSI_REQ <= 1'b0;					// Clear the REQ.
						data_state <= data_state + 1;
					end
					
					1: if (!SCSI_ACK) begin
						data_state <= data_state + 1;
						data_buffer_pos <= data_buffer_pos + 1;
					end
					
					2: begin
						if (data_buffer_pos < data_buffer_size) begin
							SCSI_REQ <= 1'b1;	// More bytes left to SEND to PCE.
							data_state <= 0;
						end
						else begin						// Else, done!
							dir_data_out <= 0;
							data_buffer_pos <= 0;
							cdc_databus <= 8'h00;	// Returning 0x00 for the "status" byte atm.
							// TODO: set IRQ TRANSFER DONE Interrupt Enable bit here! (I think).
							phase <= PHASE_STATUS;	// TESTING! ElectronAsh.
						end
					end
					
					default:;
					endcase
				end
		end // end if slow_clock.
			
		// Command parser
		if (parse_command) begin
			case (cd_command_buffer[0])
			8'h00: begin	// TEST_UNIT_READY (6).
				message_after_status <= 1'b1;	// Need to confirm for this command.
				parse_command <= 0;
				cdc_databus <= 8'h00;
				phase <= PHASE_STATUS;
			end
			
			8'h08: begin	// READ (6).
				case (read_state)
				0: begin
					//frame <= {cd_command_buffer[1][4:0], cd_command_buffer[2], cd_command_buffer[3]};
					frame <= {cd_command_buffer[1][4:0], cd_command_buffer[2], cd_command_buffer[3]} - 21'h000f32;	// Trying a 2048-byte ISO.
					frame_count <= cd_command_buffer[4];
					
					// VHD / SD loading works in 512-byte sector blocks.
					// For save backups in the tg16 core, it uses a 16-bit width, so the buffers
					// are 256 WORDS.
					// We'll need to request multiple 512-byte sectors for each of our 2048-byte CD ISO sectors.				
					//sd_lba <= (({cd_command_buffer[1][4:0], cd_command_buffer[2], cd_command_buffer[3]} - 225) * 2352) / 512;
					sd_lba <= ({cd_command_buffer[1][4:0], cd_command_buffer[2], cd_command_buffer[3]} - 21'h000f32) * 4;	// Trying a 2048-byte ISO.
					
					sd_sector_count <= 0;
					
					sd_rd <= 1'b1;
					data_buffer_pos <= 0;
					data_buffer_wr_ena <= 1;
					read_state <= read_state + 1;
				end
				
				
				// This is a bit of a kludge atm, due to the HPS using a 16-bit bus for cart ROM / VHD loading... ElectronAsh.
				1: if (sd_ack && sd_buff_wr) begin
					sd_rd <= 1'b0;								// Need to clear sd_rd as soon as sd_ack goes high, apparently.
					data_buffer_pos <= data_buffer_pos + 1;
					data_buffer_wr_force = 1;				// Force a write to the data buffer on the NEXT clock, for the upper data byte (16-bit HPS bus).
					read_state <= read_state + 1;			// (the lower data byte will get written directly by the HPS via sd_wr.)
				end
				
				2: begin
					data_buffer_wr_force = 0;
					data_buffer_pos <= data_buffer_pos + 1;

					// Check for sd_ack low, after each 512-byte VHD / SD sector is transferred into the buffer.
					if (!sd_ack) begin
						sd_lba <= sd_lba + 1;
						sd_sector_count <= sd_sector_count + 1;
						read_state <= read_state + 1;
					end
					else read_state <= read_state - 1;	// Else, loop back!
				end
				
				3: begin
					if (sd_sector_count < frame_count*4) begin
						read_state <= 1;
					end
					else begin												// Else, done!
						sd_rd <= 1'b0;										// Stop requesting SD (VHD) sectors from the HPS!
						data_buffer_size <= (frame_count*4)*512;
						data_buffer_wr_ena <= 0;
						// TODO: set IRQ TRANSFER READY Enable bit here!
						parse_command <= 0;
						phase <= PHASE_DATA_IN;
					end
				end
				default:;
				endcase				
			end
			
			8'hD8: begin	// NEC_SET_AUDIO_START_POS (10).
			
			end
			8'hD9: begin	// NEC_SET_AUDIO_STOP_POS (10).
			
			end
			8'hDA: begin	// NEC_PAUSE (10).
			
			end
			8'hDD: begin	// NEC_GET_SUBQ (10).
			
			end
			8'hDE: begin	// NEC_GET_DIR_INFO (10).
			
				case (cd_command_buffer[1])
				8'h00: begin	// Get the first and last track numbers.
					dir_buffer[0] <= 8'h01;	// Rondo - First track (BCD).
					dir_buffer[1] <= 8'h22;	// Rondo - Last track (BCD).
					data_buffer_size <= 2;
					data_buffer_pos <= 0;
					dir_data_out <= 1;
					parse_command <= 0;
					phase <= PHASE_DATA_IN;
				end
				
				8'h01: begin	// Get total disk size in MSF.
					dir_buffer[0] <= 8'h49;	// Rondo - Minutes = 0x49 (73).
					dir_buffer[1] <= 8'h09;	// Rondo - Seconds = 0x09 (9).
					dir_buffer[2] <= 8'h12;	// Rondo - Frames = 0x12 (18).
					data_buffer_size <= 3;
					data_buffer_pos <= 0;
					dir_data_out <= 1;
					parse_command <= 0;
					phase <= PHASE_DATA_IN;
				end
				
				8'h02: begin	// Get track information.
					if (cd_command_buffer[2] == 8'hAA) begin
						// MAME...
						// frame = toc->tracks[toc->numtrks-1].logframeofs;
						// frame += toc->tracks[toc->numtrks-1].frames;
						dir_buffer[3] <= 8'h04;	//? check MAME code
					end
					else begin
						// track = std::max(bcd_2_dec(m_command_buffer[2]), 1U);
						// frame = toc->tracks[track-1].logframeofs;
						// // PCE wants the start sector for data tracks to *not* include the pregap
						// if (toc->tracks[track-1].trktype != CD_TRACK_AUDIO)
						// {
						// 	frame += toc->tracks[track-1].pregap;
						// }
						// m_data_buffer[3] = (toc->tracks[track-1].trktype == CD_TRACK_AUDIO) ? 0x00 : 0x04;
						//dir_buffer[3] <= 8'h00;
					end
					
					if (cd_command_buffer[2]==8'h01) begin
						dir_buffer[0] <= 8'h00;	// M
						dir_buffer[1] <= 8'h02;	// S
						dir_buffer[2] <= 8'h00;	// F
						dir_buffer[3] <= 8'h00;	// Track type. (Rondo, track 1, Audio)
					end
					if (cd_command_buffer[2]==8'h02) begin
						dir_buffer[0] <= 8'h00;	// M
						dir_buffer[1] <= 8'h53;	// S
						dir_buffer[2] <= 8'h65;	// F
						dir_buffer[3] <= 8'h04;	// Track type. (Rondo, track 2, DATA)
					end
					
					data_buffer_size <= 4;
					data_buffer_pos <= 0;
					dir_data_out <= 1;
					parse_command <= 0;
					phase <= PHASE_DATA_IN;
				end
				default:;	// Unknown DIR command packet.
				endcase
			end
			8'hFF: begin	// END_OF_LIST (1).
			
			end
			default:;	// Unknown command.
			endcase
		end

		end // end if sel - and our main logic
	end // end else main
end // end always

endmodule