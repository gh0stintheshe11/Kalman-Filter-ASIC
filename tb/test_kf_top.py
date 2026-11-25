"""Black-box cocotb tests for kf_top.

Only the host pins are used (no hierarchical references), so the same tests
run unchanged on the RTL and on gate-level netlists.  Every iteration is
compared bit for bit (and cycle for cycle) with the ISS golden model.

Environment knobs:
    KF_ITERS   iterations of the tracking scenario (default 200)
"""

import gzip
import os
import random
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from kfasic import fixed
from kfasic import reference as ref
from kfasic.asm import assemble_file
from kfasic.iss import Iss

ROOT = Path(__file__).resolve().parents[1]
PROG = assemble_file(ROOT / "fw" / "kf_2d.s")
REG = PROG.regs
STATE = ("x1", "x2", "p11", "p12", "p21", "p22")
CLK_NS = 20
INPUT_LATENCY = 1      # host inputs are registered once in kf_top


class Host:
    """Drives the host interface; all changes happen on the falling edge."""

    def __init__(self, dut):
        self.dut = dut

    async def start_clock_and_reset(self):
        cocotb.start_soon(Clock(self.dut.clk, CLK_NS, unit="ns").start())
        await self.reset()

    async def reset(self):
        d = self.dut
        d.start.value = 0
        d.write.value = 0
        d.dir.value = 0
        d.data_in.value = 0
        d.rst_n.value = 0
        await ClockCycles(d.clk, 3)
        await FallingEdge(d.clk)
        assert d.ready.value == 0, "READY must be low during reset"
        d.rst_n.value = 1
        await FallingEdge(d.clk)
        assert d.ready.value == 0, "READY must stay low while the reset synchronizes"
        await ClockCycles(d.clk, 2)       # reset synchronizer latency
        await FallingEdge(d.clk)
        assert d.ready.value == 1, "READY must be high after reset"

    async def write(self, addr, word):
        d = self.dut
        d.dir.value = addr
        d.data_in.value = word
        d.write.value = 1
        await FallingEdge(d.clk)
        d.write.value = 0

    async def read(self, addr):
        d = self.dut
        d.dir.value = addr
        await FallingEdge(d.clk)          # dir registered
        await FallingEdge(d.clk)          # data_out registered
        return int(d.data_out.value)

    async def load(self, words: dict):
        for name, word in words.items():
            await self.write(REG[name], word)

    async def run(self, max_cycles=1000):
        """Pulse START; return the clock edges from the one that captures
        START until READY is high again (= INPUT_LATENCY + Iss.run())."""
        d = self.dut
        assert d.ready.value == 1
        d.start.value = 1
        await RisingEdge(d.clk)           # START captured here
        await ReadOnly()
        assert d.ready.value == 0, "READY must drop on the edge capturing START"
        await FallingEdge(d.clk)
        d.start.value = 0
        cycles = 0
        while True:
            await RisingEdge(d.clk)
            cycles += 1
            await ReadOnly()
            if d.ready.value == 1:
                break
            assert cycles < max_cycles, "program did not halt"
        await FallingEdge(d.clk)
        return cycles


async def check_iteration(host, iss, y, k):
    yw = fixed.from_float(y)
    await host.write(REG["y"], yw)
    iss.write(REG["y"], yw)
    cycles = await host.run()
    expected_cycles = INPUT_LATENCY + iss.run()
    assert cycles == expected_cycles, f"iteration {k}: {cycles} cycles, expected {expected_cycles}"
    got = {n: await host.read(REG[n]) for n in STATE}
    for n in STATE:
        assert got[n] == iss.read(REG[n]), (
            f"iteration {k}: {n} = {fixed.to_float(got[n]):.6f} ({got[n]:06X}), "
            f"expected {fixed.to_float(iss.read(REG[n])):.6f}")
    return got


@cocotb.test()
async def register_readback(dut):
    """Every data-bank register can be written and read back by the host."""
    host = Host(dut)
    await host.start_clock_and_reset()
    rnd = random.Random(3)
    values = [rnd.getrandbits(24) for _ in range(32)]
    for a, v in enumerate(values):
        await host.write(a, v)
    for a in rnd.sample(range(32), 32):
        assert await host.read(a) == values[a], f"DB[{a}]"


