////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PC ENGINE CD STUFF
// @see https://github.com/libretro/beetle-pce-fast-libretro/blob/master/mednafen/pce_fast/pcecd_drive.cpp
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 

#define PCE_CD_COMMAND_BUFFER_SIZE  0x10

// PCE CD stuff. ElectronAsh...
bool m_message_after_status = 0;
uint8_t m_command_buffer[PCE_CD_COMMAND_BUFFER_SIZE];
int  m_command_buffer_index;
bool m_status_sent = 0;
bool m_message_sent = 0;
bool m_selected = 0;
bool m_scsi_SEL = 1;
bool m_scsi_ATN = 0;
bool m_cd_motor_on = 1;
bool m_cd_file = 1;	// Just says when MAME has loaded an ISO file. Spoofing for now. ElectronAsh.

bool my_flag = 0;

// CDC_STAT reg (0x00).
#define BUSY_BIT 0x80
#define REQ_BIT 0x40
#define MSG_BIT 0x20
#define CD_BIT 0x10
#define IO_BIT 0x08

// INT_MASK reg (0x02).
#define ACK_BIT 0x80
#define INTACK_BIT 0x40
#define DONE_BIT 0x20
#define BRAM_BIT 0x10
#define ADF_BIT 0x08
#define ADH_BIT 0x04
#define CDDA_BIT 0x02

// Signals under the control of the initiator(not us!)
#define PCECD_Drive_kingRST_mask	0x020
#define PCECD_Drive_kingACK_mask	0x040
#define PCECD_Drive_kingSEL_mask	0x100

// BRAM_LOCK (Interrupt FLAG) reg (0x03) bites...
#define PCE_CD_IRQ_TRANSFER_READY       0x40
#define PCE_CD_IRQ_TRANSFER_DONE        0x20
#define PCE_CD_IRQ_BRAM                 0x10
#define PCE_CD_IRQ_SAMPLE_FULL_PLAY     0x08
#define PCE_CD_IRQ_SAMPLE_HALF_PLAY     0x04


// No longer needed.
// Interrupts are handled in the logic now, by setting the Interrupt FLAG bits in BRAM_LOCK.
// (and the appropriate mask bits in INT_MASK.)
// void trigger_cd_irq() {
// 	spi_uio_cmd_cont(0x52);
// 	spi_b(0);	// Dummy write should trigger the CD Interrupt (IRQ2_N on the PCE core).
// 	DisableIO();
// }

uint8_t read_cd_reg(uint8_t addr) {
	spi_uio_cmd_cont(0x50);
	spi_b(addr);
	uint8_t data = spi_b(0);
	DisableIO();
	return data;
}

void write_cd_reg(uint8_t addr, uint8_t data) {
	spi_uio_cmd_cont(0x51);
	spi_b(addr);
	spi_b(data);
	DisableIO();
}

void set_cd_reg_bits(uint8_t addr, uint8_t mask) {
	uint8_t oldreg = read_cd_reg(addr);
	write_cd_reg(addr, oldreg | mask);
}

void clear_cd_reg_bits(uint8_t addr, uint8_t mask) {
	uint8_t oldreg = read_cd_reg(addr);
	oldreg &= ~mask;
	write_cd_reg(addr, oldreg);
}

static void CDIRQ(int type)
{
	if(type & 0x8000)
	{
		type &= 0x7FFF;
		if(type == PCE_CD_IRQ_TRANSFER_DONE)
			clear_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE); //_Port[0x3] &= ~0x20;
		else if(type == PCE_CD_IRQ_TRANSFER_READY)
			clear_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_READY); //_Port[0x3] &= ~0x40;
	}
	else if(type == PCE_CD_IRQ_TRANSFER_DONE)
	{
		set_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE); //_Port[0x3] |= 0x20;
	}
	else if(type == PCE_CD_IRQ_TRANSFER_READY)
	{
		set_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_READY); //_Port[0x3] |= 0x40;
	}
	//update_irq_state();
}

#define SCSI_STATUS_OK          0x00
#define SCSI_CHECK_CONDITION    0x02

