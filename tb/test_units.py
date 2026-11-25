"""cocotb tests of the arithmetic units against kfasic.fixed, bit for bit."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from kfasic import fixed
from kfasic.iss import RCP_CYCLES

MAG_EDGE = [0, 1, 2, 3, fixed.MAG_MAX, fixed.MAG_MAX - 1, 32, 33, fixed.ONE, 0x555555, 0x2AAAAA,
            fixed.mag_of(fixed.from_float(0.1)), fixed.mag_of(fixed.from_float(511.9))]


def words(n, rnd):
    edge = [0, fixed.SIGN_BIT, 1, fixed.SIGN_BIT | 1, fixed.MAG_MAX, fixed.MASK, 32, 33,
            fixed.ONE, fixed.SIGN_BIT | fixed.ONE, fixed.from_float(0.1), fixed.from_float(-511.9)]
    out = list(edge)
    out += [rnd.getrandbits(24) for _ in range(n)]
    out += [fixed.from_float(rnd.gauss(0, 4)) for _ in range(n)]
    return out


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for sig in (dut.mul_a, dut.mul_b, dut.dot_base, dut.dot_x1, dut.dot_s1, dut.dot_x2,
                dut.dot_s2, dut.dot_m2, dut.rcp_start, dut.rcp_s):
        sig.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


@cocotb.test()
async def multiplier(dut):
    """Booth recoding + multiplier: the truncated product of magnitudes."""
    await setup(dut)
    rnd = random.Random(1)
    pairs = [(a, b) for a in MAG_EDGE for b in MAG_EDGE]
    pairs += [(rnd.getrandbits(23), rnd.getrandbits(23)) for _ in range(3000)]
    pairs += [(rnd.getrandbits(rnd.randint(1, 23)), rnd.getrandbits(rnd.randint(1, 23)))
              for _ in range(3000)]
    for a, b in pairs:
        dut.mul_a.value = a
        dut.mul_b.value = b
        await ReadOnly()
        got = int(dut.mul_p.value)
        assert got == (a * b) >> fixed.FRAC, f"mul({a:06X}, {b:06X}) = {got:08X}"
        await FallingEdge(dut.clk)


@cocotb.test()
async def accumulator(dut):
    """kf_dot: base +/- p1 +/- p2, exact, saturated once, +0 for zero."""
    await setup(dut)
    rnd = random.Random(2)
    prods = [0, 1, fixed.MAG_MAX, fixed.MAG_MAX + 1, (1 << 32) - 1, 1 << 23, fixed.ONE]

    def prod():
        r = rnd.random()
        if r < 0.2:
            return rnd.choice(prods)
        return rnd.getrandbits(rnd.randint(1, 24) if r < 0.7 else 32)

    for base in words(800, rnd):
        x1, x2 = prod(), prod()
        s1, s2, m2 = rnd.getrandbits(1), rnd.getrandbits(1), rnd.getrandbits(1)
        if rnd.random() < 0.1:                         # exact cancellation
            x1, s1, m2 = fixed.mag_of(base), 1 - fixed.sign_of(base), 0
        dut.dot_base.value = base
        dut.dot_x1.value, dut.dot_s1.value = x1, s1
        dut.dot_x2.value, dut.dot_s2.value, dut.dot_m2.value = x2, s2, m2
        await ReadOnly()
        terms = [-x1 if s1 else x1] + ([-x2 if s2 else x2] if m2 else [])
        want = fixed.dot(fixed.to_int(base), *terms)
        got = int(dut.dot_y.value)
        assert got == want, f"dot({base:06X}, {terms}) = {got:06X}, expected {want:06X}"
        await FallingEdge(dut.clk)


@cocotb.test()
async def reciprocal(dut):
    """1/S is exact, takes exactly RCP_CYCLES cycles, is on rinv_next in the
    last of them; starts back to back."""
    await setup(dut)
    rnd = random.Random(5)
    for s in words(400, rnd):
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
            cycles += 1
            if dut.rcp_last.value == 1:
                got = int(dut.rcp_rinv_next.value)
                assert got == fixed.rcp(s), f"rinv_next({s:06X}) = {got:06X}"
            assert int(dut.rcp_last.value) == (cycles == RCP_CYCLES)
            await RisingEdge(dut.clk)
            assert cycles <= RCP_CYCLES
        assert cycles == RCP_CYCLES, f"busy for {cycles} cycles"
        got = int(dut.rcp_rinv.value)
        assert got == fixed.rcp(s), f"rcp({s:06X}) = {got:06X}, expected {fixed.rcp(s):06X}"
        await FallingEdge(dut.clk)
