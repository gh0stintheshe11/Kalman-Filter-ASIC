"""Black-box cocotb tests for kf_top running the Kalman filter microcode.

Only the host pins are used, so the same tests run on the RTL and on the
final gate-level netlist.  Every iteration is compared bit for bit and cycle
for cycle with the golden model (kfasic.iss), and the estimates with a
double-precision Kalman filter.

Environment:  KF_ITERS  iterations of the tracking scenario (default 200)
"""

import gzip
import os
import random
from pathlib import Path

import cocotb
import numpy as np
from cocotb.triggers import ClockCycles, FallingEdge

from kf_host import INPUT_LATENCY, Host
from kfasic import fixed
from kfasic import reference as ref
from kfasic.asm import assemble_file
from kfasic.iss import Iss

ROOT = Path(__file__).resolve().parents[1]
PROG = assemble_file(ROOT / "fw" / "kf_2d.s")
REG = PROG.regs
STATE = ("x1", "x2", "p11", "p12", "p22")


async def load(host, iss, params):
    for name, word in ref.quantize(params).items():
        await host.write(REG[name], word)
        iss.write(REG[name], word)


async def check_iteration(host, iss, y, k):
    yw = fixed.from_float(y)
    await host.write(REG["y"], yw)
    iss.write(REG["y"], yw)
    cycles = await host.run()
    expected = INPUT_LATENCY + iss.run()
    assert cycles == expected, f"iteration {k}: {cycles} cycles, expected {expected}"
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
    """Constant-velocity tracking (the original project's test case):
    bit- and cycle-exact against the golden model, bit-exact against the
    original course RTL, and within 5e-4 of a double-precision filter."""
    n = int(os.environ.get("KF_ITERS", "200"))
    host = Host(dut)
    await host.start_clock_and_reset()
    params = ref.tracking_params()
    truth, meas = ref.tracking_data(5000)
    with gzip.open(ROOT / "tests" / "data" / "legacy_rtl_states.txt.gz", "rt") as f:
        legacy = np.loadtxt(f, dtype=int)
    iss = Iss(PROG.words)
    await load(host, iss, params)
    x_hw = []
    for k in range(n):
        got = await check_iteration(host, iss, meas[k], k + 1)
        x1, x2 = fixed.to_int(got["x1"]), fixed.to_int(got["x2"])
        assert (x1, x2) == tuple(legacy[k]), f"iteration {k + 1}: differs from the course RTL"
        x_hw.append(fixed.to_float(got["x1"]))
    x_hw = np.array(x_hw)
    x_float = ref.run_float(params, meas[:n])[:, 0]
    err = np.abs(x_hw - x_float).max()
    mse_raw = np.mean((meas[:n] - truth[:n]) ** 2)
    mse_kf = np.mean((x_hw - truth[:n]) ** 2)
    dut._log.info(f"{n} iterations: max |hw - float| = {err:.6f}, "
                  f"MSE raw = {mse_raw:.5f}, MSE filtered = {mse_kf:.5f}")
    assert err < 5e-4


@cocotb.test()
async def random_systems(dut):
    """General systems (Phi, Q, H, G, u all non-trivial): bit-exact against
    the golden model, and x, P within 0.02 of the textbook filter."""
    host = Host(dut)
    await host.start_clock_and_reset()
    rng = np.random.default_rng(7)
    for _ in range(3):
        p = ref.random_params(rng)
        ys = ref.simulate(p, 25, rng)
        iss = Iss(PROG.words)
        await load(host, iss, p)
        x, P = p.x.copy(), p.P.copy()
        for k, y in enumerate(ys):
            got = await check_iteration(host, iss, y, k + 1)
            x, P = ref.kf_step(x, P, p, y)
            hw = np.array([fixed.to_float(got[n]) for n in STATE])
            err = np.abs(hw - np.r_[x, P[0, 0], P[0, 1], P[1, 1]]).max()
            assert err < 0.02, f"iteration {k + 1}: |hw - float KF| = {err:.4f}"


@cocotb.test()
async def host_ignored_while_running(dut):
    """WRITE and START are ignored while READY = 0."""
    host = Host(dut)
    await host.start_clock_and_reset()
    iss = Iss(PROG.words)
    await load(host, iss, ref.tracking_params())
    yw = fixed.from_float(0.75)
    await host.write(REG["y"], yw)
    iss.write(REG["y"], yw)
    iss.run()

    d = dut
    rnd = random.Random(4)
    d.start.value = 1
    await FallingEdge(d.clk)                       # START captured on the edge before
    cycles = 0
    while d.ready.value != 1:
        d.write.value = 1                          # hostile host traffic
        d.dir.value = rnd.randrange(32)
        d.data_in.value = rnd.getrandbits(24)
        d.start.value = rnd.getrandbits(1)
        await FallingEdge(d.clk)
        cycles += 1
        assert cycles < 1000
    d.write.value = 0
    d.start.value = 0
    for n in STATE:
        assert await host.read(REG[n]) == iss.read(REG[n]), n


@cocotb.test()
async def reset_during_run(dut):
    """Reset in mid-iteration returns to idle; a re-initialized run is
    correct."""
    host = Host(dut)
    await host.start_clock_and_reset()
    iss = Iss(PROG.words)
    await load(host, iss, ref.tracking_params())
    await host.write(REG["y"], fixed.from_float(1.0))
    dut.start.value = 1
    await ClockCycles(dut.clk, 15)                 # reciprocal unit busy
    await FallingEdge(dut.clk)
    dut.start.value = 0
    await host.reset()
    iss = Iss(PROG.words)
    await load(host, iss, ref.tracking_params())
    await check_iteration(host, iss, 1.0, 1)
