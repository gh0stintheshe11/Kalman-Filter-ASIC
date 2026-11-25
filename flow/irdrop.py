"""Static IR drop of a LibreLane run with OpenROAD's PDNSim, with the supply
entering where it really does and with a stated switching activity.

    python flow/irdrop.py RUN_DIR [--activity 0.2]

OpenROAD is taken from $OPENROAD (default `openroad` on PATH), e.g.
    OPENROAD="$HOME/tools/librelane/squashfs-root/AppRun -- openroad"

LibreLane's IRDropReport step is optimistic for a wire-bonded chip on two
counts: PDNSim spreads the supply over the top metal like flip-chip bumps,
and the currents come from OpenSTA's vectorless default activity, which in
this clock-gated design is about the idle power.  This script

* places the voltage sources where the supply enters the core's power grid:
  the outer ends of the straps that join the core ring to the I/O cells'
  supply pins (the I/O ring's rails, fed by the supply pads, are taken as
  ideal).  Without such straps (a macro), PDNSim's default sources are
  kept;
* gives every net the same switching activity (default 0.2 per cycle);
  the total power is printed, to compare with the measured power;
* uses the run's typical-corner libraries, layer resistances (LAYERS_RC),
  constraints and extracted parasitics, in the order LibreLane uses them.
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


def supply_nets(cfg: dict, def_text: str) -> list[tuple[str, bool]]:
    """[(net, is_power)] from VDD_NETS/GND_NETS, else the DEF's special nets."""
    if cfg.get("VDD_NETS") and cfg.get("GND_NETS"):
        return [(n, True) for n in cfg["VDD_NETS"]] + [(n, False) for n in cfg["GND_NETS"]]
    sn = def_text[def_text.index("SPECIALNETS"):def_text.index("END SPECIALNETS")]
    nets = []
    for m in re.finditer(r"^\s*- (\S+) .*?\+ USE (POWER|GROUND)", sn, re.M | re.S):
        body = sn[m.start():sn.index(" ;\n", m.start())]
        if "+ SHAPE STRIPE" in body:
            nets.append((m.group(1), m.group(2) == "POWER"))
    return nets


