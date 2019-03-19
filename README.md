# PCE Engine CD ROM - Verilog and Verilator

## Requirements to compile and run the simulation

- Linux (Windows users can use VirtualBox)
- Docker

## Compiling the Verilog and simulator

```
docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc top.v --exe sim_main.cpp; cd obj_dir; make -j -f Vtop.mk Vtop"
```

## Running the simulator

```
./obj_dir/Vtop
```

## Plan

Using the contents of userio_cpp_stuff/beetle_userio_stuff.cpp, generate some Verilated Verilog code that can be run on the FPGA that would mimic how Beetle acts as a cdrom interface. It is hoped that with
some effort, the entire cdrom interface could then be added to the existing PC Engine core. 