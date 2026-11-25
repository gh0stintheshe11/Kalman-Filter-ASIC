#!/usr/bin/env python3
"""Summarize a LibreLane run as a Markdown signoff table.

    python flow/summary.py flow/ihp-sg13g2/runs/main
"""

import json
import sys
from pathlib import Path


def fanout_note(run: Path, total) -> str:
    """Max fanout is a soft guideline; say how many offenders are clock-tree
    buffers (sized by CTS for slew/skew, which are checked separately)."""
    rpts = sorted(run.glob("*-openroad-stapostpnr/*typ*/checks.rpt"))
    if not rpts:
        return str(total)
    clk = other = 0
    in_section = False
    for line in rpts[-1].read_text().splitlines():
        if line.strip() == "max fanout":
            in_section = True
        elif in_section and "violation count" in line:
            break
        elif in_section and "VIOLATED" in line:
            if line.split()[0].startswith("clkbuf"):
                clk += 1
            else:
                other += 1
    return f"{clk + other} ({clk} clock-tree buffers, {other} data net{'s' if other != 1 else ''})"


def main(run_dir: str) -> int:
    run = Path(run_dir)
    m = json.loads((run / "final" / "metrics.json").read_text())
    cfg = json.loads((run / "resolved.json").read_text())
    period = float(cfg["CLOCK_PERIOD"])

    def g(key, default="n/a"):
        return m.get(key, default)

    corners = sorted({k.split(":", 1)[1] for k in m if k.startswith("timing__setup__ws__corner:")})
    rows = [
        ("PDK / cell library", f"{cfg['PDK']} / {cfg['STD_CELL_LIBRARY']}"),
        ("Clock", f"{period:g} ns ({1000 / period:.0f} MHz)"),
        ("Die area", f"{float(g('design__die__area', 0)) / 1e6:.4f} mm²"),
        ("Core utilization", f"{100 * float(g('design__instance__utilization', 0)):.1f} %"),
        ("Standard cells (incl. fill/tap)", g("design__instance__count")),
        ("Standard-cell area", f"{float(g('design__instance__area__stdcell', g('design__instance__area', 0))):,.0f} µm²"),
    ]
    for c in corners:
        rows.append((f"Setup / hold WNS @ {c}",
                     f"{m[f'timing__setup__ws__corner:{c}']:+.2f} / {m[f'timing__hold__ws__corner:{c}']:+.2f} ns"))
    rows += [
        ("Setup / hold violations (all corners)",
         f"{g('timing__setup_vio__count')} / {g('timing__hold_vio__count')}"),
        ("Max slew / max cap violations (all corners)",
         f"{g('design__max_slew_violation__count')} / {g('design__max_cap_violation__count')}"),
        ("Nets above the max-fanout guideline", fanout_note(run, g("design__max_fanout_violation__count"))),
        ("Routing DRC (OpenROAD)", g("route__drc_errors")),
        ("Magic DRC", g("magic__drc_error__count")),
        ("KLayout DRC", g("klayout__drc_error__count")),
        ("LVS errors (Netgen)", g("design__lvs_error__count")),
        ("Antenna violating nets", g("antenna__violating__nets")),
        ("Magic vs KLayout GDS XOR differences", g("design__xor_difference__count")),
        ("Worst IR drop", f"{1000 * float(g('ir__drop__worst', 0)):.2f} mV"),
        ("Total power (typical)", f"{1000 * float(g('power__total', 0)):.3f} mW"),
    ]
    width = max(len(r[0]) for r in rows)
    print(f"| {'Metric'.ljust(width)} | Value |\n|{'-' * (width + 2)}|-------|")
    for k, v in rows:
        print(f"| {k.ljust(width)} | {v} |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "flow/ihp-sg13g2/runs/main"))
