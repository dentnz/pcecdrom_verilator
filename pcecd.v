module pcecd(
    input i_clk,
    // Allows for input from the PC Engine itself
    input [7:0] i_CDStatus,         // 0x00
    input [7:0] i_CDCommand,        // 0x01
    input [7:0] i_CDIntMask,        // 0x02
    input [7:0] i_CDReset,          // 0x03
    input [0:0] i_IRQ2_N,

    // Read internally and externally
    output reg [7:0] o_CDStatus,        // 0x00 
    output reg [7:0] o_CDCommand,       // 0x01
    output reg [7:0] o_CDIntMask,       // 0x02
    output reg [7:0] o_CDBRAMLock,      // 0x03
    output reg [7:0] o_CDReset,         // 0x04
    output reg [0:0] o_IRQ2_N,

    // Debugging output
    output reg [0:0] o_GOTCDCOMMAND,
    output reg [7:0] CurrentPhase,
    output reg [7:0] o_debug
    
);

    reg [7:0] i_CDStatus_last  = 0;
    reg [7:0] i_CDCommand_last = 0;
    reg [7:0] i_CDIntMask_last = 0;
    reg [7:0] i_CDReset_last   = 0;

    // Internal state
    reg [7:0] ChangePhase = 0;
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
    wire BSY_signal = o_CDStatus[7];
    wire REQ_signal = o_CDStatus[6];
    wire MSG_signal = o_CDStatus[5];
    wire CD_signal  = o_CDStatus[4];
    wire IO_signal  = o_CDStatus[3];

    // Signals under the control of the initiator (not us!)
    localparam PCECD_Drive_kingRST_mask	= 16'h020;
    localparam PCECD_Drive_kingACK_mask = 16'h040;
    localparam PCECD_Drive_kingSEL_mask	= 16'h100;

    // Internal Signals (IOP in beetle is used to update these)
    reg [15:0] cd_bus_signals;

    wire RST_signal = cd_bus_signals[5];
    wire ACK_signal = cd_bus_signals[6];
    // @todo this is defaulting to always having SEL on
    wire SEL_signal = 1; //cd_bus_signals[8];

    // CD command buffer stuff.. not sure if this is going to synthesize so well
    reg [7:0] cd_command_buffer [0:255];
    reg [7:0] cd_command_buffer_pos = 0;


    reg [0:0] setSelLatch = 0;
    localparam ACKDelayInit = 2;
    reg [0:0] clearACK;
    reg [7:0] clearACKDelay = ACKDelayInit;
    reg [0:0] changePhaseLatch = 0;

    always @ (posedge i_clk) begin
        o_IRQ2_N <= i_IRQ2_N;
      // Change Phase
      if (changePhaseLatch == 1) begin
        if (ChangePhase == PHASE_BUS_FREE) begin
            $display ("PHASE_BUS_FREE");
            o_CDStatus <= o_CDStatus & ~BUSY_BIT & ~MSG_BIT & ~CD_BIT & ~IO_BIT & ~REQ_BIT;
            o_CDBRAMLock <= o_CDBRAMLock & ~8'h20; // CDIRQ(IRQ_8000, PCECD_Drive_IRQ_DATA_TRANSFER_DONE);
            CurrentPhase <= PHASE_BUS_FREE;
        end
        if (ChangePhase == PHASE_DATA_IN) begin
            $display ("PHASE_DATA_IN");
            o_CDStatus <= o_CDStatus | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
            CurrentPhase <= PHASE_DATA_IN;
        end
        if (ChangePhase == PHASE_STATUS) begin
            $display ("PHASE_STATUS");
            o_CDStatus <= o_CDStatus | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
            CurrentPhase <= PHASE_STATUS;
        end
        if (ChangePhase == PHASE_MESSAGE_IN) begin
            $display ("PHASE_MESSAGE_IN");
            o_CDStatus <= o_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
            CurrentPhase <= PHASE_MESSAGE_IN;
        end
        if (ChangePhase == PHASE_COMMAND) begin
            $display ("PHASE_COMMAND");
            o_CDStatus <= o_CDStatus | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
            CurrentPhase <= PHASE_COMMAND;
        end
        changePhaseLatch <= 1;
      end

    // ACK DELAY
    clearACKDelay <= clearACKDelay - 1;
    if (clearACKDelay == 0) begin
        $display("PCECD: Clearing ACK");
        clearACKDelay <= ACKDelayInit;
        clearACK <= 0;
        // // Clear the ACK
        cd_bus_signals <= cd_bus_signals & ~PCECD_Drive_kingACK_mask; 
    end

    // PCECD_Write
    // $1800
    if (i_CDStatus != i_CDStatus_last) begin
        o_debug <= 8'h01;
        $display("Write 1800 - Status Update Received");
        if (setSelLatch == 0) begin
            $display("latch0");
            o_CDStatus <= i_CDStatus;
            cd_bus_signals[8] <= 1;  // PCECD_Drive_SetSEL(1);
            setSelLatch <= 1;
        end else begin
            $display("latch1");
            cd_bus_signals[8] <= 0; //PCECD_Drive_SetSEL(0);
            i_CDStatus_last <= i_CDStatus;
            setSelLatch <= 0;
            o_CDBRAMLock <= o_CDBRAMLock & ~(8'h20 | 8'h40);
         end
      // $1801
      end else if (i_CDCommand != i_CDCommand_last) begin
        o_debug <= 8'h02;
        $display("Write 1801 - Command Received: %h", i_CDCommand);
        o_CDCommand <= i_CDCommand;
        i_CDCommand_last <= i_CDCommand;
      // $1802
      end else if (i_CDIntMask != i_CDIntMask_last) begin
        o_debug <= 8'h03;
        $display("Write 1802 - Interrupt Received: %h", i_CDIntMask);
        o_CDIntMask <= i_CDIntMask;
        // Set ACK signal to contents of the interrupt registers 7th bit
        cd_bus_signals[6] <= i_CDIntMask[7]; // PCECD_Drive_SetACK(i_CDIntMask[7]);
        //update_irq_state();
        if ((o_CDCommand & o_CDBRAMLock & 8'h7C) != 0) begin 
            o_IRQ2_N = 1;
        end else begin
            o_IRQ2_N = 0;
        end
         i_CDIntMask_last <= i_CDIntMask;
      // $1804
      end else if (i_CDReset != i_CDReset_last) begin
        o_debug <= 8'h04;
        $display("Write 1804");
        o_CDReset <= i_CDReset;
        //PCECD_Drive_SetRST(i_CDReset[1]);
        // @dentnz - something like this would need to be done to allow the VirtualReset to occur
        //CDLastReset = 0;
        if(i_CDReset[1]) begin
            o_CDBRAMLock <= o_CDBRAMLock & ~8'h70;
            //update_irq_state();
            if ((o_CDCommand & o_CDBRAMLock & 8'h7C) != 0) begin 
                o_IRQ2_N = 1;
            end else begin
                o_IRQ2_N = 0;
            end
        end
        o_CDReset <= i_CDReset;
        i_CDReset_last <= i_CDReset;
      end

      // PCECD_Drive_Run
      case (CurrentPhase)
           PHASE_BUS_FREE: begin
            if (SEL_signal) begin
                ChangePhase <= PHASE_COMMAND;
                changePhaseLatch <= 1;
            end
         end
         PHASE_COMMAND: begin
            o_debug <= 8'h05;
            $display ("REQ_Signal is %b", REQ_signal);
            $display ("ACK_Signal is %b", ACK_signal);
            if (REQ_signal && ACK_signal) begin
                o_debug <= 8'h06;
                $display ("phase_command - setting req false and adding command to buffer");
                // Databus is valid now
                cd_command_buffer_pos <= cd_command_buffer_pos + 1;
                $display("cd_command_buffer_pos: %h", cd_command_buffer_pos);
                cd_command_buffer [cd_command_buffer_pos] <= o_CDCommand;
                // Set the REQ low
                o_CDStatus[6] <= 0;
                clearACK <= 0;
            end
            // if(!REQ_signal && !ACK_signal && cd.command_buffer_pos)	// Received at least one byte, what should we do?
            if (!REQ_signal && !ACK_signal && cd_command_buffer_pos > 8'h0) begin
                // We got a command!!!!!!!
                o_debug <= 8'h07;
                $display ("We got a command! $%h",  cd_command_buffer [cd_command_buffer_pos]);
                o_GOTCDCOMMAND <= 1;
                $finish;
                // @todo handle the command... for now, expose the fact we got to command phase
            end
         end
         PHASE_STATUS: begin
            if (REQ_signal && ACK_signal) begin
                // Set the REQ low
                o_CDStatus[6] <= 0;
                CDStatusSent <= true;
            end
            if (!REQ_signal && !ACK_signal && CDStatusSent) begin
                // Status sent, so get ready to send the message!
                CDStatusSent <= false;
                // @todo message_pending message goes on the buss
                //cd_bus.DB = cd.message_pending;
                ChangePhase <= PHASE_MESSAGE_IN;
                changePhaseLatch <= 1;
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
                // Set the REQ low
                o_CDStatus[6] <= 0;
                o_CDStatus <= o_CDStatus & ~REQ_BIT;
                CDMessageSent <= true;
            end
            if (!REQ_signal && !ACK_signal && CDMessageSent) begin
                CDMessageSent <= false;
                ChangePhase <= PHASE_BUS_FREE;
                changePhaseLatch <= 1;
            end
         end
      endcase
   end

   initial begin
    CurrentPhase = PHASE_BUS_FREE;
    changePhaseLatch = 1;
   end
endmodule