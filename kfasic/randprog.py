"""Random microcode programs for differential testing of the pipeline.

The programs exercise what the Kalman program does not: read-after-write
hazards at distance 1 and 2, RINV reads and RCP issues while the reciprocal
unit is busy, NOPs, long accumulator chains and writes to every register.
They only read ACC and RINV after initializing them, because those registers
have no reset in hardware.
"""

from __future__ import annotations

import numpy as np

OPS_TWO = ("mul", "mac", "msb", "add", "sub")


def random_program(rng: np.random.Generator, n: int = 60) -> str:
    reg = lambda: f"db[{int(rng.integers(32))}]"  # noqa: E731
    recent: list[str] = []                         # recently written registers
    lines = [f"lda acc, {reg()}", f"rcp {reg()}"]

    def src() -> str:
        if recent and rng.random() < 0.45:
            return recent[int(rng.integers(len(recent)))]
        return reg()

    for _ in range(n):
        kind = rng.choice(["two", "lda", "rcp", "nop"], p=[0.72, 0.12, 0.08, 0.08])
        dst = "acc"
        if kind in ("two", "lda") and rng.random() < 0.6:
            dst = reg()
        if kind == "two":
            op = OPS_TWO[int(rng.integers(len(OPS_TWO)))]
            b = "rinv" if rng.random() < 0.2 else src()
            lines.append(f"{op} {dst}, {src()}, {b}")
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
