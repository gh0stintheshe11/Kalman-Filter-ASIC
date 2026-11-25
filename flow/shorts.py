"""Connectivity check of the chip's pad ring on the full layout (KLayout).

    python flow/shorts.py CHIP.gds CHIP.pnl.v [--top kf_chip]

Run with a Python that has the klayout module (e.g. LibreLane's).  Exits 0
if every check passes.

Why: the flow's chip LVS (Netgen) compares Magic's extraction, in which the
I/O cells are their LEF abstracts.  The abstracts' obstructions hide the
cells' metal, so Magic cannot see what the core ring's straps and the
routes that reach into the I/O cells touch there (it reports the crossings
as illegal overlaps), and it joins the two pads of each supply by name
(MAGIC_EXT_UNIQUE notopports), not by connection.  This check extracts the
interconnect of the complete GDS -- Metal1 to TopMetal2 with vias, pin
shapes and fill, every I/O cell in full -- and verifies:

1. no net carries two different labels (no short between pads or
   supplies);
2. each top-level label is on exactly one net (the pads of a supply are
   connected inside the chip);
3. the I/O cells' pins are where the netlist puts them: the pad pin on its
   port, vdd/vss/iovdd/iovss on VDD/VSS/IOVDD/IOVSS, and every core-side
   pin (c2p, c2p_en, p2c) on a net of its own that reaches exactly the
   standard-cell pins the netlist connects to it (the netlist's cells;
   the router's vias are cells in the GDS too);
4. metal that an I/O cell does not label (pieces of the I/O ring's rails,
   joined to the rest by abutment) is reached from outside the cell only
   on the I/O supplies, never on a core supply, a signal or a pad: a core
   ring strap or a route touching an unlabelled part of a cell would
   show up here.
"""

from __future__ import annotations

import argparse
import collections
import re
import sys

import klayout.db as db

# IHP SG13G2 GDS layers: metals (drawing 0, pin 2, fill 22, text 25) and vias
METALS = [("Metal1", 8), ("Metal2", 10), ("Metal3", 30), ("Metal4", 50), ("Metal5", 67),
          ("TopMetal1", 126), ("TopMetal2", 134)]
VIAS = [("Via1", 19), ("Via2", 29), ("Via3", 49), ("Via4", 66), ("TopVia1", 125), ("TopVia2", 133)]
SUPPLIES = {"vdd": "VDD", "vss": "VSS", "iovdd": "IOVDD", "iovss": "IOVSS"}
IO_SUPPLIES = {"IOVDD", "IOVSS"}
IO_PREFIX = "sg13g2_IOPad"


def extract(gds: str, top_name: str):
    """Extract the interconnect; returns (layout, l2n), which own the netlist."""
    ly = db.Layout()
    ly.read(gds)
    top = ly.cell(top_name)
    l2n = db.LayoutToNetlist(db.RecursiveShapeIterator(ly, top, []))
    l2n.threads = 4

    def layer(num: int, dt: int, name: str, text: bool = False):
        li = ly.find_layer(num, dt)
        if li is None:
            return None
        return l2n.make_text_layer(li, name) if text else l2n.make_polygon_layer(li, name)

    stack = []
    for name, num in METALS:
        parts = [p for p in (layer(num, dt, f"{name}_{dt}") for dt in (0, 2, 22)) if p is not None]
        for i, a in enumerate(parts):
            l2n.connect(a)
            for b in parts[i + 1:]:
                l2n.connect(a, b)
        text = layer(num, 25, f"{name}_text", text=True)
        if text is not None:
            for p in parts:
                l2n.connect(p, text)
        stack.append(parts)
    for i, (name, num) in enumerate(VIAS):
        via = layer(num, 0, name)
        if via is None:
            continue
        l2n.connect(via)
        for p in stack[i] + stack[i + 1]:
            l2n.connect(via, p)
    l2n.extract_netlist()
    return ly, l2n


def names(net) -> set[str]:
    return {n for n in (net.name or "").split(",") if n}