// CD Command 0x00 - TEST UNIT READY
void test_unit_ready()
{
	printf("PCE_CD: test unit ready\n");
	// @todo currently always sending ok status
	//if (m_cd_file)
	//{
		printf("PCE_CD: Sending STATUS_OK status\n");
		reply_status_byte(SCSI_STATUS_OK);
	//}
	//else
	//{
	//	printf("PCE_CD: Sending CHECK_CONDITION status\n");
	//	reply_status_byte(SCSI_CHECK_CONDITION);
	//}
}

// Phase enum
enum
{
	PHASE_BUS_FREE = 0,
	PHASE_COMMAND,
	PHASE_DATA_IN,
	PHASE_DATA_OUT,
	PHASE_STATUS,
	PHASE_MESSAGE_IN,
	PHASE_MESSAGE_OUT
};

static unsigned int CurrentPhase;

static void ChangePhase(const unsigned int new_phase)
{
	printf("PCE_CD: ChangePhase - New phase: %d\n", new_phase);
	switch(new_phase)
	{
		case PHASE_BUS_FREE:
			// SetBSY(false);
			// SetMSG(false);
			// SetCD(false);
			// SetIO(false);
			// SetREQ(false);
			clear_cd_reg_bits(0x00, BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT);
			
			// @todo - Needto figure out what this is doing
			printf("trying to put cd irq into transfer done\n");
			CDIRQ(0x8000 | PCE_CD_IRQ_TRANSFER_DONE);
			break;

		case PHASE_DATA_IN:		// Us to them
			// SetBSY(true);
			// SetIO(true);
			// //SetREQ(true);
			// SetMSG(false);
			// SetCD(false);
			// SetREQ(false);
			set_cd_reg_bits(0x00, BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT);
			break;

		case PHASE_STATUS:		// Us to them
			// SetBSY(true);
			// SetCD(true);
			// SetIO(true);
			// SetREQ(true);
			// SetMSG(false);
			set_cd_reg_bits(0x00, BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT);
			break;

		case PHASE_MESSAGE_IN:	// Us to them
			// SetBSY(true);
			// SetMSG(true);
			// SetCD(true);
			// SetIO(true);
			// SetREQ(true);
			set_cd_reg_bits(0x00, BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT);
			break;

		case PHASE_COMMAND:		// Them to us
			// SetBSY(true);
			// SetCD(true);
			// SetREQ(true);
			// SetIO(false);
			// SetMSG(false);
			set_cd_reg_bits(0x00, BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT);
			break;

		// case PHASE_DATA_OUT:		// Them to us
		// 	// SetBSY(true);
		// 	// SetREQ(true);
		// 	// SetMSG(false);
		// 	// SetCD(false);
		// 	// SetIO(false);
		// 	set_cd_reg_bits(0x00, BUSY_BIT | REQ_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT);
		// 	break;

		// case PHASE_MESSAGE_OUT:	// Them to us
		// 	// SetBSY(true);
		// 	// SetMSG(true);
		// 	// SetCD(true);
		// 	// SetREQ(true);
		// 	// SetIO(false);
		// 	set_cd_reg_bits(0x00, BUSY_BIT | MSG_BIT | CD_BIT | REQ_BIT & ~IO_BIT);
		// 	break;
	}
	CurrentPhase = new_phase;
}

void reply_status_byte(uint8_t status)
{
	m_message_after_status = 1;
	m_status_sent = m_message_sent = 0;

	if (status == SCSI_STATUS_OK) {
		write_cd_reg(0x01, 0x00);
	} else {
		write_cd_reg(0x01, 0x01);
	}

	//printf("PCE_CD: Setting CD in reply_status_byte\n");
	//set_cd_reg_bits(0x00, CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT);
	ChangePhase(PHASE_STATUS);
}

// CD Command 0XFF - End of List marker
void end_of_list()
{
	reply_status_byte(SCSI_CHECK_CONDITION);
}

