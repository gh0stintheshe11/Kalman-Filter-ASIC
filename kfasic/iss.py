"""Cycle-accurate model of the processor (the golden model).

Pipeline, one instruction issued per cycle at most:

    S1  decode + operand read   A, D (register, RINV or 1.0), B, E (registers)
    EX  two multiplications     A*B and D*E; the addend C is read
    WB  sum + write back        ACC <- sat(base +/- A*B +/- D*E), optional
                                register write; optionally the reciprocal
                                unit is started with the result

(The fetch of the next instruction into the instruction register overlaps
with S1 and never costs a cycle.)  The result in WB is forwarded to the
operand reads in S1 and EX of the same cycle.

S1 stalls (bubble into EX) while
  * it reads a register as A, B, D or E that the instruction in EX will
    write,
  * it reads RINV while an instruction that starts the reciprocal unit is in
    EX or WB, or the unit is busy and not in its last cycle (in the last
    cycle the new RINV is forwarded),
  * it starts the reciprocal unit while another such instruction is in EX or
    WB or the unit is busy.
The reciprocal unit takes the result of the instruction that starts it at
the end of its WB cycle and works for RCP_CYCLES cycles; RINV is written at
the end of the last.  HALT ends the run once no reciprocal is pending: the
instruction in EX at that point, if any, commits one cycle after the run (it
is in WB while READY is already 1; the host cannot observe the difference).

The arithmetic is kfasic.fixed; tests require the RTL to match this model
bit for bit and cycle for cycle.
"""

from __future__ import annotations

from dataclasses import dataclass

from . import fixed
from .asm import (BASE_ACC, BASE_ZERO, OP_ALU_RCP, OP_HALT, ROM_DEPTH, SRC_REG, SRC_RINV,
                  WORD_HALT, addend, decode, is_alu, reads)

NUM_REGS = 32
RCP_CYCLES = 4          # radix-8 reciprocal: 8 digits, two per cycle


class UninitializedRead(RuntimeError):
    pass


@dataclass
class _Slot:
    x: dict                      # decoded instruction
    va: int                      # operands captured in S1
    vb: int
    vd: int | None
    ve: int | None
    vc: int | None = None        # addend, read in EX
    p1: int | None = None        # signed products, formed in EX
    p2: int | None = None

    @property
    def rc(self) -> bool:
        return self.x["op"] == OP_ALU_RCP

    @property
    def writes(self) -> int | None:
        return self.x["dst"] if self.x["wr"] else None


def alu_result(x: dict, acc: int | None, vc: int | None, p1: int, p2: int | None) -> int:
    if x["base"] == BASE_ZERO:
        base = 0
    elif x["base"] == BASE_ACC:
        if acc is None:
            raise UninitializedRead("ACC used before it was written")
        base = fixed.to_int(acc)
    else:
        base = fixed.to_int(vc)
    terms = [-p1 if x["n1"] else p1]
    if x["m2"]:
        terms.append(-p2 if x["n2"] else p2)
    return fixed.dot(base, *terms)


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

    def _commit(self, wb: _Slot) -> int:
        self.acc = alu_result(wb.x, self.acc, wb.vc, wb.p1, wb.p2)
        if wb.writes is not None:
            self.bank[wb.writes] = self.acc
        return self.acc

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
            regs, uses_rinv = reads(x)

            owed = {ex.writes} if ex is not None and ex.writes is not None else set()
            rc_pending = (ex is not None and ex.rc) or (wb is not None and wb.rc)
            stall = (bool(regs & owed)
                     or (uses_rinv and (rc_pending or rcp_cnt > 1))
                     or (x["op"] == OP_ALU_RCP and (rc_pending or rcp_cnt > 0)))
            halting = x["op"] == OP_HALT
            issue = is_alu(x) and not stall
            advance = (not halting and not stall)          # pc moves on (also NOP)
            done = halting and not rc_pending and rcp_cnt == 0
            if not advance and not halting:
                stalls += 1

            # WB: its result is forwarded to this cycle's operand reads
            result = self._commit(wb) if wb is not None else None
            # S1 operand reads, EX addend read
            if issue:
                def src(r: int, s: int) -> int:
                    if s == SRC_REG:
                        return self._reg(r)
                    if s == SRC_RINV:
                        v = rcp_val if rcp_cnt == 1 else self.rinv
                        if v is None:
                            raise UninitializedRead("read of RINV before any reciprocal")
                        return v
                    return fixed.ONE
                va, vb = src(x["a"], x["asrc"]), self._reg(x["b"])
                vd = ve = None
                if x["m2"]:
                    vd, ve = src(x["d"], x["dsrc"]), self._reg(x["e"])
            if ex is not None and addend(ex.x) is not None:
                ex.vc = self._reg(addend(ex.x))

            # ---- clock edge ----
            if ex is not None:
                ex.p1 = fixed.product(ex.va, ex.vb)
                if ex.x["m2"]:
                    ex.p2 = fixed.product(ex.vd, ex.ve)
            if rcp_cnt > 0:
                rcp_cnt -= 1
                if rcp_cnt == 0:
                    self.rinv = rcp_val
            if wb is not None and wb.rc:
                rcp_cnt, rcp_val = RCP_CYCLES, fixed.rcp(result)
            wb, ex = ex, None
            if issue:
                ex = _Slot(x, va, vb, vd, ve)
            if advance:
                pc = (pc + 1) % ROM_DEPTH
            if done:
                if wb is not None:            # commits on the edge after the run
                    self._commit(wb)
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
        if x["op"] == OP_HALT:
            break
        if not is_alu(x):
            continue
        src = lambda r, s: bank[r] if s == SRC_REG else rinv if s == SRC_RINV else 1.0  # noqa: E731
        base = 0.0 if x["base"] == BASE_ZERO else acc if x["base"] == BASE_ACC else bank[x["c"]]
        p1 = src(x["a"], x["asrc"]) * bank[x["b"]]
        total = base - p1 if x["n1"] else base + p1
        if x["m2"]:
            p2 = src(x["d"], x["dsrc"]) * bank[x["e"]]
            total = total - p2 if x["n2"] else total + p2
        acc = total
        if x["wr"]:
            bank[x["dst"]] = acc
        if x["op"] == OP_ALU_RCP:
            rinv = 1.0 / acc
    return bank
