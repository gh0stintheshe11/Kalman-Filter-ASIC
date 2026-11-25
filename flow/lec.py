"""Logic equivalence check (LEC) of a gate-level netlist against the RTL.

    python flow/lec.py RUN_DIR [--netlist NL] [--top kf_top|kf_chip]

Proves that the netlist (by default the run's final, routed netlist) and
the RTL that the flow read are sequentially equivalent: for every input
sequence, starting from the same state, the outputs are the same in every
clock cycle.

* golden design: the RTL as the flow reads it (rtl/*.v with the IHP
  cell-level read port and clock-gate wrappers); gate design: the netlist,
  with the standard cells modeled from their Liberty functions (Yosys).
* Clock gating is made explicit: every flip-flop behind an integrated
  clock gate (sg13g2_lgcp_1, possibly several in a chain) becomes a
  flip-flop on the root clock with the gates' enables as its clock enable --
  which is what the gate does under single-edge clocking.  The designs are
  then single-clock; asynchronous resets become synchronous.
* The chip's I/O cells are black boxes, cut out of both designs as in
  commercial LEC: their core-side outputs (p2c) become primary inputs and
  their core-side inputs (c2p, c2p_en) compare points, matched by instance
  name.  (The pad ring itself, bond-pad side, is checked by LVS.)
* Both designs go into one miter (outputs compared by name) and ABC's
  dprove proves its output constant 0 from the all-zero state: register
  correspondence, SAT sweeping (fraiging) and k-step induction.  This
  proves the multipliers too, which plain SAT on cones does not.

Needs Yosys and yosys-abc (OSS CAD Suite) on PATH.  Exits non-zero unless
the designs are proven equivalent.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE_RTL = ["kf_top.v", "kf_rom.v", "kf_regfile.v", "kf_booth.v", "kf_mul.v", "kf_dot.v",
            "kf_rcp.v", "kf_add.v", "kf_prefix.v"]
CHIP_RTL = ["kf_chip.v", "kf_spi.v"] + CORE_RTL
WRAPPERS = ["kf_clkgate_ihp.v", "kf_rdport_ihp.v"]

LGCP_BOX = """\
(* blackbox *)
module sg13g2_lgcp_1 (output GCLK, input GATE, input CLK);
endmodule
"""


def yosys(script: str, log: Path) -> None:
    r = subprocess.run(["yosys", "-q", "-l", str(log), "-p", script], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"yosys failed, see {log}\n{r.stderr[-2000:]}")


def ungate(design: dict, top: str) -> int:
    """Rewrite flip-flops clocked through sg13g2_lgcp_1 into enable
    flip-flops on the root clock.  Returns the number rewritten."""
    mod = design["modules"][top]
    cells = mod["cells"]
    gates = {}                                 # GCLK bit -> (CLK bit, GATE bit)
    for name, c in list(cells.items()):
        if c["type"] == "sg13g2_lgcp_1":
            con = c["connections"]
            gates[con["GCLK"][0]] = (con["CLK"][0], con["GATE"][0])
    used = [b for n in mod["netnames"].values() for b in n["bits"]]
    used += [b for c in cells.values() for bits in c["connections"].values() for b in bits]
    nxt = max(b for b in used if isinstance(b, int)) + 1

    def root(bit):
        """Root clock and the enables along the chain of gates."""
        ens = []
        while bit in gates:
            bit, en = gates[bit]
            ens.append(en)
        return bit, ens

    count = 0
    for name, c in list(cells.items()):
        if c["type"] != "$_DFF_P_":
            continue
        clk, ens = root(c["connections"]["C"][0])
        if not ens:
            continue
        en = ens[0]
        for other in ens[1:]:                  # AND of the enables of a chain
            cells[f"$lec$and${nxt}"] = {"hide_name": 1, "type": "$_AND_", "parameters": {},
                                        "attributes": {}, "port_directions":
                                        {"A": "input", "B": "input", "Y": "output"},
                                        "connections": {"A": [en], "B": [other], "Y": [nxt]}}
            en, nxt = nxt, nxt + 1
        c["type"] = "$_DFFE_PP_"
        c["port_directions"]["E"] = "input"
        c["connections"]["C"] = [clk]
        c["connections"]["E"] = [en]
        count += 1
    for name in [n for n, c in cells.items() if c["type"] == "sg13g2_lgcp_1"]:
        del cells[name]
    return count


def cut_boxes(design: dict, top: str) -> list[str]:
    """Remove the black-box cells left in the design (I/O and bond pads).
    An output pin of a box becomes a primary input named <instance>.<pin>,
    an input pin a primary output; inout pins (the pad side) and boxes
    without known pins (bond pads: metal only) are dropped, and so are the
    design's inout ports.  Returns the new port names."""
    mod = design["modules"][top]
    cells, ports = mod["cells"], mod["ports"]
    used = [b for n in mod["netnames"].values() for b in n["bits"]]
    used += [b for c in cells.values() for bits in c["connections"].values() for b in bits]
    nxt = max(b for b in used if isinstance(b, int)) + 1
    cut = []
    for name, c in list(cells.items()):
        if c["type"].startswith("$"):
            continue
        dirs = c.get("port_directions", {})
        for pin, bits in sorted(c["connections"].items()):
            d = dirs.get(pin)
            if d not in ("input", "output"):
                continue
            if d == "input":                    # a constant input: through a buffer
                fixed = []
                for b in bits:
                    if isinstance(b, int):
                        fixed.append(b)
                        continue
                    cells[f"$lec$buf${nxt}"] = {"hide_name": 1, "type": "$_BUF_", "parameters": {},
                                                "attributes": {}, "port_directions":
                                                {"A": "input", "Y": "output"},
                                                "connections": {"A": [b], "Y": [nxt]}}
                    fixed.append(nxt)
                    nxt += 1
                bits = fixed
            pname = f"{name}.{pin}"
            ports[pname] = {"direction": "input" if d == "output" else "output", "bits": bits}
            cut.append(pname)
        del cells[name]
    for pname in [p for p, v in ports.items() if v["direction"] == "inout"]:
        del ports[pname]
    return cut