void handle_data_output()
{
	static const struct {
		uint8_t   command_byte;
		uint8_t   command_size;
		//command_handler_func command_handler;
	} pce_cd_commands[] = {
		{ 0x00, 6},// &pce_cd_device::test_unit_ready },                // TEST UNIT READY
		{ 0x08, 6},// &pce_cd_device::read_6 },                         // READ (6)
		{ 0xD8,10},// &pce_cd_device::nec_set_audio_start_position },   // NEC SET AUDIO PLAYBACK START POSITION
		{ 0xD9,10},// &pce_cd_device::nec_set_audio_stop_position },    // NEC SET AUDIO PLAYBACK END POSITION
		{ 0xDA,10},// &pce_cd_device::nec_pause },                      // NEC PAUSE
		{ 0xDD,10},// &pce_cd_device::nec_get_subq },                   // NEC GET SUBCHANNEL Q
		{ 0xDE,10},// &pce_cd_device::nec_get_dir_info },               // NEC GET DIR INFO
		{ 0xFF, 1},// &pce_cd_device::end_of_list }                     // end of list marker
	};

	if ( (read_cd_reg(0x00)&REQ_BIT) && (read_cd_reg(0x02)&ACK_BIT) )
	{
		// Command byte received
		printf("PCE_CD: Command byte $%02X received\n", read_cd_reg(0x01));

		// Check for buffer overflow
		//assert(m_command_buffer_index < PCE_CD_COMMAND_BUFFER_SIZE);
		if (m_command_buffer_index >= PCE_CD_COMMAND_BUFFER_SIZE) return;

		m_command_buffer[m_command_buffer_index] = read_cd_reg(0x01);
		m_command_buffer_index++;
		clear_cd_reg_bits(0x00, REQ_BIT);
	}

	if ( !(read_cd_reg(0x00)&REQ_BIT) && !(read_cd_reg(0x02)&ACK_BIT) && m_command_buffer_index)
	{
		int i = 0;

		printf("PCE_CD: Check if command done\n");

		for(i = 0; m_command_buffer[0] > pce_cd_commands[i].command_byte; i++);

		// Check for unknown commands
		if (m_command_buffer[0] != pce_cd_commands[i].command_byte)
		{
			printf("PCE_CD: Unrecognized command: %02X\n", m_command_buffer[0]);
			if (m_command_buffer[0] == 0x03)
				printf("PCE_CD: CD command 0x03 issued (Request Sense), contact MESSdev");
		}
		//assert(m_command_buffer[0] == pce_cd_commands[i].command_byte);

		if (m_command_buffer_index == pce_cd_commands[i].command_size)
		{
			printf("PCE_CD: %02x command issued\n",m_command_buffer[0]);
			// @todo Currently, manually calling our handler functions
			// Can't call this just yet
			//(this->*pce_cd_commands[i].command_handler)();
			if (m_command_buffer[0] == 0x00) {
				test_unit_ready();
			}
			m_command_buffer_index = 0;
		}
		else
		{
			set_cd_reg_bits(0x00, REQ_BIT);
		}
	}
}

void handle_data_input()
{
	printf("PCE_CD: TODO data_input\n");
/*	if (m_scsi_CD)
	{
		// Command / Status byte
		if (m_scsi_REQ && m_scsi_ACK)
		{
			printf("status sent\n");
			m_scsi_REQ = 0;
			m_status_sent = 1;
		}

		if (! m_scsi_REQ && ! m_scsi_ACK && m_status_sent)
		{
			m_status_sent = 0;
			if (m_message_after_status)
			{
				printf("message after status\n");
				m_message_after_status = 0;
				m_scsi_MSG = m_scsi_REQ = 1;
				write_cd_reg(0x01, 0x00);
			}
		}
	}
	else
	{
		// Data
		if (m_scsi_REQ && m_scsi_ACK)
		{
			m_scsi_REQ = 0;
		}

		if (! m_scsi_REQ && ! m_scsi_ACK)
		{
			if (m_data_buffer_index == m_data_buffer_size)
			{
				//set_irq_line(PCE_CD_IRQ_TRANSFER_READY, CLEAR_LINE);
				clear_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_READY);
				if (m_data_transferred)
				{
					m_data_transferred = 0;
					reply_status_byte(SCSI_STATUS_OK);
					//set_irq_line(PCE_CD_IRQ_TRANSFER_DONE, ASSERT_LINE);
					set_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE);
				}
			}
			else
			{
				printf("Transfer byte %02x from offset %d %d\n",m_data_buffer[m_data_buffer_index] , m_data_buffer_index, m_current_frame);
				write_cd_reg(0x01, m_data_buffer[m_data_buffer_index];);
				
				m_data_buffer_index++;
				m_scsi_REQ = 1;
			}
		}
	}
*/
}