def pad_straps(def_text: str, net: str) -> list[tuple[float, float]]:
    """Outer ends (2 um inside) of the net's stripes that leave its core ring."""
    dbu = float(re.search(r"UNITS DISTANCE MICRONS (\d+)", def_text).group(1))
    sn = def_text[def_text.index("SPECIALNETS"):def_text.index("END SPECIALNETS")]
    start = sn.index(f"- {net} ")
    body = sn[start:sn.index(" ;\n", start)]
    segs = []
    for layer, w, shape, x0, y0, x1, y1 in re.findall(
            r"(?:ROUTED|NEW) (\w+) (\d+) \+ SHAPE (\w+) \( (-?\d+) (-?\d+) \) \( (\S+) (\S+) \)", body):
        x0, y0 = int(x0) / dbu, int(y0) / dbu
        x1 = x0 if x1 == "*" else int(x1) / dbu
        y1 = y0 if y1 == "*" else int(y1) / dbu
        segs.append((shape, int(w) / dbu, x0, y0, x1, y1))
    ring = [s for s in segs if s[0] == "RING"]
    if not ring:
        return []
    half = max(s[1] for s in ring) / 2
    rx0 = min(min(s[2], s[4]) for s in ring) - half
    rx1 = max(max(s[2], s[4]) for s in ring) + half
    ry0 = min(min(s[3], s[5]) for s in ring) - half
    ry1 = max(max(s[3], s[5]) for s in ring) + half
    ends = []
    for shape, _, x0, y0, x1, y1 in segs:
        if shape != "STRIPE":
            continue
        if y0 == y1 and min(x0, x1) < rx0:
            ends.append((min(x0, x1) + 2, y0))
        elif y0 == y1 and max(x0, x1) > rx1:
            ends.append((max(x0, x1) - 2, y0))
        elif x0 == x1 and min(y0, y1) < ry0:
            ends.append((x0, min(y0, y1) + 2))
        elif x0 == x1 and max(y0, y1) > ry1:
            ends.append((x0, max(y0, y1) - 2))
    return ends


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run", type=Path)
    ap.add_argument("--activity", type=float, default=0.2,
                    help="switching activity of every net, per clock cycle (default 0.2)")
    args = ap.parse_args(argv)

    run = args.run.resolve()
    cfg = json.loads((run / "resolved.json").read_text())
    design = cfg["DESIGN_NAME"]
    corner = cfg["DEFAULT_CORNER"]
    libs = next(v for k, v in cfg["LIB"].items() if re.fullmatch(k.replace("*", ".*"), corner))
    rc = cfg.get("LAYERS_RC") or {}
    rc = next((v for k, v in rc.items() if re.fullmatch(k.replace("*", ".*"), corner)), {})
    def_text = (run / "final" / "def" / f"{design}.def").read_text()
    voltage = float(re.search(r"nom_voltage\s*:\s*([\d.]+)", Path(libs[0]).read_text()).group(1))

    work = Path(tempfile.mkdtemp(prefix="irdrop_"))
    tcl = [f"read_db {run / 'final' / 'odb' / f'{design}.odb'}"]
    tcl += [f"read_liberty {lib}" for lib in libs]
    tcl += [f"read_sdc {run / 'final' / 'sdc' / f'{design}.sdc'}"]
    tcl += [f"set_layer_rc -layer {layer} -resistance {v['res']} -capacitance {v['cap']}"
            for layer, v in rc.items()]
    tcl += [f"read_spef {run / 'final' / 'spef' / 'nom' / f'{design}.nom.spef'}",
            f"set_power_activity -global -activity {args.activity} -duty 0.5",
            "report_power"]
    sources = {}
    for net, power in supply_nets(cfg, def_text):
        v = voltage if power else 0.0
        ends = pad_straps(def_text, net)
        sources[net] = len(ends)
        if ends:
            loc = work / f"{net}.loc"
            loc.write_text("".join(f"{x:.3f}, {y:.3f}, 2, {v}\n" for x, y in ends))
            tcl.append(f"analyze_power_grid -net {net} -vsrc {loc}")
        else:
            tcl += [f"set_pdnsim_net_voltage -net {net} -voltage {v}", f"analyze_power_grid -net {net}"]
    script = work / "irdrop.tcl"
    script.write_text("\n".join(tcl) + "\n")
    openroad = shlex.split(os.environ.get("OPENROAD", "openroad"))
    res = subprocess.run([*openroad, "-no_splash", "-exit", str(script)], capture_output=True, text=True)
    out = res.stdout + res.stderr
    (work / "irdrop.log").write_text(out)
    reports = re.findall(r"Net\s+:\s+(\S+).*?Total power\s+:\s+(\S+) W.*?Average IR drop\s+:\s+(\S+) V"
                         r".*?Worstcase IR drop:\s+(\S+) V", out, re.S)
    if res.returncode != 0 or len(reports) != len(sources):
        print(out[-3000:])
        print(f"IR DROP ANALYSIS FAILED (log: {work / 'irdrop.log'})")
        return 1
    print(f"{design}: typical corner, {voltage:g} V, every net switching {args.activity:g} per cycle")
    for net, power, avg, worst in reports:
        where = (f"{sources[net]} pad straps" if sources[net] else "PDNSim's default sources")
        print(f"  {net:6s} total power {float(power) * 1e3:6.2f} mW, supply at {where}: "
              f"worst IR drop {float(worst) * 1e3:6.2f} mV ({100 * float(worst) / voltage:.2f} % of "
              f"{voltage:g} V), average {float(avg) * 1e3:.2f} mV")
    print(f"(log: {work / 'irdrop.log'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
