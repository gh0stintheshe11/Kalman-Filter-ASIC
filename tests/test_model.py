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
    p = assemble(".reg a 3\n.reg b 7\n.reg t 9\nmul acc, a, b\nmac t, a, rinv\n"
                 "lda t, b\nsub acc, a, b\nrcp b\nnop\nhalt\n")
    assert p.words == [0x0400CE, 0x0748C1, 0x0F49C0, 0x0C00CE, 0x10000E, 0x000000, 0x020000]
    assert decode(0x0748C1) == {"op": 3, "wr": 1, "dst": 9, "a": 3, "b": 0, "bi": 1}


def test_committed_rom_is_up_to_date():
    rom = (ROOT / "rtl" / "kf_rom.v").read_text()
    assert rom == to_verilog(PROG), "rtl/kf_rom.v is stale: run 'make rom'"


@pytest.mark.parametrize("src, msg", [
    ("mul acc, rinv, db[1]\nhalt", "rinv can only be operand B"),
    ("rcp rinv\nhalt", "rcp expects one register"),
    ("add sr, db[1], db[2]\nhalt", "unknown register"),
    ("lda acc, db[1], db[2]\nhalt", "lda expects"),
    ("add acc, db[1], db[2]", "must end with 'halt'"),
    (".reg x 40\nhalt", "out of range"),
    ("jmp db[1]\nhalt", "unknown mnemonic"),
])
def test_assembler_rejects(src, msg):
    with pytest.raises(AsmError, match=msg):
        assemble(src)


# ----------------------------------------------------------- pipeline timing

@pytest.mark.parametrize("src, cycles, stalls", [
    # one instruction: issue, EX, then HALT completes while it commits in WB
    ("lda acc, db[1]\nhalt", 3, 0),
    # read-after-write at distance 1 stalls two cycles (EX, then WB)
    ("lda db[2], db[1]\nlda acc, db[2]\nhalt", 6, 2),
    # ... at distance 2 one cycle, at distance 3 none
    ("lda db[2], db[1]\nnop\nlda acc, db[2]\nhalt", 6, 1),
    ("lda db[2], db[1]\nnop\nnop\nlda acc, db[2]\nhalt", 6, 0),
    # RINV is valid RCP_CYCLES cycles after RCP issues
    ("rcp db[1]\nmul acc, db[1], rinv\nhalt", 1 + RCP_CYCLES + 3, RCP_CYCLES),
    # HALT also waits for the reciprocal unit
    ("rcp db[1]\nhalt", 1 + RCP_CYCLES + 1, 0),
])
def test_pipeline_timing(src, cycles, stalls):
    iss = Iss(assemble(src).words, strict=False)
    iss.write(1, fixed.ONE)
    assert iss.run() == cycles
    assert iss.stalls == stalls


def test_accumulator_semantics():
    p = assemble(".reg a 1\n.reg b 2\n.reg d 3\nmul acc, a, b\nmac acc, a, b\nmsb acc, a, a\n"
                 "mac d, b, b\nrcp b\nmul db[4], a, rinv\nhalt")
    iss = Iss(p.words, strict=False)
    a, b = fixed.from_float(1.5), fixed.from_float(-2.25)
    iss.write(1, a)
    iss.write(2, b)
    iss.run()
    acc = fixed.mul(a, b)
    acc = fixed.add(acc, fixed.mul(a, b))
    acc = fixed.sub(acc, fixed.mul(a, a))
    acc = fixed.add(acc, fixed.mul(b, b))
    assert iss.read(3) == acc
    assert iss.read(4) == fixed.mul(a, fixed.rcp(b))


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
    assert iss.run() == 49
    assert iss.stalls == 1
    with pytest.raises(UninitializedRead):
        Iss(PROG.words, strict=True).run()


def test_matches_original_course_rtl():
    """On the original project's test case (h1 = 1, h2 = 0, phi21 = 0,
    G = 0) the optimized program forms exactly the truncated products the
    original microcode formed, and fixed-point additions are exact, so it
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