/**
 * Messages coming from PCE
 */
void handle_message_output()
{
	//if (m_scsi_REQ && m_scsi_ACK)
	if ( (read_cd_reg(0x00)&REQ_BIT) && (read_cd_reg(0x02)&ACK_BIT) ) {
		//m_scsi_REQ = 0;
		clear_cd_reg_bits(0x00, REQ_BIT);
	}
}

/**
 * Message to PCE from ARM
 */
void handle_message_input()
{
	//if (m_scsi_REQ && m_scsi_ACK)
	if ( (read_cd_reg(0x00)&REQ_BIT) && (read_cd_reg(0x02)&ACK_BIT) )
	{
		//m_scsi_REQ = 0;
		clear_cd_reg_bits(0x00, REQ_BIT);
		m_message_sent = 1;
	}

	//if (! m_scsi_REQ && ! m_scsi_ACK && m_message_sent)
	if ( !(read_cd_reg(0x00)&REQ_BIT) && !(read_cd_reg(0x02)&ACK_BIT) && m_message_sent)
	{
		m_message_sent = 0;
		//m_scsi_BSY = 0;
		clear_cd_reg_bits(0x00, BUSY_BIT);
	}
}

void pce_cd_update_old()
{
	/* Check for reset of CD unit
	if (m_scsi_RST != m_scsi_last_RST)
	{
		if (m_scsi_RST)
		{
			logerror("Performing CD reset\n");
			// Reset internal data
			m_scsi_BSY = m_scsi_SEL = m_scsi_CD = m_scsi_IO = 0;
			m_scsi_MSG = m_scsi_REQ = m_scsi_ATN = 0;
			m_cd_motor_on = 0;
			m_selected = 0;
			m_cdda_status = PCE_CD_CDDA_OFF;
			m_cdda->stop_audio();
			m_adpcm_dma_timer->adjust(attotime::never); // stop ADPCM DMA here
		}
		m_scsi_last_RST = m_scsi_RST;
	}

	/* Check if bus can be freed
	if (! m_scsi_SEL && ! m_scsi_BSY && m_selected)
	{
		logerror("freeing bus\n");
		m_selected = 0;
		m_scsi_CD = m_scsi_MSG = m_scsi_IO = m_scsi_REQ = 0;
		//set_irq_line(PCE_CD_IRQ_TRANSFER_DONE, CLEAR_LINE);
		clear_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE);
	}
	*/
	if (! m_scsi_SEL && ! read_cd_reg(0x00)&BUSY_BIT && m_selected)
	{
		printf("PCE_CD: Freeing bus - TODO FREE BUS\n");
		// @dentnz will this trigger the interupt?
		clear_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE);
	}

	// Select the CD device
	if (m_scsi_SEL)
	{
		if (!m_selected)
		{
			m_selected = 1;
			printf("PCE_CD: Setting CD in device selection\n");
			//set_cd_reg_bits(0x00, BUSY_BIT | REQ_BIT | CD_BIT & ~MSG_BIT & ~IO_BIT);
			ChangePhase(PHASE_COMMAND);
		}
	}

	if (m_scsi_ATN)
	{
	}
	else
	{

// CD Interface Register 0x00 - CDC status
// x--- ---- busy signal
// -x-- ---- request signal
// --x- ---- msg bit
// ---x ---- cd signal
// ---- x--- i/o signal

// #define BUSY_BIT 0x80
// #define REQ_BIT 0x40
// #define MSG_BIT 0x20
// #define CD_BIT 0x10
// #define IO_BIT 0x08

		// Check for data and message phases
		if (read_cd_reg(0x00)&BUSY_BIT)
		{
			if (read_cd_reg(0x00)&MSG_BIT)
			{
				// message phase
				if (read_cd_reg(0x00)&IO_BIT)
				{
					//printf("handle_message_input()\n");		// (from the CD drive / HPS TO the PCE core).
					handle_message_input();
				}
				else
				{
					// PCE to CD Drive via HPS - Run was pressed\n");	// (from PCE core TO the CD drive / HPS).
					handle_message_output();
				}
			}
			else
			{
				// data phase
				if (read_cd_reg(0x00)&IO_BIT)
				{
					// Reading data from target
					//printf("handle_data_input()\n");		// (from the CD drive / HPS TO the PCE core).
					handle_data_input();
				}
				else
				{
					// Sending data to target
					//printf("handle_data_output()2\n");		// (from PCE core TO the CD drive / HPS).
					handle_data_output();
				}
			}
		}
	}

	/* FIXME: presumably CD-DA needs an irq interface for this
	if (m_cdda->audio_ended() && m_end_mark == 1)
	{
		switch (m_cdda_play_mode & 3)
		{
			case 1: m_cdda->start_audio(m_current_frame, m_end_frame - m_current_frame); m_end_mark = 1; break; //play with repeat
			case 2: {
				//set_irq_line(PCE_CD_IRQ_TRANSFER_DONE, ASSERT_LINE);
				set_cd_reg_bits(0x03, PCE_CD_IRQ_TRANSFER_DONE);
				m_end_mark = 0; break; //irq when finished
			}
			case 3: m_end_mark = 0; break; //play without repeat
		}
	}
	*/
}

