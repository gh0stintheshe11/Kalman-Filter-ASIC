# The paper, the course design and this redo

Three implementations of the same filter — two states, one measurement,
one control input, 24-bit sign-magnitude Q9.14 — and four generations of
this redo.

| | Paper (2016) | Course design | v1 | v2 | v3 | **v4 (current)** |
|---|---|---|---|---|---|---|
| Technology | ON Semi C5F 0.5 µm, 3 metals | TSMC 65 nm | IHP SG13G2 130 nm, 1.2 V core | ← | ← | ← |
| Tools | (not stated) | Synopsys DC, Cadence Innovus | Yosys, OpenROAD, Magic, KLayout, Netgen (LibreLane) | ← | ← | ← |
| Datapath | add/sub, multiply, 24-cycle divide; one operation per cycle | as the paper | as the paper, single cycle | 3-stage multiply-accumulate pipeline | fused multiply-add, forwarding | **two multipliers: dot product + addend per instruction** |
| 1/S | successive approximation, 24 cycles | 24 cycles | 24 cycles | radix-4, 12 cycles | radix-8, 7 cycles, in the background | radix-8, 2 digits/cycle, **4 cycles**, forwarded |
| Instructions per iteration | — | 161 | 161 | 51 | 36 | **22** |
| **Cycles per iteration** | **113** | **~196** | 188 (+3 host) | 53 incl. host write | 39 | **25** (START→READY) |
| Clock, guaranteed | 20 MHz (measured) | 144 MHz claimed (unconstrained path, see audit) | 50 MHz | 66.7 MHz | 121 MHz | **125 MHz** (slow corner 1.08 V/125 °C) |
| **Latency per iteration** | **5.65 µs** | — (no valid timing) | 3.82 µs | 0.80 µs | 0.32 µs | **0.20 µs** |
| Core area | — | 0.103 mm² core (no CTS, not routed to GDS) | — | 0.306 mm² | 0.346 mm² | **0.588 mm²** |
| Die | 5.6 mm² | 7.29 mm² (104 pads, never streamed out) | — | — | macro only | **1.96 mm²** with pad ring, seal ring, fill |
| Host interface, pads | parallel bus | 91 signal pads, all analog pass-through (`PDB2A`) | 58 macro pins | ← | ← | **SPI** + START/READY: 8 signal and 8 supply pads (`sg13g2_io`) |
| Energy per iteration | 0.62 µJ (1.1 mW at 200 kHz, measured, incl. pads/static) | — | 25.3 nJ | 2.90 nJ | 1.97 nJ | **2.07 nJ** |
| Idle power | — | — | 3.13 mW | 0.36 mW | 0.17 mW | **0.21 mW** |
| Functional correctness | — | covariance-update bug, ROM is a 4096-flop register file | bit-exact vs. golden model | ← | ← | ← |

Sources: the paper (Chávez-Bracamontes et al., IEICE ELEX 13(6), 2016,
Table/Sec. 4–5); the course design's own reports in the `legacy-tsmc65`
branch, with the corrections of [legacy-audit.md](legacy-audit.md); v1–v3
are earlier commits of this repository (`5330f70`, `2160277`, `fcb3833`),
measured with the same scripts as v4 (`make power`: SDF-annotated
gate-level activity, typical corner).

## Cycles: 113 → 196 → 39 → 25

The filter needs 35 multiplications, 1 reciprocal and about 35 additions
per iteration (exploiting the symmetry of P and Q).

* **The paper** executes one operation per cycle: a multiplication and the
  addition that uses its result are separate instructions, operands are
  moved through accumulator registers, and the 24-cycle division stalls
  the sequencer.  113 cycles.
* **The course design** followed the paper's architecture with an
  unoptimized program (161 instructions, ~196 cycles), which in addition
  computed two covariance terms from wrong registers.
* **v3** fused multiplication and addition into one instruction
  (ACC ← {0, ACC, C} ± A·B), pipelined it with forwarding and computed 1/S
  in the background: one instruction per multiplication, 36 instructions,
  38 + 1 cycles.  The filter's arithmetic is almost entirely two-term dot
  products, so the multiplier was the only busy resource.
