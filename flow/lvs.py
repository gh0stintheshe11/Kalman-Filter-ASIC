"""Transistor-level LVS with IHP's KLayout deck (libs.tech/klayout/tech/lvs).

    python flow/lvs.py GDS PNL TOP --pdk PDK_DIR --workdir DIR

The layout is extracted from the GDS down to the transistors of every
standard cell; the schematic is the run's powered netlist (final/pnl)
converted to SPICE against the PDK's CDL netlists (flow/v2spice.py).  Run
with a Python that has the klayout module and docopt (e.g. LibreLane's).
Exits 0 if the netlists match; otherwise lists what does not
(flow/lvs_report.py).

Used for the core macro.  At chip level the deck does not match the cells
of the IHP I/O library (their ESD devices and substrate pin are extracted
differently from their CDL); the chip's LVS is the flow's Netgen LVS.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import v2spice  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("gds", type=Path)
    ap.add_argument("pnl", type=Path)
    ap.add_argument("top")
    ap.add_argument("--pdk", type=Path, required=True)
    ap.add_argument("--workdir", type=Path, required=True)
    args = ap.parse_args(argv)

    work = args.workdir.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    cdls = [str(args.pdk / "libs.ref" / "sg13g2_stdcell" / "cdl" / "sg13g2_stdcell.cdl"),
            str(args.pdk / "libs.ref" / "sg13g2_io" / "cdl" / "sg13g2_io.cdl")]
    spice = work / f"{args.top}.spice"
    spice.write_text(v2spice.convert(str(args.pnl), args.top, cdls))
    run = work / "run"
    deck = args.pdk / "libs.tech" / "klayout" / "tech" / "lvs"
    cmd = [sys.executable, str(deck / "run_lvs.py"), f"--layout={args.gds.resolve()}",
           f"--netlist={spice}", f"--topcell={args.top}", f"--run_dir={run}"]
    print(" ".join(cmd), flush=True)
    subprocess.run(cmd, check=False)
    log = run / f"{args.top}.log"
    if log.exists() and "Congratulations! Netlists match." in log.read_text():
        print(f"LVS CLEAN: the layout of {args.top} matches its netlist")
        return 0
    print("LVS FAILED")
    lvsdb = run / f"{args.top}.lvsdb"
    if lvsdb.exists():
        subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "lvs_report.py"),
                        str(lvsdb), "--max", "10"])
    return 1


if __name__ == "__main__":
    sys.exit(main())
