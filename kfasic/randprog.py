"""Random microcode programs for differential testing of the pipeline.

The programs exercise what the Kalman program does not: read-after-write
hazards and forwarding at distance 1 and 2 on every operand (A, B, D, E and
the base register), ACC as the base after a stall or a NOP, RINV reads while
the reciprocal unit is busy and in its last cycle, starts of the unit while
it is busy, the constant operand, subtraction of either product, NOPs and
writes to every register.  They only read ACC and RINV after initializing
them, because those registers have no reset in hardware.
"""

from __future__ import annotations

import numpy as np


def random_program(rng: np.random.Generator, n: int = 60) -> str:
    reg = lambda: f"db[{int(rng.integers(32))}]"  # noqa: E731
    recent: list[str] = []                         # recently written registers
    lines = [f"acc = {reg()}*one", f"rcp {reg()}"]

    def src() -> str:
        if recent and rng.random() < 0.45:
            return recent[int(rng.integers(len(recent)))]
        return reg()

    def side_a() -> str:                           # register, RINV or 1.0
        r = rng.random()
        return "rinv" if r < 0.15 else "one" if r < 0.25 else src()

    for _ in range(n):
        if rng.random() < 0.05:
            lines.append("nop")
            continue
        dst = reg() if rng.random() < 0.6 else "acc"
        if rng.random() < 0.08:                    # bare registers: d = x +/- y
            expr = f"{src()} {'-' if rng.random() < 0.5 else '+'} {src()}"
        else:
            base = rng.choice(["", "acc", "reg"], p=[0.4, 0.2, 0.4])
            expr = "acc" if base == "acc" else src() if base == "reg" else ""
            for _ in range(1 if rng.random() < 0.4 else 2):
                f1, f2 = side_a(), src()
                if rng.random() < 0.5:
                    f1, f2 = f2, f1
                neg = rng.random() < 0.4
                if expr:
                    expr += f" {'-' if neg else '+'} {f1}*{f2}"
                else:
                    expr = f"{'-' if neg else ''}{f1}*{f2}"
        rc = ", rcp" if rng.random() < 0.08 else ""
        lines.append(f"{dst} = {expr}{rc}")
        if dst != "acc":
            recent = (recent + [dst])[-3:]
    lines.append("halt")
    return "\n".join(lines) + "\n"
