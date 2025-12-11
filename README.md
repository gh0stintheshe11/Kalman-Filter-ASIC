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

3. **Output** - Results saved to `kf_ext.log`

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

## Project Structure

```
Kalman-Filter-ASIC/
├── src/                    # RTL source files
│   ├── kf_top.v           # Top-level KF module
│   ├── kf_top_tb.v        # Unified testbench
│   ├── au.v               # Arithmetic Unit
│   ├── sequencer.v        # Instruction sequencer
│   ├── router_a.v         # Router A
│   ├── router_b.v         # Router B
│   ├── mem_reg.v          # Memory registers
│   ├── kf_1d.mem          # 1D KF instruction ROM
│   └── kf_2d.mem          # 2D KF instruction ROM
├── sim_rtl/               # RTL simulation
│   ├── sim_rtl.sh         # Simulation runner script
│   └── kf_gen_test.py     # Test data generator
└── README.md
```
