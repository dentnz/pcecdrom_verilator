//docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc pcecd_top.v --exe sim_main_pcecd.cpp; cd obj_dir; make -j -f Vpcecd_top.mk Vpcecd_top"

#include "Vpcecd_top.cpp"
#include "verilated.h"
#include <iostream>

void pcecd_read(char addr, Vpcecd_top* pcecd) {
    pcecd->addr = addr; pcecd->sel = 1; pcecd->rd = 1; pcecd->wr = 0;
}

void pcecd_write(char addr, char din, Vpcecd_top* pcecd) {
    pcecd->addr = addr; pcecd->din = din; pcecd->sel = 1; pcecd->rd = 0; pcecd->wr = 1;
}

// Here we can do specific things on certain clock ticks
void handlePositiveEdgeClock(int tick, Vpcecd_top* pcecd) {
    // This could be something smarter, but for now... we only care about a few clock cycles
    pcecd->sel = 0;
    if (tick == 1) {
        printf("1) Read from Reg: 0x4  CD_RESET         Expecting: 0x00\n");
        pcecd_read(0x04, pcecd);
    }
    if (tick == 2) {
        printf("2) Write to Reg:  0x4  CD_RESET         Data: 0x02\n");
        pcecd_write(0x04, 0x02, pcecd);
    }
    if (tick == 3) {
        printf("3) Read from Reg: 0x4  CD_RESET         Expecting: 0x02\n");
        pcecd_read(0x04, pcecd);
    }
    if (tick == 4) {
        printf("4) Write to Reg:  0x4  CD_RESET         Data: 0x00\n");
        pcecd_write(0x04, 0x00, pcecd);

    }
    if (tick == 5) {
        printf("5) Write to Reg:  0x2  INT_MASK         Data: 0x00\n");
        pcecd_write(0x02, 0x00, pcecd);
    }

    // These will need to be sorted out too
    if (tick == 6) {
        printf("6) Write to Reg:  0xf  ADPCM_FADE       Data: 0x00\n");
    }
    if (tick == 7) {
        printf("7) Write to Reg:  0xd  ADPCM_ADDR_CONT  Data: 0x80\n");
    }
    if (tick == 8) {
        printf("8) Write to Reg:  0xd  ADPCM_ADDR_CONT  Data: 0x00\n");
    }
    if (tick == 9) {
        printf("9) Write to Reg:  0xb  ADPCM_DMA_CONT   Data: 0x00\n");
    }

    if (tick == 10) {
        printf("10)Read from Reg: 0x2  INT_MASK         Expecting: 0x00\n");
        pcecd_read(0x02, pcecd);
    }
    if (tick == 11) {
        printf("11)Write to Reg:  0x2  INT_MASK         Data: 0x00\n");
        pcecd_write(0x02, 0x00, pcecd);
    }

    // This one too
    if (tick == 12) {
        printf("12)Write to Reg:  0xe  ADPCM_RATE       Data: 0x00\n");
    }
    if (tick == 13) {
        printf("13)Read from Reg: 0x3  BRAM_LOCK        Expecting: 0x00\n");
        pcecd_read(0x03, pcecd);
    }
    if (tick == 14) {
        printf("14)Write to Reg:  0x1  CD_CMD           Data: 0x81\n");
        pcecd_write(0x01, 0x81, pcecd);
    }
    if (tick == 15) {
        printf("15)Read from Reg: 0x0  CDC_STAT         Expecting: 0x00\n");
        pcecd_read(0x00, pcecd);
    }
    if (tick == 16) {
        printf("16)Write to Reg:  0x0  CDC_STAT         Data: 0x81       Clear the ACK,DONE,BRAM interrupt flags\n");
        pcecd_write(0x00, 0x81, pcecd);
    }
    if (tick == 17) {
        printf("17)Read from Reg: 0x0  CDC_STAT         Expecting: 0xd1  [7]BUSY [6]REQ  [4]CD\n");
        pcecd_read(0x00, pcecd);
    }
    if (tick == 18) {
        printf("18)Read from Reg: 0x0  CDC_STAT         Expecting: 0xd1  [7]BUSY [6]REQ  [4]CD\n");
        pcecd_read(0x00, pcecd);
    }
    if (tick == 19) {
        printf("19)Write to Reg: 0x1  CDC_CMD           Data: 0x00\n");
        pcecd_write(0x00, 0x00, pcecd);
    }
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
