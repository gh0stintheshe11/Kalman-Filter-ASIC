"""Fast pure-Python checks of the arithmetic model, assembler and microcode."""

import gzip
from pathlib import Path

import numpy as np
import pytest

from kfasic import fixed
from kfasic import reference as ref
from kfasic.asm import AsmError, assemble, assemble_file, decode, to_verilog
from kfasic.iss import Iss, UninitializedRead, execute_float

ROOT = Path(__file__).resolve().parents[1]
PROG = assemble_file(ROOT / "fw" / "kf_2d.s")
rng = np.random.default_rng(2016)


def random_words(n):
    """Random words with a bias toward edge cases."""
    edge = [0, fixed.SIGN_BIT, 1, fixed.SIGN_BIT | 1, fixed.MAG_MAX, fixed.MASK,
            fixed.ONE, fixed.SIGN_BIT | fixed.ONE, fixed.from_float(511.5)]
    out = list(edge)
    out += [int(v) for v in rng.integers(0, 1 << 24, size=n)]
    out += [fixed.from_float(v) for v in rng.normal(0, 3, size=n)]
    return out


# ---------------------------------------------------------------- arithmetic

def hw_reciprocal(s):
    """Bit-serial successive approximation exactly as the RTL performs it."""
    q = 0
    for i in range(fixed.MAG_BITS - 1, -1, -1):
        t = q | (1 << i)
        if t * fixed.mag_of(s) <= 1 << (2 * fixed.FRAC):
            q = t
    return q


def test_reciprocal_matches_successive_approximation():
    for s in random_words(2000):
        assert fixed.reciprocal_mag(s) == hw_reciprocal(s), hex(s)


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
    for r in random_words(200):
        for s in random_words(20):
            a, b = fixed.to_int(r), fixed.to_int(s)
            clip = lambda v: max(-fixed.MAG_MAX, min(fixed.MAG_MAX, v))  # noqa: E731
            assert fixed.to_int(fixed.add(r, s)) == clip(a + b)
            assert fixed.to_int(fixed.sub(r, s)) == clip(a - b)


def test_mul_truncates_toward_zero():
    for r in random_words(200):
        for s in random_words(20):
            exact = fixed.to_int(r) * fixed.to_int(s)
            mag = min(abs(exact) >> fixed.FRAC, fixed.MAG_MAX)
            assert fixed.to_int(fixed.mul(r, s)) == (mag if exact >= 0 else -mag)


def test_div_error_bound():
    # R/S = R * (1/S): 1/S is truncated to 1 LSB and the product truncated
    # again, so |error| <= (|R| + 1) LSB.  (Kalman gain range: |R| <= |S|.)
    lsb = 2.0 ** -fixed.FRAC
    for _ in range(3000):
        s = fixed.from_float(rng.uniform(0.01, 50) * rng.choice([-1, 1]))
        r = fixed.from_float(rng.uniform(-1, 1) * abs(fixed.to_float(s)))
        rv, sv = fixed.to_float(r), fixed.to_float(s)
        q = fixed.to_float(fixed.div(r, s))
        assert abs(q - rv / sv) <= (abs(rv) + 1) * lsb


# ----------------------------------------------------------------- assembler

def test_assembler_encodings():
    p = assemble(".reg a 3\n.reg b 7\nmul sr, a, b\nmov a, sr\nadd a, a, b\n"
                 "div sr, a, b\nnop\nhalt\n")
    assert p.words == [0x19CA, 0x1801, 0x19C3, 0x19DE, 0x0000, 0x0020]
    assert decode(0x19DE) == {"a": 3, "b": 7, "c": 1, "d": 3, "e": 1, "f": 0}


def test_committed_rom_is_up_to_date():
    rom = (ROOT / "rtl" / "kf_rom.v").read_text()
    assert rom == to_verilog(PROG), "rtl/kf_rom.v is stale: run 'make rom'"


@pytest.mark.parametrize("src, msg", [
    ("div db[1], db[1], db[2]\nhalt", "div can only target sr"),
    ("add db[3], db[1], db[2]\nhalt", "must be the first source"),
    ("add sr, db[1], nope\nhalt", "unknown register"),
    ("add sr, db[1], db[2]", "must end with 'halt'"),
    (".reg x 40\nhalt", "out of range"),
])
def test_assembler_rejects(src, msg):
    with pytest.raises(AsmError, match=msg):
        assemble(src)


# ----------------------------------------------------------------- microcode

def load(iss, params: ref.KfParams):
    for name, word in ref.quantize(params).items():
        iss.write(PROG.regs[name], word)


def test_microcode_is_the_kalman_filter():
    """Exact (float) execution of the microcode == textbook KF equations."""
    for _ in range(50):
        p = ref.random_params(rng)
        y = float(rng.normal())
        bank = [0.0] * 32
        for name, v in p.registers().items():
            bank[PROG.regs[name]] = v
        bank[PROG.regs["y"]] = y
        out = execute_float(PROG.words, bank)
        x, P = ref.kf_step(p.x, p.P, p, y)
        got = [out[PROG.regs[n]] for n in ("x1", "x2", "p11", "p12", "p21", "p22")]
        np.testing.assert_allclose(got, [*x, *P.ravel()], rtol=1e-12, atol=1e-12)


def test_no_uninitialized_reads_and_cycle_count():
    iss = Iss(PROG.words, strict=True)
    load(iss, ref.tracking_params())
    iss.write(PROG.regs["y"], fixed.from_float(0.5))
    assert iss.run() == 188
    with pytest.raises(UninitializedRead):
        Iss(PROG.words, strict=True).run()


def test_matches_original_rtl_5000_iterations():
    """Bit-exact against the original course RTL (legacy-tsmc65 branch)."""
    with gzip.open(ROOT / "tests" / "data" / "legacy_rtl_states.txt.gz", "rt") as f:
        golden = np.loadtxt(f, dtype=int)
    _, meas = ref.tracking_data(5000)
    iss = Iss(PROG.words)
    load(iss, ref.tracking_params())
    for k, y in enumerate(meas):
        iss.write(PROG.regs["y"], fixed.from_float(y))
        iss.run()
        got = (fixed.to_int(iss.read(0)), fixed.to_int(iss.read(1)))
        assert got == tuple(golden[k]), f"iteration {k + 1}"


def test_fixed_point_tracks_float_reference():
    for seed in range(5):
        r = np.random.default_rng(seed)
        p = ref.random_params(r)
        ys = ref.simulate(p, 300, r)
        iss = Iss(PROG.words)
        load(iss, p)
        hw = []
        for y in ys:
            iss.write(PROG.regs["y"], fixed.from_float(y))
            iss.run()
            hw.append([fixed.to_float(iss.read(0)), fixed.to_float(iss.read(1))])
        err = np.abs(np.array(hw) - ref.run_float(p, ys)).max()
        assert err < 0.02, f"seed {seed}: max |fixed - float| = {err}"
