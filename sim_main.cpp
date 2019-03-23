//docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc top.v --exe sim_main.cpp; cd obj_dir; make -j -f Vtop.mk Vtop"

#include "Vtop.cpp"
#include "verilated.h"
#include <iostream>

// Here we can do specific things on certain clock ticks
void handlePositiveEdgeClock(int tick, Vtop* top) {
    // This could be something smarter, but for now... we only care about a few clock cycles
    if (tick == 1) {
        // @todo stuff on first tick
    }
}

// Here we can do specific things on certain clock ticks
void logCdRegisters(Vtop* top) {
    printf("PCE_CD: 0x00 CDC_STAT:    %02x", top->r_CDStatus);
    if (top->r_CDStatus & 0x80) printf(" [7]BUSY ");
    if (top->r_CDStatus & 0x40) printf(" [6]REQ  ");
    if (top->r_CDStatus & 0x20) printf(" [5]MSG  ");
    if (top->r_CDStatus & 0x10) printf(" [4]CD   ");
    if (top->r_CDStatus & 0x08) printf(" [3]IO   ");
    printf("\n");

    printf("PCE_CD: 0x02 INT_MASK:    %02x", top->r_CDIntMask);
    if (top->r_CDIntMask & 0x80) printf(" [7]ACK_FLAG! ");    // Actual ACKnowledge flag, AFAIK. ElectronAsh.
    if (top->r_CDIntMask & 0x40) printf(" [6]ACK_MASK  ");
    if (top->r_CDIntMask & 0x20) printf(" [5]DONE_MASK ");
    if (top->r_CDIntMask & 0x10) printf(" [4]BRAM_MASK ");
    if (top->r_CDIntMask & 0x08) printf(" [3]FULL_MASK ");
    if (top->r_CDIntMask & 0x04) printf(" [2]HALF_MASK ");
    if (top->r_CDIntMask & 0x02) printf(" [1]L/R ");
    printf("\n");
    
    printf("PCE_CD: 0x03 BRAM_LOCK:   %02x", top->r_CDBRAMLock);
    if (top->r_CDBRAMLock & 0x40) printf(" ACK  "); // Bit 6.
    if (top->r_CDBRAMLock & 0x20) printf(" DONE "); // Bit 5.
    if (top->r_CDBRAMLock & 0x10) printf(" BRAM "); // Bit 4.
    if (top->r_CDBRAMLock & 0x08) printf(" FULL "); // Bit 3.
    if (top->r_CDBRAMLock & 0x04) printf(" HALF "); // Bit 2.
    if (top->r_CDBRAMLock & 0x02) printf(" L/R ");  // Bit 1.
    printf("\n");

    // 	data = read_cd_reg(0x04);
    // 	if (previous_reg_04 != data) {
    // 		printf("PCE_CD: 0x04 CD RESET:    %02x\n", data);
    // 		previous_reg_04 = data;
    // 	}

    // 	data = read_cd_reg(0x05);
    // 	if (previous_reg_05 != data) {
    // 		printf("PCE_CD: 0x05 CONV_PCM:    %02x\n", data);
    // 		previous_reg_05 = data;
    // 	}

    // 	data = read_cd_reg(0x06);
    // 	if (previous_reg_06 != data) {
    // 		printf("PCE_CD: 0x06 PCM_DATA:    %02x\n", data);
    // 		previous_reg_06 = data;
    // 	}

    // 	data = read_cd_reg(0x07);
    // 	if (previous_reg_07 != data) {
    // 		printf("PCE_CD: 0x07 BRAM_UNLOCK: %02x\n", data);
    // 		previous_reg_07 = data;
    // 	}

    // 	// todo: need to complete all of these
    // 	// printf("0x00 CDC_STAT:    %02x\n", read_cd_reg(0x00));
    // 	// printf("0x01 CDC_CMD:     %02x\n", read_cd_reg(0x01));
    // 	// printf("0x02 INT_MASK:    %02x\n", read_cd_reg(0x02));
    // 	// printf("0x03 BRAM_LOCK:   %02x\n", read_cd_reg(0x03));
    // 	// printf("0x04 CD RESET:    %02x\n", read_cd_reg(0x04));
    // 	// printf("0x05 CONV_PCM:    %02x\n", read_cd_reg(0x05));
    // 	// printf("0x06 PCM_DATA:    %02x\n", read_cd_reg(0x06));
    // 	// printf("0x07 BRAM_UNLOCK: %02x\n", read_cd_reg(0x07));
    // 	// printf("0x08 ADPCM_A_LO:  %02x\n", read_cd_reg(0x08));
    // 	// printf("0x09 ADPCM_A_HI:  %02x\n", read_cd_reg(0x09));
    // 	// printf("0x0a AD_RAM_DATA: %02x\n", read_cd_reg(0x0a));
    // 	// printf("0x0b AD_DMA_CONT: %02x\n", read_cd_reg(0x0b));
    // 	// printf("0x0c ADPCM_STAT:  %02x\n", read_cd_reg(0x0c));
    // 	// printf("0x0d ADPCM_ADDR:  %02x\n", read_cd_reg(0x0d));
    // 	// printf("0x0e ADPCM_RATE:  %02x\n", read_cd_reg(0x0e));
    // 	// printf("0x0f ADPCM_FADE:  %02x\n", read_cd_reg(0x0f));
}

int main(int argc, char **argv, char **env) {    
    Verilated::commandArgs(argc, argv);
    // Create instance
    Vtop* top = new Vtop;

    // Simulation time...
    int tick = 0;
    while (!Verilated::gotFinish()) {
        tick++;
        char input;
        cin>>input;
        // Toggle the clock - tick tock
        top->i_clk = 0;
        top->eval();
        // tick
        top->i_clk = 1;
        handlePositiveEdgeClock(tick, top);
        top->eval();
        logCdRegisters(top);
        // tock
        top->i_clk = 0;
        top->eval();
    }

    // Done simulating
    top->final();
    // Clean-up
    delete top;
    exit(0);
}
