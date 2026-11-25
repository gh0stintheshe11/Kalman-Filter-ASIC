"""Bit-accurate model of the datapath arithmetic.

Number format (paper, Sec. 3): 24-bit sign-magnitude fixed point, Q9.14

    bit 23      sign (1 = negative)
    bits 22..0  magnitude: 9 integer bits + 14 fractional bits

Range is +/-(512 - 2**-14), resolution 2**-14 (~6.1e-5).

Every function here defines *exactly* what the RTL computes; the RTL tests
compare against these bit for bit.  Rules shared by all operations:

* results saturate to the largest magnitude instead of wrapping;
* a zero result is always +0 (the hardware never produces -0);
* MUL/DIV truncate the magnitude (round toward zero).
"""

from __future__ import annotations

W = 24                      # word width
FRAC = 14                   # fractional bits
MAG_BITS = W - 1            # magnitude bits
MAG_MAX = (1 << MAG_BITS) - 1
SIGN_BIT = 1 << MAG_BITS
ONE = 1 << FRAC             # 1.0 in Q9.14
MASK = (1 << W) - 1


def pack(sign: int, mag: int) -> int:
    """Build a word from sign and magnitude, normalizing -0 to +0."""
    if mag < 0 or mag > MAG_MAX:
        raise ValueError(f"magnitude out of range: {mag}")
    return ((sign & 1) << MAG_BITS) | mag if mag else 0


def sign_of(w: int) -> int:
    return (w >> MAG_BITS) & 1


def mag_of(w: int) -> int:
    return w & MAG_MAX


def to_int(w: int) -> int:
    """Signed value in LSBs (units of 2**-14)."""
    return -mag_of(w) if sign_of(w) else mag_of(w)


def from_int(v: int) -> int:
    """Signed LSB count -> word, saturating."""
    return pack(1 if v < 0 else 0, min(abs(v), MAG_MAX))


def from_float(x: float) -> int:
    """Real -> word: round half away from zero, then saturate."""
    mag = int(abs(x) * ONE + 0.5)
    return pack(1 if x < 0 else 0, min(mag, MAG_MAX))


def to_float(w: int) -> float:
    return to_int(w) / ONE


# --------------------------------------------------------------------------
# Arithmetic unit operations
# --------------------------------------------------------------------------

def add(r: int, s: int) -> int:
    return from_int(to_int(r) + to_int(s))


def sub(r: int, s: int) -> int:
    return from_int(to_int(r) - to_int(s))


def _scale_product(p: int, sign: int) -> int:
    """46-bit magnitude product (Q18.28) -> Q9.14 word, truncating."""
    mag = MAG_MAX if p >> (MAG_BITS + FRAC) else (p >> FRAC) & MAG_MAX
    return pack(sign, mag)


def mul(r: int, s: int) -> int:
    return _scale_product(mag_of(r) * mag_of(s), sign_of(r) ^ sign_of(s))


def product(r: int, s: int) -> int:
    """R * S as a signed LSB count: the magnitude |R| |S| truncated to 14
    fractional bits, *not* saturated, with the sign of R * S.  Its magnitude
    is below 2^32."""
    mag = (mag_of(r) * mag_of(s)) >> FRAC
    return -mag if sign_of(r) ^ sign_of(s) else mag


def dot(base: int, *terms: int) -> int:
    """The arithmetic instruction: base + the signed products in terms,
    computed exactly and saturated once.  base is a signed LSB count (0,
    ACC or a register via to_int), terms are product() values, negated for
    subtraction.  Equal to a chain of mul/add/sub whenever no intermediate
    result of that chain saturates."""
    return from_int(base + sum(terms))


def reciprocal_mag(s: int) -> int:
    """Magnitude of 1/S as built by the successive-approximation unit.

    The hardware tests bits 22..0 and keeps a bit when Q*|S| <= 2**28
    (i.e. <= 1.0 in Q18.28), which yields the largest 23-bit Q with
    Q*|S| <= 2**28.  For S = 0 every bit is kept (Q = MAG_MAX).
    """
    sm = mag_of(s)
    if sm == 0:
        return MAG_MAX
    return min((1 << (2 * FRAC)) // sm, MAG_MAX)


def rcp(s: int) -> int:
    """1/S as produced by the reciprocal unit: sign of S, magnitude
    reciprocal_mag(S).  The magnitude is never zero (>= 32 LSB)."""
    return pack(sign_of(s), reciprocal_mag(s))


def div(r: int, s: int) -> int:
    """R / S = R * (1/S); identical to mul(r, rcp(s))."""
    return _scale_product(mag_of(r) * reciprocal_mag(s), sign_of(r) ^ sign_of(s))


OPS = {"add": add, "sub": sub, "mul": mul, "div": div}
