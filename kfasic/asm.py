"""Assembler for the KF ASIC microcode.

Instruction word (26 bits):

    25..23  op    0 NOP  1 HALT  2 MUL  3 MAC  4 MSB  5 MAD  6 MSD  7 RCP
        22  wr    also write the new ACC value to register dst
    21..17  dst   destination register
    16..12  a     operand A register
    11..7   b     operand B register (the divisor of RCP)
     6..5   bs    operand B source: 0 register b, 1 RINV, 2 the constant 1.0
     4..0   c     addend register of MAD and MSD

Semantics (ACC accumulator, RINV reciprocal register, B = reg[b], RINV or
1.0 as selected by bs):

    MUL  ACC <- A * B              MAD  ACC <- C + A * B
    MAC  ACC <- ACC + A * B        MSD  ACC <- C - A * B
    MSB  ACC <- ACC - A * B        RCP  RINV <- 1 / reg[b]  (background, 7 cycles)

Assembly syntax (';', '#' or '//' start a comment):

    .reg  NAME  INDEX       name a data-bank register (0..31)
    mul   acc, A, B         result in ACC only
    mac   d, A, B           result in ACC and in register d
    mad   d, A, B, C        ACC <- C + A * B
    msb   acc, A, rinv      operand B may be rinv or one (the constant 1.0)
    rcp   B                 RINV <- 1/B
    nop
    halt

    lda   d, A              pseudo-instruction: mul d, A, one
    add   d, X, Y           pseudo-instruction: mad d, Y, one, X   (X + Y)
    sub   d, X, Y           pseudo-instruction: msd d, Y, one, X   (X - Y)

A * 1.0 is exact in the fixed-point format, so the pseudo-instructions are
exact too.

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
WORD_BITS = 26

OPCODES = {"nop": 0, "halt": 1, "mul": 2, "mac": 3, "msb": 4, "mad": 5, "msd": 6, "rcp": 7}
OPNAMES = {v: k for k, v in OPCODES.items()}
OP_NOP, OP_HALT, OP_MUL, OP_MAC, OP_MSB, OP_MAD, OP_MSD, OP_RCP = range(8)

ACC_OPS = (OP_MUL, OP_MAC, OP_MSB, OP_MAD, OP_MSD)   # multiply, write ACC
ADDEND_OPS = (OP_MAD, OP_MSD)                        # read register c
SUB_OPS = (OP_MSB, OP_MSD)                           # subtract the product

BS_REG, BS_RINV, BS_ONE = 0, 1, 2

WORD_HALT = OP_HALT << 23
WORD_NOP = 0


def encode(op: int, wr: int = 0, dst: int = 0, a: int = 0, b: int = 0, bs: int = 0,
           c: int = 0) -> int:
    return (op << 23) | (wr << 22) | (dst << 17) | (a << 12) | (b << 7) | (bs << 5) | c


def decode(word: int) -> dict[str, int]:
    return {
        "op": (word >> 23) & 7,
        "wr": (word >> 22) & 1,
        "dst": (word >> 17) & 31,
        "a": (word >> 12) & 31,
        "b": (word >> 7) & 31,
        "bs": (word >> 5) & 3,
        "c": word & 31,
    }


def used_fields(x: dict[str, int]) -> dict[str, bool]:
    """Which fields of a decoded instruction matter."""
    op = x["op"]
    acc = op in ACC_OPS
    return {
        "a": acc,
        "b": (acc and x["bs"] == BS_REG) or op == OP_RCP,
        "bs": acc,
        "c": op in ADDEND_OPS,
        "wr": acc,
        "dst": acc and bool(x["wr"]),
    }


def reads(x: dict[str, int]) -> tuple[set[int], bool]:
    """Registers read in S1 (operands A and B, the divisor of RCP) by a
    decoded instruction, and whether it reads RINV.  The addend C of
    MAD/MSD is read one stage later (see addend())."""
    u = used_fields(x)
    regs = {x[f] for f in ("a", "b") if u[f]}
    return regs, x["op"] in ACC_OPS and x["bs"] == BS_RINV


def addend(x: dict[str, int]) -> int | None:
    """Register read as the addend C (in EX), or None."""
    return x["c"] if x["op"] in ADDEND_OPS else None


def disassemble(word: int, names: dict[int, str] | None = None) -> str:
    names = names or {}
    reg = lambda i: names.get(i, f"db[{i}]")  # noqa: E731
    x = decode(word)
    op = x["op"]
    name = OPNAMES[op]
    if op in ACC_OPS:
        dst = reg(x["dst"]) if x["wr"] else "acc"
        b = {BS_REG: reg(x["b"]), BS_RINV: "rinv"}.get(x["bs"], "one")
        args = [dst, reg(x["a"]), b] + ([reg(x["c"])] if op in ADDEND_OPS else [])
        return f"{name:<4} " + ", ".join(args)
    if op == OP_RCP:
        return f"rcp  {reg(x['b'])}"
    return name


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
_SPECIAL_B = {"rinv": BS_RINV, "one": BS_ONE}


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
        elif tok.lower() in _SPECIAL_B:
            raise err(lineno, f"'{tok}' can only be operand B")
        else:
            raise err(lineno, f"unknown register '{tok}'")
        if not 0 <= idx < NUM_REGS:
            raise err(lineno, f"register index out of range: {idx}")
        return idx

    def dest(tok: str, lineno: int) -> tuple[int, int]:
        return (0, 0) if tok.lower() == "acc" else (1, reg(tok, lineno))

    def operand_b(tok: str, lineno: int) -> tuple[int, int]:
        """(b, bs) for operand B."""
        if tok.lower() in _SPECIAL_B:
            return 0, _SPECIAL_B[tok.lower()]
        return reg(tok, lineno), BS_REG

    def acc_op(op: int, d: str, a: str, b: str, c: str | None, lineno: int) -> int:
        if a.lower() in _SPECIAL_B and b.lower() not in _SPECIAL_B:
            a, b = b, a                                # A * B is commutative
        wr, dd = dest(d, lineno)
        bb, bs = operand_b(b, lineno)
        cc = reg(c, lineno) if c is not None else 0
        return encode(op, wr, dd, reg(a, lineno), bb, bs, cc)

    for lineno, raw in enumerate(text.splitlines(), start=1):
        code, comment = _split_comment(raw)
        if not code:
            continue
        mnem, _, rest = code.partition(" ")
        mnem = mnem.lower()
        args = [a.strip() for a in rest.split(",")] if rest.strip() else []

        if mnem == ".reg":
            parts = rest.split()
            if len(parts) != 2:
                raise err(lineno, ".reg expects: .reg NAME INDEX")
            name, idx = parts[0], int(parts[1], 0)
            if not re.fullmatch(r"[A-Za-z_]\w*", name) or name.lower() in ("acc", "rinv", "one"):
                raise err(lineno, f"invalid register name '{name}'")
            if name in prog.regs:
                raise err(lineno, f"register '{name}' defined twice")
            if not 0 <= idx < NUM_REGS:
                raise err(lineno, f"register index out of range: {idx}")
            prog.regs[name] = idx
            continue

        if mnem in ("mul", "mac", "msb"):
            if len(args) != 3:
                raise err(lineno, f"'{mnem}' expects 3 operands: dst, A, B")
            word = acc_op(OPCODES[mnem], *args, None, lineno)
        elif mnem in ("mad", "msd"):
            if len(args) != 4:
                raise err(lineno, f"'{mnem}' expects 4 operands: dst, A, B, C")
            word = acc_op(OPCODES[mnem], *args, lineno)
        elif mnem == "lda":
            if len(args) != 2:
                raise err(lineno, "lda expects: lda dst, A")
            word = acc_op(OP_MUL, args[0], args[1], "one", None, lineno)
        elif mnem in ("add", "sub"):
            if len(args) != 3:
                raise err(lineno, f"'{mnem}' expects 3 operands: dst, X, Y")
            op = OP_MAD if mnem == "add" else OP_MSD
            word = acc_op(op, args[0], args[2], "one", args[1], lineno)
        elif mnem == "rcp":
            if len(args) == 2 and args[0].lower() == "rinv":
                args = args[1:]
            if len(args) != 1:
                raise err(lineno, "rcp expects one register operand: rcp B")
            word = encode(OP_RCP, b=reg(args[0], lineno))
        elif mnem in ("nop", "halt"):
            if args:
                raise err(lineno, f"'{mnem}' takes no operands")
            word = encode(OPCODES[mnem])
        else:
            raise err(lineno, f"unknown mnemonic '{mnem}'")

        pc = len(prog.instrs)
        if pc >= ROM_DEPTH:
            raise err(lineno, f"program exceeds ROM depth ({ROM_DEPTH})")
        prog.instrs.append(Instr(pc, word, code, comment, lineno))

    if not prog.instrs or prog.instrs[-1].word != WORD_HALT:
        raise AsmError(f"{source}: program must end with 'halt'")
    if optimize:
        for instr, word in zip(prog.instrs, reduce_toggles(prog.words)):
            old, new = decode(instr.word), decode(word)
            if old["op"] in ACC_OPS and old["a"] != new["a"]:   # A and B exchanged
                mnem, _, rest = instr.text.partition(" ")
                args = [s.strip() for s in rest.split(",")]
                args[1], args[2] = args[2], args[1]
                instr.text = f"{mnem:<4} " + ", ".join(args)
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

_FIELDS = ("a", "b", "bs", "c", "wr", "dst")


def reduce_toggles(words: list[int]) -> list[int]:
    """Re-encode a program so that it executes identically but makes the
    hardware toggle less.

    * Fields an instruction does not use repeat the previous instruction's
      values, so the read addresses and the pipeline control registers do
      not change.
    * Operands A and B are exchanged where both are registers (the product
      is exactly commutative, also in fixed point) if that keeps a register
      read on consecutive cycles on the same port or leaves a multiplier
      operand register unchanged.

    The choice is a shortest path over the program (dynamic programming over
    the field values each instruction leaves behind).  Read sets, written
    registers and therefore pipeline timing are unchanged.
    """
    start = (0, 0, 0, 0, 0, 0, None, None)          # a, b, bs, c, wr, dst, ma, mb
    states: dict[tuple, tuple[float, list[int]]] = {start: (0.0, [])}
    for word in words:
        x = decode(word)
        u = used_fields(x)
        variants = [x]
        if x["op"] in ACC_OPS and x["bs"] == BS_REG and x["a"] != x["b"]:
            variants.append(dict(x, a=x["b"], b=x["a"]))
        nxt: dict[tuple, tuple[float, list[int]]] = {}
        for prev, (cost, enc) in states.items():
            p = dict(zip(_FIELDS, prev[:6]))
            ma, mb = prev[6], prev[7]
            for v in variants:
                f = {k: (v[k] if u[k] else p[k]) for k in _FIELDS}
                c = cost
                for port in ("a", "b", "c"):
                    if f[port] != p[port]:
                        c += _COST_PORT_CHANGE + _COST_ADDR_BIT * bin(f[port] ^ p[port]).count("1")
                c += _COST_CTRL_BIT * sum(bin(f[k] ^ p[k]).count("1") for k in ("bs", "wr", "dst"))
                nma, nmb = ma, mb
                if x["op"] in ACC_OPS:
                    nma, nmb = f["a"], (f["b"] if f["bs"] == BS_REG else -1 - f["bs"])
                    c += _COST_MUL_OPERAND * ((nma != ma) + (nmb != mb))
                key = (*(f[k] for k in _FIELDS), nma, nmb)
                w = encode(x["op"], f["wr"], f["dst"], f["a"], f["b"], f["bs"], f["c"])
                if key not in nxt or c < nxt[key][0]:
                    nxt[key] = (c, enc + [w])
        states = nxt
    return min(states.values(), key=lambda v: v[0])[1]


# --------------------------------------------------------------------------
# Output writers
# --------------------------------------------------------------------------

def to_hex(prog: Program) -> str:
    return "".join(f"{w:07X}\n" for w in prog.words)


def to_listing(prog: Program) -> str:
    out = [f"; listing of {prog.source}", ";  PC  word     instruction"]
    for i in prog.instrs:
        tail = f"  ; {i.comment}" if i.comment else ""
        out.append(f"{i.pc:5d}  {i.word:07X}  {i.text}{tail}")
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
        lines.append(f"      8'd{i.pc:<3d}: data = {w}'h{i.word:07X};  // {i.text}")
    lines += [
        f"      default: data = {w}'h{WORD_HALT:07X};  // halt",
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
