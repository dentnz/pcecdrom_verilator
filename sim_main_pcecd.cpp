//docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc pcecd_top.v --exe sim_main_pcecd.cpp; cd obj_dir; make -j -f Vpcecd_top.mk Vpcecd_top"

#include "Vpcecd_top.cpp"
#include "verilated.h"
#include <iostream>

// Here we can do specific things on certain clock ticks
void handlePositiveEdgeClock(int tick, Vpcecd_top* pcecd) {
    // This could be something smarter, but for now... we only care about a few clock cycles
    pcecd->sel = 0;
    if (tick == 1) {
        printf("Read from Reg: 0x4  CD_RESET         Expecting: 0x00\n");
        pcecd->addr = 0x04;
        pcecd->sel = 1;
        pcecd->rd = 1;
        pcecd->wr = 0;
    }
    if (tick == 2) {
        printf("Write to Reg:  0x4  CD_RESET         Data: 0x02\n");
        pcecd->addr = 0x04;
        pcecd->wr = 1;
        pcecd->rd = 0;
        pcecd->sel = 1;
        pcecd->din = 0x02;
    }
    if (tick == 3) {
        printf("Read from Reg:  0x4  CD_RESET        Expecting: 0x02\n");
        pcecd->addr = 0x04;
        pcecd->sel = 1;
        pcecd->rd = 1;
        pcecd->wr = 0;
    }
    if (tick == 4) {
        printf("Write to Reg:  0x4  CD_RESET         Data: 0x00\n");
        pcecd->addr = 0x04;
        pcecd->wr = 1;
        pcecd->rd = 0;
        pcecd->sel = 1;
        pcecd->din = 0x00;
    }
    if (tick == 5) {
        printf("Write to Reg:  0x2  INT_MASK         Data: 0x00\n");
        pcecd->addr = 0x02;
        pcecd->wr = 1;
        pcecd->rd = 0;
        pcecd->sel = 1;
        pcecd->din = 0x00;
    }

    // These will need to be sorted out too
    if (tick == 6) {
        printf("TBC: Write to Reg:  0xf  ADPCM_FADE          Data: 0x00\n");
    }
    if (tick == 7) {
        printf("TBC: Write to Reg:  0xd  ADPCM_ADDR_CONT     Data: 0x80\n");
    }
    if (tick == 8) {
        printf("TBC: Write to Reg:  0xd  ADPCM_ADDR_CONT     Data: 0x00\n");
    }
    if (tick == 9) {
        printf("TBC: Write to Reg:  0xb  ADPCM_DMA_CONT      Data: 0x00\n");
    }

    if (tick == 10) {
        printf("Read from Reg: 0x2  INT_MASK         Expecting: 0x00\n");
        pcecd->addr = 0x02;
        pcecd->sel = 1;
        pcecd->rd = 1;
        pcecd->wr = 0;
    }
    if (tick == 11) {
        printf("Write to Reg:  0x2  INT_MASK         Data: 0x00\n");
        pcecd->addr = 0x02;
        pcecd->sel = 1;
        pcecd->rd = 1;
        pcecd->wr = 1;
        pcecd->din - 0x00;
    }

    // This one too
    if (tick == 12) {
        printf("TBC: Write to Reg:  0xe  ADPCM_RATE         Data: 0x00\n");
    }
    if (tick == 13) {
        printf("Read from Reg: 0x3  BRAM_LOCK        Expecting: 0x00\n");
        pcecd->addr = 0x03;
        pcecd->sel = 1;
        pcecd->rd = 1;
        pcecd->wr = 0;
    }
}

// Here we can do specific things on certain clock ticks
void logCdRegisters(Vpcecd_top* pcecd) {
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
    Vpcecd_top* pcecd = new Vpcecd_top;

    // Simulation time...
    int tick = 0;
    while (!Verilated::gotFinish()) {
        tick++;
        char input;
        cin>>input;
        // Toggle the clock - tick tock
        pcecd->clk = 0;
        pcecd->eval();
        // tick
        pcecd->clk = 1;
        handlePositiveEdgeClock(tick, pcecd);
        pcecd->eval();
        //logCdRegisters(pcecd);
        // tock
        pcecd->clk = 0;
        pcecd->eval();
    }

    // Done simulating
    pcecd->final();
    // Clean-up
    delete pcecd;
    exit(0);
}
