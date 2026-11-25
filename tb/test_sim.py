"""pytest entry points: build the HDL and run the cocotb tests.

    pytest tb                         RTL, Icarus Verilog
    SIM=verilator pytest tb           RTL, Verilator
    pytest tb -m slow                 5000-iteration regression
    GL_NETLIST=... GL_CELLS=... pytest tb -k kf_top
                                      gate-level netlist (see Makefile 'gls')
    ... GL_SDF=<OpenSTA SDF> KF_CLK_NS=<period> pytest tb -k kf_top
                                      gate-level netlist with back-annotated
                                      delays, at the given clock period
"""

import json
import os
import shutil
import sys
from pathlib import Path

import numpy as np
import pytest
from cocotb_tools.runner import get_results, get_runner

from kfasic.asm import assemble, to_hex
from kfasic.iss import Iss
from kfasic.randprog import random_program

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "tb"
RTL_CORE = [ROOT / "rtl" / f for f in
            ("kf_top.v", "kf_regfile.v", "kf_rdport.v", "kf_mul.v", "kf_addsub.v", "kf_rcp.v", "kf_clkgate.v")]
RTL = RTL_CORE + [ROOT / "rtl" / "kf_rom.v"]
SIM = os.environ.get("SIM", "icarus")
GL_NETLIST = os.environ.get("GL_NETLIST")
GL_CELLS = [p for p in os.environ.get("GL_CELLS", "").split(":") if p]
GL_SDF = os.environ.get("GL_SDF")
rtl_only = pytest.mark.skipif(GL_NETLIST is not None, reason="runs on RTL only")


def _unwrap_oss_cad_suite_vvp():
    """OSS CAD Suite's `vvp` is a wrapper that forces the suite's bundled
    Python (PYTHONHOME/PYTHONEXECUTABLE).  cocotb then embeds a mix of two
    Python installations and cannot import this project's packages.  Put a
    shim that runs the same vvp binary without that override first on PATH."""
    vvp = shutil.which("vvp")
    if not vvp:
        return
    head = Path(vvp).read_bytes()[:4096]
    if not head.startswith(b"#!") or b"PYTHONHOME" not in head:
        return
    top = Path(vvp).resolve().parent.parent
    shim_dir = ROOT / "build" / "sim" / "bin"
    shim_dir.mkdir(parents=True, exist_ok=True)
    shim = shim_dir / "vvp"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        f'exec "{top}/lib/ld-linux-x86-64.so.2" --inhibit-cache --inhibit-rpath "" '
        f'--library-path "{top}/lib" "{top}/libexec/vvp" "$@"\n')
    shim.chmod(0o755)
    os.environ["PATH"] = f"{shim_dir}{os.pathsep}{os.environ['PATH']}"


if SIM == "icarus":
    _unwrap_oss_cad_suite_vvp()


def build(top, sources, tag, defines=None, extra_args=()):
    build_dir = ROOT / "build" / "sim" / f"{SIM}-{tag}"
    runner = get_runner(SIM)
    build_args = ["-Wno-fatal"] if SIM == "verilator" else []
    runner.build(sources=sources, hdl_toplevel=top, build_dir=build_dir,
                 always=True, timescale=("1ns", "1ps"), defines=defines or {},
                 build_args=[*build_args, *extra_args])
    return runner, build_dir


def run(runner, build_dir, top, module, env=None, plusargs=(), results="results.xml",
        log_file=None):
    env = dict(env or {})
    env["PYTHONPATH"] = os.pathsep.join(p for p in (str(TB), os.environ.get("PYTHONPATH")) if p)
    xml = runner.test(hdl_toplevel=top, test_module=module, build_dir=build_dir,
                      test_dir=build_dir, extra_env=env, plusargs=list(plusargs),
                      results_xml=str(build_dir / results), log_file=log_file)
    n_tests, n_failed = get_results(xml)
    assert n_tests > 0 and n_failed == 0, f"{n_failed} of {n_tests} cocotb tests failed"


@rtl_only
def test_units():
    sources = [TB / "kf_units_tb.v", *(ROOT / "rtl" / f for f in
               ("kf_mul.v", "kf_addsub.v", "kf_rcp.v", "kf_clkgate.v"))]
    runner, bdir = build("kf_units_tb", sources, "units")
    run(runner, bdir, "kf_units_tb", "test_units")