@cocotb.test()
async def tracking_scenario(dut):
    """The original project's tracking test: bit-exact vs the ISS and vs the
    original course RTL, and close to the floating-point filter."""
    n = int(os.environ.get("KF_ITERS", "200"))
    host = Host(dut)
    await host.start_clock_and_reset()
    params = ref.tracking_params()
    truth, meas = ref.tracking_data(5000)
    iss = Iss(PROG.words)
    words = ref.quantize(params)
    await host.load(words)
    for name, w in words.items():
        iss.write(REG[name], w)
    with gzip.open(ROOT / "tests" / "data" / "legacy_rtl_states.txt.gz", "rt") as f:
        legacy = np.loadtxt(f, dtype=int)
    x_hw = []
    for k in range(n):
        got = await check_iteration(host, iss, meas[k], k + 1)
        x1, x2 = fixed.to_int(got["x1"]), fixed.to_int(got["x2"])
        assert (x1, x2) == tuple(legacy[k]), f"iteration {k + 1}: differs from original RTL"
        x_hw.append(fixed.to_float(got["x1"]))
    x_float = ref.run_float(params, meas[:n])[:, 0]
    mse_raw = np.mean((meas[:n] - truth[:n]) ** 2)
    mse_kf = np.mean((np.array(x_hw) - truth[:n]) ** 2)
    dut._log.info(f"{n} iterations: max |hw - float| = {np.abs(np.array(x_hw) - x_float).max():.6f}, "
                  f"MSE raw = {mse_raw:.5f}, MSE filtered = {mse_kf:.5f}")
    assert np.abs(np.array(x_hw) - x_float).max() < 2e-3


@cocotb.test()
async def random_systems(dut):
    """General systems (h2, phi21, q21, G, u all non-zero): bit-exact vs the
    ISS, and x/P within 0.02 of the textbook floating-point filter.  The
    original microcode's P+ operand bug fails the second check (~0.1-0.2)."""
    host = Host(dut)
    await host.start_clock_and_reset()
    rng = np.random.default_rng(7)
    for _ in range(3):
        p = ref.random_params(rng)
        ys = ref.simulate(p, 25, rng)
        iss = Iss(PROG.words)
        words = ref.quantize(p)
        await host.load(words)
        for name, w in words.items():
            iss.write(REG[name], w)
        x, P = p.x.copy(), p.P.copy()
        for k, y in enumerate(ys):
            got = await check_iteration(host, iss, y, k + 1)
            x, P = ref.kf_step(x, P, p, y)
            hw = np.array([fixed.to_float(got[n]) for n in STATE])
            err = np.abs(hw - np.r_[x, P.ravel()]).max()
            assert err < 0.02, f"iteration {k + 1}: |hw - float KF| = {err:.4f}"


@cocotb.test()
async def host_ignored_while_running(dut):
    """WRITE and START are ignored while READY = 0."""
    host = Host(dut)
    await host.start_clock_and_reset()
    words = ref.quantize(ref.tracking_params())
    iss = Iss(PROG.words)
    await host.load(words)
    for name, w in words.items():
        iss.write(REG[name], w)
    yw = fixed.from_float(0.75)
    await host.write(REG["y"], yw)
    iss.write(REG["y"], yw)
    iss.run()

    d = dut
    rnd = random.Random(4)
    d.start.value = 1
    await RisingEdge(d.clk)
    cycles = 0
    while True:
        await FallingEdge(d.clk)
        d.write.value = 1                       # hostile host traffic
        d.dir.value = rnd.randrange(32)
        d.data_in.value = rnd.getrandbits(24)
        d.start.value = rnd.getrandbits(1)
        await RisingEdge(d.clk)
        cycles += 1
        await ReadOnly()
        if d.ready.value == 1:
            break
        assert cycles < 1000
    await FallingEdge(d.clk)
    d.write.value = 0
    d.start.value = 0
    for n in STATE:
        assert await host.read(REG[n]) == iss.read(REG[n]), n


@cocotb.test()
async def reset_during_run(dut):
    """Reset mid-iteration returns to idle; a re-initialized run is correct."""
    host = Host(dut)
    await host.start_clock_and_reset()
    words = ref.quantize(ref.tracking_params())
    await host.load(words)
    await host.write(REG["y"], fixed.from_float(1.0))
    dut.start.value = 1
    await ClockCycles(dut.clk, 60)               # inside the first DIV
    dut.start.value = 0
    await host.reset()
    iss = Iss(PROG.words)
    await host.load(words)
    for name, w in words.items():
        iss.write(REG[name], w)
    await check_iteration(host, iss, 1.0, 1)
