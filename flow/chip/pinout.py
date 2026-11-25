"""Pinout / bonding diagram of the chip from its DEF.

    python flow/chip/pinout.py RUN_DIR/final/def/kf_chip.def --png docs/img/pinout.png

Draws the die, the seal-ring margin, the I/O ring with every pad cell and
its bond pad, and the core area, and prints a Markdown table of the bond
pads: pad number (counter-clockwise from the lower-left corner, as on a
bonding diagram), side, signal, I/O cell and bond-pad center in µm from
the die's lower-left corner.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

PAD_W, PAD_H = 80.0, 180.0          # sg13g2_io pad cells
CORNER = 180.0
BOND = 70.0                         # flow/chip/bondpad_70x70


def parse(def_path: str):
    text = Path(def_path).read_text()
    dbu = float(re.search(r"UNITS DISTANCE MICRONS (\d+)", text).group(1))
    x0, y0, x1, y1 = (float(v) / dbu for v in
                      re.search(r"DIEAREA \( (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) \)", text).groups())
    comps = {}
    for m in re.finditer(r"^\s*- (\S+) (\S+) \+ (?:FIXED|PLACED) \( (-?\d+) (-?\d+) \) (\w+)", text, re.M):
        name, cell, x, y, orient = m.groups()
        if cell.startswith(("sg13g2_IOPad", "sg13g2_Corner")) or name.startswith("IO_BOND_"):
            comps[name] = (cell, float(x) / dbu, float(y) / dbu, orient)
    return (x0, y0, x1, y1), comps


def footprint(cell: str, x: float, y: float, orient: str):
    if cell == "sg13g2_Corner":
        w = h = CORNER
    elif cell.startswith("sg13g2_IOPad"):
        w, h = (PAD_W, PAD_H) if orient in ("N", "S", "FN", "FS") else (PAD_H, PAD_W)
    else:
        w = h = BOND
    return x, y, w, h


def signal(inst: str) -> str:
    base = re.sub(r"_pad(_[nsew])?$", "", inst)
    return base.upper() if base in ("vdd", "vss", "iovdd", "iovss") else base


def kind(cell: str) -> str:
    if cell in ("sg13g2_IOPadVdd", "sg13g2_IOPadVss"):
        return "core supply"
    if cell in ("sg13g2_IOPadIOVdd", "sg13g2_IOPadIOVss"):
        return "I/O supply"
    if cell == "sg13g2_IOPadIn":
        return "input"
    return "output"


COLORS = {"core supply": "#d62728", "I/O supply": "#9467bd", "input": "#1f77b4", "output": "#ff7f0e"}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("def_file")
    ap.add_argument("--png")
    ap.add_argument("--core", default="365,365,1035,1035", help="core area x0,y0,x1,y1 in µm")
    args = ap.parse_args(argv)

    (dx0, dy0, dx1, dy1), comps = parse(args.def_file)
    cx, cy = (dx0 + dx1) / 2, (dy0 + dy1) / 2
    pads = []
    for inst, (cell, x, y, orient) in comps.items():
        if not cell.startswith("sg13g2_IOPad"):
            continue
        bond = comps.get(f"IO_BOND_{inst}")
        bx, by = (bond[1] + BOND / 2, bond[2] + BOND / 2) if bond else (None, None)
        px, py, w, h = footprint(cell, x, y, orient)
        mx, my = px + w / 2 - cx, py + h / 2 - cy
        side = ("S" if abs(my) > abs(mx) and my < 0 else "N" if abs(my) > abs(mx)
                else "W" if mx < 0 else "E")
        pads.append(dict(inst=inst, cell=cell, side=side, bx=bx, by=by, box=(px, py, w, h)))

    # bonding-diagram numbering: counter-clockwise from the lower-left corner
    order = {"S": 0, "E": 1, "N": 2, "W": 3}
    key = {"S": lambda p: p["bx"], "E": lambda p: p["by"],
           "N": lambda p: -p["bx"], "W": lambda p: -p["by"]}
    pads.sort(key=lambda p: (order[p["side"]], key[p["side"]](p)))
    side_name = {"S": "south", "E": "east", "N": "north", "W": "west"}
    print("| # | Side | Signal | I/O cell | Bond pad center (µm) |")
    print("|---|---|---|---|---|")
    for i, p in enumerate(pads, 1):
        print(f"| {i} | {side_name[p['side']]} | {signal(p['inst'])} | `{p['cell']}` | "
              f"({p['bx']:.0f}, {p['by']:.0f}) |")

    if args.png:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.patches import Patch, Rectangle

        fig, ax = plt.subplots(figsize=(8, 8))
        ax.add_patch(Rectangle((dx0, dy0), dx1 - dx0, dy1 - dy0, fill=False, lw=2, ec="black"))
        m = 70.0                                   # seal ring margin outside the bond pads
        ax.add_patch(Rectangle((dx0, dy0), dx1 - dx0, dy1 - dy0, fc="#cccccc", ec="none"))
        ax.add_patch(Rectangle((dx0 + m, dy0 + m), dx1 - dx0 - 2 * m, dy1 - dy0 - 2 * m, fc="white", ec="none"))
        ring0, ring1 = 140.0, 140.0 + PAD_H        # I/O ring (fillers between the pads)
        ax.add_patch(Rectangle((ring0, ring0), dx1 - 2 * ring0, dy1 - 2 * ring0, fc="#eeeeee", ec="#999999"))
        ax.add_patch(Rectangle((ring1, ring1), dx1 - 2 * ring1, dy1 - 2 * ring1, fc="white", ec="#999999"))
        c = [float(v) for v in args.core.split(",")]
        ax.add_patch(Rectangle((c[0], c[1]), c[2] - c[0], c[3] - c[1], fc="#e8f4e8", ec="#2ca02c", lw=1.5))
        ax.text((c[0] + c[2]) / 2, (c[1] + c[3]) / 2,
                f"core\n{c[2] - c[0]:.0f} × {c[3] - c[1]:.0f} µm\nkf_top + SPI slave",
                ha="center", va="center", fontsize=11, color="#2ca02c")
        for inst, (cell, x, y, orient) in comps.items():
            if cell == "sg13g2_Corner":
                ax.add_patch(Rectangle((x, y), CORNER, CORNER, fc="#bbbbbb", ec="#777777"))
        for i, p in enumerate(pads, 1):
            px, py, w, h = p["box"]
            col = COLORS[kind(p["cell"])]
            ax.add_patch(Rectangle((px, py), w, h, fc=col, alpha=0.35, ec=col))
            ax.add_patch(Rectangle((p["bx"] - BOND / 2, p["by"] - BOND / 2), BOND, BOND,
                                   fc="#d4af37", ec="#8a6d00"))
            ax.text(p["bx"], p["by"], str(i), ha="center", va="center", fontsize=8, weight="bold")
            # label on the core side of the pad cell
            lx, ly = px + w / 2, py + h / 2
            rot = 90 if p["side"] in ("N", "S") else 0
            ax.text(lx, ly, signal(p["inst"]), ha="center", va="center", fontsize=8, rotation=rot)
        ax.legend(handles=[Patch(fc=v, alpha=0.5, label=k) for k, v in COLORS.items()]
                  + [Patch(fc="#d4af37", label="bond pad 70 × 70 µm"),
                     Patch(fc="#cccccc", label="seal ring margin")],
                  loc="upper center", bbox_to_anchor=(0.5, -0.07), ncol=3, fontsize=8, frameon=False)
        ax.set_xlim(dx0 - 20, dx1 + 20)
        ax.set_ylim(dy0 - 20, dy1 + 20)
        ax.set_aspect("equal")
        ax.set_xlabel("µm")
        ax.set_title(f"kf_chip pinout: {dx1 - dx0:.0f} × {dy1 - dy0:.0f} µm die, IHP SG13G2, "
                     f"{len(pads)} pads (numbered counter-clockwise)", fontsize=10)
        fig.tight_layout()
        fig.savefig(args.png, dpi=150)
        print(f"\nwrote {args.png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
