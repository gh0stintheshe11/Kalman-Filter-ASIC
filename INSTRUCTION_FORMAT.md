# Instruction Format for Kalman Filter ASIC

## Overview

Based on the paper (Section 4, page 5):
> "The KF matrix operations are split into their simplest scalar arithmetic operations and are codified in a 16-bit word/instruction formatted as **a4 a3 a2 a1 a0 b4 b3 b2 b1 b0 c1 c0 d1 d0 e f**"

## 16-bit Instruction Layout

```
Bit:  15 14 13 12 11 | 10  9  8  7  6 |  5  4 |  3  2 |  1 |  0
      a4 a3 a2 a1 a0 | b4 b3 b2 b1 b0 | c1 c0 | d1 d0 |  e |  f
      ───────────────┼────────────────┼───────┼───────┼────┼────
         Field A     |    Field B     |   C   |   D   |  E |  F
         (5 bits)    |    (5 bits)    |(2 bit)|(2 bit)|(1b)|(1b)
```

## Field Definitions

### Field A [15:11] - Address A / Write Address (5 bits)
- Primary address for Data Bank operations
- Used as write address when f=1
- Used as read address for port A
- **5 bits = addresses 0-31** (32 registers in Data Bank)

### Field B [10:6] - Address B / Read Address (5 bits)
- Secondary address for Data Bank port B read
- **5 bits = addresses 0-31** (32 registers in Data Bank)

### Field C [5:4] - Sequencer/PC Control (2 bits)
Per the paper's description of the sequencer:
- `00`: **INCREMENT** - PC increments by 1 (for 1-cycle operations: ADD/SUB/MUL)
- `01`: **WAIT** - PC holds until `continue` signal (for multi-cycle operations: inverse, 24 cycles)
- `10`: **HALT** - Stop execution, set READY=1, PC freezes
- `11`: Reserved (treat as INCREMENT)

### Field D [3:2] - AU Operation Select (2 bits)
- `00`: **ADD** - Addition (R + S), 1 cycle
- `01`: **SUB** - Subtraction (R - S), 1 cycle
- `10`: **MUL** - Multiplication (R × S), 1 cycle
- `11`: **INV** - Multiplicative Inverse (1/S) then multiply, 24 cycles

### Field E [1] - AU Start (1 bit)
- `0`: No AU operation
- `1`: Start AU operation with current operands

### Field F [0] - Write Enable (1 bit)
- `0`: No memory write
- `1`: Write data to Data Bank at address specified by Field A

## Data Flow in the Architecture

Based on Paper's Figure 3:

```
                    ┌─────────────────────────────────────────────┐
   DATA_IN ────────►│ Router A                                    │
                    │   - Selects: DATA_IN / AU_RESULT / constant │
   RESULT ─────────►│   - Routes to Data Bank write port          │
   (from AU)        └──────────────┬──────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────────────────┐
                    │ Data Bank (NR × 24-bit registers)            │
                    │   - Write: addr from Field A, data from Router A │
                    │   - Read A: addr from Field A                │
                    │   - Read B: addr from Field B                │
                    │                                              │
                    │ RQ, RD: Accumulator registers                │
                    └──────────────┬───────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────────────────┐
                    │ Router B                                     │
                    │   - R operand: from port A, RQ, 0, or 1s     │
                    │   - S operand: from port B, RD, 0, or 1s     │
                    └──────────────┬───────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────────────────┐
                    │ Arithmetic Unit                              │
                    │   - Adder/Subtractor (1 cycle)               │
                    │   - Multiplier (1 cycle)                     │
                    │   - Multiplicative Inverse (24 cycles)       │
                    │   - Result → SR register → Router A          │
                    └──────────────────────────────────────────────┘
```

## Operand Selection (Router B)

The paper shows Router B selects operands from multiple sources. The selection bits
are likely encoded within Fields A and B or require additional control bits.

Based on paper's Figure 3 and architecture:
- **R input**: Data Bank port A output, RQ register, zero, or constant
- **S input**: Data Bank port B output, RD register, zero, or constant

**Note**: The paper doesn't explicitly show how operand selection (sel_R, sel_S) is encoded.
Options:
1. High bits of Field A/B could encode operand source selection
2. Additional control bits in the instruction
3. Implicit based on operation type

## Instruction Timing

| Operation | Field D | Field C | Cycles | Description |
|-----------|---------|---------|--------|-------------|
| ADD       | 00      | 00 (INC)| 1      | R + S, PC increments immediately |
| SUB       | 01      | 00 (INC)| 1      | R - S, PC increments immediately |
| MUL       | 10      | 00 (INC)| 1      | R × S, PC increments immediately |
| INV/DIV   | 11      | 01 (WAIT)| 24    | 1/S then ×R, PC waits for continue |
| HALT      | xx      | 10      | -      | Stop execution |

## Example Instructions

### Load DATA_IN to DB[0]
```
Field A = 00000 (addr=0)
Field B = 00000 (unused)
Field C = 00    (INC)
Field D = 00    (ADD, but not started)
Field E = 0     (no AU start)
Field F = 1     (write enable)

Binary: 00000_00000_00_00_0_1 = 0x0001
```

### ADD DB[0] + DB[1], store to DB[2]
```
; First: Read DB[0] and DB[1], start ADD
Field A = 00000 (addr_a=0 for R operand)
Field B = 00001 (addr_b=1 for S operand)
Field C = 00    (INC)
Field D = 00    (ADD)
Field E = 1     (start AU)
Field F = 0     (no write yet)

Binary: 00000_00001_00_00_1_0 = 0x0042

; Then: Write result to DB[2]
Field A = 00010 (addr=2)
Field B = 00000 (unused)
Field C = 00    (INC)
Field D = 00    (unused)
Field E = 0     (no AU start)
Field F = 1     (write enable)

Binary: 00010_00000_00_00_0_1 = 0x1001
```

### HALT
```
Field A = 00000 (unused)
Field B = 00000 (unused)
Field C = 10    (HALT)
Field D = 00    (unused)
Field E = 0     (unused)
Field F = 0     (unused)

Binary: 00000_00000_10_00_0_0 = 0x0020
```

## Design Parameters (from paper)

- **Word width (W)**: 24 bits (1 sign + 9 integer + 14 fractional)
- **Data Bank size (NR)**: 32 registers for 2-state KF (Equation 10: NR = 5n² + r² + 2nr + nm + n + r + m + 1)
- **ROM size**: 256 × 16-bit (Equation 9)
- **Address width**: 5 bits (log2(32) = 5)

## Notes

1. The paper's exact encoding for operand selection (Router B control) is not fully specified
2. The paper mentions RQ and RD registers are "accumulators for temporary operands"
3. For a 2-state, 1-measurement KF: 113 clock cycles per iteration (Table III)
4. The architecture has no branch instructions - purely sequential execution