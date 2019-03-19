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