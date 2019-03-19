//docker run --rm -v $(pwd):/data rweda/verilator "cd /data; verilator -Wall --cc top.v --exe sim_main.cpp; cd obj_dir; make -j -f Vtop.mk Vtop"

#include "Vtop.cpp"
#include "verilated.h"
#include <iostream>

int main(int argc, char **argv, char **env) {
    Verilated::commandArgs(argc, argv);
    // Create instance
    Vtop* top = new Vtop;

    // Simulation time...
    while (!Verilated::gotFinish()) {
        // Evaluate the model
        top->eval();
        // Read a output
        //cout << top->w_CDStatus << endl;
    }

    // Done simulating
    top->final();
    // Cleanup
    delete top;
    exit(0);
}