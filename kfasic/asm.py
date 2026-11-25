"""Assembler for the KF ASIC microcode.

Instruction word (21 bits):

    20..17  op    0 NOP  1 HALT  2 MUL  3 MAC  4 MSB  5 ADD  6 SUB  7 LDA  8 RCP
        16  wr    also write the new ACC value to register dst
    15..11  dst   destination register
    10..6   a     operand A register
     5..1   b     operand B register
         0  bi    operand B is RINV instead of register b

Semantics (ACC accumulator, RINV reciprocal register):

    MUL  ACC <- A * B        MAC  ACC <- ACC + A * B      MSB  ACC <- ACC - A * B
    ADD  ACC <- A + B        SUB  ACC <- A - B            LDA  ACC <- A
    RCP  RINV <- 1 / B       (separate unit, runs in the background for 8 cycles)

Assembly syntax (';', '#' or '//' start a comment):

    .reg  NAME  INDEX       name a data-bank register (0..31)
    mul   acc, A, B         result in ACC only
    mac   d, A, B           result in ACC and in register d
    msb   acc, A, rinv      operand B may be RINV
    lda   acc, A            (lda d, A also copies A to register d)
    rcp   B                 RINV <- 1/B
    nop
    halt

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
WORD_BITS = 21

OPCODES = {"nop": 0, "halt": 1, "mul": 2, "mac": 3, "msb": 4,
           "add": 5, "sub": 6, "lda": 7, "rcp": 8}
OPNAMES = {v: k for k, v in OPCODES.items()}
OP_NOP, OP_HALT, OP_MUL, OP_MAC, OP_MSB, OP_ADD, OP_SUB, OP_LDA, OP_RCP = range(9)

MUL_OPS = (OP_MUL, OP_MAC, OP_MSB)        # use the multiplier
ALU_OPS = (OP_ADD, OP_SUB, OP_LDA)        # use the adder
TWO_OPERAND_OPS = MUL_OPS + (OP_ADD, OP_SUB)
ACC_OPS = MUL_OPS + ALU_OPS               # write ACC

WORD_HALT = OP_HALT << 17
WORD_NOP = 0


def encode(op: int, wr: int = 0, dst: int = 0, a: int = 0, b: int = 0, bi: int = 0) -> int:
    return (op << 17) | (wr << 16) | (dst << 11) | (a << 6) | (b << 1) | bi


def decode(word: int) -> dict[str, int]:
    return {
        "op": (word >> 17) & 15,
        "wr": (word >> 16) & 1,
        "dst": (word >> 11) & 31,
        "a": (word >> 6) & 31,
        "b": (word >> 1) & 31,
        "bi": word & 1,
    }


def reads(x: dict[str, int]) -> tuple[set[int], bool]:
    """Registers read by a decoded instruction, and whether it reads RINV."""
    op = x["op"]
    regs: set[int] = set()
    if op in TWO_OPERAND_OPS or op == OP_LDA:
        regs.add(x["a"])
    if (op in TWO_OPERAND_OPS and not x["bi"]) or op == OP_RCP:
        regs.add(x["b"])
    return regs, op in TWO_OPERAND_OPS and bool(x["bi"])


def disassemble(word: int, names: dict[int, str] | None = None) -> str:
    names = names or {}
    reg = lambda i: names.get(i, f"db[{i}]")  # noqa: E731
    x = decode(word)
    op = x["op"]
    if op not in OPNAMES:
        return f".word 0x{word:06X}"
    name = OPNAMES[op]
    dst = reg(x["dst"]) if x["wr"] else "acc"
    if op in TWO_OPERAND_OPS:
        b = "rinv" if x["bi"] else reg(x["b"])
        return f"{name:<4} {dst}, {reg(x['a'])}, {b}"
    if op == OP_LDA:
        return f"lda  {dst}, {reg(x['a'])}"
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


def _split_comment(line: str) -> tuple[str, str]:
    m = _COMMENT.search(line)
    if not m:
        return line.strip(), ""
    return line[: m.start()].strip(), m.group(2).strip()


def assemble(text: str, source: str = "<string>") -> Program:
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
        else:
            raise err(lineno, f"unknown register '{tok}'")
        if not 0 <= idx < NUM_REGS:
            raise err(lineno, f"register index out of range: {idx}")
        return idx

    def dest(tok: str, lineno: int) -> tuple[int, int]:
        return (0, 0) if tok.lower() == "acc" else (1, reg(tok, lineno))

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
            if not re.fullmatch(r"[A-Za-z_]\w*", name) or name.lower() in ("acc", "rinv"):
                raise err(lineno, f"invalid register name '{name}'")
            if name in prog.regs:
                raise err(lineno, f"register '{name}' defined twice")
            if not 0 <= idx < NUM_REGS:
                raise err(lineno, f"register index out of range: {idx}")
            prog.regs[name] = idx
            continue

        if mnem not in OPCODES:
            raise err(lineno, f"unknown mnemonic '{mnem}'")
        op = OPCODES[mnem]
        if op in TWO_OPERAND_OPS:
            if len(args) != 3:
                raise err(lineno, f"'{mnem}' expects 3 operands: dst, A, B")
            wr, d = dest(args[0], lineno)
            if args[1].lower() == "rinv":
                raise err(lineno, "rinv can only be operand B")
            bi = int(args[2].lower() == "rinv")
            b = 0 if bi else reg(args[2], lineno)
            word = encode(op, wr, d, reg(args[1], lineno), b, bi)
        elif op == OP_LDA:
            if len(args) != 2:
                raise err(lineno, "lda expects: lda dst, A")
            wr, d = dest(args[0], lineno)
            word = encode(op, wr, d, a=reg(args[1], lineno))
        elif op == OP_RCP:
            if len(args) == 2 and args[0].lower() == "rinv":
                args = args[1:]
            if len(args) != 1 or args[0].lower() == "rinv":
                raise err(lineno, "rcp expects one register operand: rcp B")
            word = encode(op, b=reg(args[0], lineno))
        else:
            if args:
                raise err(lineno, f"'{mnem}' takes no operands")
            word = encode(op)

        pc = len(prog.instrs)
        if pc >= ROM_DEPTH:
            raise err(lineno, f"program exceeds ROM depth ({ROM_DEPTH})")
        prog.instrs.append(Instr(pc, word, code, comment, lineno))

    if not prog.instrs or prog.instrs[-1].word != WORD_HALT:
        raise AsmError(f"{source}: program must end with 'halt'")
    return prog


def assemble_file(path: str | Path) -> Program:
    path = Path(path)
    return assemble(path.read_text(), source=str(path))


# --------------------------------------------------------------------------
# Output writers
# --------------------------------------------------------------------------

def to_hex(prog: Program) -> str:
    return "".join(f"{w:06X}\n" for w in prog.words)


def to_listing(prog: Program) -> str:
    out = [f"; listing of {prog.source}", ";  PC  word    instruction"]
    for i in prog.instrs:
        tail = f"  ; {i.comment}" if i.comment else ""
        out.append(f"{i.pc:5d}  {i.word:06X}  {i.text}{tail}")
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
        lines.append(f"      8'd{i.pc:<3d}: data = {w}'h{i.word:06X};  // {i.text}")
    lines += [
        f"      default: data = {w}'h{WORD_HALT:06X};  // halt",
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
