module top(output r_CDStatus);

    reg [7:0] r_CDStatus;
    reg [7:0] r_CurrentPhase;

    localparam PHASE_BUS_FREE    = 8'b00000000;
    localparam PHASE_COMMAND     = 8'b00000001;
    localparam PHASE_DATA_IN     = 8'b00000010;
    localparam PHASE_DATA_OUT    = 8'b00000100;
    localparam PHASE_STATUS      = 8'b00001000;
    localparam PHASE_MESSAGE_IN  = 8'b00010000;
    localparam PHASE_MESSAGE_OUT = 8'b00100000;

    localparam BUSY_BIT = 8'h80;
    localparam REQ_BIT = 8'h40;
    localparam MSG_BIT = 8'h20;
    localparam CD_BIT = 8'h10;
    localparam IO_BIT = 8'h08;

    task change_phase;
        input [7:0] new_phase;
        begin
            $display ("New Phase: %h", new_phase);
            if (new_phase == PHASE_BUS_FREE)
                begin
                    $display ("PHASE_BUS_FREE");
                    r_CDStatus = r_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
                    r_CurrentPhase = PHASE_BUS_FREE;
                end
            if (new_phase == PHASE_DATA_IN)
                begin
                    $display ("PHASE_DATA_IN");
                    r_CDStatus = r_CDStatus | BUSY_BIT | IO_BIT & ~MSG_BIT & ~CD_BIT & ~REQ_BIT;
                    r_CurrentPhase = PHASE_DATA_IN;
                end
            if (new_phase == PHASE_STATUS)
                begin
                    $display ("PHASE_STATUS");
                    r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | IO_BIT | REQ_BIT & ~MSG_BIT;
                    r_CurrentPhase = PHASE_STATUS;
                end
            if (new_phase == PHASE_MESSAGE_IN)
                begin
                    $display ("PHASE_MESSAGE_IN");
                    r_CDStatus = r_CDStatus | BUSY_BIT | MSG_BIT | CD_BIT | IO_BIT | REQ_BIT;
                    r_CurrentPhase = PHASE_MESSAGE_IN;
                end
            if (new_phase == PHASE_COMMAND)
                begin
                    $display ("PHASE_COMMAND");
                    r_CDStatus = r_CDStatus | BUSY_BIT | CD_BIT | REQ_BIT & ~IO_BIT & ~MSG_BIT;
                    r_CurrentPhase = PHASE_COMMAND;
                end
            log_cdstatus_register;
        end
    endtask

    task log_cdstatus_register;
        begin
            $display ("PCE_CD: 0X00 CDC_STAT: %h", r_CDStatus);
        end
    endtask

    initial 
        begin
            r_CDStatus = 0;
            log_cdstatus_register;
            $display("testing change_phase");
            change_phase(PHASE_BUS_FREE);
            r_CDStatus = 0;
            change_phase(PHASE_DATA_IN);
            r_CDStatus = 0;
            change_phase(PHASE_STATUS);
            r_CDStatus = 0;
            change_phase(PHASE_MESSAGE_IN);
            r_CDStatus = 0;
            change_phase(PHASE_COMMAND);
            $finish; 
        end

endmodule