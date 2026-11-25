"""Black-box cocotb tests of the chip (kf_chip) through its pads: an SPI
master loads the filter, runs it and reads the results, which must match
the golden model bit for bit.  The same tests run on the RTL with the IHP
pad models and on the chip's gate-level netlist.

Environment:  KF_CLK_NS   core clock period in ns (default 10)
              KF_ITERS    iterations of the tracking scenario (default 12)
"""

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, Timer
from cocotb.utils import get_sim_time

from kfasic import fixed
from kfasic import reference as ref
from kfasic.asm import assemble_file
from kfasic.iss import Iss

ROOT = Path(__file__).resolve().parents[1]
PROG = assemble_file(ROOT / "fw" / "kf_2d.s")
REG = PROG.regs
STATE = ("x1", "x2", "p11", "p12", "p22")
CLK_NS = float(os.environ.get("KF_CLK_NS", "10"))
OP_NOP, OP_WRITE, OP_READ, OP_WRITE_START, OP_START, OP_CONTROL = 0, 1, 2, 3, 4, 5


class SpiMaster:
    """SPI mode 0, MSB first, SCLK = CLK / 10."""

    def __init__(self, dut, half_ns=5 * CLK_NS):
        self.dut = dut
        self.half = half_ns

    async def frame(self, op, addr=0, data=0, bits=32):
        d = self.dut
        word = (op << 29) | (addr << 24) | (data & 0xFFFFFF)
        d.cs_n_PAD.value = 0
        await Timer(self.half, unit="ns")
        miso = 0
        for i in range(bits):
            d.mosi_PAD.value = (word >> (31 - i)) & 1
            await Timer(self.half, unit="ns")
            d.sclk_PAD.value = 1
            await ReadOnly()
            v = d.miso_PAD.value
            assert v.is_resolvable, f"MISO is {v} during a frame"
            miso = (miso << 1) | int(v)
            await Timer(self.half, unit="ns")
            d.sclk_PAD.value = 0
        await Timer(self.half, unit="ns")
        d.cs_n_PAD.value = 1
        await Timer(self.half, unit="ns")
        return miso

    async def status(self):
        return (await self.frame(OP_NOP)) >> 24

    async def write(self, addr, word):
        await self.frame(OP_WRITE, addr, word)

    async def read(self, addr):
        return (await self.frame(OP_READ, addr)) & 0xFFFFFF


async def power_up(dut):
    cocotb.start_soon(Clock(dut.clk_PAD, CLK_NS, unit="ns").start())
    for pin in (dut.sclk_PAD, dut.mosi_PAD, dut.start_PAD):
        pin.value = 0
    dut.cs_n_PAD.value = 1
    dut.rst_n_PAD.value = 0
    await ClockCycles(dut.clk_PAD, 4)
    await FallingEdge(dut.clk_PAD)
    dut.rst_n_PAD.value = 1
    await ClockCycles(dut.clk_PAD, 6)
    assert dut.ready_PAD.value == 1, "READY must be high after reset"
    if "icarus" in cocotb.SIM_NAME.lower():           # Verilator has no high impedance on ports
        assert not dut.miso_PAD.value.is_resolvable, "MISO must be released while CS_N is high"
    return SpiMaster(dut)


async def wait_ready(dut, max_cycles=200):
    for _ in range(max_cycles):
        await FallingEdge(dut.clk_PAD)
        if dut.ready_PAD.value == 1:
            return
    raise AssertionError("READY did not return")


async def load(spi, iss, params):
    for name, word in ref.quantize(params).items():
        await spi.write(REG[name], word)
        iss.write(REG[name], word)


@cocotb.test()
async def status_and_readback(dut):
    """Status after reset; every register can be written and read back."""
    spi = await power_up(dut)
    st = await spi.status()
    assert st == 0b1000_0000, f"status after reset {st:08b}"
    rnd = random.Random(3)
    values = [rnd.getrandbits(24) for _ in range(32)]
    for a, v in enumerate(values):
        await spi.write(a, v)
    for a in rnd.sample(range(32), 32):
        got = await spi.read(a)
        assert got == values[a], f"DB[{a}] = {got:06X}, expected {values[a]:06X}"


@cocotb.test()
async def tracking_through_spi(dut):
    """The tracking scenario through SPI (WRITE_START y, READ the state):
    bit-exact against the golden model; ITER counts the iterations."""
    spi = await power_up(dut)
    iss = Iss(PROG.words)
    await load(spi, iss, ref.tracking_params())
    _, meas = ref.tracking_data(5000)
    n = int(os.environ.get("KF_ITERS", "12"))
    for k in range(n):
        yw = fixed.from_float(meas[k])
        await spi.frame(OP_WRITE_START, REG["y"], yw)
        iss.write(REG["y"], yw)
        iss.run()
        await wait_ready(dut)
        for name in STATE:
            got = await spi.read(REG[name])
            assert got == iss.read(REG[name]), (
                f"iteration {k + 1}: {name} = {got:06X}, expected {iss.read(REG[name]):06X}")
    st = await spi.status()
    assert st & 0x1F == n % 32, f"ITER = {st & 0x1F}, expected {n % 32}"


