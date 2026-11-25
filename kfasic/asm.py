"""Assembler for the KF ASIC microcode.

Instruction word (16 bits, paper Sec. 4: "a4..a0 b4..b0 c1 c0 d1 d0 e f"):

    15..11  a   register address A: operand R, and write-back address
    10..6   b   register address B: operand S
     5..4   c   sequencing: 00 NEXT, 01 WAIT (required on DIV), 10 HALT
     3..2   d   AU operation: 00 ADD, 01 SUB, 10 MUL, 11 DIV
        1   e   execute: run the AU on (DB[a], DB[b]); result -> SR
        0   f   write: DB[a] <- (e ? AU result : SR)

Assembly syntax (one instruction per line, ';' '#' or '//' start a comment):

    .reg  NAME  INDEX          name a data-bank register (0..31)
    add   sr, A, B             SR <- A + B            (also sub, mul)
    add   A, A, B              A  <- A + B, SR <- A+B (write back to A)
    div   sr, A, B             SR <- A / B            (25 cycles)
    mov   A, sr                A  <- SR               (alias: st A)
    nop
    halt                       stop, READY <- 1

Registers are referenced by .reg name or as db[N].

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

C_NEXT, C_WAIT, C_HALT = 0, 1, 2
OPCODES = {"add": 0, "sub": 1, "mul": 2, "div": 3}
OPNAMES = {v: k for k, v in OPCODES.items()}

WORD_HALT = C_HALT << 4
WORD_NOP = 0


def encode(a: int = 0, b: int = 0, c: int = C_NEXT, d: int = 0, e: int = 0, f: int = 0) -> int:
    return (a << 11) | (b << 6) | (c << 4) | (d << 2) | (e << 1) | f


def decode(word: int) -> dict[str, int]:
    return {
        "a": (word >> 11) & 31,
        "b": (word >> 6) & 31,
        "c": (word >> 4) & 3,
        "d": (word >> 2) & 3,
        "e": (word >> 1) & 1,
        "f": word & 1,
    }


def disassemble(word: int, names: dict[int, str] | None = None) -> str:
    """Render one instruction word in assembly syntax."""
    names = names or {}
    reg = lambda i: names.get(i, f"db[{i}]")  # noqa: E731
    x = decode(word)
    if x["c"] == C_HALT:
        return "halt"
    if x["e"]:
        op = OPNAMES[x["d"]]
        dst = reg(x["a"]) if x["f"] else "sr"
        return f"{op:<4} {dst}, {reg(x['a'])}, {reg(x['b'])}"
    if x["f"]:
        return f"mov  {reg(x['a'])}, sr"
    return "nop"


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
            if not re.fullmatch(r"[A-Za-z_]\w*", name) or name.lower() == "sr":
                raise err(lineno, f"invalid register name '{name}'")
            if name in prog.regs:
                raise err(lineno, f"register '{name}' defined twice")
            if not 0 <= idx < NUM_REGS:
                raise err(lineno, f"register index out of range: {idx}")
            prog.regs[name] = idx
            continue

        if mnem in OPCODES:
            if len(args) != 3:
                raise err(lineno, f"'{mnem}' expects 3 operands: dst, A, B")
            dst, a_tok, b_tok = args
            a, b = reg(a_tok, lineno), reg(b_tok, lineno)
            d = OPCODES[mnem]
            if dst.lower() == "sr":
                word = encode(a=a, b=b, c=C_WAIT if mnem == "div" else C_NEXT, d=d, e=1)
            else:
                if mnem == "div":
                    raise err(lineno, "div can only target sr (store it with 'mov X, sr')")
                if reg(dst, lineno) != a:
                    raise err(lineno, "write-back destination must be the first source "
                                      f"operand ('{dst}' != '{a_tok}'); use 'sr' + 'mov'")
                word = encode(a=a, b=b, d=d, e=1, f=1)
        elif mnem in ("mov", "st"):
            if mnem == "st":
                args = args + ["sr"]
            if len(args) != 2 or args[1].lower() != "sr":
                raise err(lineno, "mov expects: mov X, sr")
            word = encode(a=reg(args[0], lineno), f=1)
        elif mnem == "halt" and not args:
            word = WORD_HALT
        elif mnem == "nop" and not args:
            word = WORD_NOP
        else:
            raise err(lineno, f"cannot parse '{code}'")

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
    return "".join(f"{w:04X}\n" for w in prog.words)


def to_listing(prog: Program) -> str:
    out = [f"; listing of {prog.source}", ";  PC  word  instruction"]
    for i in prog.instrs:
        tail = f"  ; {i.comment}" if i.comment else ""
        out.append(f"{i.pc:5d}  {i.word:04X}  {i.text}{tail}")
    return "\n".join(out) + "\n"


def to_verilog(prog: Program, module: str = "kf_rom") -> str:
    """Hard-wired ROM as a case statement (synthesizes to plain logic)."""
    src = "/".join(Path(prog.source).parts[-2:])     # e.g. fw/kf_2d.s
    lines = [
        f"// {module}.v -- microcode ROM, {len(prog.words)} of {ROM_DEPTH} words used.",
        f"// AUTO-GENERATED by kfasic.asm from {src}; DO NOT EDIT.",
        "// Unused addresses read as HALT.",
        "`default_nettype none",
        "",
        f"module {module} (",
        "    input  wire [7:0]  addr,",
        "    output reg  [15:0] data",
        ");",
        "  always @(*) begin",
        "    case (addr)",
    ]
    for i in prog.instrs:
        lines.append(f"      8'd{i.pc:<3d}: data = 16'h{i.word:04X};  // {i.text}")
    lines += [
        f"      default: data = 16'h{WORD_HALT:04X};  // halt",
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
    n_div = sum(1 for w in prog.words if decode(w)["e"] and decode(w)["d"] == 3)
    print(f"{args.source}: {len(prog.words)} instructions ({n_div} div), "
          f"{len(prog.regs)} named registers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