def prepare(side: str, top: str, reads: str, liberty: str, work: Path) -> None:
    """Read one design, flatten it to Yosys gates and single-bit flip-flops
    (lgcp kept as a box), remove the clock gates, write <side>.il."""
    box = work / "lgcp_box.v"
    box.write_text(LGCP_BOX)
    raw = work / f"{side}_raw.json"
    yosys(f"read_verilog {box}; read_liberty -ignore_miss_func {liberty}; {reads}; "
          f"hierarchy -top {top}; proc; memory_map; flatten; "
          + ("rename -hide w:_*; " if side == "gate" else "")
          + "opt_clean; async2sync; dffunmap; techmap; opt -fast -nodffe -nosdff; dffunmap; "
          f"opt_clean; rename {top} {side}; write_json {raw}", work / f"{side}_read.log")
    design = json.loads(raw.read_text())
    n = ungate(design, side)
    cut = cut_boxes(design, side)
    ug = work / f"{side}_ungated.json"
    ug.write_text(json.dumps(design))
    yosys(f"read_json {ug}; hierarchy -top {side}; opt_clean; write_rtlil {work / (side + '.il')}",
          work / f"{side}_ungate.log")
    print(f"{side}: {n} flip-flops behind clock gates rewritten as enable flip-flops"
          + (f"; black boxes cut at {len(cut)} pins" if cut else ""))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run_dir", type=Path)
    ap.add_argument("--netlist", help="default: the run's final netlist")
    ap.add_argument("--top", default=None)
    ap.add_argument("--workdir", type=Path, default=None)
    ap.add_argument("--timeout", type=int, default=7200, help="seconds for ABC")
    args = ap.parse_args(argv)

    cfg = json.loads((args.run_dir / "resolved.json").read_text())
    top = args.top or cfg["DESIGN_NAME"]
    netlist = Path(args.netlist or args.run_dir / "final" / "nl" / f"{top}.nl.v").resolve()
    liberty = next(lib for lib in cfg["LIB"][cfg["DEFAULT_CORNER"]] if "stdcell" in lib)
    work = (args.workdir or (ROOT / "build" / "lec" / args.run_dir.name)).resolve()
    work.mkdir(parents=True, exist_ok=True)

    rtl = CHIP_RTL if top == "kf_chip" else CORE_RTL
    gold_files = [ROOT / "rtl" / f for f in rtl] + [ROOT / "flow" / "ihp-sg13g2" / f for f in WRAPPERS]
    pads = ""
    if top == "kf_chip":
        pdk = Path(liberty).parents[3]
        pads = f"read_verilog -lib {pdk / 'libs.ref' / 'sg13g2_io' / 'verilog' / 'sg13g2_io.v'}; "
    prepare("gold", top, pads + "read_verilog " + " ".join(map(str, gold_files)), liberty, work)
    prepare("gate", top, pads + f"read_verilog {netlist}", liberty, work)

    aig = work / "miter.aig"
    yosys(f"read_rtlil {work / 'gold.il'}; read_rtlil {work / 'gate.il'}; "
          "miter -equiv -flatten gold gate miter; hierarchy -top miter; flatten; techmap; "
          "opt -fast -nodffe -nosdff; dffunmap; zinit -all; aigmap; opt_clean; "
          f"write_aiger -zinit {aig}", work / "miter.log")
    print(f"miter: {aig}; running ABC dprove (timeout {args.timeout} s)")
    try:
        r = subprocess.run(["yosys-abc", "-c", f"read {aig}; print_stats; strash; dprove -v"],
                           capture_output=True, text=True, timeout=args.timeout, cwd=work)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        out = "timeout"
    (work / "dprove.log").write_text(out)
    print("\n".join(line for line in out.splitlines() if line.strip())[-1500:])
    if "Networks are equivalent" in out:
        print(f"LEC PASS: {netlist.name} is equivalent to the RTL")
        return 0
    print("LEC FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
