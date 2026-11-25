"""Fast pure-Python checks of the arithmetic model, assembler, ISS and
microcode."""

import gzip
from pathlib import Path

import numpy as np
import pytest

from kfasic import fixed
from kfasic import reference as ref
from kfasic.asm import AsmError, assemble, assemble_file, decode, to_verilog
from kfasic.iss import RCP_CYCLES, Iss, UninitializedRead, execute_float
from kfasic.randprog import random_program

ROOT = Path(__file__).resolve().parents[1]
PROG = assemble_file(ROOT / "fw" / "kf_2d.s")
REG = PROG.regs
STATE = ("x1", "x2", "p11", "p12", "p22")
rng = np.random.default_rng(2016)


def random_words(n):
    """Random words with a bias toward edge cases."""
    edge = [0, fixed.SIGN_BIT, 1, fixed.SIGN_BIT | 1, fixed.MAG_MAX, fixed.MASK,
            fixed.ONE, fixed.SIGN_BIT | fixed.ONE, fixed.from_float(511.5), 32, 33]
    out = list(edge)
    out += [int(v) for v in rng.integers(0, 1 << 24, size=n)]
    out += [fixed.from_float(v) for v in rng.normal(0, 3, size=n)]
    return out


def load(iss, params):
    for name, word in ref.quantize(params).items():
        iss.write(REG[name], word)


# ---------------------------------------------------------------- arithmetic