#define BSY_signal ((const bool)(read_cd_reg(0x00) & BUSY_BIT))
#define MSG_signal ((const bool)(read_cd_reg(0x00) & MSG_BIT)
#define REQ_signal ((const bool)(read_cd_reg(0x00) & REQ_BIT))
#define IO_signal ((const bool)(read_cd_reg(0x00) & IO_BIT))
#define CD_signal ((const bool)(read_cd_reg(0x00) & CD_BIT))


#define ACK_signal ((const bool)(read_cd_reg(0x02) & PCECD_Drive_kingACK_mask))
#define RST_signal ((const bool)(read_cd_reg(0x02) & PCECD_Drive_kingRST_mask))
#define SEL_signal ((const bool)(read_cd_reg(0x02) & PCECD_Drive_kingSEL_mask))

// A representation of the CD drive itself, including a command buffer
typedef struct
{
	bool last_RST_signal;

	// The pending message to send(in the message phase)
	uint8_t message_pending;

	bool status_sent, message_sent;

	// Pending error codes
	uint8_t key_pending, asc_pending, ascq_pending, fru_pending;

	uint8_t command_buffer[256];
	uint8_t command_buffer_pos;
	uint8_t command_size_left;

	// FALSE if not all pending data is in the FIFO, TRUE if it is.
	// Used for multiple sector CD reads.
	bool data_transfer_done;

	bool TrayOpen;
	bool DiscChanged;

	uint8_t SubQBuf[4][0xC];		// One for each of the 4 most recent q-Modes.
	uint8_t SubQBuf_Last[0xC];	// The most recent q subchannel data, regardless of q-mode.

	uint8_t SubPWBuf[96];

} pcecd_drive_t;

static pcecd_drive_t cd;