def parse_netlist(pnl: str) -> tuple[dict, dict]:
    """Instances {name: (cell, {pin: net})} and nets {net: [(cell, pin)]}."""
    text = re.sub(r"//[^\n]*", "", open(pnl).read())
    insts, nets = {}, collections.defaultdict(list)
    for m in re.finditer(r"^\s*(sg13g2_\w+|bondpad\w*)\s+(\\\S+|\w+)\s*\((.*?)\);", text, re.M | re.S):
        cell, inst, body = m.groups()
        conns = {p: n.strip().lstrip("\\").strip() for p, n in re.findall(r"\.(\w+)\(([^()]*)\)", body)}
        insts[inst.lstrip("\\")] = (cell, conns)
        for p, n in conns.items():
            if n:
                nets[n].append((cell, p))
    return insts, nets


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("gds")
    ap.add_argument("pnl")
    ap.add_argument("--top", default="kf_chip")
    args = ap.parse_args(argv)

    insts, sch_nets = parse_netlist(args.pnl)
    ly, l2n = extract(args.gds, args.top)
    nl = l2n.netlist()
    top = nl.circuit_by_name(args.top)
    errors: list[str] = []

    # 1. no net with two different labels, in any circuit
    for c in nl.each_circuit():
        for net in c.each_net():
            if len(names(net)) > 1:
                errors.append(f"short in {c.name}: one net carries the labels {sorted(names(net))}")

    # 2. every top-level label on exactly one net
    by_label = collections.defaultdict(list)
    for net in top.each_net():
        for n in names(net):
            by_label[n].append(net)
    for label, nets in sorted(by_label.items()):
        if len(nets) != 1:
            errors.append(f"open: label {label} is on {len(nets)} separate nets")
    ports = sorted(by_label)

    # 3. I/O cell pins, matched to the netlist by the port on their pad pin
    sch_cells = {cell for cell, _ in insts.values()}
    sch_io = {name: (cell, conns) for name, (cell, conns) in insts.items() if cell.startswith(IO_PREFIX)}
    sch_by_port = {conns["pad"]: (name, cell, conns) for name, (cell, conns) in sch_io.items() if "pad" in conns}
    sch_supply_pads = collections.Counter(cell for cell, conns in sch_io.values() if "pad" not in conns)
    lay_supply_pads = collections.Counter()
    core_side = 0
    unlabelled = collections.Counter()
    for sc in top.each_subcircuit():
        cell = sc.circuit_ref()
        if not cell.name.startswith(IO_PREFIX):
            continue
        pins = {p.expanded_name(): sc.net_for_pin(p.id()) for p in cell.each_pin()}
        pad_net = pins.get("pad")
        if pad_net is None:
            lay_supply_pads[cell.name] += 1
            inst = f"{cell.name} (supply pad)"
            sch_conns = None
        else:
            port = ",".join(sorted(names(pad_net))) or pad_net.expanded_name()
            if port not in sch_by_port:
                errors.append(f"{cell.name}: pad pin on {port}, which no I/O cell drives in the netlist")
                continue
            inst, sch_cell, sch_conns = sch_by_port[port]
            if sch_cell != cell.name:
                errors.append(f"{inst}: {cell.name} in the layout, {sch_cell} in the netlist")
        for pin, net in sorted(pins.items()):
            base = pin.split("$")[0]
            got = ",".join(sorted(names(net))) if net is not None and names(net) else None
            if pin == "pad":
                continue
            if base in SUPPLIES:
                if got != SUPPLIES[base]:
                    errors.append(f"{inst}: pin {pin} on {got or 'an unlabelled net'}, expected {SUPPLIES[base]}")
            elif pin.startswith("$"):                 # unlabelled metal of the cell
                unlabelled[(cell.name, got)] += 1
                if got not in IO_SUPPLIES:
                    errors.append(f"{inst}: unlabelled metal of the cell reached on "
                                  f"{got or 'an unlabelled net'} from outside")
            else:                                     # core-side pin
                core_side += 1
                if net is None or sch_conns is None or pin not in sch_conns:
                    errors.append(f"{inst}: core-side pin {pin} not in the netlist")
                    continue
                if got is not None:
                    errors.append(f"{inst}: core-side pin {pin} on the labelled net {got}")
                lay = collections.Counter()
                for ref in net.each_subcircuit_pin():
                    c = ref.subcircuit().circuit_ref()
                    if c.name in sch_cells:               # not the router's via cells
                        lay[(c.name, ref.pin().expanded_name())] += 1
                sch = collections.Counter(sch_nets[sch_conns[pin]])
                if lay != sch:
                    errors.append(f"{inst}.{pin} (net {sch_conns[pin]}): layout reaches "
                                  f"{dict(lay - sch)} more and {dict(sch - lay)} less than the netlist")
    if lay_supply_pads != sch_supply_pads:
        errors.append(f"supply pads: layout {dict(lay_supply_pads)}, netlist {dict(sch_supply_pads)}")
    missing = set(sch_by_port) - set(by_label)
    if missing:
        errors.append(f"ports without a label in the layout: {sorted(missing)}")

    n_io = sum(lay_supply_pads.values()) + len(sch_by_port)
    print(f"{args.top}: {len(ports)} labelled top-level nets ({', '.join(ports)})")
    print(f"I/O cells: {n_io}; core-side pins checked: {core_side}; "
          f"unlabelled cell metal reached from outside: "
          + (", ".join(f"{n}x {c} on {net}" for (c, net), n in sorted(unlabelled.items(), key=str)) or "none"))
    for e in errors:
        print("ERROR:", e)
    if errors:
        print(f"PAD RING CHECK FAILED: {len(errors)} errors")
        return 1
    print("PAD RING CHECK CLEAN: no shorts or opens between labelled nets; "
          "every I/O cell pin on its net")
    return 0


if __name__ == "__main__":
    sys.exit(main())