def test_kf_top():
    top = "kf_top"
    if GL_NETLIST and GL_SDF:
        assert SIM == "icarus", "back-annotated simulation needs Icarus Verilog"
        sys.path.insert(0, str(ROOT / "flow"))
        from power import sdf_for_icarus
        sdf = ROOT / "build" / "sim" / "gl.sdf"
        sdf.parent.mkdir(parents=True, exist_ok=True)
        sdf_for_icarus(Path(GL_SDF), sdf)
        top = "kf_top_sdf"
        runner, bdir = build(top, [*GL_CELLS, GL_NETLIST, TB / "kf_top_sdf.v"], "gl-sdf",
                             extra_args=["-gspecify", "-ginterconnect", f'-DKF_SDF="{sdf}"'])
        log = bdir / "sim.log"
        try:
            run(runner, bdir, top, "test_kf_top", log_file=log)
        finally:
            text = log.read_text() if log.exists() else ""
            print(text[-4000:])
        assert "SDF ERROR" not in text, "SDF back-annotation failed"
        return
    elif GL_NETLIST:
        runner, bdir = build(top, [*GL_CELLS, GL_NETLIST], "gl")
    else:
        runner, bdir = build(top, RTL, "rtl")
    run(runner, bdir, top, "test_kf_top")


@pytest.mark.slow
@rtl_only
def test_kf_top_5000_iterations():
    runner, bdir = build("kf_top", RTL, "rtl-long")
    run(runner, bdir, "kf_top", "test_kf_top", env={"KF_ITERS": "5000"})


DIRECTED = {
    "raw-distance-1": "lda db[2], db[1]\nlda acc, db[2]\nmac db[3], db[2], db[2]\nhalt",
    "raw-distance-2": "lda db[2], db[1]\nnop\nlda acc, db[2]\nhalt",
    "forward-b": "mul db[2], db[1], db[1]\nnop\nmul db[3], db[4], db[2]\nhalt",
    "forward-addend": "lda db[2], db[1]\nmad db[3], db[4], db[5], db[2]\n"
                      "msd db[6], db[4], one, db[3]\nhalt",
    "forward-divisor": "lda db[2], db[1]\nrcp db[2]\nmul db[5], db[1], rinv\nhalt",
    "rinv-wait": "rcp db[1]\nmul db[5], db[1], rinv\nhalt",
    "rcp-back-to-back": "rcp db[1]\nrcp db[2]\nmul db[6], db[3], rinv\nhalt",
    "halt-waits-for-rcp": "lda acc, db[0]\nrcp db[1]\nhalt",
    "acc-chain": "mul acc, db[1], db[2]\nmac acc, db[3], db[4]\nmsb acc, db[5], db[6]\n"
                 "add db[7], db[1], db[2]\nsub acc, db[8], db[9]\nmac db[10], db[11], db[12]\n"
                 "mad acc, db[1], one, db[10]\nmsd db[13], db[2], db[3], db[7]\nhalt",
}
N_RANDOM = int(os.environ.get("KF_RANDOM_PROGRAMS", "24"))


def _cases(prog, rng, n_cases=3):
    cases = []
    for _ in range(n_cases):
        init = [int(v) for v in rng.integers(0, 1 << 24, size=32)]
        iss = Iss(prog.words, strict=True)
        for addr, word in enumerate(init):
            iss.write(addr, word)
        cycles = iss.run()
        cases.append({"init": init, "cycles": cycles,
                      "expected": [iss.read(a) for a in range(32)]})
    return cases


@rtl_only
def test_programs():
    """Directed hazard programs and random programs: RTL == golden model."""
    runner, bdir = build("kf_top", [*RTL_CORE, TB / "kf_rom_sim.v"], "programs")
    rng = np.random.default_rng(1234)
    programs = dict(DIRECTED)
    programs.update({f"random-{i}": random_program(rng) for i in range(N_RANDOM)})
    for name, src in programs.items():
        prog = assemble(src, source=name)
        hexfile = bdir / f"{name}.hex"
        hexfile.write_text(to_hex(prog))
        spec = bdir / f"{name}.json"
        spec.write_text(json.dumps({"name": name, "cases": _cases(prog, rng)}))
        run(runner, bdir, "kf_top", "test_programs", env={"KF_PROGRAM_SPEC": str(spec)},
            plusargs=[f"+rom={hexfile}"], results=f"{name}.xml")