static void VirtualReset(void)
{
	// din.Flush();

	// cdda.CDDADivAcc = (int64)System_Clock * 65536 / 44100;
	// CDReadTimer = 0;

	// pce_lastsapsp_timestamp = monotonic_timestamp;

	// SectorAddr = SectorCount = 0;
	// read_sec_start = read_sec = 0;
	// read_sec_end = ~0;

	// cdda.PlayMode = PLAYMODE_SILENT;
	// cdda.CDDAReadPos = 0;
	// cdda.CDDAStatus = CDDASTATUS_STOPPED;
	// cdda.CDDADiv = 0;

	// cdda.ScanMode = 0;
	// cdda.scan_sec_end = 0;

	ChangePhase(PHASE_BUS_FREE);
}

void pce_cd_update() {
    //RunCDRead(system_timestamp, run_time);
    //RunCDDA(system_timestamp, run_time);

    bool ResetNeeded = false;

    if (RST_signal && !cd.last_RST_signal)
        ResetNeeded = true;

    cd.last_RST_signal = RST_signal;

    if (ResetNeeded) {
        printf("PCE_CD: VirtualReset\n");
        VirtualReset();	
    } else switch (CurrentPhase) {
		case PHASE_BUS_FREE:
			if (SEL_signal) {
				ChangePhase(PHASE_COMMAND);
			}
			break;

		case PHASE_COMMAND:
			printf("PCE_CD: todo PHASE_COMMAND\n");
				
			if (REQ_signal && ACK_signal) // Data bus is valid nowww
			{
				//printf("Command Phase Byte I->T: %02x, %d\n", cd_bus.DB, cd.command_buffer_pos);
				//cd.command_buffer[cd.command_buffer_pos++] = cd_bus.DB;
				//SetREQ(FALSE);
				clear_cd_reg_bits(0x00, REQ_BIT);
			}

			if (!REQ_signal && !ACK_signal && cd.command_buffer_pos) // Received at least one byte, what should we do?
			{
				printf("PCE_CD: received command byte\n");
				// if (cd.command_buffer_pos == RequiredCDBLen[cd.command_buffer[0] >> 4]) {
				//     const SCSICH * cmd_info_ptr = PCECommandDefs;

				//     while (cmd_info_ptr - > pretty_name && cmd_info_ptr - > cmd != cd.command_buffer[0])
				//         cmd_info_ptr++;

				//     if (cmd_info_ptr - > pretty_name == NULL) // Command not found!
				//     {
				//         CommandCCError(SENSEKEY_ILLEGAL_REQUEST, NSE_INVALID_COMMAND);

				//         SCSIDBG("Bad Command: %02x\n", cd.command_buffer[0]);

				//         cd.command_buffer_pos = 0;
				//     } else {
				//         if (cd.TrayOpen && (cmd_info_ptr - > flags & SCF_REQUIRES_MEDIUM)) {
				//             CommandCCError(SENSEKEY_NOT_READY, NSE_TRAY_OPEN);
				//         } else if (!Cur_CDIF && (cmd_info_ptr - > flags & SCF_REQUIRES_MEDIUM)) {
				//             CommandCCError(SENSEKEY_NOT_READY, NSE_NO_DISC);
				//         } else if (cd.DiscChanged && (cmd_info_ptr - > flags & SCF_REQUIRES_MEDIUM)) {
				//             CommandCCError(SENSEKEY_UNIT_ATTENTION, NSE_DISC_CHANGED);
				//             cd.DiscChanged = false;
				//         } else {
				//             cmd_info_ptr - > func(cd.command_buffer);
				//         }

				//         cd.command_buffer_pos = 0;
				//     }
				//} // end if(cd.command_buffer_pos == RequiredCDBLen[cd.command_buffer[0] >> 4])
				//else {
					// Otherwise, get more data for the command!
					//SetREQ(TRUE);
				//	set_cd_reg_bits(0x00, REQ_BIT);
				//}
			}
			break;

		case PHASE_STATUS:
			printf("PCE_CD: todo PHASE_STATUS\n");
				
			if (REQ_signal && ACK_signal) {
				//SetREQ(FALSE);
				clear_cd_reg_bits(0x00, REQ_BIT);
				cd.status_sent = true;
			}

			if (!REQ_signal && !ACK_signal && cd.status_sent) {
				// Status sent, so get ready to send the message!
				cd.status_sent = false;
				//cd_bus.DB = cd.message_pending;

				ChangePhase(PHASE_MESSAGE_IN);
			}
			break;

		case PHASE_DATA_IN:
			printf("PCE_CD: todo PHASE_DATA_IN\n");

			if (!REQ_signal && !ACK_signal) {
				//puts("REQ and ACK false");
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
			}
			if (REQ_signal && ACK_signal) {
				//puts("REQ and ACK true");
				//SetREQ(FALSE);
				clear_cd_reg_bits(0x00, REQ_BIT);
			}
			break;

		case PHASE_MESSAGE_IN:
			printf("PCE_CD: MESSAGE_IN\n");
				
			if (REQ_signal && ACK_signal) {
				//SetREQ(FALSE);
				clear_cd_reg_bits(0x00, REQ_BIT);
				cd.message_sent = true;
			}

			if (!REQ_signal && !ACK_signal && cd.message_sent) {
				cd.message_sent = false;
				ChangePhase(PHASE_BUS_FREE);
			}
			break;
    }

    // int32 next_time = 0x7fffffff;

    // if (CDReadTimer > 0 && CDReadTimer < next_time)
    //     next_time = CDReadTimer;

    // if (cdda.CDDAStatus == CDDASTATUS_PLAYING) {
    //     int32 cdda_div_sexytime = (cdda.CDDADiv + 0xFFFF) >> 16;
    //     if (cdda_div_sexytime > 0 && cdda_div_sexytime < next_time)
    //         next_time = cdda_div_sexytime;
    // }

    // assert(next_time >= 0);

    // return (next_time);
	return;
}

