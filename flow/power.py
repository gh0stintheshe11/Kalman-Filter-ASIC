#!/usr/bin/env python3
"""Activity-based power of a routed netlist.

Replays a workload on the final gate-level netlist of a LibreLane run with
Icarus Verilog, dumps a VCD for the measurement window and runs OpenSTA with
the extracted parasitics at the typical corner:

    python flow/power.py flow/ihp-sg13g2/runs/main [--iterations 20] [--idle 2000]

Two scenarios are reported:
  active  back-to-back filter iterations (write y, start, wait for ready)
  idle    no host activity, clock running

By default the simulation is back-annotated with the run's typical-corner
SDF (cell and interconnect delays), so the activity includes glitches.
--zero-delay simulates without delays instead: faster, but combinational
power is then only a lower bound.

OpenSTA is taken from $STA (default: `sta` on PATH), e.g.
    STA="$HOME/tools/librelane/squashfs-root/AppRun -- sta"
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from kfasic import fixed  # noqa: E402
from kfasic import reference as ref  # noqa: E402
from kfasic.asm import assemble_file  # noqa: E402

TB = ROOT / "tb" / "power" / "kf_power_tb.v"


def w(cmd, addr=0, data=0):
    return (cmd << 29) | (addr << 24) | (data & 0xFFFFFF)


def script_active(n_iter, warmup=3):
    regs = assemble_file(ROOT / "fw" / "kf_2d.s").regs
    _, meas = ref.tracking_data(5000)
    out = [w(1, regs[k], v) for k, v in ref.quantize(ref.tracking_params()).items()]
    for k in range(warmup):
        out += [w(1, regs["y"], fixed.from_float(meas[k])), w(2)]
    out.append(w(3))
    for k in range(warmup, warmup + n_iter):
        out += [w(1, regs["y"], fixed.from_float(meas[k])), w(2)]
    return out + [w(0)]


def script_idle(n_cycles):
    regs = assemble_file(ROOT / "fw" / "kf_2d.s").regs
    out = [w(1, regs[k], v) for k, v in ref.quantize(ref.tracking_params()).items()]
    out += [w(1, regs["y"], fixed.from_float(0.5)), w(2), w(4, 0, 16), w(3), w(4, 0, n_cycles)]
    return out + [w(0)]


def sdf_for_icarus(src: Path, dst: Path) -> None:
    """Copy an OpenSTA SDF file in a form Icarus Verilog can annotate.

    Icarus cannot parse the COND expressions OpenSTA writes for
    state-dependent delays; every such arc also has an unconditional
    IOPATH, which is kept.  The operating-condition header entries (with an
    empty typical value) are dropped.
    """
    out, skip = [], False
    for line in src.read_text().splitlines():
        if skip:                          # the IOPATH of a COND entry
            skip = False
            continue
        if line.lstrip().startswith("(COND"):
            skip = True
            continue
        if re.match(r"\s*\((VOLTAGE|PROCESS|TEMPERATURE)\b", line):
            continue
        out.append(line)
    dst.write_text("\n".join(out) + "\n")


def simulate(run: Path, cfg: dict, script: list[int], work: Path, tag: str,
             sdf: Path | None = None):
    period = float(cfg["CLOCK_PERIOD"])
    sfile = work / f"{tag}.hex"
    sfile.write_text("".join(f"{x:08X}\n" for x in script))
    vcd = work / f"{tag}.vcd"
    vvp = work / f"{tag}.vvp"
    cells = cfg["CELL_VERILOG_MODELS"]
    opts = ["-g2012", f"-Pkf_power_tb.PERIOD={period}"]
    if sdf is not None:
        opts += ["-gspecify", "-ginterconnect", f'-DKF_SDF="{sdf}"']
    subprocess.run(["iverilog", *opts, "-o", str(vvp),
                    *cells, str(run / "final" / "nl" / "kf_top.nl.v"), str(TB)],
                   check=True, capture_output=True, text=True)
    res = subprocess.run(["vvp", "-n", str(vvp), f"+script={sfile}", f"+vcd={vcd}"],
                         check=True, capture_output=True, text=True)
    if "SDF ERROR" in res.stdout + res.stderr:
        raise RuntimeError("SDF annotation failed:\n" + (res.stdout + res.stderr)[-3000:])
    m = re.search(r"WINDOW cycles=(\d+) iterations=(\d+)", res.stdout)
    if not m:
        raise RuntimeError(res.stdout + res.stderr)
    return vcd, int(m.group(1)), int(m.group(2))


def sta_power(run: Path, cfg: dict, vcd: Path, work: Path, tag: str) -> dict:
    corner = cfg.get("DEFAULT_CORNER", "nom_typ_1p20V_25C")
    libs = cfg["LIB"][corner]
    spef = sorted((run / "final" / "spef").glob("*/*.spef"))[0]
    tcl = work / f"{tag}.tcl"
    tcl.write_text("\n".join([
        *[f"read_liberty {lib}" for lib in libs],
        f"read_verilog {run / 'final' / 'nl' / 'kf_top.nl.v'}",
        "link_design kf_top",
        f"read_sdc {run / 'final' / 'sdc' / 'kf_top.sdc'}",
        f"read_spef {spef}",
        f"read_vcd -scope kf_power_tb/dut {vcd}",
        "report_power -digits 6",
        "exit",
    ]) + "\n")
    sta = shlex.split(os.environ.get("STA", "sta"))
    res = subprocess.run([*sta, "-no_splash", "-exit", str(tcl)], capture_output=True, text=True)
    out = res.stdout + res.stderr
    groups = {}
    for name in ("Sequential", "Combinational", "Clock", "Total"):
        m = re.search(rf"^{name}\s+([-\d.e+]+)\s+([-\d.e+]+)\s+([-\d.e+]+)\s+([-\d.e+]+)", out, re.M)
        if not m:
            raise RuntimeError(f"no '{name}' line in OpenSTA output:\n{out[-3000:]}")
        groups[name] = [float(x) for x in m.groups()]  # internal, switching, leakage, total
    return groups


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run", nargs="?", default="flow/ihp-sg13g2/runs/main")
    ap.add_argument("--iterations", type=int, default=20)
    ap.add_argument("--idle", type=int, default=2000, help="idle window in cycles")
    ap.add_argument("--zero-delay", action="store_true",
                    help="simulate without SDF delays (no glitches)")
    ap.add_argument("--json", help="also write results here")
    args = ap.parse_args(argv)

    run = Path(args.run).resolve()
    cfg = json.loads((run / "resolved.json").read_text())
    period = float(cfg["CLOCK_PERIOD"])
    corner = cfg.get("DEFAULT_CORNER", "nom_typ_1p20V_25C")
    results = {"clock_ns": period, "delays": "zero" if args.zero_delay else "sdf"}
    with tempfile.TemporaryDirectory(prefix="kf_power_") as tmp:
        work = Path(tmp)
        sdf = None
        if not args.zero_delay:
            sdf = work / "icarus.sdf"
            sdf_for_icarus(run / "final" / "sdf" / corner / f"kf_top__{corner}.sdf", sdf)
        for tag, script in (("active", script_active(args.iterations)), ("idle", script_idle(args.idle))):
            vcd, cycles, iters = simulate(run, cfg, script, work, tag, sdf)
            g = sta_power(run, cfg, vcd, work, tag)
            results[tag] = {"cycles": cycles, "iterations": iters, "power_w": g["Total"][3],
                            "sequential_w": g["Sequential"][3], "combinational_w": g["Combinational"][3],
                            "clock_w": g["Clock"][3], "leakage_w": g["Total"][2]}

    a, i = results["active"], results["idle"]
    t_iter = a["cycles"] / a["iterations"] * period * 1e-9
    a["energy_per_iteration_j"] = a["power_w"] * t_iter
    mode = "zero-delay activity (no glitches)" if args.zero_delay else "SDF-annotated activity"
    print(f"clock {period:g} ns, typical corner, {mode}")
    print(f"active: {a['iterations']} iterations in {a['cycles']} cycles "
          f"({a['cycles'] / a['iterations']:.1f} cycles/iteration incl. host writes)")
    print(f"  power {a['power_w'] * 1e3:.3f} mW = sequential {a['sequential_w'] * 1e3:.3f} + "
          f"combinational {a['combinational_w'] * 1e3:.3f} + clock {a['clock_w'] * 1e3:.3f} mW")
    print(f"  energy per iteration {a['energy_per_iteration_j'] * 1e9:.2f} nJ")
    print(f"idle:   power {i['power_w'] * 1e6:.1f} uW (clock {i['clock_w'] * 1e6:.1f} uW, "
          f"leakage {i['leakage_w'] * 1e6:.2f} uW)")
    if args.json:
        Path(args.json).write_text(json.dumps(results, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
