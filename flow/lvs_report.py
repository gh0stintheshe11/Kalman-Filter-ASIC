"""Summarize a KLayout LVS database (.lvsdb): per circuit pair the match
status, and for every mismatching circuit the pins, nets, devices and
subcircuits that are unmatched (layout side / schematic side).

    python flow/lvs_report.py RUN_DIR/kf_chip.lvsdb [--max 20]

Needs the klayout Python module (e.g. LibreLane's environment).  Exits 0 if
the netlists match.
"""

import argparse
import sys

import klayout.db as db


def name(obj):
    if obj is None:
        return "-"
    n = obj.expanded_name() if hasattr(obj, "expanded_name") else obj.name
    return n or "(unnamed)"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("lvsdb")
    ap.add_argument("--max", type=int, default=20, help="entries to list per category")
    args = ap.parse_args(argv)

    lvs = db.LayoutVsSchematic()
    lvs.read(args.lvsdb)
    xref = lvs.xref()
    status_name = {db.NetlistCrossReference.Match: "match",
                   db.NetlistCrossReference.MatchWithWarning: "match (warning)",
                   db.NetlistCrossReference.Mismatch: "MISMATCH",
                   db.NetlistCrossReference.NoMatch: "NO MATCH",
                   db.NetlistCrossReference.Skipped: "skipped",
                   db.NetlistCrossReference.None_: "-"}
    bad = 0
    for pair in xref.each_circuit_pair():
        st = pair.status()
        a, b = pair.first(), pair.second()
        if st in (db.NetlistCrossReference.Match, db.NetlistCrossReference.MatchWithWarning):
            continue
        bad += 1
        print(f"circuit layout={name(a)} schematic={name(b)}: {status_name.get(st, st)}")
        if a is None or b is None:
            continue
        for what, it in (("pin", xref.each_pin_pair), ("net", xref.each_net_pair),
                         ("device", xref.each_device_pair), ("subcircuit", xref.each_subcircuit_pair)):
            rows = [p for p in it(pair) if p.status() not in (db.NetlistCrossReference.Match,
                                                               db.NetlistCrossReference.MatchWithWarning)]
            if not rows:
                continue
            print(f"  {len(rows)} unmatched {what}s:")
            for p in rows[: args.max]:
                f, s = p.first(), p.second()
                extra = ""
                if what == "subcircuit":
                    cf = f.circuit_ref().name if f is not None else "-"
                    cs = s.circuit_ref().name if s is not None else "-"
                    extra = f"  [{cf} / {cs}]"
                print(f"    layout {name(f):40s} schematic {name(s):40s} {status_name.get(p.status(), p.status())}{extra}")
    print("netlists match" if bad == 0 else f"{bad} circuit(s) do not match")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
