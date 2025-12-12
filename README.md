# Kalman-Filter-ASIC
ECE1388 course project: a simple 2x2 Kalman Filter ASIC design

## RTL Simulation

All simulation is run from the `sim_rtl/` directory:

```bash
cd sim_rtl
```

### Usage

```bash
./sim_rtl.sh              # Run basic module tests (AU, router, mem, sequencer)
./sim_rtl.sh -t <mem>     # Run top-level KF test with specified .mem file
./sim_rtl.sh -e <N>       # Run extended test with N iterations
./sim_rtl.sh -a           # Run all tests
./sim_rtl.sh -h           # Show help
```

### Examples

```bash
# Basic module tests
./sim_rtl.sh

# Top-level KF tests
./sim_rtl.sh -t ../src/kf_1d.mem    # 1D Kalman Filter test
./sim_rtl.sh -t ../src/kf_2d.mem    # 2D Kalman Filter test

# Extended tests with configurable iterations
./sim_rtl.sh -e 200                  # Run 200 iterations
./sim_rtl.sh -e 50                   # Run 50 iterations
./sim_rtl.sh -e 20                   # Run 20 iterations

# Run everything
./sim_rtl.sh -a
```

### Extended Test Flow (`-e`)

The extended test verifies the ASIC against a Python reference implementation:

1. **Generate test data** - Python script creates:
   - `truth.txt` - ground truth positions
   - `measurements.txt` - noisy measurements
   - `kf_expected.txt` - expected KF outputs from Python

2. **Run ASIC simulation** - Verilog testbench:
   - Loads test data from files
   - Runs N KF iterations
   - Compares ASIC output vs Python reference
   - Exports ASIC results to `kf_asic.txt`

3. **Generate plot** - Python creates comparison plot:
   - Position estimation: truth vs measurements vs Python KF vs ASIC KF
   - Error analysis: raw error vs KF error
   - Saves to `kf_results.png`

### Output Files

| File | Description |
|------|-------------|
| `au.log` | Arithmetic Unit test results |
| `router_a.log` | Router A test results |
| `router_b.log` | Router B test results |
| `mem_reg.log` | Memory Register test results |
| `sequencer.log` | Sequencer test results |
| `kf_1d.log` | 1D Kalman Filter test results |
| `kf_2d.log` | 2D Kalman Filter test results |
| `kf_ext.log` | Extended test results |
| `kf_results.png` | Visual comparison plot |

## Post-Synthesis Simulation

Post-synthesis simulation verifies the synthesized gate-level netlist against the standard cell library.

All simulation is run from the `sim_post_syn/` directory:

```bash
cd sim_post_syn
```

### Prerequisites

- Synthesized netlists in `syn/` (sub-modules) and `syn_top/` (kf_top)
- TSMC 65nm standard cell library (`tcbn65gplus.v`) in `sim_post_syn/`

### Usage

```bash
./sim_post_syn.sh              # Run all sub-module post-syn tests
./sim_post_syn.sh -m <module>  # Run specific module test
./sim_post_syn.sh -t           # Run kf_top post-syn test
./sim_post_syn.sh -h           # Show help
```

### Examples

```bash
# Run all sub-module tests (au, router_a, router_b, mem_reg, sequencer)
./sim_post_syn.sh

# Test specific module
./sim_post_syn.sh -m au        # Test AU module only
./sim_post_syn.sh -m router_a  # Test Router A only

# Test full top-level design
./sim_post_syn.sh -t           # Run kf_top post-syn test
```

### Output Files

| File | Description |
|------|-------------|
| `au_post_syn.log` | AU post-syn test results |
| `router_a_post_syn.log` | Router A post-syn test results |
| `router_b_post_syn.log` | Router B post-syn test results |
| `mem_reg_post_syn.log` | Memory Register post-syn test results |
| `sequencer_post_syn.log` | Sequencer post-syn test results |
| `kf_top_post_syn.log` | Top-level KF post-syn test results |

### Notes

- Sub-module tests use `+define+POST_SYN` to handle parameter differences between RTL and synthesized netlists
- The kf_top test loads ROM contents via the programming port (since `$readmemh` doesn't work on synthesized ROM)
- Post-syn tests cannot probe internal signals; they verify functionality through external I/O only

## Project Structure

```
Kalman-Filter-ASIC/
├── src/                    # RTL source files
│   ├── kf_top.v           # Top-level KF module
│   ├── kf_top_tb.v        # Unified testbench (RTL + post-syn)
│   ├── au.v               # Arithmetic Unit
│   ├── sequencer.v        # Instruction sequencer
│   ├── router_a.v         # Router A
│   ├── router_b.v         # Router B
│   ├── mem_reg.v          # Memory registers
│   ├── *_tb.v             # Sub-module testbenches
│   ├── kf_1d.mem          # 1D KF instruction ROM
│   └── kf_2d.mem          # 2D KF instruction ROM
├── sim_rtl/               # RTL simulation
│   ├── sim_rtl.sh         # RTL simulation runner
│   └── kf_gen_test.py     # Test data generator
├── syn/                   # Sub-module synthesis outputs
│   └── *_syn.v            # Synthesized sub-module netlists
├── syn_top/               # Top-level synthesis
│   ├── synthesis_kf_top.tcl  # DC synthesis script
│   └── kf_top_syn.v       # Synthesized top-level netlist
├── sim_post_syn/          # Post-synthesis simulation
│   ├── sim_post_syn.sh    # Post-syn simulation runner
│   └── tcbn65gplus.v      # TSMC 65nm standard cell library
└── README.md
```
