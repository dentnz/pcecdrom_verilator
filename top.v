module top(output r_CDStatus);
    // These will eventually be external registers
    reg [7:0] r_CDStatus = 0;
    //reg [7:0] r_CDIntMask;
    
    // Internal state
    reg [7:0] CurrentPhase = 0;
    reg [0:0] CDLastReset = 0;
    reg [0:0] CDStatusSent = 0;
    reg [0:0] CDMessageSent = 0;

    localparam PHASE_BUS_FREE    = 8'b00000000;
    localparam PHASE_COMMAND     = 8'b00000001;
    localparam PHASE_DATA_IN     = 8'b00000010;
    localparam PHASE_DATA_OUT    = 8'b00000100;
    localparam PHASE_STATUS      = 8'b00001000;
    localparam PHASE_MESSAGE_IN  = 8'b00010000;
    localparam PHASE_MESSAGE_OUT = 8'b00100000;

    localparam true = 1;
    localparam false = 0;

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

    // Signals under the control of the initiator(not us!)
    localparam PCECD_Drive_kingRST_mask	= 16'h020;
    localparam PCECD_Drive_kingACK_mask = 16'h040;
    localparam PCECD_Drive_kingSEL_mask	= 16'h100;

    // Internal Signals 
    reg [15:0] cd_bus_signals;

    function RST_signal; RST_signal = cd_bus_signals[5] ; endfunction
    function ACK_signal; ACK_signal = cd_bus_signals[6]; endfunction
    // @todo assume a cd device has been selected, but this would be bit cd_bus_signals[8]
    function SEL_signal; SEL_signal = 1; endfunction

    task ChangePhase;
        input [7:0] new_phase;
        begin
            if (new_phase == PHASE_BUS_FREE)
                begin
                    $display ("PHASE_BUS_FREE");
                    r_CDStatus = r_CDStatus & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
                    // @todo Need to do some kind of interrupt here
                    CurrentPhase = PHASE_BUS_FREE;
                end
            if (new_phase == PHASE_DATA_IN)
                begin
                    $display ("PHASE_DATA_IN");
                    r_CDStatus = r_CDStatus | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
                    CurrentPhase = PHASE_DATA_IN;
                end
            if (new_phase == PHASE_STATUS)
                begin
                    $display ("PHASE_STATUS");
                    r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
                    CurrentPhase = PHASE_STATUS;
                end
            if (new_phase == PHASE_MESSAGE_IN)
                begin
                    $display ("PHASE_MESSAGE_IN");
                    r_CDStatus = r_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
                    CurrentPhase = PHASE_MESSAGE_IN;
                end
            if (new_phase == PHASE_COMMAND)
                begin
                    $display ("PHASE_COMMAND");
                    r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
                    CurrentPhase = PHASE_COMMAND;
                end
        end
    endtask

    task VirtualReset;
        $display("VirtualReset");
        // @todo reset the cd drive - i.e anything internal to this module
        ChangePhase(PHASE_BUS_FREE);
    endtask
    
    task LogRegisers;
        $display ("PCE_CD: 0X00 CDC_STAT: %h", r_CDStatus);
    endtask

    task RunCDRead;
        $display ("PCE_CD: RunCDRead - TBC");
    endtask

    task RunCDDA;
        $display ("PCE_CD: RunCDDA - TBC");
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
                            // @todo handle the command
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

    initial begin
        CurrentPhase = 0;
        ChangePhase(PHASE_BUS_FREE);
        PCECD_Drive_Run;
        $finish; 
    end

endmodule