"""Random microcode programs for differential testing of the pipeline.

The programs exercise what the Kalman program does not: read-after-write
hazards and forwarding at distance 1 and 2 on every operand (A, B, the
addend C, the divisor of RCP), RINV reads and RCP issues while the
reciprocal unit is busy, the constant operand, NOPs, long accumulator chains
and writes to every register.  They only read ACC and RINV after
initializing them, because those registers have no reset in hardware.
"""

from __future__ import annotations

import numpy as np

OPS_MUL = ("mul", "mac", "msb")
OPS_ADDEND = ("mad", "msd")
OPS_PSEUDO = ("add", "sub")


def random_program(rng: np.random.Generator, n: int = 60) -> str:
    reg = lambda: f"db[{int(rng.integers(32))}]"  # noqa: E731
    recent: list[str] = []                         # recently written registers
    lines = [f"lda acc, {reg()}", f"rcp {reg()}"]

    def src() -> str:
        if recent and rng.random() < 0.45:
            return recent[int(rng.integers(len(recent)))]
        return reg()

    def opnd_b() -> str:
        r = rng.random()
        return "rinv" if r < 0.15 else "one" if r < 0.25 else src()

    for _ in range(n):
        kind = rng.choice(["mul", "addend", "pseudo", "lda", "rcp", "nop"],
                          p=[0.45, 0.25, 0.08, 0.08, 0.08, 0.06])
        dst = "acc"
        if kind in ("mul", "addend", "pseudo", "lda") and rng.random() < 0.6:
            dst = reg()
        if kind == "mul":
            op = OPS_MUL[int(rng.integers(len(OPS_MUL)))]
            lines.append(f"{op} {dst}, {src()}, {opnd_b()}")
        elif kind == "addend":
            op = OPS_ADDEND[int(rng.integers(len(OPS_ADDEND)))]
            lines.append(f"{op} {dst}, {src()}, {opnd_b()}, {src()}")
        elif kind == "pseudo":
            op = OPS_PSEUDO[int(rng.integers(len(OPS_PSEUDO)))]
            lines.append(f"{op} {dst}, {src()}, {src()}")
        elif kind == "lda":
            lines.append(f"lda {dst}, {src()}")
        elif kind == "rcp":
            lines.append(f"rcp {src()}")
        else:
            lines.append("nop")
        if dst != "acc":
            recent = (recent + [dst])[-3:]
    lines.append("halt")
    return "\n".join(lines) + "\n"
