module top(
    input i_clk,
    // Allows for input from the PC Engine itself
    input [7:0] i_CDStatus,
    input [7:0] i_CDCommand,
    input [7:0] i_CDIntMask,
    input [7:0] i_CDReset,
    
    // Read internally and externally
    output r_CDStatus,       // 0x00 
    output r_CDComand,       // 0x01
    output r_CDIntMask,      // 0x02
    output r_CDBRAMLock,     // 0x03
    output r_CDReset,        // 0x04
    output o_GOTCDCOMMAND
);
    reg [7:0] r_CDStatus = 0;
    reg [7:0] r_CDCommand = 0;
    reg [7:0] r_CDBRAMLock = 0;
    // Debug
    reg [0:0] o_GOTCDCOMMAND = 0;
    //reg [7:0] r_CDIntMask;
    localparam [7:0] i_CDStatus_last = 0;
    localparam [7:0] i_CDCommand_last = 0;
    localparam [7:0] i_CDIntMask_last = 0;
    localparam [7:0] i_CDReset_last = 0;

    // Internal state
    reg [7:0] CurrentPhase = 0;
    // I believe this is the command bus
    reg [7:0] CDBusDb = 0;
    reg [0:0] CDLastReset = 0;
    reg [0:0] CDStatusSent = 0;
    reg [0:0] CDMessageSent = 0;

    localparam true = 1;
    localparam false = 0;
    localparam IRQ_8000 = 1;
    localparam IRQ_No_8000 = 0;

    localparam PHASE_BUS_FREE    = 8'b00000000;
    localparam PHASE_COMMAND     = 8'b00000001;
    localparam PHASE_DATA_IN     = 8'b00000010;
    localparam PHASE_DATA_OUT    = 8'b00000100;
    localparam PHASE_STATUS      = 8'b00001000;
    localparam PHASE_MESSAGE_IN  = 8'b00010000;
    localparam PHASE_MESSAGE_OUT = 8'b00100000;

    localparam PCECD_Drive_IRQ_DATA_TRANSFER_DONE = 3'b001;
    localparam PCECD_Drive_IRQ_DATA_TRANSFER_READY = 3'b010;
    localparam PCECD_Drive_IRQ_MAGICAL_REQ = 3'b011;

    // CD Interface Register 0x00 - CDC status
    // x--- ---- busy signal
    // -x-- ---- request signal
    // --x- ---- msg bit
    // ---x ---- cd signal
    // ---- x--- i/o signal
    localparam BUSY_BIT = 8'h80;
    localparam REQ_BIT = 8'h40;
    localparam MSG_BIT = 8'h20;
    localparam CD_BIT = 8'h10;
    localparam IO_BIT = 8'h08;

    // Signals under our(the "target") control.
    function BSY_signal; BSY_signal = r_CDStatus[7]; endfunction
    function REQ_signal; REQ_signal = r_CDStatus[6]; endfunction
    function MSG_signal; MSG_signal = r_CDStatus[5]; endfunction
    function CD_signal; CD_signal = r_CDStatus[4]; endfunction
    function IO_signal; IO_signal = r_CDStatus[3]; endfunction
    task SetREQ; input [0:0] bitValue; r_CDStatus[6] = bitValue; endtask

    // Signals under the control of the initiator (not us!)
    localparam PCECD_Drive_kingRST_mask	= 16'h020;
    localparam PCECD_Drive_kingACK_mask = 16'h040;
    localparam PCECD_Drive_kingSEL_mask	= 16'h100;

    // Internal Signals (IOP in beetle)
    reg [15:0] cd_bus_signals;
    function RST_signal; RST_signal = cd_bus_signals[5]; endfunction
    function ACK_signal; ACK_signal = cd_bus_signals[6]; endfunction
    function SEL_signal; SEL_signal = cd_bus_signals[8]; endfunction

    task SetkingRST; input [0:0] bitValue; cd_bus_signals[5] = bitValue; endtask
    task PCECD_Drive_SetRST; input [0:0] bitValue; SetkingRST(bitValue); endtask
    task SetkingACK; input [0:0] bitValue; cd_bus_signals[6] = bitValue; endtask
    task PCECD_Drive_SetACK; input [0:0] bitValue; SetkingACK(bitValue); endtask
    task SetkingSEL; input [0:0] bitValue; cd_bus_signals[8] = bitValue; endtask
    task PCECD_Drive_SetSEL; input [0:0] bitValue; SetkingSEL(bitValue); endtask

    // Command bus getter/setters?
    //function PCECD_Drive_GetDB; PCECD_Drive_GetDB = CDBusDb; endfunction
    task PCECD_Drive_SetDB; input [7:0] dbValue; CDBusDb = dbValue; endtask

    task PCECD_Drive_Power;
        CurrentPhase = PHASE_BUS_FREE;
        VirtualReset;
    endtask;

    task CDIRQ;
        input [0:0] mode; // 8000 is used to do different things to the IRQ register by pce_fast... this replicates that
        input [2:0] irqType;
        begin
            if (mode) begin
                if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_DONE) begin
                    r_CDBRAMLock &= ~8'h20;
                end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_READY) begin
                    r_CDBRAMLock &= ~8'h40;
                end
            end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_DONE) begin
                r_CDBRAMLock |= 8'h20;
            end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_READY) begin
                r_CDBRAMLock |= 8'h40;
            end
            // @todo update_irq_state();
        end
    endtask

    task ChangePhase;
        input [7:0] new_phase;
        begin
            if (new_phase == PHASE_BUS_FREE) begin
                $display ("PHASE_BUS_FREE");
                r_CDStatus = r_CDStatus & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
                CDIRQ(IRQ_8000, PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
                CurrentPhase = PHASE_BUS_FREE;
            end
            if (new_phase == PHASE_DATA_IN) begin
                $display ("PHASE_DATA_IN");
                r_CDStatus = r_CDStatus | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
                CurrentPhase = PHASE_DATA_IN;
            end
            if (new_phase == PHASE_STATUS) begin
                $display ("PHASE_STATUS");
                r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
                CurrentPhase = PHASE_STATUS;
            end
            if (new_phase == PHASE_MESSAGE_IN) begin
                $display ("PHASE_MESSAGE_IN");
                r_CDStatus = r_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
                CurrentPhase = PHASE_MESSAGE_IN;
            end
            if (new_phase == PHASE_COMMAND) begin
                $display ("PHASE_COMMAND");
                r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
                CurrentPhase = PHASE_COMMAND;
            end
        end
    endtask

    task VirtualReset;
        $display("VirtualReset");
        r_CDStatus = 0;
        o_GOTCDCOMMAND = 0;
        CurrentPhase = 0;
        CDLastReset = 0;
        CDStatusSent = 0;
        CDMessageSent = 0;
        ChangePhase(PHASE_BUS_FREE);
    endtask

    task RunCDRead;
        //$display ("PCE_CD: RunCDRead - TBC");
    endtask

    task RunCDDA;
        //$display ("PCE_CD: RunCDDA - TBC");
    endtask

    task PCECD_Drive_Run;
        reg [0:0] ResetNeeded;
        begin
            // @todo Might not be right to call long running things in here, also Verilog is not always procedural
            RunCDRead;
            RunCDDA;
            ResetNeeded = 0;
            if (RST_signal() && !CDLastReset) begin 
                ResetNeeded = 1;
            end

            CDLastReset = RST_signal();

            if (ResetNeeded) begin
                VirtualReset;
            end
            else begin
                case (CurrentPhase)
                    PHASE_BUS_FREE: begin
                        if (SEL_signal()) begin
                            ChangePhase(PHASE_COMMAND);
                        end
                    end
                    PHASE_COMMAND: begin
                        if (REQ_signal() && ACK_signal()) begin
                            // Databus is valid now
                            // @todo put DB command on the buffer?
                            // cd.command_buffer[cd.command_buffer_pos++] = cd_bus.DB;
                            SetREQ(false);
                        end
                        // if(!REQ_signal && !ACK_signal && cd.command_buffer_pos)	// Received at least one byte, what should we do?
                        if (!REQ_signal() && !ACK_signal()) begin
                            // We got a command!!!!!!!
                            $display ("We got a command!");
                            o_GOTCDCOMMAND = 1;
                            $finish;
                            // @todo handle the command... for now, expose the fact we got to command phase
                        end
                    end
                    PHASE_STATUS: begin
                        if (REQ_signal() && ACK_signal()) begin
                            SetREQ(false);
                            CDStatusSent = true;
                        end
                        if (!REQ_signal() && !ACK_signal() && CDStatusSent) begin
                            // Status sent, so get ready to send the message!
                            CDStatusSent = false;
                            // @todo message_pending message goes on the buss
                            //cd_bus.DB = cd.message_pending;
                            ChangePhase(PHASE_MESSAGE_IN);
                        end
                    end
                    PHASE_DATA_IN: begin
                        $display ("PHASE_DATA_IN TBC");
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
                        if (REQ_signal() && ACK_signal()) begin
                            SetREQ(false);
                            r_CDStatus = r_CDStatus & ~REQ_BIT;
                            CDMessageSent = true;
                        end
                        if (!REQ_signal() && !ACK_signal() && CDMessageSent) begin
                            CDMessageSent = false;
                            ChangePhase(PHASE_BUS_FREE);
                        end
                    end
                endcase
            end
        end
    endtask

    task PCECD_Run;
        // @todo ClearACKDelay?
        PCECD_Drive_SetACK(false);
        PCECD_Drive_Run;
        // @todo ADPCM stuff
        // @todo Fadeouts/ins
    endtask

    // Writes from the PC Engine only, I guess...
    task PCECD_Write;
        // $1800
        if (i_CDStatus != i_CDStatus_last) begin
            $display("Write 1800");
            PCECD_Drive_SetSEL(1);
            PCECD_Run;
            PCECD_Drive_SetSEL(0);
            PCECD_Run;
            r_CDBRAMLock &= ~(8'h20 | 8'h40);
            i_CDStatus_last = i_CDStatus;
            // @todo work out how this is done...
            //update_irq_state();
        // $1801
        end else if (i_CDCommand != i_CDCommand_last) begin
            $display("Command Received");
            r_CDCommand = i_CDCommand;
            PCECD_Run;
            i_CDCommand_last = i_CDCommand;
        // $1802
        end else if (i_CDIntMask != i_CDIntMask_last) begin
            $display("Write 1802");
            PCECD_Drive_SetACK(i_CDIntMask & 8'h80);
            PCECD_Run;
            r_CDIntMask = i_CDIntMask;
            i_CDIntMask_last = i_CDIntMask;
        // $1804
        end else if (i_CDReset != i_CDReset_last) begin
            $display("Write 1804");
            PCECD_Drive_SetRST(i_CDReset & 8'h2);
            PCECD_Run;
            if(i_CDReset & 8'h2) begin
                r_CDBRAMLock &= ~8'h70;
                //update_irq_state();
            end
            r_CDReset = i_CDReset;
            i_CDReset_last = i_CDReset;
        end
    endtask

    always @ (posedge i_clk) begin
        PCECD_Write;
    end

    initial begin
        PCECD_Drive_Power;
    end
endmodule