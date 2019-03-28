module top(
    input i_clk,
    // Allows for input from the PC Engine itself
    input [7:0] i_CDStatus,         // 0x00
    input [7:0] i_CDCommand,        // 0x01
    input [7:0] i_CDIntMask,        // 0x02
    input [7:0] i_CDReset,          // 0x03
    
    // Read internally and externally
    output [7:0] r_CDStatus,        // 0x00 
    output [7:0] r_CDCommand,       // 0x01
    output [7:0] r_CDIntMask,       // 0x02
    output [7:0] r_CDBRAMLock,      // 0x03
    output [7:0] r_CDReset,         // 0x04
    
    // Debugging output
    output o_GOTCDCOMMAND,
    output [7:0] CurrentPhase
);
    reg [7:0] r_CDStatus   = 0;
    reg [7:0] r_CDCommand  = 0;
    reg [7:0] r_CDBRAMLock = 0;
    // Debug
    reg [0:0] o_GOTCDCOMMAND = 0;
    //reg [7:0] r_CDIntMask;
    reg [7:0] i_CDStatus_last  = 0;
    reg [7:0] i_CDCommand_last = 0;
    reg [7:0] i_CDIntMask_last = 0;
    reg [7:0] i_CDReset_last   = 0;

    // Internal state
    reg [7:0] CurrentPhase  = 0;
    // I believe this is the command bus
    //reg [7:0] CDBusDb       = 0;
    //reg [0:0] CDLastReset   = 0;
    reg [0:0] CDStatusSent  = 0;
    reg [0:0] CDMessageSent = 0;

    localparam true         = 1;
    localparam false        = 0;
    localparam IRQ_8000     = 1;
    localparam IRQ_No_8000  = 0;

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
    localparam REQ_BIT  = 8'h40;
    localparam MSG_BIT  = 8'h20;
    localparam CD_BIT   = 8'h10;
    localparam IO_BIT   = 8'h08;

    // Signals under our(the "target") control.
    wire BSY_signal = r_CDStatus[7];
    wire REQ_signal = r_CDStatus[6];
    wire MSG_signal = r_CDStatus[5];
    wire CD_signal  = r_CDStatus[4];
    wire IO_signal  = r_CDStatus[3];

    function SetREQ; input [0:0] bitValue; r_CDStatus[6] <= bitValue; SetREQ = 1; endfunction

    // Signals under the control of the initiator (not us!)
    localparam PCECD_Drive_kingRST_mask	= 16'h020;
    localparam PCECD_Drive_kingACK_mask = 16'h040;
    localparam PCECD_Drive_kingSEL_mask	= 16'h100;

    // Internal Signals (IOP in beetle)
    reg [15:0] cd_bus_signals;
    
    function SetIOP; 
        input [15:0] mask; 
        input [0:0] set; 
        begin
            if (set) begin
                cd_bus_signals <= cd_bus_signals | mask;
            end else begin
                cd_bus_signals <= cd_bus_signals & ~mask; 
            end
            SetIOP = 1;
        end
    endfunction

    wire RST_signal = cd_bus_signals[5];
    wire ACK_signal = cd_bus_signals[6];
    // @todo this is defaulting to always having SEL on
    wire SEL_signal = 1; //cd_bus_signals[8];

    function SetkingRST; input [0:0] set; SetIOP(PCECD_Drive_kingRST_mask, set); SetkingRST = 1; endfunction
    function PCECD_Drive_SetRST; input [0:0] value; SetkingRST(value); PCECD_Drive_SetRST = 1; endfunction
    function SetkingACK; input [0:0] set; SetIOP(PCECD_Drive_kingACK_mask, set); SetkingACK = 1; endfunction
    function PCECD_Drive_SetACK; input [0:0] value; SetkingACK(value); PCECD_Drive_SetACK = 1; endfunction
    function SetkingSEL; input [0:0] set; SetIOP(PCECD_Drive_kingSEL_mask, set); SetkingSEL = 1; endfunction
    function PCECD_Drive_SetSEL; input [0:0] value; SetkingSEL(value); PCECD_Drive_SetSEL = 1; endfunction

    // CD command buffer stuff.. not sure if this is going to synthesize so well
    reg [7:0] cd_command_buffer [0:255];
    reg [7:0] cd_command_buffer_pos = 0;

    function PCECD_Drive_Power;
        CurrentPhase <= PHASE_BUS_FREE;
        //VirtualReset;
        PCECD_Drive_Power = 1;
    endfunction;

    wire [7:0] IRQ = r_CDIntMask & r_CDBRAMLock & (8'h4|8'h8|8'h10|8'h20|8'h40); 

    function CDIRQ;
        input [0:0] mode; // 8000 is used to do different things to the IRQ register by pce_fast... this replicates that
        input [2:0] irqType;
        begin
            $display("CDIRQ");
            if (mode) begin
                if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_DONE) begin
                    r_CDBRAMLock <= r_CDBRAMLock & ~8'h20;
                end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_READY) begin
                    r_CDBRAMLock <= r_CDBRAMLock & ~8'h40;
                end
            end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_DONE) begin
                r_CDBRAMLock <= r_CDBRAMLock | 8'h20;
            end else if (irqType == PCECD_Drive_IRQ_DATA_TRANSFER_READY) begin
                r_CDBRAMLock <= r_CDBRAMLock | 8'h40;
            end
            // @todo update_irq_state();
            CDIRQ = 1;
        end
    endfunction

    function ChangePhase;
        input [7:0] new_phase;
        begin
            if (new_phase == PHASE_BUS_FREE) begin
                $display ("PHASE_BUS_FREE");
                r_CDStatus <= r_CDStatus & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
                CDIRQ(IRQ_8000, PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
                CurrentPhase <= PHASE_BUS_FREE;
            end
            if (new_phase == PHASE_DATA_IN) begin
                $display ("PHASE_DATA_IN");
                r_CDStatus <= r_CDStatus | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
                CurrentPhase <= PHASE_DATA_IN;
            end
            if (new_phase == PHASE_STATUS) begin
                $display ("PHASE_STATUS");
                r_CDStatus <= r_CDStatus | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
                CurrentPhase <= PHASE_STATUS;
            end
            if (new_phase == PHASE_MESSAGE_IN) begin
                $display ("PHASE_MESSAGE_IN");
                r_CDStatus <= r_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
                CurrentPhase <= PHASE_MESSAGE_IN;
            end
            if (new_phase == PHASE_COMMAND) begin
                $display ("PHASE_COMMAND");
                r_CDStatus <= r_CDStatus | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
                CurrentPhase <= PHASE_COMMAND;
            end
            ChangePhase = 1;
        end
    endfunction

    // function VirtualReset;
    //     $display("VirtualReset");
    //     r_CDStatus = 0;
    //     o_GOTCDCOMMAND = 0;
    //     CurrentPhase = 0;
    //     // We have done a reset
    //     //CDLastReset = 1;
    //     CDStatusSent = 0;
    //     CDMessageSent = 0;
    //     ChangePhase(PHASE_BUS_FREE);
    // endtask

    // task RunCDRead;
    //     //$display ("PCE_CD: RunCDRead - TBC");
    // endtask

    // task RunCDDA;
    //     //$display ("PCE_CD: RunCDDA - TBC");
    // endtask

    localparam ACKDelayInit = 1;
    reg [0:0] clearACK;
    reg [7:0] clearACKDelay = ACKDelayInit;

    function handleClearACK();
        begin
            clearACKDelay <= clearACKDelay - 1;
            if (clearACKDelay == 0) begin
                $display("PCECD: Clearing ACK");
                clearACKDelay <= ACKDelayInit;
                clearACK <= 0;
                SetkingACK(0);
            end
        end
    endfunction

    function PCECD_Drive_Run;
        //reg [0:0] ResetNeeded;
        begin
            // @todo Might not be right to call long running things in here, also Verilog is not always procedural
            // RunCDRead;
            // RunCDDA;
            // ResetNeeded = 0;
            // if (RST_signal && !CDLastReset) begin 
            //     ResetNeeded = 1;
            // end
            // CDLastReset = RST_signal;

            // if (ResetNeeded) begin
            //     VirtualReset;
            // end
            // else begin
                case (CurrentPhase)
                    PHASE_BUS_FREE: begin
                        if (SEL_signal) begin
                            ChangePhase(PHASE_COMMAND);
                        end
                    end
                    PHASE_COMMAND: begin
                        $display ("REQ_Signal is %b", REQ_signal);
                        $display ("ACK_Signal is %b", ACK_signal);
                        if (REQ_signal && ACK_signal) begin
                            $display ("phase_command - setting req false and adding command to buffer");
                            // Databus is valid now
                            cd_command_buffer_pos <= cd_command_buffer_pos + 1;
                            $display("cd_command_buffer_pos: %h", cd_command_buffer_pos);
                            cd_command_buffer [cd_command_buffer_pos] <= r_CDCommand;
                            SetREQ(false);
                            clearACK <= 0;
                        end
                        // if(!REQ_signal && !ACK_signal && cd.command_buffer_pos)	// Received at least one byte, what should we do?
                        if (!REQ_signal && !ACK_signal && cd_command_buffer_pos > 8'h0) begin
                            // We got a command!!!!!!!
                            $display ("We got a command! $%h",  cd_command_buffer [cd_command_buffer_pos]);
                            o_GOTCDCOMMAND <= 1;
                            $finish;
                            // @todo handle the command... for now, expose the fact we got to command phase
                        end
                    end
                    PHASE_STATUS: begin
                        if (REQ_signal && ACK_signal) begin
                            SetREQ(false);
                            CDStatusSent <= true;
                        end
                        if (!REQ_signal && !ACK_signal && CDStatusSent) begin
                            // Status sent, so get ready to send the message!
                            CDStatusSent <= false;
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
                        if (REQ_signal && ACK_signal) begin
                            SetREQ(false);
                            r_CDStatus <= r_CDStatus & ~REQ_BIT;
                            CDMessageSent <= true;
                        end
                        if (!REQ_signal && !ACK_signal && CDMessageSent) begin
                            CDMessageSent <= false;
                            ChangePhase(PHASE_BUS_FREE);
                        end
                    end
                endcase
            //end
            PCECD_Drive_Run = 1;
        end
    endfunction

    reg setSelLatch = 0;

    always @ (posedge i_clk) begin
        // $1800
        // @dentnz fpr now, we are just clearing the ack
        //PCECD_Drive_Run();
        handleClearACK();

        if (i_CDStatus != i_CDStatus_last) begin
            $display("Write 1800 - Status Update Received");
            if (setSelLatch == 0) begin
                $display("latch0");
                PCECD_Drive_SetSEL(1);
                setSelLatch <= 1;
                r_CDStatus <= i_CDStatus;
            end else begin
                $display("latch1");
                r_CDStatus <= i_CDStatus;
                PCECD_Drive_SetSEL(0);
                i_CDStatus_last <= i_CDStatus;
                setSelLatch <= 0;
                r_CDBRAMLock <= r_CDBRAMLock & ~(8'h20 | 8'h40);
            end
            PCECD_Drive_Run();
            //update_irq_state();
        // $1801
        end else if (i_CDCommand != i_CDCommand_last) begin
            $display("Write 1801 - Command Received: %h", i_CDCommand);
            r_CDCommand <= i_CDCommand;
            i_CDCommand_last <= i_CDCommand;
            PCECD_Drive_Run();
        // $1802
        end else if (i_CDIntMask != i_CDIntMask_last) begin
            $display("Write 1802 - Interrupt Received: %h", i_CDIntMask);
            r_CDIntMask <= i_CDIntMask;
            PCECD_Drive_SetACK(i_CDIntMask[7]);
            i_CDIntMask_last <= i_CDIntMask;
            PCECD_Drive_Run();
        // $1804
        end else if (i_CDReset != i_CDReset_last) begin
            $display("Write 1804");
            r_CDReset <= i_CDReset;
            PCECD_Drive_SetRST(i_CDReset[1]);
            // @dentnz - something like this would need to be done to allow the VirtualReset to occur
            //CDLastReset = 0;
    
            if(i_CDReset[1]) begin
                r_CDBRAMLock <= r_CDBRAMLock & ~8'h70;
                //update_irq_state();
            end
            r_CDReset <= i_CDReset;
            i_CDReset_last <= i_CDReset;
            PCECD_Drive_Run();
        end
    end

    initial begin
        CurrentPhase = PHASE_BUS_FREE;
    end
endmodule