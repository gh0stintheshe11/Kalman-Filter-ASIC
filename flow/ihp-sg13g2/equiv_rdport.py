#!/usr/bin/env python3
"""Prove that kf_rdport_ihp.v (cells) implements rtl/kf_rdport.v.

Builds a miter of the behavioral read port and the cell-level IHP version
(with the PDK's Verilog models of the cells it uses) and has Yosys' SAT
solver prove that the outputs are equal for every address and register
contents:

    python flow/ihp-sg13g2/equiv_rdport.py <IHP sg13g2_stdcell.v>

`make equiv` takes the cell-model path from a LibreLane run.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CELLS = ("sg13g2_a22oi_1", "sg13g2_nand4_1", "sg13g2_or4_1")


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 2
    models = Path(argv[0]).read_text()
    with tempfile.TemporaryDirectory(prefix="kf_equiv_") as tmp:
        work = Path(tmp)
        cells = []
        for c in CELLS:
            m = re.search(rf"^module {c} .*?^endmodule", models, re.M | re.S)
            if not m:
                print(f"error: {c} not found in {argv[0]}")
                return 2
            cells.append(re.sub(r"specify.*?endspecify", "", m.group(0), flags=re.S))
        (work / "cells.v").write_text("\n".join(cells) + "\n")
        gate = (HERE / "kf_rdport_ihp.v").read_text()
        (work / "gate.v").write_text(re.sub(r"^module kf_rdport\b", "module kf_rdport_gate",
                                            gate, flags=re.M))
        (work / "equiv.ys").write_text("\n".join([
            f"read_verilog {ROOT / 'rtl' / 'kf_rdport.v'}",
            f"read_verilog {work / 'cells.v'} {work / 'gate.v'}",
            "hierarchy -check",
            "proc",
            "flatten",
            "opt_clean",
            "miter -equiv -flatten -make_assert kf_rdport kf_rdport_gate miter",
            "hierarchy -top miter",
            "sat -verify -prove-asserts miter",
        ]) + "\n")
        res = subprocess.run(["yosys", "-q", str(work / "equiv.ys")], capture_output=True, text=True)
    if res.returncode == 0:
        print("kf_rdport_ihp.v is equivalent to rtl/kf_rdport.v (SAT proof)")
        return 0
    print(res.stdout[-3000:] + res.stderr[-3000:])
    print("kf_rdport_ihp.v is NOT equivalent to rtl/kf_rdport.v")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
