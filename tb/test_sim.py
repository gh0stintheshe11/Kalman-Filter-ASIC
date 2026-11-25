"""pytest entry points: build the HDL and run the cocotb tests.

    pytest tb                         RTL, Icarus Verilog
    SIM=verilator pytest tb           RTL, Verilator
    pytest tb -m slow                 5000-iteration regression
    GL_NETLIST=... GL_CELLS=... pytest tb -k kf_top
                                      gate-level netlist (see Makefile 'gls')
"""

import os
import shutil
from pathlib import Path

import pytest
from cocotb_tools.runner import get_results, get_runner

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "tb"
RTL = [ROOT / "rtl" / f for f in
       ("kf_top.v", "kf_sequencer.v", "kf_rom.v", "kf_regfile.v", "kf_au.v")]
SIM = os.environ.get("SIM", "icarus")
GL_NETLIST = os.environ.get("GL_NETLIST")
GL_CELLS = [p for p in os.environ.get("GL_CELLS", "").split(":") if p]


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


def run(top, module, sources, tag, env=None, defines=None):
    build_dir = ROOT / "build" / "sim" / f"{SIM}-{tag}"
    runner = get_runner(SIM)
    build_args = ["-Wno-fatal"] if SIM == "verilator" else []
    runner.build(sources=sources, hdl_toplevel=top, build_dir=build_dir,
                 always=True, timescale=("1ns", "1ps"), defines=defines or {},
                 build_args=build_args)
    env = dict(env or {})
    env["PYTHONPATH"] = os.pathsep.join(p for p in (str(TB), os.environ.get("PYTHONPATH")) if p)
    results = runner.test(hdl_toplevel=top, test_module=module, build_dir=build_dir,
                          test_dir=build_dir, extra_env=env)
    n_tests, n_failed = get_results(results)
    assert n_tests > 0 and n_failed == 0, f"{n_failed} of {n_tests} cocotb tests failed"


@pytest.mark.skipif(GL_NETLIST is not None, reason="unit test runs on RTL only")
def test_au():
    run("kf_au", "test_au", [ROOT / "rtl" / "kf_au.v"], "au")


def test_kf_top():
    if GL_NETLIST:
        run("kf_top", "test_kf_top", [*GL_CELLS, GL_NETLIST], "gl",
            defines={"FUNCTIONAL": 1, "UNIT_DELAY": "#0"})
    else:
        run("kf_top", "test_kf_top", RTL, "rtl")


@pytest.mark.slow
@pytest.mark.skipif(GL_NETLIST is not None, reason="too slow for gate level")
def test_kf_top_5000_iterations():
    run("kf_top", "test_kf_top", RTL, "rtl-long", env={"KF_ITERS": "5000"})
