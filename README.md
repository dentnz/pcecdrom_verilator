# PCE Engine CD ROM - Verilog and Verilator

## Requirements to compile and run the simulation

- Linux (Windows users can use VirtualBox)
- Docker

## Compiling the Verilog and simulator

```
docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc pcecd_top.v --exe sim_main_pcecd.cpp; cd obj_dir; make -j -f Vpcecd_top.mk Vpcecd_top"
```

## Running the simulator

```
./obj_dir/Vpcecd_top
```
From here you can type a character (or several) and press enter to advance the clock:
```
....................................................
1) Read from Reg: 0x4  CD_RESET         Expecting: 0x00
Read 0x4. dout = 0x00
2) Write to Reg:  0x4  CD_RESET         Data: 0x02
3) Read from Reg: 0x4  CD_RESET         Expecting: 0x02
Read 0x4. dout = 0x02
Performing reset
4) Write to Reg:  0x4  CD_RESET         Data: 0x00
Phase Changed: 01
5) Write to Reg:  0x2  INT_MASK         Data: 0x00
6) Write to Reg:  0xf  ADPCM_FADE       Data: 0x00
7) Write to Reg:  0xd  ADPCM_ADDR_CONT  Data: 0x80
8) Write to Reg:  0xd  ADPCM_ADDR_CONT  Data: 0x00
9) Write to Reg:  0xb  ADPCM_DMA_CONT   Data: 0x00
10)Read from Reg: 0x2  INT_MASK         Expecting: 0x00
Read 0x2. dout = 0x00
Phase Changed: 02
PHASE_COMMAND
11)Write to Reg:  0x2  INT_MASK         Data: 0x00
12)Write to Reg:  0xe  ADPCM_RATE       Data: 0x00
13)Read from Reg: 0x3  BRAM_LOCK        Expecting: 0x00
Read 0x3. dout = 0x00
bram_enabled = 0x0
14)Write to Reg:  0x1  CD_CMD           Data: 0x81
Write to reg 0x01, value 0x81
here we go...
15)Read from Reg: 0x0  CDC_STAT         Expecting: 0x00 <======== This is failing
Read 0x0. dout = 0xd0
16)Write to Reg:  0x0  CDC_STAT         Data: 0x81       Clear the ACK,DONE,BRAM interrupt flags
Write to reg 0x00, value 0x81
17)Read from Reg: 0x0  CDC_STAT         Expecting: 0xd1  [7]BUSY [6]REQ  [4]CD
Read 0x0. dout = 0xd1
18)Read from Reg: 0x0  CDC_STAT         Expecting: 0xd1  [7]BUSY [6]REQ  [4]CD
Read 0x0. dout = 0xd1
19)Write to Reg: 0x1  CDC_CMD           Data: 0x00
Write to reg 0x01, value 0x00
20)Read from Reg: 0x2  INT_MASK         Expecting: 0x00
Read 0x2. dout = 0x00
21)Write to Reg:  0x2  INT_MASK         Data: 0x80
22)Read from Reg: 0x0  CDC_STAT         Expecting: 0x91  [7]BUSY [4]CD <============== Fail
Read 0x0. dout = 0xd1
phase_command - Adding command to buffer
23))Read from Reg: 0x2  INT_MASK        Expecting: 0x80  [7]ACK!
Read 0x2. dout = 0x80
24))Write to Reg:  0x2  INT_MASK        Data: 0x00
25)Read from Reg: 0x0  CDC_STAT         Epecting: 0xd1  [7]BUSY [6]REQ  [4]CD) <======== Fail
Read 0x0. dout = 0x91
0x00 TEST_UNIT_READY (6) - command byte 1 of 6
26)Write to Reg:  0x1  CDC_CMD          Data: 0x00
Write to reg 0x01, value 0x00
27)Read from Reg: 0x2  INT_MASK         Expecting: 0x00
Read 0x2. dout = 0x00
```

## Methodology

ElectronAsh connected a real PCE Core Grafx to a DE1 in a previous project. This allowed him to
deploy our code into a FPGA for testing against real hardware. He ironed out the REQ/ACK process
and eventually got the PCE to send the first command bytes (TEST UNIT READY (6)).

Next, Ash moved the code into the existing TGFX16 core. He proceeded to add more code, in 
particular, he introduced more state machines and a clock divider to ensure better timing with 
the register updates.