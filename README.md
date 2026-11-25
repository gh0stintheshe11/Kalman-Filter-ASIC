# Kalman Filter ASIC

A two-state Kalman filter processor based on the architecture of
Chávez-Bracamontes et al., *"VLSI architecture of a Kalman filter optimized
for real-time applications"*, IEICE Electronics Express 13(6), 2016
([doi:10.1587/elex.13.20160043](https://doi.org/10.1587/elex.13.20160043)),
designed, verified and implemented down to GDS with open-source tools only,
on the **IHP SG13G2** 130 nm open PDK.

> [!NOTE]
> This is a from-scratch redo of a course project.  The original TSMC 65 nm /
> Cadence version is preserved unchanged in the `legacy-tsmc65` branch;
> [docs/legacy-audit.md](docs/legacy-audit.md) lists what was wrong with it
> and how this version addresses each point.

## Status

| Stage | Tools | Result |
|---|---|---|
| Microcode | `kfasic.asm` (this repo) | 36 instructions, **38 cycles** per filter iteration, no stall (original: 188) |
| Lint | Verilator `-Wall`, Yosys `check -assert` | clean, no combinational loops |
| RTL verification | cocotb 2.1 on Icarus Verilog **and** Verilator | bit- and cycle-exact against the golden model; random-program differential tests of the pipeline; bit-exact against the original design's 5000-iteration run |
| RTL → GDS | LibreLane 3.0.17 (Yosys, OpenROAD) | 0.35 mm² macro, **121 MHz** |
| Signoff | OpenSTA (3 corners), KLayout + Magic DRC, Netgen LVS | timing, slew, capacitance and fanout met at all corners; DRC, LVS, antenna clean |
| Gate-level simulation | cocotb + Icarus on the routed netlist | the same black-box tests pass, also with typical- and fast-corner delays at 121 MHz |
| Power | OpenSTA with SDF-annotated simulated activity | **1.97 nJ per iteration** (glitches included), 0.17 mW idle |

## The filter

Discrete-time model x_k = Φx_{k-1} + Gu_{k-1} + w, y_k = Hx_k + v with two
states, one measurement and one control input.  One iteration is

```text
x- = Φ x + G u              P- = Φ P Φᵀ + Q
K  = P- Hᵀ (H P- Hᵀ + R)⁻¹
x+ = x- + K (y − H x-)      P+ = (I − K H) P-
```

All of Φ, G, u, H, Q and R are run-time parameters in the data bank, so any
2-state/1-measurement system can be filtered without changing the hardware.

![Tracking result](docs/img/tracking.png)

*Constant-velocity tracking (the original project's test case): the
hardware's 24-bit fixed-point result stays within a few LSB (≤ 3·10⁻⁴) of a
double-precision filter.  Produced by `python -m kfasic.plot`, using the
golden model that the RTL matches bit for bit.*

## Architecture

A microcoded multiply-accumulate machine derived from the paper's design.
A sequencer reads a 256 × 26 ROM into an instruction register (prefetched,
so no cycle is lost). A 32 × 24-bit register file holds the state, the
parameters and temporaries. Every instruction is a fused multiply-add,
ACC ← {0, ACC, C} ± A·B with B a register, 1/S or 1.0, executed by a
three-stage pipeline:

1. read operands A and B;
2. multiply, and read the addend C;
3. accumulate and write back.

Results are forwarded from the last stage, so an instruction only waits if
it needs the result of the one just before it.  A separate radix-8 unit
computes 1/S in 7 cycles while the pipeline keeps working.  Numbers are
24-bit sign-magnitude Q9.14, as in the paper.

The microcode uses the symmetry of the covariance matrices and evaluates
P⁺ = P⁻ − K(P⁻Hᵀ)ᵀ; in exact arithmetic this is identical to the textbook
equations.  Fusing the additions of Q, R, y, x⁻ and P⁻ into the multiply-adds
and ordering the dot products so that nothing waits gives 36 instructions
and 38 cycles per iteration, instead of 188.

For low power, every register group is clock-gated (one gate per
register-file entry, gates for the operand, result, accumulator, reciprocal
and control registers) behind a core clock gate that stops the clock while
idle.  The register-file read ports decode their address one-hot, so a
new address toggles two select lines instead of select lines that reach
every bit, and the instruction register keeps the ROM's glitches out of
them.  The assembler encodes unused instruction fields
and the order of commutative operands so that as few bits as possible change
from one instruction to the next.

The host writes parameters and each new measurement while `ready` is high,
pulses `start`, and reads the updated state back when `ready` returns.
Details, the instruction set and the assembly syntax are in
[docs/architecture.md](docs/architecture.md).

## Verification

The normative model is Python: `kfasic/fixed.py` defines the arithmetic bit
for bit and `kfasic/iss.py` models the pipeline cycle for cycle.

* `tests/` (pure Python, ~1 s):
  * arithmetic properties, and the reciprocal against a bit-serial radix-8 model;
  * assembler encodings and errors;
  * hand-derived pipeline timings;
  * the microcode run in exact arithmetic against the textbook equations on random systems;
  * all 5000 outputs of the original design reproduced bit for bit (`tests/data/`).
* `tb/` (cocotb):
  * the multiplier, adder and reciprocal units against the model;
  * the whole chip as a black box through its pins: register readback,
    tracking, random systems (also compared with a floating-point filter),
    host traffic while busy, reset in mid-run;
  * **random programs**: random instruction streams with dense hazards and
    reciprocal-unit conflicts, run on the RTL and on the model, with every
    register and the cycle count compared.

  Inputs change on the falling clock edge, and the tests pass on both Icarus
  and Verilator, so they do not depend on simulator event ordering.
* The same black-box tests run on the final gate-level netlist (`make gls`),
  and on the netlist back-annotated with the typical- and the fast-corner
  delays at the design's clock period (`make gls SDF=1`, `SDF_CORNER=...`),
  which exercises the clock gating, resets and hold paths with real timing.
* The cell-level register-file read port used in the IHP flow is proven
  equal to its RTL with a SAT miter (`make equiv`).

## Physical implementation (IHP SG13G2)

Hardened as a standalone macro (no pad ring) with LibreLane 3.0.17: Yosys
0.62, OpenROAD/OpenSTA (2026-02), Magic 8.3.623, KLayout 0.30.7 and Netgen
1.5.316, on the IHP SG13G2 PDK as pinned by LibreLane.  The clock gates map to
the PDK's integrated clock-gating cell `sg13g2_lgcp_1`.  Configuration and
constraints: [`flow/ihp-sg13g2/`](flow/ihp-sg13g2/).  Synthesis uses ABC's
`AREA 3` script (delay-driven mapping); the clock trees are built from 4x
and 2x buffers instead of the 16x buffers of the IHP default, which cuts
clock power several-fold.

| Metric | Value |
|---|---|
| Clock | 8.25 ns (121 MHz) |
| Die | 0.346 mm² (579 × 598 µm), 50.0 % core utilization |
| Cells | 30,792 including fill, decap and tap cells; 160,705 µm² |
| Setup / hold WNS, slow 1.08 V / 125 °C | +0.11 / +0.11 ns |
| Setup / hold WNS, typical 1.20 V / 25 °C | +2.51 / +0.26 ns |
| Setup / hold WNS, fast 1.32 V / −40 °C | +3.84 / +0.09 ns |
| Max slew / max capacitance violations | 0 / 0 |
| Nets above the library's fanout guideline (8) | 0 |
| Routing DRC, Magic DRC, KLayout DRC | 0, 0, 0 |
| LVS (Netgen) | clean |
| Antenna violations | 0 |
| Magic vs KLayout GDS (XOR) | identical |
| Worst IR drop | 2.5 mV |
| Throughput | 39 cycles per iteration (START to READY) → 3.1 M iterations/s |

Timing includes ±5 % derate and 0.25 ns clock uncertainty and is signed off
at all three corners (the IHP default checks setup only at typical).
Besides the asynchronous reset input, the constraints
([`kf_top.sdc`](flow/ihp-sg13g2/kf_top.sdc)) contain one exception: hold
checks from the register file to the operand registers are waived, because
forwarding guarantees that an operand register never captures a register
on the edge that writes it; without the waiver, hold repair put delay cells
into the read ports on the critical path.  Gate-level simulation with
fast-corner delays confirms it.  At 8 ns only the multiplier path
(operand register → Booth/Wallace multiplier → result register) still
fails; the other pipeline stages have been brought to the same length.
`make summary` regenerates this table from a run.

![Layout](docs/img/layout.png)

*The routed macro, rendered from the final GDS with KLayout
(`flow/render_gds.py`).*

For comparison, the paper's chip (0.5 µm, 3 metal layers) ran at up to
20 MHz in 5.6 mm² and needed 113 cycles per iteration.

### Tapeout readiness

The macro passes every check that applies to a hardened block:

* static timing at all three corners (setup, hold, slew, capacitance), with
  on-chip-variation derate and clock uncertainty;
* DRC with IHP's KLayout deck (FEOL and BEOL rules; recommended rules off,
  as in LibreLane's IHP flow) and with Magic, LVS with Netgen, antenna
  rules, Magic-vs-KLayout GDS XOR, IR drop;
* dynamic checks: the routed netlist, back-annotated with the typical- and
  the fast-corner delays, passes the black-box tests at the design clock
  (`make gls SDF=1`), and the hand-instantiated read-port cells are
  formally equivalent to their RTL (`make equiv`).

For a shuttle submission it still has to be integrated into a chip: pad
ring (IHP's `sg13g2_io` cells), seal ring, and metal/active fill checked
against the density rules (IHP's `density.drc`), all of which apply to the
whole die.  With 58 signal pins, a pad-limited die would also call for a
narrower host interface (for example byte-wide or serial).

## Power

`flow/power.py` replays a workload on the routed netlist, back-annotated
with the typical-corner SDF delays so that the recorded switching activity
includes glitches, and has OpenSTA compute power with the extracted
parasitics at the typical corner.  (Zero-delay activity, `--zero-delay`,
misses them and underestimates the combinational power by 35–65 % for these
designs.)  All versions below are measured this way: the first open-source
version (single-cycle datapath, 188-cycle microcode, no clock gating; commit
`5330f70`), the first pipelined version (commit `2160277`) and the current
one.

| | first version | pipelined | current |
|---|---|---|---|
| Clock | 50 MHz | 66.7 MHz | 121 MHz |
| Cycles per iteration (incl. host write of y) | 191 | 53 | 41 |
| Power while filtering | 6.61 mW | 3.65 mW | 5.82 mW |
| **Energy per iteration** | **25.3 nJ** | **2.90 nJ** | **1.97 nJ** (12.8× less than the first) |
| Idle power (clock running) | 3.13 mW | 0.36 mW | 0.17 mW |
| Leakage | 8.6 µW | 9.4 µW | 11.0 µW |

Where the 1.97 nJ of an iteration go (`make power`, which attributes each
cell to a block by the registers in its fan-in cone):

| Block | pJ | Share |
|---|---|---|
| Multiplier | 659 | 33 % |
| Flip-flops | 454 | 23 % |
| Clock trees and clock gates | 254 | 13 % |
| ROM, decode, register reads | 174 | 9 % |
| Accumulate (WB adder) | 168 | 9 % |
| Write-back, forwarding and data-in multiplexers | 145 | 7 % |
| Reciprocal unit | 73 | 4 % |
| Hold-fix delay cells, control, fill, I/O | 42 | 2 % |

Most of the multiplier's share is glitching in the Wallace tree.  Before
the one-hot read ports and the instruction register (the RTL of commit
`f94aa72`, hardened at 100 MHz), the ROM and the register reads took 40 %.

## Quick start

Tools: Python ≥ 3.10 with a shared `libpython` (uv-managed Pythons have one),
Icarus Verilog and/or Verilator, Yosys (e.g. [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)),
and for the physical flow [LibreLane](https://github.com/librelane/librelane)
(its AppImage needs no root; extract it with `--appimage-extract` if FUSE is
unavailable).  LibreLane downloads the PDK by itself.

```sh
make venv                 # .venv with kfasic, cocotb, numpy (uses uv)
make lint
make test                 # model, unit, chip and random-program tests; SIM=verilator also works
make test-long            # 5000-iteration RTL regression
LL=$HOME/tools/librelane/squashfs-root/AppRun
make flow LIBRELANE="$LL -- librelane"
make summary              # signoff table
make gls                  # gate-level simulation of the final netlist (SDF=1: with delays)
make equiv                # formal check of the cell-level read port
make power STA="$LL -- sta"
```

Changing the program: edit `fw/kf_2d.s`, then `make rom` regenerates
`rtl/kf_rom.v` (a test fails if the committed ROM is stale).

## Repository layout

```text
rtl/        Verilog: kf_top, kf_rom (generated), kf_regfile, kf_rdport, kf_mul, kf_addsub, kf_rcp, kf_clkgate
fw/         microcode (assembly source)
kfasic/     Python: fixed-point model, assembler, ISS, random programs, reference filter, plots
tests/      fast model tests (pytest)
tb/         cocotb testbenches, the pytest runner, the power-analysis testbench
flow/       LibreLane configuration (flow/ihp-sg13g2), signoff summary, power analysis
docs/       architecture, audit of the course version, images
```
