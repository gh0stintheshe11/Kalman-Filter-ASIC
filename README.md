# Kalman Filter ASIC

A two-state Kalman filter processor following the architecture of
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
| Microcode | `kfasic.asm` (this repo) | 140 instructions, 188 program cycles per filter iteration |
| Lint | Verilator `-Wall`, Yosys `check -assert` | clean, no combinational loops |
| RTL verification | cocotb 2.1 on Icarus Verilog **and** Verilator | bit- and cycle-exact against the golden model; bit-exact against the original design's 5000-iteration run |
| RTL → GDS | LibreLane 3.0.17 (Yosys, OpenROAD) | 530 × 548 µm macro, 50 MHz |
| Signoff | OpenSTA (3 corners), KLayout + Magic DRC, Netgen LVS | timing met at all corners; DRC, LVS, antenna clean |
| Gate-level simulation | cocotb + Icarus on the routed netlist | the same black-box tests pass |

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

A minimal microcoded processor, as in the paper: a sequencer reads a 256×16
ROM (no fetch cycle, no instruction register), a 32×24-bit register file holds
the filter state, parameters and temporaries, and an arithmetic unit performs
add/subtract and multiply in one cycle and division in 25 cycles by
successive approximation of 1/S on the same multiplier.  Numbers are 24-bit
sign-magnitude Q9.14.

The host writes parameters and each new measurement while `ready` is high,
pulses `start`, and reads the updated state back when `ready` returns.
Details, the instruction set and the assembly syntax are in
[docs/architecture.md](docs/architecture.md).

## Verification

The normative model is Python: `kfasic/fixed.py` defines the arithmetic bit
for bit and `kfasic/iss.py` executes the microcode cycle for cycle.

* `tests/` (pure Python, < 1 s): arithmetic properties, the reciprocal unit
  against a bit-serial model, assembler encodings and errors, and the
  microcode run in exact arithmetic against the textbook equations on random
  systems.  The golden model also reproduces all 5000 outputs of the original
  design bit for bit (`tests/data/`).
* `tb/` (cocotb): the arithmetic unit against the model (≈10,000 vectors),
  and the whole chip as a black box through its pins: register readback,
  the tracking scenario, random systems (also compared with a
  floating-point filter), host traffic while busy, reset in mid-run.  Every
  iteration is checked bit-exact and cycle-exact.  Inputs change on the
  falling clock edge, and the tests pass on both Icarus and Verilator, so
  they do not depend on simulator event ordering.
* The same black-box tests run on the final gate-level netlist (`make gls`).

## Physical implementation (IHP SG13G2)

Hardened as a standalone macro (no pad ring) with LibreLane 3.0.17: Yosys
0.62, OpenROAD/OpenSTA (2026-02), Magic 8.3.623, KLayout 0.30.7 and Netgen
1.5.316, on the IHP SG13G2 PDK as pinned by LibreLane.  Configuration and
constraints: [`flow/ihp-sg13g2/`](flow/ihp-sg13g2/).

<img src="docs/img/layout.png" width="480" alt="Final layout">

| Metric | Value |
|---|---|
| Clock | 20 ns (50 MHz) |
| Die | 529.7 × 548.4 µm = 0.290 mm², 54.6 % core utilization |
| Cells | 23,845 including fill, decap and tap cells; 146,317 µm² |
| Setup / hold WNS, slow 1.08 V / 125 °C | +1.45 / +0.62 ns |
| Setup / hold WNS, typical 1.20 V / 25 °C | +8.24 / +0.29 ns |
| Setup / hold WNS, fast 1.32 V / −40 °C | +12.25 / +0.09 ns |
| Max slew / max capacitance violations | 0 / 0 |
| Routing DRC, Magic DRC, KLayout DRC | 0, 0, 0 |
| LVS (Netgen) | clean |
| Antenna violations | 0 |
| Magic vs KLayout GDS (XOR) | identical |
| Worst IR drop | 1.3 mV |
| Power, typical corner, 50 MHz | 3.5 mW |
| Throughput | 189 cycles per iteration → 265,000 iterations/s |

Notes:

* Timing includes ±5 % derate and 0.25 ns clock uncertainty and is signed
  off at all three corners (the IHP default checks setup only at typical).
* The flow also reports 76 nets above the library's max-fanout guideline
  of 8: 75 are clock-tree leaf buffers, whose loading is chosen by CTS and
  covered by the slew, capacitance and skew checks above, and one data net
  has a fanout of 11.
* `python flow/summary.py flow/ihp-sg13g2/runs/main` regenerates this table
  from a run.

For comparison, the paper's chip (0.5 µm, 3 metal layers) ran at up to
20 MHz in 5.6 mm² and needed 113 cycles per iteration with its own
(unpublished) microcode.

## Quick start

Tools: Python ≥ 3.10 with a shared `libpython` (uv-managed Pythons have one),
Icarus Verilog and/or Verilator, Yosys (e.g. [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)),
and for the physical flow [LibreLane](https://github.com/librelane/librelane)
(its AppImage needs no root; extract it with `--appimage-extract` if FUSE is
unavailable).  LibreLane downloads the PDK by itself.

```sh
make venv                 # .venv with kfasic, cocotb, numpy (uses uv)
make lint
make test                 # model + RTL tests on Icarus; SIM=verilator also works
make test-long            # 5000-iteration RTL regression
make flow LIBRELANE="$HOME/tools/librelane/squashfs-root/AppRun -- librelane"
make gls                  # gate-level simulation of the final netlist
python flow/summary.py flow/ihp-sg13g2/runs/main
```

Changing the program: edit `fw/kf_2d.s`, then `make rom` regenerates
`rtl/kf_rom.v` (a test fails if the committed ROM is stale).

## Repository layout

```text
rtl/        Verilog: kf_top, kf_sequencer, kf_rom (generated), kf_regfile, kf_au
fw/         microcode (assembly source)
kfasic/     Python: fixed-point model, assembler, ISS, reference filter, plots
tests/      fast model tests (pytest)
tb/         cocotb testbenches and the pytest runner
flow/       LibreLane configuration (flow/ihp-sg13g2) and reporting scripts
docs/       architecture, audit of the course version, images
```
