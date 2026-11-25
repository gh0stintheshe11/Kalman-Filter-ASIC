"""cocotb tests of the arithmetic units against kfasic.fixed, bit for bit."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from kfasic import fixed
from kfasic.iss import RCP_CYCLES


def operands(n, rnd):
    edge = [0, fixed.SIGN_BIT, 1, fixed.SIGN_BIT | 1, fixed.MAG_MAX, fixed.MASK, 32, 33,
            fixed.ONE, fixed.SIGN_BIT | fixed.ONE, fixed.from_float(0.1), fixed.from_float(-511.9)]
    pairs = [(a, b) for a in edge for b in edge]
    pairs += [(rnd.getrandbits(24), rnd.getrandbits(24)) for _ in range(n)]
    pairs += [(fixed.from_float(rnd.gauss(0, 4)), fixed.from_float(rnd.gauss(0, 4))) for _ in range(n)]
    return pairs


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for sig in (dut.mul_a, dut.mul_b, dut.as_a, dut.as_b, dut.as_sub, dut.rcp_start, dut.rcp_s):
        sig.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


@cocotb.test()
async def multiplier(dut):
    await setup(dut)
    for a, b in operands(3000, random.Random(1)):
        dut.mul_a.value = a
        dut.mul_b.value = b
        await ReadOnly()
        got = int(dut.mul_y.value)
        assert got == fixed.mul(a, b), f"mul({a:06X}, {b:06X}) = {got:06X}"
        await FallingEdge(dut.clk)


@cocotb.test()
async def adder_subtractor(dut):
    await setup(dut)
    for sub in (0, 1):
        ref = fixed.sub if sub else fixed.add
        for a, b in operands(3000, random.Random(2 + sub)):
            dut.as_a.value = a
            dut.as_b.value = b
            dut.as_sub.value = sub
            await ReadOnly()
            got = int(dut.as_y.value)
            assert got == ref(a, b), f"{'sub' if sub else 'add'}({a:06X}, {b:06X}) = {got:06X}"
            await FallingEdge(dut.clk)


@cocotb.test()
async def reciprocal(dut):
    """1/S is exact and takes exactly RCP_CYCLES cycles; starts back to back."""
    await setup(dut)
    rnd = random.Random(5)
    values = [b for _, b in operands(400, rnd)]
    for s in values:
        dut.rcp_s.value = s
        dut.rcp_start.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.rcp_start.value = 0
        dut.rcp_s.value = rnd.getrandbits(24)       # must have been captured
        cycles = 0
        while True:
            await ReadOnly()
            if dut.rcp_busy.value == 0:
                break
            await RisingEdge(dut.clk)
            cycles += 1
            assert cycles <= RCP_CYCLES
        assert cycles == RCP_CYCLES, f"busy for {cycles} cycles"
        got = int(dut.rcp_rinv.value)
        assert got == fixed.rcp(s), f"rcp({s:06X}) = {got:06X}, expected {fixed.rcp(s):06X}"
        await FallingEdge(dut.clk)