void scan_cd_registers(void)
{
	uint8_t scanByte = 0;
	uint8_t registerAddress = 0;
	for (registerAddress = 0; registerAddress <= 255; registerAddress++) {
		for (scanByte = 0; scanByte <= 255; scanByte++) {
			printf("PCE_CD: scanning register: %02x ", registerAddress);
			printf(" with byte: %02x\n", scanByte);
			set_cd_reg_bits(registerAddress, scanByte);
			log_cd_registers();
		}
	}
}

void user_io_cdrom_get_status(void)
{
	pce_cd_update();
	log_cd_registers();
}

using byte = unsigned char;
byte previous_reg_00 = 0x00;
byte previous_reg_01 = 0x00;
byte previous_reg_02 = 0x00;
byte previous_reg_03 = 0x00;
byte previous_reg_04 = 0x00;
byte previous_reg_05 = 0x00;
byte previous_reg_06 = 0x00;
byte previous_reg_07 = 0x00;
byte previous_reg_08 = 0x00;
byte previous_reg_09 = 0x00;
byte previous_reg_0a = 0x00;
byte previous_reg_0b = 0x00;
byte previous_reg_0c = 0x00;
byte previous_reg_0d = 0x00;
byte previous_reg_0e = 0x00;
byte previous_reg_0f = 0x00;
			
