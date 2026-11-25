"""Plot the tracking scenario: truth, measurements, float KF and the
bit-exact hardware model (identical to the RTL, see tb/test_kf_top.py).

    python -m kfasic.plot docs/img/tracking.png [iterations]
"""

import sys
from pathlib import Path

import numpy as np

from . import fixed
from . import reference as ref
from .asm import assemble_file
from .iss import Iss

ROOT = Path(__file__).resolve().parents[1]


def run_hw(params, ys):
    prog = assemble_file(ROOT / "fw" / "kf_2d.s")
    iss = Iss(prog.words)
    for name, w in ref.quantize(params).items():
        iss.write(prog.regs[name], w)
    out = []
    for y in ys:
        iss.write(prog.regs["y"], fixed.from_float(y))
        iss.run()
        out.append([fixed.to_float(iss.read(prog.regs["x1"])), fixed.to_float(iss.read(prog.regs["x2"]))])
    return np.array(out)


def main(argv=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    argv = argv if argv is not None else sys.argv[1:]
    out = argv[0] if argv else "tracking.png"
    n = int(argv[1]) if len(argv) > 1 else 500
    params = ref.tracking_params()
    truth, meas = ref.tracking_data(5000)
    truth, meas = truth[:n], meas[:n]
    hw = run_hw(params, meas)
    fl = ref.run_float(params, meas)
    k = np.arange(1, n + 1)

    mse_raw = np.mean((meas - truth) ** 2)
    mse_hw = np.mean((hw[:, 0] - truth) ** 2)
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(10, 6.5), sharex=True,
                                 gridspec_kw={"height_ratios": [3, 1.3]})
    a1.plot(k, meas, color="0.65", lw=0.8, label="measurement")
    a1.plot(k, truth, color="tab:green", lw=2, label="ground truth")
    a1.plot(k, fl[:, 0], color="tab:blue", lw=1.5, ls="--", label="float KF")
    a1.plot(k, hw[:, 0], color="tab:red", lw=1.2, ls=":", label="ASIC (Q9.14, bit-exact model)")
    a1.set_ylabel("position x1")
    a1.set_title(f"Tracking, {n} iterations: MSE {mse_raw:.4f} (raw) -> {mse_hw:.4f} (filtered), "
                 f"{100 * (1 - mse_hw / mse_raw):.0f}% lower")
    a1.legend(loc="upper left", fontsize=9)
    a1.grid(alpha=0.3)
    a2.plot(k, (hw[:, 0] - fl[:, 0]) * 1e3, color="tab:red", lw=0.8)
    a2.set_ylabel("ASIC - float\n(x1e-3)")
    a2.set_xlabel("iteration")
    a2.grid(alpha=0.3)
    fig.tight_layout()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=130)
    print(f"wrote {out}: MSE raw {mse_raw:.5f}, filtered {mse_hw:.5f}, "
          f"max |ASIC - float| {np.abs(hw[:, 0] - fl[:, 0]).max():.6f}")


if __name__ == "__main__":
    main()
