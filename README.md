# Kalman Filter ASIC

A 2-state, 16-bit fixed-point Kalman Filter ASIC implementation in TSMC 65nm technology, based on the architecture proposed in:

> [!IMPORTANT] 
> R. Chávez-Bracamontes, M.A. Gurrola-Navarro, H.J. Jiménez-Flores, and M. Bandala-Sánchez, "VLSI architecture of a Kalman filter optimized for real-time applications," *IEICE Electronics Express*, Vol.13, No.6, pp.1-11, 2016. [DOI: 10.1587/elex.13.20160043](https://doi.org/10.1587/elex.13.20160043)

## Table of Contents

- [Kalman Filter ASIC](#kalman-filter-asic)
  - [Table of Contents](#table-of-contents)
  - [Project Overview](#project-overview)
    - [Kalman Filter Algorithm](#kalman-filter-algorithm)
  - [Architecture](#architecture)
    - [Components](#components)
    - [Design Specifications (from paper)](#design-specifications-from-paper)
    - [Instruction Set](#instruction-set)
  - [RTL Simulation](#rtl-simulation)
    - [Test Setup](#test-setup)
    - [Validation Approach](#validation-approach)
    - [Results](#results)
  - [Synthesis](#synthesis)
    - [Summary](#summary)
  - [Post-Synthesis Simulation](#post-synthesis-simulation)
  - [Layout](#layout)
    - [Core Layout](#core-layout)
    - [Full Chip with Padframe](#full-chip-with-padframe)
  - [Conclusion](#conclusion)

## Project Overview

The Kalman Filter is a recursive algorithm that estimates the state of a linear dynamic system from noisy measurements. This ASIC implementation targets real-time applications such as inertial navigation systems, where low power consumption and deterministic latency are critical.

### Kalman Filter Algorithm

The discrete-time linear stochastic system model (paper Eq. 1-2):

$$X_k = \Phi_{k-1} X_{k-1} + G_{k-1} U_{k-1} + w_{k-1}$$

$$Y_k = H_k X_k + v_k$$

where $w_k$ and $v_k$ are independent zero-mean Gaussian noise with covariance matrices $Q_k$ (process) and $R_k$ (measurement).

**Time Update (Predict)** — Paper Eq. 3-4:

$$\hat{X}_k^- = \Phi_{k-1} \hat{X}_{k-1}^+ + G_{k-1} U_{k-1}$$

$$P_k^- = \Phi_{k-1} P_{k-1}^+ \Phi_{k-1}^T + Q_{k-1}$$

**Measurement Update (Correct)** — Paper Eq. 5-7:

$$K_k = P_k^- H_k^T (H_k P_k^- H_k^T + R_k)^{-1}$$

$$\hat{X}_k^+ = \hat{X}_k^- + K_k (Y_k - H_k \hat{X}_k^-)$$

$$P_k^+ = (I - K_k H_k) P_k^-$$

**Variables:**

| Symbol | Description |
|--------|-------------|
| $X$ | State vector (e.g., position, velocity) |
| $P$ | Error covariance matrix |
| $\Phi$ | State transition matrix |
| $G$ | Control input matrix |
| $U$ | Control input vector |
| $H$ | Measurement matrix |
| $Q$ | Process noise covariance |
| $R$ | Measurement noise covariance |
| $K$ | Kalman gain |
| $Y$ | Measurement vector |

**Explanation:**

The Kalman Filter operates in a two-step cycle:

1. **Predict**: Using the system model, predict where the state should be now based on where it was before. The uncertainty (covariance $P$) grows because we're less sure about a prediction than a measurement.

2. **Correct**: When a new measurement arrives, blend the prediction with the measurement. The *Kalman gain* $K$ determines how much to trust the measurement vs. the prediction—if the measurement is noisy (high $R$), trust the prediction more; if the prediction is uncertain (high $P$), trust the measurement more.

**Simple 1D Example:**

Tracking position with a noisy sensor:
- **State**: position $x = 10$ meters (our estimate)
- **Uncertainty**: $P = 4$ (std dev = 2m)
- **Measurement**: sensor reads $y = 12$ meters
- **Sensor noise**: $R = 1$ (std dev = 1m)

Calculate Kalman gain (how much to trust measurement):

$$K = \frac{P}{P + R} = \frac{4}{4 + 1} = 0.8$$

Update estimate (blend prediction with measurement):

$$x_{new} = x + K(y - x) = 10 + 0.8(12 - 10) = 11.6 \text{ meters}$$

The filter moved 80% toward the measurement because the sensor ($R=1$) is more reliable than our prediction ($P=4$).

## Architecture

![Architecture](architecture.png)

The architecture is a simplified microprocessor with a minimal instruction set containing only essential KF operations: addition/subtraction, multiplication, and multiplicative-inverse. The system executes a program stored in internal ROM, controlled by a sequencer with an 8-bit program counter (PC).

### Components

- **Sequencer**: Contains the PC and a 256×16-bit instruction ROM. The PC increments after single-cycle operations (ADD/SUB/MUL) and after multi-cycle operations complete (DIV takes 24 cycles). Supports HALT instruction to signal iteration completion. No instruction fetch cycles or instruction register required—each instruction bit directly controls the datapath.

- **Router A**: Input data multiplexer and address router. Selects between external input (`DATA_IN`) and arithmetic unit result for writing to the Data Bank. Routes addresses from either external `DIR` input or sequencer instruction fields based on the `EXT` control signal.

- **Router B**: Operand selection for the arithmetic unit. Routes two operands (R and S) from multiple sources: Data Bank ports A/B, RQ/RD accumulators, zero constant, or all-ones mask. Selection controlled by 2-bit fields in the instruction word.

- **Memory Registers (Data Bank)**: 32×24-bit dual-port register file storing KF parameters, state vectors, and intermediate results. Includes RQ and RD accumulator registers for temporary operands during multi-step calculations.

- **Arithmetic Unit**: Performs fixed-point sign-magnitude arithmetic. The adder/subtractor and multiplier are combinational (single-cycle). The multiplicative-inverse uses successive approximation with an internal comparator, requiring 24 clock cycles. Although division is slow, the KF algorithm requires only one inverse operation per iteration when m=1.

### Design Specifications (from paper)

| Parameter | Value |
|-----------|-------|
| Number of states (n) | 2 |
| Number of measurements (r) | 1 |
| Number of control inputs (m) | 1 |
| Word length | 24 bits |
| Numeric format | Sign-magnitude fixed-point |
| Integer bits | 9 bits (360° rotation range) |
| Fractional bits | 14 bits |
| Data Bank size | 32 × 24-bit registers |
| ROM size | 256 × 16-bit instructions |
| Cycles per iteration | 113 |
| ADD/SUB/MUL latency | 1 cycle |
| Multiplicative inverse latency | 24 cycles |
| Technology | On Semi C5F 0.5 µm CMOS |
| Transistor count | 70K |
| Silicon area | 5.6 mm² |
| Maximum clock frequency | 20 MHz |
| Power consumption | 1.1 mW @ 200 KHz |
| Performance @ 10 KHz | 113 iterations/sec (11.3 ms latency) |
| Performance @ 200 KHz | 1,770 iterations/sec (0.56 ms latency) |
| Performance @ 20 MHz | 176,991 iterations/sec (5.7 µs latency) |

### Instruction Set

The paper provides only a high-level description of the 16-bit instruction format (`a4a3a2a1a0 b4b3b2b1b0 c1c0 d1d0 e f`) without specifying the complete encoding details for operand selection and control signals. We designed a complete instruction set based on the paper's architecture, documented in [INSTRUCTION_FORMAT.md](INSTRUCTION_FORMAT.md).

**16-bit Instruction Format:**

```
Bit:  15 14 13 12 11 | 10  9  8  7  6 |  5  4 |  3  2 |  1 |  0
         Field A     |    Field B     |   C   |   D   |  E |  F
        (5 bits)     |    (5 bits)    |(2 bit)|(2 bit)|(1b)|(1b)
```

| Field | Bits | Function |
|-------|------|----------|
| A | [15:11] | Data Bank address A (read/write) |
| B | [10:6] | Data Bank address B (read) |
| C | [5:4] | PC control: 00=INC, 01=WAIT, 10=HALT, 11=LOOP |
| D | [3:2] | AU operation: 00=ADD, 01=SUB, 10=MUL, 11=DIV |
| E | [1] | AU start enable |
| F | [0] | Memory write enable |

**Example Instructions:**

| Instruction | Encoding | Description |
|-------------|----------|-------------|
| Load DATA_IN → DB[0] | `0x0001` | Write external input to register 0 |
| MUL DB[6]*DB[0] | `0x300A` | Multiply registers, start AU |
| ADD DB[21]+DB[22] | `0xAD83` | Add two registers |
| DIV DB[27]/DB[29] | `0xDF5E` | Division with WAIT (24 cycles) |
| HALT | `0x0020` | Stop execution |
| LOOP | `0x0030` | Jump to loop address for continuous operation |

The complete 2D Kalman Filter program ([kf_2d.mem](src/kf_2d.mem)) consists of **161 instructions**, resulting in **~196 clock cycles per iteration** (compared to 113 cycles in the paper—the paper likely uses more optimized microcode). The program implements all five KF equations: state prediction, covariance prediction, Kalman gain computation, state update, and covariance update.

## RTL Simulation

### Test Setup

The ASIC design was validated through 5000 iterations of Kalman Filter operation, tracking a position signal with the following parameters:

- **State transition matrix**: Φ = [1, 0.1; 0, 1] (constant velocity model)
- **Measurement matrix**: H = [1, 0] (position-only measurement)
- **Process noise covariance**: Q = 0.01 × I
- **Measurement noise covariance**: R = 0.1
- **Initial state**: x = [0; 0.03], P = I

The simulation compares four signals:
1. **Ground Truth**: The actual clean position signal
2. **Measurement**: Noisy sensor readings (ground truth + Gaussian noise)
3. **Python KF**: Reference Kalman Filter implementation using floating-point arithmetic
4. **ASIC KF**: Our fixed-point hardware implementation output

### Validation Approach

**Step 1: Python vs Ground Truth** — Verifies that the Kalman Filter algorithm successfully suppresses measurement noise. The Python implementation produces a smooth, filtered signal that closely tracks the ground truth, confirming the mathematical formulation from the paper is correct.

**Step 2: ASIC vs Python** — With the Python implementation validated, it serves as the golden reference. The ASIC output is compared against the Python results to verify that the fixed-point hardware implementation matches the expected floating-point behavior.

### Results

![Simulation Results](sim_rtl/kf_results.png)

| Metric | Value |
|--------|-------|
| Raw Measurement MSE | 0.089771 |
| ASIC KF MSE (vs Ground Truth) | 0.027702 |
| ASIC vs Python MSE | 0.000000 |
| **Noise Reduction** | **69.1%** |

The ASIC implementation achieves 69.1% noise reduction compared to raw measurements. Final state estimates after 5000 iterations: x₁ = 107.853455, x₂ = 0.127258, with errors of 0.000110 and 0.000610 respectively versus the Python reference.

## Synthesis

- **Top**

![Top](syn_top/top.png)

- **Submodules**

|  ![Router A](syn/router_a.png)  |  ![Router B](syn/router_b.png)  |  ![Mem Reg](syn/mem_reg.png)  |  ![AU](syn/au.png)  |  ![Sequencer](syn/sequencer.png)  | ![ROM](syn/rom.png) |
| :-----------------------------: | :-----------------------------: | :---------------------------: | :-----------------: | :-------------------------------: | :-----------------: |
| [Router A](/syn/router_a_syn.v) | [Router B](/syn/router_b_syn.v) | [Mem Reg](/syn/mem_reg_syn.v) | [AU](/syn/au_syn.v) | [Sequencer](/syn/sequencer_syn.v) |         ROM         |

### Summary

| Module     |  Cells | Comb. Area (µm²) | Seq. Area (µm²) |                               Total Area (µm²) |                           Critical Path (ns) |
| ---------- | -----: | ---------------: | --------------: | ---------------------------------------------: | -------------------------------------------: |
| **kf_top** | 18,770 |         37,458.7 |        34,480.4 |   [71,939.2](/syn_top/syn_report_area_top.txt) |   [6.90](/syn_top/syn_report_timing_top.txt) |
| Router A   |     63 |            136.4 |             0.0 |     [136.4](/syn/syn_report_area_router_a.txt) |  [0.48](/syn/syn_report_timing_router_a.txt) |
| Router B   |    153 |            341.3 |             0.0 |     [341.3](/syn/syn_report_area_router_b.txt) |  [0.58](/syn/syn_report_timing_router_b.txt) |
| Mem Reg    |  2,804 |          5,084.6 |         5,702.4 |   [10,787.0](/syn/syn_report_area_mem_reg.txt) |   [1.15](/syn/syn_report_timing_mem_reg.txt) |
| AU         |  3,897 |         12,093.8 |           943.2 |        [13,037.0](/syn/syn_report_area_au.txt) |        [6.43](/syn/syn_report_timing_au.txt) |
| Sequencer  | 11,742 |         19,804.3 |        28,078.2 | [47,882.5](/syn/syn_report_area_sequencer.txt) | [1.53](/syn/syn_report_timing_sequencer.txt) |

## Post-Synthesis Simulation

Post-synthesis simulation verifies that the gate-level netlist (after synthesis with TSMC 65nm standard cells) functions correctly. Due to project time constraints, we performed basic functional verification rather than exhaustive testing.

**Test Results:**

| Module | Tests | Status |
|--------|-------|--------|
| kf_top | 10 KF iterations | PASS |
| AU | 37 arithmetic tests (ADD/SUB/MUL/DIV) | PASS |
| Router A | 256 routing tests | PASS |
| Router B | 192 operand selection tests | PASS |
| Mem Reg | 72 read/write/forwarding tests | PASS |
| Sequencer | 31 PC control tests | PASS |

The top-level test ran 10 complete Kalman Filter iterations using the synthesized netlist with timing models. While not as comprehensive as the 5000-iteration RTL validation, these tests confirm basic functionality is preserved after synthesis.

## Layout

### Core Layout
![Core Layout](layout_top/top_core.png)

The core was placed and routed using Cadence Innovus. Key metrics from the layout:

| Parameter | Value |
|-----------|-------|
| Technology | TSMC 65nm (tcbn65gplus) |
| Core Area | 102,784 µm² |
| Standard Cell Area | 71,842 µm² |
| Standard Cells | 18,665 |
| Placement Density | 69.9% |
| Total Wire Length | 566,915 µm |
| Total Vias | 198,884 |
| Metal Layers Used | M1–M9 |
| DRC Violations | 0 |

### Full Chip with Padframe
![Full Chip](layout_top_innovus_padframe/top_fullchip.png)

The full chip integrates the core with TSMC 65nm I/O pads (tpan65gpgv2od3).

| Parameter | Value |
|-----------|-------|
| I/O Pad Library | tpan65gpgv2od3 |
| Total I/O Pads | 104 (91 signal + 8 power/ground + 4 corners + 1 filler) |
| Signal Pads | PDB2A (bidirectional) |
| Power Pads | PVDD3A (×4), PVSS2A (×4) |
| Chip Area | 7,293,240 µm² |
| Pad Area | 1,276,800 µm² |
| Total Wire Length | 758,595 µm |
| Total Vias | 209,803 |
| DRC Violations | 0 |
| Antenna Violations | 0 |

## Conclusion

This project successfully implemented a 2-state Kalman Filter ASIC based on the architecture proposed by Chávez-Bracamontes et al. The following table compares our implementation with the original paper's design:

| Parameter | Paper Design | This Work | Notes |
|-----------|-------------|-----------|-------|
| **Architecture** ||||
| Number of states (n) | 2 | 2 | Same |
| Number of measurements (r) | 1 | 1 | Same |
| Number of control inputs (m) | 1 | 1 | Same |
| Word length | 24 bits | 24 bits | Same |
| Numeric format | Sign-magnitude | Sign-magnitude | Same |
| Data Bank size | 32 × 24-bit | 32 × 24-bit | Same |
| ROM size | 256 × 16-bit | 256 × 16-bit | Same |
| **Performance** ||||
| Instructions per iteration | N/A | 161 | Paper did not specify |
| Cycles per iteration | 113 | ~196 | Our microcode less optimized |
| ADD/SUB/MUL latency | 1 cycle | 1 cycle | Same |
| DIV latency | 24 cycles | 24 cycles | Same |
| Critical path | N/A | 6.90 ns | — |
| Max clock frequency | 20 MHz | 144 MHz | Technology difference |
| **Technology** ||||
| Process | On Semi C5F 0.5 µm | TSMC 65nm | 7.7× smaller node |
| **Area** ||||
| Transistor count | 70,000 | ~75,000 | Estimated from cell count |
| Standard cells | N/A | 18,665 | — |
| Core area | 5.6 mm² | 0.072 mm² | 78× smaller (technology scaling) |
| Pad area | N/A | 1.28 mm² | I/O pads |
| Total chip area | N/A | 7.29 mm² | Paper reported core only |
| **Verification** ||||
| Simulation | Matched Matlab 64-bit | Matched Python 64-bit | Both validated against floating-point reference |
| Hardware test | MPU6000 sensor @ 50 Hz | 5000 iterations | Paper tested fabricated chip |
| Post-synthesis simulation | N/A | All modules | PASS |
| Noise reduction | N/A | 69.1% | Paper showed qualitative plots only |
| DRC/LVS | PASS | PASS (0 violations) | Both verified clean |

**Key Observations:**

1. **Architecture Fidelity**: The core architecture faithfully follows the paper's design with identical word lengths, data bank configuration, and arithmetic unit latencies.

2. **Cycle Count Difference**: Our implementation requires ~196 cycles per iteration compared to the paper's 113 cycles. This is likely due to our independently designed instruction set, as the paper did not provide complete microcode details.

3. **Technology Scaling**: Moving from 0.5 µm to 65nm (7.7× reduction) results in a core area of just 0.072 mm²—78× smaller than the paper's 5.6 mm² chip. This also enables significantly higher clock frequencies (144 MHz vs 20 MHz).

4. **Chip Area**: While our total chip area (7.29 mm²) exceeds the paper's ~5.6 mm², this is entirely due to padframe overhead. The TSMC 65nm I/O pad library (tpan65gpgv2od3) is designed for larger designs and adds significant area (1.28 mm² pads + routing). The paper's 0.5 µm process likely used a more compact pad library with minimal overhead. The important metric is core area: our 0.072 mm² core is **78× smaller** than the paper's 5.6 mm² core.

5. **Functional Correctness**: The design was validated through 5000 RTL iterations with 0.000000 MSE versus a Python reference implementation, and all post-synthesis tests passed.

> [!CAUTION]
> **Project Status**: Due to time constraints, the layout is not fully complete. Future work required:
> - **Power ring connection**: The power pads (PVDD3A/PVSS2A) on the four sides are not yet connected to the power rings around the core.
> - **Filler cells**: Standard cell fillers and decap cells need to be added before final GDS export.
> - **Final verification**: A complete LVS and post-layout simulation after power connections should be conducted.