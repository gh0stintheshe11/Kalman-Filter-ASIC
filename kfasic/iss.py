"""Cycle-accurate instruction-set simulator (the golden model).

Executes a microcode image exactly like the RTL: same arithmetic
(kfasic.fixed), same result-register (SR) semantics and the same cycle count,
so tests can require bit-exact and cycle-exact agreement.
"""

from __future__ import annotations

from . import fixed
from .asm import C_HALT, ROM_DEPTH, WORD_HALT, decode

NUM_REGS = 32
OP_DIV = 3
# DIV occupies the sequencer for 25 cycles: 1 setup + 23 bit tests + 1 final
# multiply.  Every other instruction (including HALT) takes one cycle.
DIV_CYCLES = 25


class UninitializedRead(RuntimeError):
    pass


class Iss:
    """Model of the data bank, SR and sequencer.

    With ``strict=True`` reading a register (or SR) that was never written
    raises, which catches microcode that depends on stale data.
    """

    def __init__(self, words: list[int], strict: bool = True):
        if len(words) > ROM_DEPTH:
            raise ValueError("program larger than ROM")
        self.rom = list(words)
        self.strict = strict
        self.bank: list[int | None] = [None if strict else 0] * NUM_REGS
        self.sr: int | None = None if strict else 0

    # -- host interface (only legal while READY=1) --------------------------
    def write(self, addr: int, word: int) -> None:
        self.bank[addr] = word & fixed.MASK

    def read(self, addr: int) -> int:
        return self._get(addr)

    # -- execution -----------------------------------------------------------
    def _get(self, addr: int) -> int:
        v = self.bank[addr]
        if v is None:
            raise UninitializedRead(f"read of uninitialized register {addr}")
        return v

    def run(self, max_cycles: int = 100_000) -> int:
        """Run from PC=0 to HALT.

        Returns the number of clock cycles from the edge that samples START
        to the edge after which READY is high again.
        """
        pc, cycles = 0, 0
        while True:
            word = self.rom[pc] if pc < len(self.rom) else WORD_HALT
            x = decode(word)
            cycles += 1
            if cycles > max_cycles:
                raise RuntimeError("program did not halt")
            if x["c"] == C_HALT:
                return cycles
            if x["e"]:
                r, s = self._get(x["a"]), self._get(x["b"])
                op = ("add", "sub", "mul", "div")[x["d"]]
                self.sr = fixed.OPS[op](r, s)
                if x["d"] == OP_DIV:
                    cycles += DIV_CYCLES - 1
                elif x["f"]:
                    self.bank[x["a"]] = self.sr
            elif x["f"]:
                if self.sr is None:
                    raise UninitializedRead("store of SR before any result")
                self.bank[x["a"]] = self.sr
            pc = (pc + 1) % ROM_DEPTH


def execute_float(words: list[int], bank: list[float]) -> list[float]:
    """Run a program once with exact floating-point arithmetic.

    Separates algorithm bugs (wrong operand, wrong order) from fixed-point
    effects: the result must match the textbook equations to ~1e-12.
    """
    bank = list(bank)
    sr = 0.0
    for word in words:
        x = decode(word)
        if x["c"] == C_HALT:
            break
        a, b = bank[x["a"]], bank[x["b"]]
        if x["e"]:
            sr = (a + b, a - b, a * b, a / b if b else float("inf"))[x["d"]]
            if x["f"] and x["d"] != OP_DIV:
                bank[x["a"]] = sr
        elif x["f"]:
            bank[x["a"]] = sr
    return bank
