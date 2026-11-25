"""Cycle-accurate model of the processor (the golden model).

Pipeline, one instruction issued per cycle at most:

    S1  fetch + operand read   ROM[PC] decoded, registers A/B (or RINV) read
    EX  execute                multiply, or add/subtract/load -> XR
    WB  accumulate + write     ACC <- XR or ACC +/- XR, optional register write

S1 stalls (bubble into EX) while
  * it reads a register that the instruction in EX or WB will write,
  * it reads RINV, or is an RCP, while the reciprocal unit is busy.
RCP does not enter EX/WB: at issue the reciprocal unit takes the divisor and
runs for RCP_CYCLES cycles; RINV is valid the cycle after.  HALT completes
once EX and the reciprocal unit are empty; an instruction in WB commits on
that same clock edge.

The arithmetic is kfasic.fixed; tests require the RTL to match this model
bit for bit and cycle for cycle.
"""

from __future__ import annotations

from dataclasses import dataclass

from . import fixed
from .asm import (ACC_OPS, OP_ADD, OP_HALT, OP_LDA, OP_MAC, OP_MSB, OP_RCP,
                  OP_SUB, ROM_DEPTH, TWO_OPERAND_OPS, WORD_HALT, decode, reads)

NUM_REGS = 32
RCP_CYCLES = 8          # radix-8 reciprocal: 24 quotient bits, 3 per cycle


class UninitializedRead(RuntimeError):
    pass


@dataclass
class _Slot:
    op: int
    wr: int
    dst: int
    va: int | None = None     # operand values captured in S1
    vb: int | None = None
    xr: int | None = None     # EX result


def ex_result(op: int, va: int, vb: int | None) -> int:
    if op == OP_ADD:
        return fixed.add(va, vb)
    if op == OP_SUB:
        return fixed.sub(va, vb)
    if op == OP_LDA:
        return va
    return fixed.mul(va, vb)                 # MUL, MAC, MSB


def wb_result(op: int, acc: int | None, xr: int) -> int:
    if op in (OP_MAC, OP_MSB):
        if acc is None:
            raise UninitializedRead("MAC/MSB with uninitialized ACC")
        return fixed.add(acc, xr) if op == OP_MAC else fixed.sub(acc, xr)
    return xr


class Iss:
    """Data bank, ACC, RINV and the pipeline.

    With ``strict=True`` reading a register, ACC or RINV that was never
    written raises, which catches microcode depending on stale data.
    """

    def __init__(self, words: list[int], strict: bool = True):
        if len(words) > ROM_DEPTH:
            raise ValueError("program larger than ROM")
        self.rom = list(words)
        self.strict = strict
        self.bank: list[int | None] = [None if strict else 0] * NUM_REGS
        self.acc: int | None = None if strict else 0
        self.rinv: int | None = None if strict else 0
        self.stalls = 0           # stall cycles of the last run (for reports)

    # -- host interface (only legal while READY = 1) ------------------------
    def write(self, addr: int, word: int) -> None:
        self.bank[addr] = word & fixed.MASK

    def read(self, addr: int) -> int:
        return self._reg(addr)

    def _reg(self, addr: int) -> int:
        v = self.bank[addr]
        if v is None:
            raise UninitializedRead(f"read of uninitialized register {addr}")
        return v

    # -- execution -----------------------------------------------------------
    def run(self, max_cycles: int = 100_000) -> int:
        """Run from PC 0 until HALT completes.

        Returns the number of clock cycles the sequencer is running (from the
        edge that starts it to the edge that returns it to idle).
        """
        pc, cycles, stalls = 0, 0, 0
        ex: _Slot | None = None
        wb: _Slot | None = None
        rcp_cnt, rcp_val = 0, None
        while True:
            cycles += 1
            if cycles > max_cycles:
                raise RuntimeError("program did not halt")
            word = self.rom[pc] if pc < len(self.rom) else WORD_HALT
            x = decode(word)
            op = x["op"]
            regs, uses_rinv = reads(x)

            pending = {s.dst for s in (ex, wb) if s is not None and s.wr}
            busy = rcp_cnt > 0
            stall = bool(regs & pending) or ((uses_rinv or op == OP_RCP) and busy)
            halting = op == OP_HALT
            issue = not halting and not stall
            # an instruction still in WB commits on the edge that ends the run
            done = halting and ex is None and not busy
            if not issue and not halting:
                stalls += 1

            # S1 reads happen before this cycle's WB write
            va = vb = None
            if issue:
                if op in TWO_OPERAND_OPS or op == OP_LDA:
                    va = self._reg(x["a"])
                if uses_rinv:
                    if self.rinv is None:
                        raise UninitializedRead("read of RINV before any RCP")
                    vb = self.rinv
                elif op in TWO_OPERAND_OPS or op == OP_RCP:
                    vb = self._reg(x["b"])

            # ---- clock edge ----
            if wb is not None:
                self.acc = wb_result(wb.op, self.acc, wb.xr)
                if wb.wr:
                    self.bank[wb.dst] = self.acc
            if ex is not None:
                ex.xr = ex_result(ex.op, ex.va, ex.vb)
            wb, ex = ex, None
            if rcp_cnt > 0:
                rcp_cnt -= 1
                if rcp_cnt == 0:
                    self.rinv = rcp_val
            if issue:
                if op in ACC_OPS:
                    ex = _Slot(op, x["wr"], x["dst"], va, vb)
                elif op == OP_RCP:
                    rcp_cnt, rcp_val = RCP_CYCLES, fixed.rcp(vb)
                pc = (pc + 1) % ROM_DEPTH
            if done:
                self.stalls = stalls
                return cycles


def execute_float(words: list[int], bank: list[float]) -> list[float]:
    """Run a program once with exact floating-point arithmetic (no pipeline
    effects: those never change results).  Separates algorithm bugs from
    fixed-point effects: the result must match the textbook equations."""
    bank = list(bank)
    acc = rinv = 0.0
    for word in words:
        x = decode(word)
        op = x["op"]
        if op == OP_HALT:
            break
        a = bank[x["a"]]
        b = rinv if x["bi"] else bank[x["b"]]
        if op == OP_RCP:
            rinv = 1.0 / b
            continue
        if op not in ACC_OPS:
            continue
        acc = {OP_ADD: a + b, OP_SUB: a - b, OP_LDA: a,
               OP_MAC: acc + a * b, OP_MSB: acc - a * b}.get(op, a * b)
        if x["wr"]:
            bank[x["dst"]] = acc
    return bank
