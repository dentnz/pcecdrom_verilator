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
.................
Read from Reg: 0x4  CD_RESET         Expecting: 0x00
Read 0x4. dout = 0x00
Write to Reg:  0x4  CD_RESET         Data: 0x02
Write to 0x4. irq2_assert will be: 0x0
Read from Reg:  0x4  CD_RESET        Expecting: 0x02
Read 0x4. dout = 0x02
Write to Reg:  0x4  CD_RESET         Data: 0x00
Write to Reg:  0x2  INT_MASK         Data: 0x00
Write to 0x2. irq2_assert will be: 0x0
TBC: Write to Reg:  0xf  ADPCM_FADE          Data: 0x00
TBC: Write to Reg:  0xd  ADPCM_ADDR_CONT     Data: 0x80
TBC: Write to Reg:  0xd  ADPCM_ADDR_CONT     Data: 0x00
TBC: Write to Reg:  0xb  ADPCM_DMA_CONT      Data: 0x00
Read from Reg: 0x2  INT_MASK         Expecting: 0x00
Read 0x2. dout = 0x00
Write to Reg:  0x2  INT_MASK         Data: 0x00
Read 0x2. dout = 0x00
TBC: Write to Reg:  0xe  ADPCM_RATE         Data: 0x00
Read from Reg: 0x3  BRAM_LOCK        Expecting: 0x00
Read 0x3. dout = 0x00
bram_enabled = 0x0
```

## Plan

Plan has changed, now using this code here as the guide for implementing this stuff:

https://github.com/TASVideos/BizHawk/blob/master/BizHawk.Emulation.Cores/Consoles/PC%20Engine/PCEngine.TurboCD.cs