def hw_reciprocal(s):
    """Radix-8 restoring division of 2^28 by |S|, as the RTL performs it."""
    d = fixed.mag_of(s)
    if d <= 32:
        return fixed.MAG_MAX
    r, q = 16, 0
    for _ in range(8):
        r <<= 3
        digit = min(r // d, 7)
        r -= digit * d
        q = (q << 3) | digit
    return q


def test_reciprocal_matches_radix8_division():
    for s in random_words(3000):
        assert fixed.reciprocal_mag(s) == hw_reciprocal(s), hex(s)
        assert fixed.mag_of(fixed.rcp(s)) == fixed.reciprocal_mag(s)
        assert fixed.sign_of(fixed.rcp(s)) == fixed.sign_of(s)


@pytest.mark.parametrize("op", ["add", "sub", "mul", "div"])
def test_results_are_normalized_and_saturated(op):
    f = fixed.OPS[op]
    words = random_words(300)
    for r in words[::7]:
        for s in words[::11]:
            w = f(r, s)
            assert 0 <= w <= fixed.MASK
            assert w != fixed.SIGN_BIT, "hardware never produces -0"


def test_add_sub_exact():
    clip = lambda v: max(-fixed.MAG_MAX, min(fixed.MAG_MAX, v))  # noqa: E731
    for r in random_words(200):
        for s in random_words(20):
            a, b = fixed.to_int(r), fixed.to_int(s)
            assert fixed.to_int(fixed.add(r, s)) == clip(a + b)
            assert fixed.to_int(fixed.sub(r, s)) == clip(a - b)


def test_mul_truncates_toward_zero():
    for r in random_words(200):
        for s in random_words(20):
            exact = fixed.to_int(r) * fixed.to_int(s)
            mag = min(abs(exact) >> fixed.FRAC, fixed.MAG_MAX)
            assert fixed.to_int(fixed.mul(r, s)) == (mag if exact >= 0 else -mag)


def test_product_is_mul_without_saturation():
    for r in random_words(200):
        for s in random_words(20):
            p = fixed.product(r, s)
            assert abs(p) < 1 << 32
            assert fixed.from_int(p) == fixed.mul(r, s)


def test_dot_is_exact_and_saturates_once():
    """dot() sums exactly and saturates once; it equals the chain of
    saturating add/sub whenever no partial sum of the chain saturates."""
    clip = lambda v: max(-fixed.MAG_MAX, min(fixed.MAG_MAX, v))  # noqa: E731
    words = random_words(60)
    for base in words[::3]:
        for a in words[::7]:
            for b in words[::11]:
                p1, p2 = fixed.product(a, b), fixed.product(b, base)
                v = fixed.to_int(base) + p1 - p2
                assert fixed.to_int(fixed.dot(fixed.to_int(base), p1, -p2)) == clip(v)
                partial = fixed.to_int(base) + p1
                if abs(partial) <= fixed.MAG_MAX and max(abs(p1), abs(p2)) <= fixed.MAG_MAX:
                    chain = fixed.sub(fixed.add(base, fixed.mul(a, b)), fixed.mul(b, base))
                    assert fixed.dot(fixed.to_int(base), p1, -p2) == chain


def test_reciprocal_times_value_error_bound():
    # R * (1/S): 1/S truncated to 1 LSB, then the product truncated again,
    # so |error| <= (|R| + 1) LSB.  (Kalman gain range: |R| <= |S|.)
    lsb = 2.0 ** -fixed.FRAC
    for _ in range(3000):
        s = fixed.from_float(rng.uniform(0.01, 50) * rng.choice([-1, 1]))
        r = fixed.from_float(rng.uniform(-1, 1) * abs(fixed.to_float(s)))
        rv, sv = fixed.to_float(r), fixed.to_float(s)
        q = fixed.to_float(fixed.mul(r, fixed.rcp(s)))
        assert q == fixed.to_float(fixed.div(r, s))
        assert abs(q - rv / sv) <= (abs(rv) + 1) * lsb


# ----------------------------------------------------------------- assembler

def test_assembler_encodings():
    p = assemble(".reg a 3\n.reg b 7\n.reg t 9\nt = a*b\nacc = acc + a*rinv - b*one\n"
                 "t = b - a*b, rcp\nacc = a + b\nnop\nhalt\n", optimize=False)
    assert p.words == [0x205230E0000, 0x258004608E0, 0x3A5230E0007, 0x280008E0003,
                       0x00000000000, 0x10000000000]
    assert decode(0x258004608E0) == {"op": 2, "base": 1, "n1": 0, "m2": 1, "n2": 1, "wr": 0,
                                     "dst": 0, "a": 0, "asrc": 1, "b": 3, "d": 0, "dsrc": 2,
                                     "e": 7, "c": 0}
    # t = b - a*b: base register b, subtract;  acc = a + b: a is the base, b*1.0
    assert decode(0x3A5230E0007)["c"] == 7 and decode(0x280008E0003)["asrc"] == 2


def test_assembler_puts_constants_on_the_a_side():
    p = assemble(".reg a 3\nacc = rinv*a\nacc = a*one + one*a\nhalt\n", optimize=False)
    x = [decode(w) for w in p.words[:2]]
    assert (x[0]["asrc"], x[0]["b"]) == (1, 3)
    assert (x[1]["asrc"], x[1]["b"], x[1]["dsrc"], x[1]["e"]) == (2, 3, 2, 3)


def test_low_power_encoding_exchanges_operands():
    # after the first instruction, a stays on port A and b on port B if the
    # factors of the second product are exchanged
    x = [decode(w) for w in assemble(".reg a 3\n.reg b 7\ndb[9] = a*b\n"
                                     "acc = b*a\nhalt\n").words]
    assert (x[0]["a"], x[0]["b"]) == (x[1]["a"], x[1]["b"])


def test_low_power_encoding_exchanges_products():
    # the second instruction's products are exchanged so that both
    # multipliers keep their operands
    x = [decode(w) for w in assemble(".reg a 3\n.reg b 7\n.reg c 5\n.reg d 6\n"
                                     "db[9] = a*b + c*d\nacc = c*d - a*b\nhalt\n").words]
    ports = lambda w: (w["a"], w["b"], w["d"], w["e"])  # noqa: E731
    assert ports(x[0]) == ports(x[1])
    # the product of 3 and 7 is subtracted, wherever it went
    assert x[1]["n1" if {x[1]["a"], x[1]["b"]} == {3, 7} else "n2"] == 1


def test_low_power_encoding_fills_unused_fields():
    x = [decode(w) for w in assemble(".reg a 3\n.reg b 7\ndb[9] = a + b*b - a*b\n"
                                     "acc = b*rinv\nhalt\n").words]
    # the second instruction keeps c, d, e, dst; HALT keeps everything
    assert (x[1]["c"], x[1]["d"], x[1]["e"], x[1]["dst"]) == (x[0]["c"], x[0]["d"], x[0]["e"], 9)
    assert {k: v for k, v in x[2].items() if k != "op"} == {k: v for k, v in x[1].items() if k != "op"}


def test_low_power_encoding_preserves_behavior():
    """Re-encoded random programs give the same registers, cycle counts and
    stalls as the plain encoding."""
    r = np.random.default_rng(11)
    for n in range(40):
        src = random_program(r)
        plain, opt = assemble(src, optimize=False), assemble(src)
        assert plain.words != opt.words
        for _ in range(3):
            init = [int(v) for v in r.integers(0, 1 << 24, size=32)]
            out = []
            for prog in (plain, opt):
                iss = Iss(prog.words, strict=False)
                for addr, word in enumerate(init):
                    iss.write(addr, word)
                cycles = iss.run()
                out.append((cycles, iss.stalls, [iss.read(a) for a in range(32)]))
            assert out[0] == out[1], f"program {n}"


def test_committed_rom_is_up_to_date():
    rom = (ROOT / "rtl" / "kf_rom.v").read_text()
    assert rom == to_verilog(PROG), "rtl/kf_rom.v is stale: run 'make rom'"


@pytest.mark.parametrize("src, msg", [
    ("acc = rinv*one\nhalt", "one factor must be a register"),
    ("db[1] = db[2] + acc*db[3]\nhalt", "'acc' can only be"),
    ("acc = db[1]*db[2] + db[3]*db[4] + db[5]*db[6]\nhalt", "at most two products"),
    ("acc = db[1] + db[2] + acc\nhalt", "the addend"),
    ("acc = acc\nhalt", "at least one product"),
    ("acc = db[1]*db[2] db[3]\nhalt", "expected '\\+' or '-'"),
    ("sr = db[1]*db[2]\nhalt", "unknown register"),
    ("rcp db[1], db[2]\nhalt", "rcp expects one register"),
    ("acc = db[1]*db[2]", "must end with 'halt'"),
    (".reg x 40\nhalt", "out of range"),
    ("jmp db[1]\nhalt", "unknown instruction"),
])
def test_assembler_rejects(src, msg):
    with pytest.raises(AsmError, match=msg):
        assemble(src)


# ----------------------------------------------------------- pipeline timing

@pytest.mark.parametrize("src, cycles, stalls", [
    # one instruction: HALT ends the run while it is in EX (it commits on
    # the next edge, before the host can see the register file)
    ("acc = db[1]*one\nhalt", 2, 0),
    # operand written by the instruction just ahead: one stall, then the
    # result is forwarded from WB; on any of the four factors
    ("db[2] = db[1]*one\nacc = db[2]*one\nhalt", 4, 1),
    ("db[2] = db[1]*one\nacc = db[1]*db[2]\nhalt", 4, 1),
    ("db[2] = db[1]*one\nacc = db[1]*db[1] + db[2]*rinv\nhalt", 4, 1),
    ("db[2] = db[1]*one\nacc = db[1]*db[1] - db[1]*db[2]\nhalt", 4, 1),
    # ... written two instructions ahead: forwarded, no stall
    ("db[2] = db[1]*one\nnop\nacc = db[2]*one\nhalt", 4, 0),
    ("db[2] = db[1]*one\nnop\nnop\nacc = db[2]*one\nhalt", 5, 0),
    # the base is read in EX: never a stall
    ("db[2] = db[1]*one\ndb[3] = db[2] + db[1]*db[1]\nhalt", 3, 0),
    ("acc = db[1]*one\nacc = acc + db[1]*db[1]\nhalt", 3, 0),
    # RINV: the reciprocal unit takes the result in WB, works RCP_CYCLES
    # cycles and forwards RINV in the last
    ("rcp db[1]\nacc = db[1]*rinv\nhalt", 2 + RCP_CYCLES + 2, 1 + RCP_CYCLES),
    # starting the unit while it is busy or about to start waits for it
    ("rcp db[1]\nrcp db[2]\nhalt", 2 * (2 + RCP_CYCLES) + 3, 2 + RCP_CYCLES),
    # HALT waits for the reciprocal unit
    ("rcp db[1]\nhalt", 2 + RCP_CYCLES + 2, 0),
    ("db[2] = db[1]*one\nrcp db[2]\nhalt", 2 + 2 + RCP_CYCLES + 2, 1),
])
def test_pipeline_timing(src, cycles, stalls):
    iss = Iss(assemble(src).words, strict=False)
    iss.write(1, fixed.ONE)
    assert iss.run() == cycles
    assert iss.stalls == stalls


def test_instruction_semantics():
    p = assemble(".reg a 1\n.reg b 2\n.reg d 3\nacc = a*b\nacc = acc + a*b - a*a\n"
                 "d = acc + b*b\nrcp b\ndb[4] = a*rinv\ndb[5] = d + a*b\n"
                 "db[6] = d - b*b\ndb[7] = a + b\ndb[8] = a - b\ndb[9] = b\n"
                 "db[10] = db[5] + a*one\ndb[11] = -a*b - d*rinv\n"
                 "db[12] = a*b + d*one, rcp\ndb[13] = b*rinv\nhalt")
    iss = Iss(p.words, strict=False)
    a, b = fixed.from_float(1.5), fixed.from_float(-2.25)
    iss.write(1, a)
    iss.write(2, b)
    iss.run()
    P = fixed.product
    acc = fixed.dot(P(a, b) + P(a, b), -P(a, a))
    d = fixed.dot(fixed.to_int(acc), P(b, b))
    assert iss.read(3) == d
    assert iss.read(4) == fixed.mul(a, fixed.rcp(b))
    assert iss.read(5) == fixed.dot(fixed.to_int(d), P(a, b))
    assert iss.read(6) == fixed.dot(fixed.to_int(d), -P(b, b))
    assert iss.read(7) == fixed.add(a, b)
    assert iss.read(8) == fixed.sub(a, b)
    assert iss.read(9) == b
    assert iss.read(10) == fixed.add(iss.read(5), a)
    assert iss.read(11) == fixed.dot(-P(a, b), -P(d, fixed.rcp(b)))
    assert iss.read(12) == fixed.dot(P(a, b), fixed.to_int(d))
    assert iss.read(13) == fixed.mul(b, fixed.rcp(iss.read(12)))


# ----------------------------------------------------------------- microcode

def test_microcode_is_the_kalman_filter():
    """Exact (float) execution of the microcode == textbook KF equations."""
    for _ in range(100):
        p = ref.random_params(rng)
        y = float(rng.normal())
        bank = [0.0] * 32
        for name, v in p.registers().items():
            bank[REG[name]] = v
        bank[REG["y"]] = y
        out = execute_float(PROG.words, bank)
        x, P = ref.kf_step(p.x, p.P, p, y)
        got = [out[REG[n]] for n in STATE]
        np.testing.assert_allclose(got, [x[0], x[1], P[0, 0], P[0, 1], P[1, 1]],
                                   rtol=1e-12, atol=1e-12)


def test_no_uninitialized_reads_and_cycle_count():
    iss = Iss(PROG.words, strict=True)
    load(iss, ref.tracking_params())
    iss.write(REG["y"], fixed.from_float(0.5))
    assert iss.run() == 24
    assert iss.stalls == 1
    with pytest.raises(UninitializedRead):
        Iss(PROG.words, strict=True).run()


def test_matches_original_course_rtl():
    """On the original project's test case (h1 = 1, h2 = 0, phi21 = 0,
    G = 0) the program forms exactly the truncated products the original
    microcode formed, and the sums are exact (no saturation), so it
    reproduces all 5000 outputs of the original NC-Verilog run bit for bit
    (tests/data, branch legacy-tsmc65)."""
    with gzip.open(ROOT / "tests" / "data" / "legacy_rtl_states.txt.gz", "rt") as f:
        golden = np.loadtxt(f, dtype=int)
    _, meas = ref.tracking_data(5000)
    iss = Iss(PROG.words)
    load(iss, ref.tracking_params())
    for k, y in enumerate(meas):
        iss.write(REG["y"], fixed.from_float(y))
        iss.run()
        got = (fixed.to_int(iss.read(REG["x1"])), fixed.to_int(iss.read(REG["x2"])))
        assert got == tuple(golden[k]), f"iteration {k + 1}"


def test_tracking_accuracy():
    truth, meas = ref.tracking_data(5000)
    iss = Iss(PROG.words)
    load(iss, ref.tracking_params())
    hw = []
    for y in meas:
        iss.write(REG["y"], fixed.from_float(y))
        iss.run()
        hw.append(fixed.to_float(iss.read(REG["x1"])))
    hw = np.array(hw)
    assert np.abs(hw - ref.run_float(ref.tracking_params(), meas)[:, 0]).max() < 5e-4
    assert np.mean((hw - truth) ** 2) < 0.35 * np.mean((meas - truth) ** 2)


def test_random_systems_accuracy():
    for seed in range(8):
        r = np.random.default_rng(seed)
        p = ref.random_params(r)
        ys = ref.simulate(p, 300, r)
        iss = Iss(PROG.words)
        load(iss, p)
        hw = []
        for y in ys:
            iss.write(REG["y"], fixed.from_float(y))
            iss.run()
            hw.append([fixed.to_float(iss.read(REG["x1"])), fixed.to_float(iss.read(REG["x2"]))])
        err = np.abs(np.array(hw) - ref.run_float(p, ys)).max()
        assert err < 0.02, f"seed {seed}: max |fixed - float| = {err}"