* **v4** makes the instruction a two-term dot product with an addend,
  ACC ← {0, ACC, C} ± A·B ± D·E, on two multipliers: every matrix element
  of Φ P, P⁻, P⁻Hᵀ, S, x⁻ and the innovation is one instruction (22 in
  all).  The dependency chain A = ΦP → P⁻ → P⁻Hᵀ → S → 1/S → K → P⁺, x⁺
  is now what sets the length: S cannot issue before cycle 10, the
  reciprocal takes 4 cycles plus 2 of pipeline, and 7 instructions need
  1/S.  A branch-and-bound search over all legal instruction orders
  (`kfasic`'s cycle-accurate model as the cost function) finds 24 cycles
  as the optimum; HALT completes while the last instruction is still in
  flight, which saves one more.

The program forms exactly the truncated products of the course design and
adds them exactly, so on the course design's test case all 5000 outputs
are reproduced bit for bit — by every version from v1 to v4.

## Clock: 20 MHz → 50 → 66.7 → 121 → 125 MHz

The clock is signed off at the slow corner (1.08 V, 125 °C) with ±5 %
on-chip-variation derate and 0.25 ns clock uncertainty — the industry
convention.  At 8.0 ns the v4 core keeps 0.36 ns of slack there (131 MHz
would be the limit of this placement), the chip 0.23 ns.  The typical
corner (1.2 V, 25 °C) is about 1.6× faster (204 MHz for v4).  At the slow
corner each v4 pipeline stage is close to 8 ns:

| Stage | Logic |
|---|---|
| S1 | instruction register → one-hot register-file read (32:1 AND-OR) → forwarding → Booth recoding |
| EX | 23 × 23 Booth multiplier: partial products, Wallace tree, Kogge-Stone adder |
| WB | three-input sign-magnitude add (carry-save + compound Kogge-Stone), saturation, write-back and forwarding to S1, EX and the reciprocal unit |
| reciprocal | two radix-8 restoring steps per cycle on precomputed multiples |

Getting there needed:

* datapath arithmetic written as explicit structures (Booth recoding
  before the operand registers, Wallace tree, Kogge-Stone adders): Yosys'
  own adders are Brent-Kung or ripple and its multiplier took 6.7 ns
  instead of 5.5 ns in isolation;
* realistic wire RC during placement-stage timing repair (LibreLane's
  default averages all metal layers, including the thick top metals, and
  made the repair work against a 1.4 ns too optimistic estimate),
  and timing-driven placement.

The remaining limit is the write-back stage: the 35-bit sign-magnitude
sum and its fan-out to forwarding, register file and reciprocal unit.
Deeper pipelining would raise the clock but add a cycle to every
dependency in the chain above, which is what sets the iteration length;
the latency would not improve.

## Area and energy

v4 is 1.7× the area of v3 (a second multiplier, two more register-file
read ports, a two-step reciprocal), and executes 22 instead of 36
instructions: fewer instruction fetches, register reads, operand-register
loads and clock pulses per iteration, and the same 35 multiplications.
The energy per iteration stays about the same (2.07 nJ against
1.97 nJ, typical corner, glitches included): the instructions saved, the
exact three-term adder (23 % of the energy, against 9 % for v3's two-input
adder) and the faster reciprocal unit roughly cancel.  With 0.20 instead
of 0.32 µs per iteration, energy × latency is 35 % lower.  Idle power
grows from 0.17 to 0.21 mW, mostly the clock network that keeps running
while idle (148 µW) and the larger core's leakage (20 µW instead of 11).

The paper's 1.1 mW at 200 kHz (0.62 µJ per iteration) is a measured
whole-chip figure at 5 V in 0.5 µm, including pads and static current; it
is quoted for completeness, not as a like-for-like comparison.

## Verification and signoff

| | Paper | Course design | This redo (v4) |
|---|---|---|---|
| Golden model | — | Python float reference | bit-exact fixed-point model and cycle-accurate ISS (`kfasic`) |
| RTL tests | — | a 5000-iteration run (NC-Verilog only: it races on other simulators) | directed and random-program differential tests, 5000-iteration regression, chip tests through the pads; Icarus and Verilator |
| Gate level | silicon | "PASS" printed unconditionally | the same black-box tests on the routed netlist, with SDF delays at typical and fast corners; chip through its pads |
| Timing | — | no clock defined | setup, hold, slew, capacitance at three corners |
| Physical | fabricated | not routed to GDS, no CTS | complete die with pad ring, seal ring and fill; DRC (Magic, KLayout, IHP's full deck incl. density and antenna), LVS (Netgen for the chip, IHP's KLayout deck at transistor level for the core), a short and open check of the pad ring on the full layout, GDS XOR, static IR drop with the supply at the pads |
| Equivalence | — | — | routed netlists (core and chip) sequentially equivalent to the RTL: Yosys + ABC `dprove`, checked against injected faults |