@cocotb.test()
async def start_pin_and_continuous_mode(dut):
    """The START pin runs one iteration; continuous mode runs them back to
    back and stops when cleared; a malformed frame sets ERR once."""
    spi = await power_up(dut)
    iss = Iss(PROG.words)
    await load(spi, iss, ref.tracking_params())
    await spi.write(REG["y"], fixed.from_float(0.25))
    iss.write(REG["y"], fixed.from_float(0.25))
    # START pin
    dut.start_PAD.value = 1
    for _ in range(10):
        await FallingEdge(dut.clk_PAD)
        if dut.ready_PAD.value == 0:
            break
    else:
        raise AssertionError("the START pin did not start the core")
    dut.start_PAD.value = 0
    await wait_ready(dut)
    iss.run()
    for name in STATE:
        assert await spi.read(REG[name]) == iss.read(REG[name]), name
    # continuous mode: several iterations per SPI frame
    await spi.frame(OP_CONTROL, data=1)
    st0 = await spi.status()
    st1 = await spi.status()
    assert st0 & 0x40 and st1 & 0x40, "CONT must be set"
    assert (st1 - st0) & 0x1F >= 5, f"continuous mode: ITER {st0 & 0x1F} -> {st1 & 0x1F}"
    await spi.frame(OP_CONTROL, data=0)
    await wait_ready(dut)
    await ClockCycles(dut.clk_PAD, 40)
    assert dut.ready_PAD.value == 1, "the core must stay idle after continuous mode"
    # malformed frame: ERR in the next status only
    await spi.frame(OP_WRITE, REG["y"], 0x123456, bits=31)
    assert (await spi.status()) & 0x20, "ERR must be set after a short frame"
    assert not (await spi.status()) & 0x20, "ERR must be cleared once reported"
    assert await spi.read(REG["y"]) != 0x123456, "a short frame must be ignored"


@cocotb.test()
async def requests_wait_for_ready(dut):
    """WRITEs that arrive while the core is busy (continuous mode) are all
    executed, between iterations."""
    spi = await power_up(dut)
    iss = Iss(PROG.words)
    await load(spi, iss, ref.tracking_params())
    await spi.frame(OP_CONTROL, data=1)                  # keep the core busy
    for k in range(4):
        await spi.write(REG["u"], fixed.from_float(0.25 * k))
        await spi.write(REG["g1"], fixed.from_float(-0.125 * k))
    await spi.frame(OP_CONTROL, data=0)
    await wait_ready(dut)
    assert await spi.read(REG["u"]) == fixed.from_float(0.75)
    assert await spi.read(REG["g1"]) == fixed.from_float(-0.375)


@cocotb.test()
async def start_pin_latency(dut):
    """Cycle counts at the pins: after START rises, READY falls after the 5th
    rising clock edge (two-flop synchronizer, edge detector, the SPI
    slave's request and start registers, the core's input register), plus
    the output delay, and stays low for the 25 cycles of an iteration.
    Measured in time, so pad and clock-tree delays (READY may take up to a
    period, kf_chip.sdc) do not shift the counts."""
    spi = await power_up(dut)
    iss = Iss(PROG.words)
    await load(spi, iss, ref.tracking_params())
    await spi.write(REG["y"], fixed.from_float(0.25))
    await FallingEdge(dut.clk_PAD)
    dut.start_PAD.value = 1
    first_edge = get_sim_time("ns") + CLK_NS / 2      # the edge that samples START

    async def wait_ready(level, max_cycles):
        t0 = get_sim_time("ns")
        while int(dut.ready_PAD.value) != level:
            await Timer(CLK_NS / 16, unit="ns")
            assert get_sim_time("ns") - t0 < max_cycles * CLK_NS, f"READY did not become {level}"
        return get_sim_time("ns")

    t_fall = await wait_ready(0, 20)
    t_rise = await wait_ready(1, 100)
    dut.start_PAD.value = 0
    edge = int((t_fall - first_edge) // CLK_NS) + 1
    low = round((t_rise - t_fall) / CLK_NS)
    dut._log.info(f"READY falls {t_fall - first_edge:.2f} ns after the edge sampling START "
                  f"(edge {edge}); low for {t_rise - t_fall:.2f} ns = {low} cycles")
    assert (edge, low) == (5, 25), f"READY falls after edge {edge}, low for {low} cycles"
    iss.write(REG["y"], fixed.from_float(0.25))
    iss.run()
    for name in STATE:
        assert await spi.read(REG[name]) == iss.read(REG[name]), name
