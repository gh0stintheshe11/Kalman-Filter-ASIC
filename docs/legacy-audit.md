# Audit of the original course version

The original TSMC 65 nm / Cadence implementation is kept unchanged in the
`legacy-tsmc65` branch.  It was audited before this redo by re-running it with
open-source tools (Icarus Verilog, Verilator, Yosys) and by reading its logs
and reports.  These are the findings, with what the redo does about each.

## Functional

| # | Finding | Evidence | In this version |
|---|---|---|---|
| 1 | **Microcode bug in the covariance update**: two instructions read the wrong register, so P⁺₂₁ subtracted `q21` instead of K₂h₂p₂₁ and P⁺₂₂ subtracted `phi21` instead of K₂h₂p₂₂. | `src/kf_2d.mem` PC 154 (`EB06`) and 158 (`EA06`): the comments name DB[22]/DB[20], the encodings address DB[12]/DB[8]. In exact arithmetic the state estimate drifts by up to 0.2 on a general system. The 5000-iteration test passed only because its system has h₂ = q₂₁ = φ₂₁ = 0, so wrong and right operands were both zero. | Fixed in `fw/kf_2d.s`. `tests/test_model.py::test_microcode_is_the_kalman_filter` runs the program in exact arithmetic against the textbook equations on random systems, and `tb/test_kf_top.py::random_systems` checks the RTL against the float filter; both fail on the old program. |
| 2 | **Combinational loop**: AU result → Router A → data-bank write-through to port B → Router B → AU. | Innovus `TA-146` / `CTE_loops.rpt`, Verilator `UNOPTFLAT`, Yosys "found logic loop". Not triggered by the existing microcode, but an in-place `x = x + x` would oscillate. | No forwarding path; Verilator and Yosys `check -assert` run clean in `make lint`. |
| 3 | **Testbench races**: inputs driven with blocking assignments at `posedge clk`. | Under Icarus all 14 DIV tests return X and every top-level test fails (START is never sampled); they pass only with NC-Verilog's event ordering. | cocotb tests drive on the falling edge; the same tests pass on Icarus and Verilator. |
| 4 | **Post-synthesis top-level test checks nothing**: prints `POST-SYN TEST PASSED` unconditionally and waits a fixed 200 cycles per 195-cycle iteration, so measurements land on the wrong instruction. | `src/kf_top_tb.v` lines 457–473. | The chip is tested as a black box through its pins (writes, readback, cycle counts), so the same test runs on RTL and on the final netlist. |
| 5 | **Host interface not usable on silicon**: parameters had to be streamed on consecutive cycles, the program never returned to READY (LOOP forever), the measurement had to arrive exactly when PC = 20 (the testbench peeked at the internal PC), and DATA_OUT showed whatever the AU computed that cycle. | `src/kf_2d.mem`, `src/kf_top_tb.v`. | Paper protocol: write registers while READY, START, program ends in HALT, read any register back. |
| 6 | 1-D program is not a complete Kalman step (no Φ, no P update). | `src/kf_1d.mem`. | Dropped; the 2-state program is general. |

## Implementation

| # | Finding | Evidence | In this version |
|---|---|---|---|
| 7 | **No timing constraints**: the SDC holds only `set_units`; no clock was defined. | `syn_top/kf_top_syn.sdc`; DC report says "Path is unconstrained". The quoted 6.90 ns / 144 MHz is an unconstrained path through the loop of #2. | Real clock, I/O and load constraints; setup, hold, slew and capacitance signed off at three corners. |
| 8 | **No clock tree, no timing optimization, no GDS**: no CTS, `optDesign` or `streamOut` in any Innovus session; ~5000 clock sinks were routed as a plain net. | `layout_top*/innovus.cmd*`. | Full flow: CTS, post-CTS and post-route repair, fill, GDS from two tools with XOR check. |
| 9 | **DRC/LVS claims**: only Innovus `verifyGeometry` was run; LVS never ran. | `layout_top/kf_top.geom.rpt`. | Magic and KLayout DRC in the flow, and IHP's full KLayout deck (including density and antenna) on the whole chip; Netgen LVS, transistor-level LVS with IHP's KLayout deck, and a short and open check of the pad ring on the full layout. The routed netlists are also proven equivalent to the RTL. |
| 10 | **Analog pads for digital I/O**: all 91 signal pads were `PDB2A` from `tpan65gpgv2od3` (analog pass-through, one `AIO` pin), wired straight to core pins. | `layout_top_innovus_padframe/kf_top_padframe.v`. | Digital I/O cells (`sg13g2_IOPadIn`, `sg13g2_IOPadOut16mA`, `sg13g2_IOPadTriOut16mA`) and an SPI host interface: 8 signal and 8 supply pads, with pad ring, bond pads, seal ring and fill in the GDS ([chip.md](chip.md)). |
| 11 | **"ROM" was 4096 flip-flops**: a debug write port made it a register file (81 % of all flops, ~2/3 of the area). | DC area reports; Yosys statistics. | Hard-wired ROM generated from the assembler. |
| 12 | Three 23×23 multipliers in the AU (the paper reuses one). | `src/au.v`. | Two Booth multipliers, both busy in every instruction (each instruction is a two-term dot product). |
| 13 | Mixed reset styles (`initial` + synchronous in the sequencer, asynchronous elsewhere). | Verilator `SYNCASYNCNET`. | Asynchronous reset with a synchronizer everywhere. |

## Repository

About 100 MB of generated tool output (databases, logs, three copies of the
same netlist) and absolute `/CMC/...` paths made the flow non-reproducible
outside the university environment.

## Size comparison

| | Course version | This version |
|---|---|---|
| Flip-flops (Yosys generic synthesis of the core) | 5,054, all clocked every cycle | 1,240, behind 43 clock gates |
| Generic cells (Yosys) | 25,096 | 21,130 (two multipliers) |
| Signal pads | 91 | 8 (SPI, START, READY, clock, reset) |
| Cycles per iteration | 195 | 24 (+1 input register) |
