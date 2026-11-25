"""Host-side driver for kf_top, shared by the cocotb tests.

Only the chip's pins are used, so the same code drives the RTL and
gate-level netlists, with or without back-annotated delays.  Inputs change
on the falling clock edge.  READY is sampled on the falling edge, half a
cycle after the rising edge that updates it; data_out at 90 % of the cycle,
because the read port may take the whole cycle (flow/ihp-sg13g2/kf_top.sdc:
in the chip, the SPI slave captures data_out on the next rising edge).
Results do not depend on the simulator's event ordering, and real cell
delays are tolerated.

Environment:  KF_CLK_NS  clock period in ns (default 20)
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer

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
        """data_out = DB[dir] in the cycle after dir is presented, sampled at
        the end of that cycle; returns on the next falling edge."""
        d = self.dut
        d.dir.value = addr
        await FallingEdge(d.clk)                  # dir captured on the rising edge before
        await Timer(0.4 * CLK_NS, unit="ns")      # 90 % of the cycle
        value = int(d.data_out.value)
        await FallingEdge(d.clk)
        return value

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
