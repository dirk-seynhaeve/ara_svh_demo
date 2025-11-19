# Ara

[![ci](https://github.com/pulp-platform/ara/actions/workflows/ci.yml/badge.svg)](https://github.com/pulp-platform/ara/actions/workflows/ci.yml)

Ara is a vector unit working as a coprocessor for the CVA6 core.
It supports the RISC-V Vector Extension, [version 1.0](https://github.com/riscv/riscv-v-spec/releases/tag/v1.0).

Prototypical documentation can be found at https://pulp-platform.github.io/ara

## Quick overview

This repository contains the Ara vector coprocessor RTL and a set of software and verification
artifacts to build and test Ara on a host machine using a RISC-V toolchain and the Spike ISA
simulator.

- `toolchain/*` contains submodules and scripts to build RISC-V toolchains and runtime libraries.
- `toolchain/riscv-isa-sim` contains Spike (the RISC-V ISA simulator) used for software verification.
- `toolchain/verilator` contains a pinned Verilator version for RTL simulation.

Typical workflow:

1. Initialize submodules: `make git-submodules`
2. Build an LLVM-based RISC-V toolchain (RVV support): `make toolchain-llvm`
3. Build Spike (patched for Ara): `make riscv-isa-sim` (see notes below if linking errors occur)
4. Build Verilator for RTL simulation: `make verilator` (see notes below for clang/libc++ issues)

This README documents the prerequisites, the step-by-step build commands used here, and
the troubleshooting steps we applied to get the repository to build on modern Ubuntu systems.

## Prerequisites (Ubuntu)

The following packages are recommended on a fresh Ubuntu install to run the full build and
simulation flow (toolchains, Spike, and Verilator). These were installed on the machine used
to verify the steps in this README.

Install command (run as root or with sudo):

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake ninja-build autoconf automake libtool pkg-config \
  texinfo help2man flex bison \
  clang gcc g++ \
  libc++-dev libc++abi-dev \
  python3 python3-pip git \
  ccache \
  # Verilator prerequisites
  libelf-dev zlib1g zlib1g-dev libfl-dev linux-headers-$(uname -r)
```

Notes:
- If you plan to build Verilator or other tools with `clang`, having `libc++-dev` and `libc++abi-dev`
  available makes it easier to force clang to use libc++ (via `-stdlib=libc++`) when the
  default linking configuration fails.
- `ninja-build` and `cmake` are required to build the LLVM toolchain (riscv-llvm).
- `flex` and `bison` are required by some utilities (e.g., `dtc`).

# Bootstrap helper:

We provide a bootstrap helper script that checks for these packages and can install them for you.
Run it from the project root:

```bash
# Check system for missing packages and compiler/link behavior
./scripts/bootstrap-host.sh --check

# Install recommended packages (requires sudo)
sudo ./scripts/bootstrap-host.sh --install --yes
```

The script also tests whether `clang++` links C++ programs by default or whether you need to
pass `-stdlib=libc++` (this is useful when building Verilator with `clang`).

## Dependencies

Check `DEPENDENCIES.md` for a list of hardware and software dependencies of Ara.


## Supported instructions

Check `FUNCTIONALITIES.md` to check which instructions are currently supported by Ara.

## Get started

Make sure you clone this repository recursively to get all the necessary submodules:

```bash
make git-submodules
```

If the repository path of any submodule changes, run the following command to change your submodule's pointer to the remote repository:

```bash
git submodule sync --recursive
```

## Toolchain

Ara requires a RISC-V LLVM toolchain capable of understanding the vector extension, version 1.0.

To build this toolchain, run the following command in the project's root directory.

```bash
# Build the LLVM toolchain
make toolchain-llvm
```

Ara also requires an updated Spike ISA simulator, with support for the vector extension.
There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike. Therefore, here we resort to older versions of the compilers. If there are problems with dynamic linking, use:
`make riscv-isa-sim LDFLAGS="-static-libstdc++"`. Spike was compiled successfully using gcc and g++ version 7.2.0.

To build Spike, run the following command in the project's root directory.

```bash
# Build Spike
make riscv-isa-sim
```

Troubleshooting notes used while setting up this repository:

- Missing integer types (e.g., `uint64_t`) during compilation: modern compilers may be stricter
  about headers and no longer depend on transitive includes. We fixed this by adding an explicit
  `#include <cstdint>` to `fesvr/device.h`; that change is included in `patches/0003-riscv-isa-sim-patch`.

- If `make riscv-isa-sim` fails with linker errors referring to `libstdc++`, try:

  ```bash
  make riscv-isa-sim LDFLAGS="-static-libstdc++"
  ```

  This forces static linkage against libstdc++ and avoids dynamic linking mismatches on hosts with
  newer compilers. Alternatively, build Spike with older gcc/g++ binaries if available.

- If `configure` or `dtc` steps fail, ensure that the Makefile's sequence is running in the intended
  `build` directory (the Makefile clones `dtc` into `toolchain/riscv-isa-sim/build/dtc`). During
  development there were duplicate `dtc` clones; remove or re-clone as needed so the build uses
  `build/dtc`.

## Verilator

Ara requires an updated version of Verilator, for RTL simulations.

To build it, run the following command in the project's root directory.

```bash
# Build Verilator
# If you build Verilator using `clang` you may need to ensure clang can link C++ programs.
# On some Ubuntu installs clang links against libstdc++ by default and the configure test may fail.
# Passing `-stdlib=libc++` to clang and clang++ resolves this on systems where libc++ is
# available and preferred. Example (explicit):

# Use clang+libc++ (example):
CC=clang CXX=clang++ CXXFLAGS="-stdlib=libc++" LDFLAGS="-stdlib=libc++" make verilator

# Or use gcc/g++ (example):
CC=gcc CXX=g++ make verilator
```

## Full package checklist (recommended)

Below is a more complete list of packages that were validated or are commonly required
to pass through the entire build and simulation flow. This matches the 'complete list'
we compiled while validating the repository on Ubuntu.

- Essential build tools: `build-essential`, `cmake`, `ninja-build`, `autoconf`, `automake`, `libtool`, `pkg-config`
- Compiler toolchain: `clang`, `libc++-dev`, `libc++abi-dev`, `gcc`, `g++`
- Parser/lexer generators: `flex`, `bison`
- Documentation tools: `help2man`, `texinfo`
- Python: `python3`, `python3-pip` (some helper scripts)
- Version control: `git`
- Optional but useful: `ccache`

Install these with the `apt` command shown in the Prerequisites section earlier. Depending on your
environment (container, CI runner, or remote demo server), you may prefer to install only a subset
or to provide prebuilt toolchains instead of building them from source.

## Configuration

Ara's parameters are centralized in the `config` folder, which provides several configurations to the vector machine.
Please check `config/README.md` for more details.

Prepend `config=chosen_ara_configuration` to your Makefile commands, or export the `ARA_CONFIGURATION` variable to choose a configuration other than the `default` one.

## Software

### Build Applications

The `apps` folder contains example applications that work on Ara. Run the following command to build an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world
```

### SPIKE Simulation

All the applications can be simulated with SPIKE. Run the following command to build and run an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world.spike
make spike-run-hello_world
```

### RISC-V Tests

The `apps` folder also contains the RISC-V tests repository, including a few unit tests for the vector instructions. Run the following command to build the unit tests:

```bash
cd apps
make riscv_tests
```

## RTL Simulation

### Hardware dependencies

The Ara repository depends on external IPs and uses Bender to handle the IP dependencies.
To install Bender and initialize all the hardware IPs, run the following commands:

```bash
# Go to the hardware folder
cd hardware
# Install Bender and checkout all the IPs
make checkout
```

### Patches (only once!)

Note: this step is required only once, and needs to be repeated ONLY if the IP hardware dependencies are deleted and checked out again.

Some of the IPs need to be patched to work with Verilator.

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
```

### Simulation

To simulate the Ara system with ModelSim, go to the `hardware` folder, which contains all the SystemVerilog files. Use the following command to run your simulation:

```bash
# Go to the hardware folder
cd hardware
# Only compile the hardware without running the simulation.
make compile
# Run the simulation with the *hello_world* binary loaded
app=hello_world make sim
# Run the simulation with the *some_binary* binary. This allows specifying the full path to the binary
preload=/some_path/some_binary make sim
# Run the simulation without starting the gui
app=hello_world make simc
```

We also provide the `simv` makefile target to run simulations with the Verilator model.

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Only compile the hardware without running the simulation.
make verilate
# Run the simulation with the *hello_world* binary loaded
app=hello_world make simv
```

It is also possible to simulate the unit tests compiled in the `apps` folder. Given the number of unit tests, we use Verilator. Use the following command to install Verilator, verilate the design, and run the simulation:

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Verilate the design
make verilate
# Run the tests
make riscv_tests_simv
```

Alternatively, you can also use the `riscv_tests` target at Ara's top-level Makefile to both compile the RISC-V tests and run their simulation.

### Traces

Add `trace=1` to the `verilate`, `simv`, and `riscv_tests_simv` commands to generate waveform traces in the `fst` format.
You can use `gtkwave` to open such waveforms.

### Ideal Dispatcher mode

CVA6 can be replaced by an ideal FIFO that dispatches the vector instructions to Ara with the maximum issue-rate possible.
In this mode, only Ara and its memory system affect performance.
This mode has some limitations:
 - The dispatcher is a simple FIFO. Ara and the dispatcher cannot have complex interactions.
 - Therefore, the vector program should be fire-and-forget. There cannot be runtime dependencies from the vector to the scalar code.
 - Not all the vector instructions are supported, e.g., the ones that use the `rs2` register.

To compile a program and generate its vector trace:

```bash
cd apps
make bin/${program}.ideal
```

This command will generate the `ideal` binary to be loaded in the L2 memory for the simulation (data accessed by the vector code).
To run the system in Ideal Dispatcher mode:

```bash
cd hardware
make sim app=${program} ideal_dispatcher=1
```

### VCD Dumping

It's possible to dump VCD files for accurate activity-based power analyses. To do so, use the `vcd_dump=1` option to compile the program and to run the simulation:

```bash
make -C apps bin/${program} vcd_dump=1
make -C hardware simc app=${program} vcd_dump=1
```

Currently, the following kernels support automatic VCD dumping: `fmatmul`, `fconv3d`, `fft`, `dwt`, `exp`, `cos`, `log`, `dropout`, `jacobi2d`.

### Linting Flow

We also provide Synopsys Spyglass linting scripts in the hardware/spyglass. Run make lint in the hardware folder, with a specific MemPool configuration, to run the tests associated with the lint_rtl target.

### Support for `rvv-bench`

To run `rvv-bench` instructions benchmark, execute:

```bash
make rvv-bench
make -C apps bin/rvv
make -C hardware simv app=rvv
```

## FPGA implementation and Linux flow

Ara supports Cheshire's FPGA flow and can be currently implemented on VCU128 and VCU118 in bare-metal and with Linux. The tested configuration is with 2 lanes.

For information about the FPGA bare-metal and Linux flows, please refer to `cheshire/README.md`.

## Publications

If you want to use Ara, you can cite us:
```
@Article{Ara2020,
  author = {Matheus Cavalcante and Fabian Schuiki and Florian Zaruba and Michael Schaffner and Luca Benini},
  journal= {IEEE Transactions on Very Large Scale Integration (VLSI) Systems},
  title  = {Ara: A 1-GHz+ Scalable and Energy-Efficient RISC-V Vector Processor With Multiprecision Floating-Point Support in 22-nm FD-SOI},
  year   = {2020},
  volume = {28},
  number = {2},
  pages  = {530-543},
  doi    = {10.1109/TVLSI.2019.2950087}
}
```
```
@INPROCEEDINGS{9912071,
  author={Perotti, Matteo and Cavalcante, Matheus and Wistoff, Nils and Andri, Renzo and Cavigelli, Lukas and Benini, Luca},
  booktitle={2022 IEEE 33rd International Conference on Application-specific Systems, Architectures and Processors (ASAP)},
  title={A “New Ara” for Vector Computing: An Open Source Highly Efficient RISC-V V 1.0 Vector Processor Design},
  year={2022},
  volume={},
  number={},
  pages={43-51},
  doi={10.1109/ASAP54787.2022.00017}}
```
```
@ARTICLE{10500752,
  author={Perotti, Matteo and Cavalcante, Matheus and Andri, Renzo and Cavigelli, Lukas and Benini, Luca},
  journal={IEEE Transactions on Computers},
  title={Ara2: Exploring Single- and Multi-Core Vector Processing With an Efficient RVV 1.0 Compliant Open-Source Processor},
  year={2024},
  volume={73},
  number={7},
  pages={1822-1836},
  keywords={Vectors;Registers;Computer architecture;Vector processors;Multicore processing;Microarchitecture;Kernel;RISC-V;vector;ISA;RVV;processor;efficiency;multi-core},
  doi={10.1109/TC.2024.3388896}}
```