void log_cd_registers()
{
	uint8_t data;
	
	data = read_cd_reg(0x00);
	if (previous_reg_00 != data) {
		// CD Interface Register 0x00 - CDC status
		// x--- ---- busy signal
		// -x-- ---- request signal
		// ---x ---- cd signal
		// ---- x--- i/o signal
        printf("PCE_CD: 0x00 CDC_STAT:    %02x", data);
        if (data&0x80) printf(" [7]BUSY ");
        if (data&0x40) printf(" [6]REQ  ");
        if (data&0x20) printf(" [5]MSG  ");
        if (data&0x10) printf(" [4]CD   ");
        if (data&0x08) printf(" [3]IO   ");
		printf("\n");
		previous_reg_00 = data;
	}

	data = read_cd_reg(0x01);
	if (previous_reg_01 != data) {
		printf("PCE_CD: 0x01 CDC_CMD:     %02x\n", data);
		previous_reg_01 = data;
	}

	data = read_cd_reg(0x02);
	if (previous_reg_02 != data) {
		printf("PCE_CD: 0x02 INT_MASK:    %02x", data);
		if (data&0x80) printf(" [7]ACK_FLAG! ");    // Actual ACKnowledge flag, AFAIK. ElectronAsh.
        if (data&0x40) printf(" [6]ACK_MASK  ");
        if (data&0x20) printf(" [5]DONE_MASK ");
        if (data&0x10) printf(" [4]BRAM_MASK ");
        if (data&0x08) printf(" [3]FULL_MASK ");
        if (data&0x04) printf(" [2]HALF_MASK ");
        if (data&0x02) printf(" [1]L/R ");
		printf("\n");
		previous_reg_02 = data;
	}

	data = read_cd_reg(0x03);
	if (previous_reg_03 != data) {
		// CD Interface Register 0x03 - BRAM lock / CD status
		// -x-- ---- acknowledge signal
		// --x- ---- done signal
		// ---x ---- bram signal
		// ---- x--- ADPCM 2
		// ---- -x-- ADPCM 1
		// ---- --x- CDDA left/right speaker select
		printf("PCE_CD: 0x03 BRAM_LOCK:   %02x", data);
		if (data&0x40) printf(" ACK  ");	// Bit 6.
		if (data&0x20) printf(" DONE ");	// Bit 5.
		if (data&0x10) printf(" BRAM ");	// Bit 4.
		if (data&0x08) printf(" FULL ");	// Bit 3.
		if (data&0x04) printf(" HALF ");	// Bit 2.
		if (data&0x02) printf(" L/R ");		// Bit 1.
		printf("\n");
		previous_reg_03 = data;
	}

	data = read_cd_reg(0x04);
	if (previous_reg_04 != data) {
		printf("PCE_CD: 0x04 CD RESET:    %02x\n", data);
		previous_reg_04 = data;
	}

	data = read_cd_reg(0x05);
	if (previous_reg_05 != data) {
		printf("PCE_CD: 0x05 CONV_PCM:    %02x\n", data);
		previous_reg_05 = data;
	}

	data = read_cd_reg(0x06);
	if (previous_reg_06 != data) {
		printf("PCE_CD: 0x06 PCM_DATA:    %02x\n", data);
		previous_reg_06 = data;
	}

	data = read_cd_reg(0x07);
	if (previous_reg_07 != data) {
		printf("PCE_CD: 0x07 BRAM_UNLOCK: %02x\n", data);
		previous_reg_07 = data;
	}

	// todo: need to complete all of these

	// printf("0x00 CDC_STAT:    %02x\n", read_cd_reg(0x00));
	// printf("0x01 CDC_CMD:     %02x\n", read_cd_reg(0x01));
	// printf("0x02 INT_MASK:    %02x\n", read_cd_reg(0x02));
	// printf("0x03 BRAM_LOCK:   %02x\n", read_cd_reg(0x03));
	// printf("0x04 CD RESET:    %02x\n", read_cd_reg(0x04));
	// printf("0x05 CONV_PCM:    %02x\n", read_cd_reg(0x05));
	// printf("0x06 PCM_DATA:    %02x\n", read_cd_reg(0x06));
	// printf("0x07 BRAM_UNLOCK: %02x\n", read_cd_reg(0x07));
	// printf("0x08 ADPCM_A_LO:  %02x\n", read_cd_reg(0x08));
	// printf("0x09 ADPCM_A_HI:  %02x\n", read_cd_reg(0x09));
	// printf("0x0a AD_RAM_DATA: %02x\n", read_cd_reg(0x0a));
	// printf("0x0b AD_DMA_CONT: %02x\n", read_cd_reg(0x0b));
	// printf("0x0c ADPCM_STAT:  %02x\n", read_cd_reg(0x0c));
	// printf("0x0d ADPCM_ADDR:  %02x\n", read_cd_reg(0x0d));
	// printf("0x0e ADPCM_RATE:  %02x\n", read_cd_reg(0x0e));
	// printf("0x0f ADPCM_FADE:  %02x\n", read_cd_reg(0x0f));
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// END PC ENGINE CD STUFF
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

