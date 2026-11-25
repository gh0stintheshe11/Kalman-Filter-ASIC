"""cocotb tests for kf_au: every result is compared bit for bit with
kfasic.fixed, DIV latency is checked.

Inputs are driven on the falling clock edge and sampled in ReadOnly, so the
results cannot depend on simulator event ordering.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from kfasic import fixed
from kfasic.iss import DIV_CYCLES

OPS = {0: ("add", fixed.add), 1: ("sub", fixed.sub), 2: ("mul", fixed.mul), 3: ("div", fixed.div)}


def operands(n, rnd):
    edge = [0, fixed.SIGN_BIT, 1, fixed.SIGN_BIT | 1, fixed.MAG_MAX, fixed.MASK,
            fixed.ONE, fixed.SIGN_BIT | fixed.ONE, fixed.from_float(0.1), fixed.from_float(-511.9)]
    pairs = [(a, b) for a in edge for b in edge]
    pairs += [(rnd.getrandbits(24), rnd.getrandbits(24)) for _ in range(n)]
    pairs += [(fixed.from_float(rnd.gauss(0, 4)), fixed.from_float(rnd.gauss(0, 4))) for _ in range(n)]
    return pairs


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.start.value = 0
    dut.op.value = 0
    dut.r.value = 0
    dut.s.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


@cocotb.test()
async def single_cycle_ops(dut):
    """ADD/SUB/MUL are combinational and exact."""
    await setup(dut)
    rnd = random.Random(1)
    vectors = operands(1500, rnd)
    for op in (0, 1, 2):
        name, ref = OPS[op]
        for r, s in vectors:
            dut.op.value = op
            dut.r.value = r
            dut.s.value = s
            dut.start.value = 1
            await ReadOnly()
            got = int(dut.y.value)
            assert got == ref(r, s), f"{name}({r:06X}, {s:06X}) = {got:06X}, expected {ref(r, s):06X}"
            assert dut.done.value == 0
            await FallingEdge(dut.clk)
    dut.start.value = 0


@cocotb.test()
async def division(dut):
    """DIV takes exactly DIV_CYCLES cycles and is exact; back-to-back DIVs work."""
    await setup(dut)
    rnd = random.Random(2)
    vectors = operands(150, rnd)
    for r, s in vectors:
        dut.op.value = 3
        dut.r.value = r
        dut.s.value = s
        dut.start.value = 1
        cycles = 1
        while True:
            await ReadOnly()
            if dut.done.value == 1:
                break
            await FallingEdge(dut.clk)
            cycles += 1
            assert cycles <= DIV_CYCLES, "DIV did not finish"
        got = int(dut.y.value)
        assert cycles == DIV_CYCLES, f"DIV took {cycles} cycles"
        assert got == fixed.div(r, s), f"div({r:06X}, {s:06X}) = {got:06X}, expected {fixed.div(r, s):06X}"
        await FallingEdge(dut.clk)   # next instruction is another DIV (start stays 1)
    dut.start.value = 0
    await ClockCycles(dut.clk, 2)
    await ReadOnly()
    assert dut.done.value == 0, "AU must stay idle once start is released"


@cocotb.test()
async def reset_aborts_division(dut):
    """An asynchronous reset in the middle of a DIV returns the AU to idle."""
    await setup(dut)
    dut.op.value = 3
    dut.r.value = fixed.from_float(3.0)
    dut.s.value = fixed.from_float(1.5)
    dut.start.value = 1
    await ClockCycles(dut.clk, 7)
    dut.start.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    for _ in range(DIV_CYCLES + 2):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert dut.done.value == 0
