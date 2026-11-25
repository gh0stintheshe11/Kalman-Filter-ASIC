"""Assembler for the KF ASIC microcode.

Every arithmetic instruction is a two-term dot product with an optional
addend, written to the accumulator ACC and optionally to a register:

    ACC <- base +/- A*B [+/- D*E]          base: 0, ACC or register C

A and D are a register, RINV (the reciprocal register) or the constant 1.0;
B and E are registers.
The products are truncated to the number format but not saturated; the sum
is formed exactly and saturated once (kfasic.fixed.dot).  An instruction can
also start the reciprocal unit with its result: RINV <- 1/result, in the
background.

Instruction word (42 bits):

    41..40  op    0 NOP, 1 HALT, 2 ALU, 3 ALU and start the reciprocal unit
    39..38  base  0 zero, 1 ACC, 2 register c
        37  n1    subtract A*B
        36  m2    the second product D*E is present
        35  n2    subtract D*E
        34  wr    also write the result to register dst
    33..29  dst
    28..24  a     operand A register
    23..22  asrc  operand A source: 0 register a, 1 RINV, 2 the constant 1.0
    21..17  b     operand B register
    16..12  d     operand D register
    11..10  dsrc  operand D source, as asrc
     9..5   e     operand E register
     4..0   c     addend register (base 2)

Assembly syntax (';', '#' or '//' start a comment):

    .reg NAME INDEX                     name a data-bank register (0..31)
    DST = TERMS [, rcp]                 DST is a register or 'acc' (ACC only)
    rcp X                               pseudo-instruction: acc = X, rcp
    nop
    halt

TERMS is a sum of up to two products X*Y and at most one addend: 'acc' or
a register, with '+' (e.g. 'p11 = q11 + a11*phi11 + a12*phi12',
'inn = y - h1*x1m - h2*x2m', 'x1m = acc + g1*u', 'k1 = pht1*rinv').  In a
product one factor must be a register; the other may be 'rinv' or 'one'
(either order: the assembler puts it on the A/D side).
Further bare registers become products with 'one' (X * 1.0 is exact), so
'd = x + y' and 'd = x - y' work too.  ', rcp' starts the reciprocal unit
with the result.

Usage:
    python -m kfasic.asm fw/kf_2d.s --verilog rtl/kf_rom.v \
        --hex build/kf_2d.hex --listing build/kf_2d.lst
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROM_DEPTH = 256
NUM_REGS = 32
WORD_BITS = 42

OP_NOP, OP_HALT, OP_ALU, OP_ALU_RCP = range(4)
BASE_ZERO, BASE_ACC, BASE_C = range(3)
SRC_REG, SRC_RINV, SRC_ONE = range(3)

# (name, lsb, width), most significant first
FIELDS = (
    ("op", 40, 2), ("base", 38, 2), ("n1", 37, 1), ("m2", 36, 1), ("n2", 35, 1),
    ("wr", 34, 1), ("dst", 29, 5), ("a", 24, 5), ("asrc", 22, 2), ("b", 17, 5),
    ("d", 12, 5), ("dsrc", 10, 2), ("e", 5, 5), ("c", 0, 5),
)
FIELD_NAMES = tuple(f[0] for f in FIELDS)

WORD_HALT = OP_HALT << 40
WORD_NOP = 0


def encode(**x: int) -> int:
    word = 0
    for name, lsb, width in FIELDS:
        v = x.get(name, 0)
        if not 0 <= v < (1 << width):
            raise ValueError(f"field {name} out of range: {v}")
        word |= v << lsb
    return word


def decode(word: int) -> dict[str, int]:
    return {name: (word >> lsb) & ((1 << width) - 1) for name, lsb, width in FIELDS}


def is_alu(x: dict[str, int]) -> bool:
    return x["op"] in (OP_ALU, OP_ALU_RCP)


def used_fields(x: dict[str, int]) -> dict[str, bool]:
    """Which fields of a decoded instruction matter."""
    alu = is_alu(x)
    m2 = alu and bool(x["m2"])
    return {
        "op": True,
        "base": alu, "n1": alu, "m2": alu, "wr": alu,
        "dst": alu and bool(x["wr"]),
        "asrc": alu, "a": alu and x["asrc"] == SRC_REG, "b": alu,
        "n2": m2, "dsrc": m2, "d": m2 and x["dsrc"] == SRC_REG, "e": m2,
        "c": alu and x["base"] == BASE_C,
    }


def reads(x: dict[str, int]) -> tuple[set[int], bool]:
    """Registers read in S1 (operands A, B, D, E) by a decoded instruction,
    and whether it reads RINV.  The addend C is read one stage later (see
    addend())."""
    u = used_fields(x)
    regs = {x[f] for f in ("a", "b", "d", "e") if u[f]}
    rinv = is_alu(x) and (x["asrc"] == SRC_RINV or (bool(x["m2"]) and x["dsrc"] == SRC_RINV))
    return regs, rinv


def addend(x: dict[str, int]) -> int | None:
    """Register read as the addend C (in EX), or None."""
    return x["c"] if is_alu(x) and x["base"] == BASE_C else None


def disassemble(word: int, names: dict[int, str] | None = None) -> str:
    names = names or {}
    reg = lambda i: names.get(i, f"db[{i}]")  # noqa: E731
    x = decode(word)
    if not is_alu(x):
        return "halt" if x["op"] == OP_HALT else "nop"
    def product(a: int, asrc: int, b: int) -> str:
        if asrc == SRC_REG:
            return f"{reg(a)}*{reg(b)}"
        return f"{reg(b)}*{'rinv' if asrc == SRC_RINV else 'one'}"

    text = "acc" if x["base"] == BASE_ACC else reg(x["c"]) if x["base"] == BASE_C else ""
    prods = [(x["n1"], product(x["a"], x["asrc"], x["b"]))]
    if x["m2"]:
        prods.append((x["n2"], product(x["d"], x["dsrc"], x["e"])))
    for neg, t in prods:
        text = (f"{text} - {t}" if neg else f"{text} + {t}") if text else (f"-{t}" if neg else t)
    dst = reg(x["dst"]) if x["wr"] else "acc"
    return f"{dst} = {text}" + (", rcp" if x["op"] == OP_ALU_RCP else "")


class AsmError(Exception):
    pass


@dataclass
class Instr:
    pc: int
    word: int
    text: str
    comment: str
    line: int


@dataclass
class Program:
    source: str
    instrs: list[Instr] = field(default_factory=list)
    regs: dict[str, int] = field(default_factory=dict)

    @property
    def words(self) -> list[int]:
        return [i.word for i in self.instrs]

    @property
    def reg_names(self) -> dict[int, str]:
        return {v: k for k, v in self.regs.items()}


_COMMENT = re.compile(r"\s*(;|#|//)(.*)$")
_SPECIAL = {"rinv": SRC_RINV, "one": SRC_ONE}
_RESERVED = ("acc", "rinv", "one", "rcp", "nop", "halt")
_TERM = re.compile(r"([+-]?)\s*([A-Za-z_][\w\[\]]*)\s*(?:\*\s*([A-Za-z_][\w\[\]]*))?\s*")


def _split_comment(line: str) -> tuple[str, str]:
    m = _COMMENT.search(line)
    if not m:
        return line.strip(), ""
    return line[: m.start()].strip(), m.group(2).strip()


def assemble(text: str, source: str = "<string>", optimize: bool = True) -> Program:
    """Assemble a program.  With ``optimize`` the words are re-encoded by
    reduce_toggles(): same behavior, less switching in the hardware."""
    prog = Program(source=source)

    def err(lineno: int, msg: str) -> AsmError:
        return AsmError(f"{source}:{lineno}: {msg}")

    def reg(tok: str, lineno: int) -> int:
        tok = tok.strip()
        m = re.fullmatch(r"db\[(\d+)\]", tok, re.IGNORECASE)
        if m:
            idx = int(m.group(1))
        elif tok in prog.regs:
            idx = prog.regs[tok]
        elif tok.lower() in _SPECIAL:
            raise err(lineno, f"'{tok}' can only be a factor of a product")
        elif tok.lower() == "acc":
            raise err(lineno, "'acc' can only be the destination or an addend")
        else:
            raise err(lineno, f"unknown register '{tok}'")
        if not 0 <= idx < NUM_REGS:
            raise err(lineno, f"register index out of range: {idx}")
        return idx

    def factor_a(tok: str, lineno: int) -> tuple[int, int]:
        """(register, source) of the A/D side of a product."""
        if tok.lower() in _SPECIAL:
            return 0, _SPECIAL[tok.lower()]
        return reg(tok, lineno), SRC_REG

    def alu(dst: str, expr: str, rcp: bool, lineno: int) -> int:
        x = {"op": OP_ALU_RCP if rcp else OP_ALU}
        if dst.lower() == "acc":
            x["wr"] = 0
        else:
            x["wr"], x["dst"] = 1, reg(dst, lineno)
        terms, pos = [], 0
        expr = expr.strip()
        while pos < len(expr):
            m = _TERM.match(expr, pos)
            if not m or m.end() == pos:
                raise err(lineno, f"cannot parse '{expr[pos:]}'")
            sign, f1, f2 = m.groups()
            if terms and not sign:
                raise err(lineno, f"expected '+' or '-' before '{m.group(0).strip()}'")
            terms.append((sign == "-", f1, f2))
            pos = m.end()
        if not terms:
            raise err(lineno, "empty expression")
        base, prods = None, []
        for neg, f1, f2 in terms:
            if f2 is None:                                  # bare operand
                if f1.lower() == "acc" or (not neg and base is None):
                    if neg or base is not None:
                        raise err(lineno, "the addend must be added and can appear only once")
                    base = f1
                    continue
                f2 = "one"
            if f1.lower() in _SPECIAL and f2.lower() in _SPECIAL:
                raise err(lineno, f"'{f1}*{f2}': one factor must be a register")
            if f2.lower() in _SPECIAL:
                f1, f2 = f2, f1                             # rinv/one on the A side
            prods.append((neg, f1, f2))                     # (sign, A side, B side)
        if not prods:
            if base is None or base.lower() == "acc":
                raise err(lineno, "an instruction needs at least one product")
            prods, base = [(False, "one", base)], None
        if len(prods) > 2:
            raise err(lineno, "at most two products per instruction")
        if base is None:
            x["base"] = BASE_ZERO
        elif base.lower() == "acc":
            x["base"] = BASE_ACC
        else:
            x["base"], x["c"] = BASE_C, reg(base, lineno)
        (n1, a, b), *rest = prods
        x["n1"], x["b"] = int(n1), reg(b, lineno)
        x["a"], x["asrc"] = factor_a(a, lineno)
        if rest:
            n2, d, e = rest[0]
            x["m2"], x["n2"], x["e"] = 1, int(n2), reg(e, lineno)
            x["d"], x["dsrc"] = factor_a(d, lineno)
        return encode(**x)

    for lineno, raw in enumerate(text.splitlines(), start=1):
        code, comment = _split_comment(raw)
        if not code:
            continue
        if code.startswith(".reg"):
            parts = code.split()
            if len(parts) != 3:
                raise err(lineno, ".reg expects: .reg NAME INDEX")
            name, idx = parts[1], int(parts[2], 0)
            if not re.fullmatch(r"[A-Za-z_]\w*", name) or name.lower() in _RESERVED:
                raise err(lineno, f"invalid register name '{name}'")
            if name in prog.regs:
                raise err(lineno, f"register '{name}' defined twice")
            if not 0 <= idx < NUM_REGS:
                raise err(lineno, f"register index out of range: {idx}")
            prog.regs[name] = idx
            continue
        if "=" in code:
            dst, _, rhs = code.partition("=")
            rhs, rcp = rhs.strip(), False
            m = re.fullmatch(r"(.*?),\s*rcp", rhs, re.IGNORECASE)
            if m:
                rhs, rcp = m.group(1), True
            word = alu(dst.strip(), rhs, rcp, lineno)
        else:
            mnem, _, rest = code.partition(" ")
            mnem, rest = mnem.lower(), rest.strip()
            if mnem == "rcp":
                if not rest or "," in rest:
                    raise err(lineno, "rcp expects one register: rcp X")
                word = alu("acc", rest, True, lineno)
            elif mnem in ("nop", "halt"):
                if rest:
                    raise err(lineno, f"'{mnem}' takes no operands")
                word = WORD_HALT if mnem == "halt" else WORD_NOP
            else:
                raise err(lineno, f"unknown instruction '{code}'")
        pc = len(prog.instrs)
        if pc >= ROM_DEPTH:
            raise err(lineno, f"program exceeds ROM depth ({ROM_DEPTH})")
        prog.instrs.append(Instr(pc, word, code, comment, lineno))

    if not prog.instrs or prog.instrs[-1].word != WORD_HALT:
        raise AsmError(f"{source}: program must end with 'halt'")
    if optimize:
        for instr, word in zip(prog.instrs, reduce_toggles(prog.words)):
            old, new = decode(instr.word), decode(word)
            u = used_fields(new)
            if any(old[f] != new[f] for f in FIELD_NAMES if u[f]):     # operands exchanged
                names = dict(prog.reg_names)
                names.update({prog.regs[t]: t for t in re.findall(r"[A-Za-z_]\w*", instr.text)
                              if t in prog.regs})
                instr.text = disassemble(word, names)
            instr.word = word
    return prog


def assemble_file(path: str | Path, optimize: bool = True) -> Program:
    path = Path(path)
    return assemble(path.read_text(), source=str(path), optimize=optimize)


# --------------------------------------------------------------------------
# Low-power encoding
# --------------------------------------------------------------------------

# Relative costs used by reduce_toggles(): a port that reads a different
# register makes the read port and the operand register toggle; an address
# bit that flips drives select logic; a new multiplier operand makes the
# multiplier toggle.
_COST_PORT_CHANGE = 6
_COST_ADDR_BIT = 1
_COST_MUL_OPERAND = 6
_COST_CTRL_BIT = 0.5

_PORTS = ("a", "b", "d", "e", "c")
_CTRL = ("base", "n1", "m2", "n2", "wr", "dst", "asrc", "dsrc")


def _variants(x: dict[str, int]) -> list[dict[str, int]]:
    """Encodings of the same operation: the factors of a product exchanged
    (both registers), the two products exchanged."""
    if not is_alu(x):
        return [x]
    out = [x]
    if x["m2"]:
        out.append(dict(x, n1=x["n2"], a=x["d"], asrc=x["dsrc"], b=x["e"],
                        n2=x["n1"], d=x["a"], dsrc=x["asrc"], e=x["b"]))
    for v in list(out):
        if v["asrc"] == SRC_REG and v["a"] != v["b"]:
            out.append(dict(v, a=v["b"], b=v["a"]))
    for v in list(out):
        if v["m2"] and v["dsrc"] == SRC_REG and v["d"] != v["e"]:
            out.append(dict(v, d=v["e"], e=v["d"]))
    return out


def reduce_toggles(words: list[int]) -> list[int]:
    """Re-encode a program so that it executes identically but makes the
    hardware toggle less.

    * Fields an instruction does not use repeat the previous instruction's
      values, so the read addresses and the pipeline control registers do
      not change.
    * The factors of a product, and the two products, are exchanged where
      that keeps a register read on consecutive cycles on the same port or
      leaves a multiplier operand register unchanged (products are exactly
      commutative, also in fixed point).

    The choice is a shortest path over the program (dynamic programming over
    the field values each instruction leaves behind).  Read sets, written
    registers and therefore pipeline timing are unchanged.
    """
    start = tuple(0 for _ in FIELD_NAMES) + (None,) * 4   # fields, then ma mb md me
    states: dict[tuple, tuple[float, list[int]]] = {start: (0.0, [])}
    for word in words:
        x = decode(word)
        variants = [(v, used_fields(v)) for v in _variants(x)]
        nxt: dict[tuple, tuple[float, list[int]]] = {}
        for prev, (cost, enc) in states.items():
            p = dict(zip(FIELD_NAMES, prev))
            ops = prev[len(FIELD_NAMES):]
            for v, u in variants:
                f = {k: (v[k] if u[k] else p[k]) for k in FIELD_NAMES}
                c = cost
                for port in _PORTS:
                    if f[port] != p[port]:
                        c += _COST_PORT_CHANGE + _COST_ADDR_BIT * bin(f[port] ^ p[port]).count("1")
                c += _COST_CTRL_BIT * sum(bin(f[k] ^ p[k]).count("1") for k in _CTRL)
                ma, mb, md, me = ops
                if is_alu(x):
                    ma, mb = (f["a"] if f["asrc"] == SRC_REG else -1 - f["asrc"]), f["b"]
                    c += _COST_MUL_OPERAND * ((ma != ops[0]) + (mb != ops[1]))
                    if x["m2"]:
                        md, me = (f["d"] if f["dsrc"] == SRC_REG else -1 - f["dsrc"]), f["e"]
                        c += _COST_MUL_OPERAND * ((md != ops[2]) + (me != ops[3]))
                key = (*(f[k] for k in FIELD_NAMES), ma, mb, md, me)
                w = encode(**f)
                if key not in nxt or c < nxt[key][0]:
                    nxt[key] = (c, enc + [w])
        states = nxt
    return min(states.values(), key=lambda v: v[0])[1]


# --------------------------------------------------------------------------
# Output writers
# --------------------------------------------------------------------------

_HEX_DIGITS = (WORD_BITS + 3) // 4


def to_hex(prog: Program) -> str:
    return "".join(f"{w:0{_HEX_DIGITS}X}\n" for w in prog.words)


def to_listing(prog: Program) -> str:
    out = [f"; listing of {prog.source}", f";  PC  {'word':<{_HEX_DIGITS}}  instruction"]
    for i in prog.instrs:
        tail = f"  ; {i.comment}" if i.comment else ""
        out.append(f"{i.pc:5d}  {i.word:0{_HEX_DIGITS}X}  {i.text}{tail}")
    return "\n".join(out) + "\n"


def to_verilog(prog: Program, module: str = "kf_rom") -> str:
    """Hard-wired ROM as a case statement (synthesizes to plain logic)."""
    src = "/".join(Path(prog.source).parts[-2:])     # e.g. fw/kf_2d.s
    w = WORD_BITS
    lines = [
        f"// {module}.v -- microcode ROM, {len(prog.words)} of {ROM_DEPTH} words used.",
        f"// AUTO-GENERATED by kfasic.asm from {src}; DO NOT EDIT.",
        "// Unused addresses read as HALT.",
        "`default_nettype none",
        "",
        f"module {module} (",
        "    input  wire [7:0]  addr,",
        f"    output reg  [{w - 1}:0] data",
        ");",
        "  always @(*) begin",
        "    case (addr)",
    ]
    for i in prog.instrs:
        lines.append(f"      8'd{i.pc:<3d}: data = {w}'h{i.word:0{_HEX_DIGITS}X};  // {i.text}")
    lines += [
        f"      default: data = {w}'h{WORD_HALT:0{_HEX_DIGITS}X};  // halt",
        "    endcase",
        "  end",
        "endmodule",
        "",
        "`default_nettype wire",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("source")
    ap.add_argument("--verilog", help="write hard-wired ROM module here")
    ap.add_argument("--hex", help="write $readmemh image here")
    ap.add_argument("--listing", help="write listing here")
    args = ap.parse_args(argv)
    try:
        prog = assemble_file(args.source)
    except AsmError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    for path, render in ((args.verilog, to_verilog), (args.hex, to_hex), (args.listing, to_listing)):
        if path:
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            Path(path).write_text(render(prog))
    print(f"{args.source}: {len(prog.words)} instructions, {len(prog.regs)} named registers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
