"""Convert a powered structural Verilog netlist (LibreLane's final/pnl) into a
SPICE netlist for KLayout LVS against the foundry deck.

    python flow/v2spice.py NETLIST.pnl.v TOP OUT.spice CDL [CDL ...]

Every instance becomes an X line with its nets in the pin order of the
cell's .SUBCKT in the CDL files (the standard cells and the I/O cells), and
the CDL files are included.  Cells without a CDL definition (the bond pads,
metal only) get an empty subcircuit with the pins they are connected by.
Unconnected pins get a net of their own.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def subckt_pins(cdl_files: list[str]) -> dict[str, list[str]]:
    """Pin order of every .SUBCKT in the CDL files."""
    pins: dict[str, list[str]] = {}
    for f in cdl_files:
        text = Path(f).read_text().replace("\n+", " ")
        for m in re.finditer(r"^\.subckt\s+(\S+)\s+([^\n]*)$", text, re.M | re.I):
            pins[m.group(1)] = m.group(2).split()
    return pins


def net(name: str) -> str:
    """Verilog net -> SPICE net (escaped identifiers lose the backslash)."""
    return name.strip().lstrip("\\").strip()


def convert(netlist: str, top: str, cdl_files: list[str]) -> str:
    text = Path(netlist).read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    mod = re.search(rf"\bmodule\s+{re.escape(top)}\s*\((.*?)\);(.*?)\bendmodule", text, re.S)
    if not mod:
        raise SystemExit(f"module {top} not found in {netlist}")
    ports_decl, body = mod.groups()
    # ports, with buses expanded
    widths: dict[str, tuple[int, int]] = {}
    for m in re.finditer(r"\b(?:input|output|inout)\s+(?:wire\s+)?(?:\[(\d+):(\d+)\]\s*)?([^;]+);",
                         body):
        for name in m.group(3).split(","):
            if m.group(1) is not None:
                widths[name.strip()] = (int(m.group(1)), int(m.group(2)))
            else:
                widths[name.strip()] = None
    ports = []
    for p in re.split(r"\s*,\s*", ports_decl.strip()):
        p = p.strip()
        if not p:
            continue
        w = widths.get(p)
        if w is None:
            ports.append(p)
        else:
            hi, lo = w
            step = -1 if hi >= lo else 1
            ports += [f"{p}[{i}]" for i in range(hi, lo + step, step)]

    pins = subckt_pins(cdl_files)
    extra: dict[str, list[str]] = {}
    lines = [f"* {top}: from {Path(netlist).name} by flow/v2spice.py",
             *[f".INCLUDE '{Path(f).resolve()}'" for f in cdl_files], "",
             f".SUBCKT {top} " + " ".join(ports)]
    unconnected = 0
    inst_re = re.compile(r"^\s*(\w+)\s+(\\\S+|\w+)\s*\((.*?)\)\s*;", re.M | re.S)
    for m in inst_re.finditer(body):
        cell, inst, conns = m.groups()
        if cell in ("wire", "input", "output", "inout", "assign", "reg"):
            continue
        conn = {p: net(n) for p, n in re.findall(r"\.(\w+)\s*\(\s*(\\\S+\s|[^()]*?)\s*\)", conns)}
        order = pins.get(cell)
        if order is None:                       # metal-only cell (bond pad)
            order = extra.setdefault(cell, sorted(conn))
        nets = []
        for p in order:
            n = conn.get(p, "")
            if not n:
                unconnected += 1
                n = f"__nc{unconnected}"
            nets.append(n)
        lines.append(f"X{net(inst)} " + " ".join(nets) + f" {cell}")
    lines.append(f".ENDS {top}")
    for cell, order in extra.items():
        lines += ["", f".SUBCKT {cell} " + " ".join(order), f".ENDS {cell}"]
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 5:
        print(__doc__)
        return 2
    netlist, top, out, *cdls = argv[1:]
    Path(out).write_text(convert(netlist, top, cdls))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
