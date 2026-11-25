"""Host-side driver for kf_top, shared by the cocotb tests.

Only the chip's pins are used, so the same code drives the RTL and
gate-level netlists, with or without back-annotated delays.  Inputs change
on the falling clock edge and outputs are sampled on the falling edge, half
a cycle after the rising edge that updates them: results do not depend on
the simulator's event ordering, and cell delays up to half a period are
tolerated.

Environment:  KF_CLK_NS  clock period in ns (default 20)
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

CLK_NS = float(os.environ.get("KF_CLK_NS", "20"))
INPUT_LATENCY = 1      # host inputs are registered once in kf_top


class Host:
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
        await ClockCycles(d.clk, 2)
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
        """data_out = DB[dir] one cycle after dir is presented."""
        d = self.dut
        d.dir.value = addr
        await FallingEdge(d.clk)
        return int(d.data_out.value)

    async def run(self, max_cycles=2000):
        """Pulse START; return the clock edges from the one that captures
        START until READY is high again (= INPUT_LATENCY + Iss.run())."""
        d = self.dut
        assert d.ready.value == 1
        d.start.value = 1
        await FallingEdge(d.clk)                  # START captured on the rising edge before
        d.start.value = 0
        assert d.ready.value == 0, "READY must drop on the edge capturing START"
        cycles = 0
        while True:
            await FallingEdge(d.clk)
            cycles += 1
            if d.ready.value == 1:
                break
            assert int(d.data_out.value) == 0, "data_out must be 0 while busy"
            assert cycles < max_cycles, "program did not halt"
        return cycles
