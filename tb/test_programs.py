"""Differential test of arbitrary programs: RTL (with tb/kf_rom_sim.v)
against the golden model.

The pytest runner (tb/test_sim.py) assembles a program, loads it through
+rom=<hex>, and passes the cases in a JSON file named by KF_PROGRAM_SPEC:
initial register values plus the expected registers and cycle count, all
computed by kfasic.iss.  Every register and the exact cycle count must match.
"""

import json
import os
from pathlib import Path

import cocotb

from kf_host import INPUT_LATENCY, Host


@cocotb.test()
async def program(dut):
    spec = json.loads(Path(os.environ["KF_PROGRAM_SPEC"]).read_text())
    host = Host(dut)
    await host.start_clock_and_reset()
    for n, case in enumerate(spec["cases"]):
        for addr, word in enumerate(case["init"]):
            await host.write(addr, word)
        cycles = await host.run()
        assert cycles == INPUT_LATENCY + case["cycles"], (
            f"{spec['name']} case {n}: {cycles} cycles, expected {INPUT_LATENCY + case['cycles']}")
        for addr, want in enumerate(case["expected"]):
            got = await host.read(addr)
            assert got == want, f"{spec['name']} case {n}: DB[{addr}] = {got:06X}, expected {want:06X}"
