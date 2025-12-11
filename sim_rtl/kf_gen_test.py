#!/usr/bin/env python3
"""
Kalman Filter Test Data Generator
Generates test data for ASIC verification.

Usage: python3 kf_gen_test.py <num_iterations>

Outputs:
  - truth.txt:        Ground truth positions (one value per line)
  - measurements.txt: Noisy measurements (one value per line)
  - kf_expected.txt:  Expected KF outputs after each iteration (x1, x2 per line)
"""

import numpy as np
import sys

def run_kf_iteration(x, P, Phi, Q, H, R, y):
    """Run one KF iteration (predict + update) per paper Eq. 3-7"""
    # TIME UPDATE (Predict) - Eq. 3, 4
    x_pred = Phi @ x
    P_pred = Phi @ P @ Phi.T + Q

    # MEASUREMENT UPDATE (Correct) - Eq. 5, 6, 7
    S = H @ P_pred @ H.T + R
    K = P_pred @ H.T / S
    innovation = y - H @ x_pred
    x_upd = x_pred + K * innovation
    I = np.eye(len(x))
    P_upd = (I - K @ H) @ P_pred

    return x_upd, P_upd

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 kf_gen_test.py <num_iterations>")
        sys.exit(1)

    num_iters = int(sys.argv[1])

    # Fixed random seed for reproducibility
    np.random.seed(42)

    # === Parameters (matching ASIC) ===
    dt = 0.1
    true_x0 = 0.0
    true_v0 = 0.03  # Small velocity to stay in Q9.14 range
    measurement_noise_std = 0.3
    process_noise_std = 0.1

    # KF matrices
    Phi = np.array([[1.0, dt], [0.0, 1.0]])
    Q = np.array([[0.01, 0.0], [0.0, 0.01]])
    H = np.array([[1.0, 0.0]])
    R = np.array([[0.1]])

    # Initial KF state
    x_kf = np.array([[0.0], [0.03]])
    P_kf = np.array([[1.0, 0.0], [0.0, 1.0]])

    # === Generate ground truth trajectory ===
    true_positions = []
    pos, vel = true_x0, true_v0
    for _ in range(num_iters):
        true_positions.append(pos)
        pos += vel * dt + np.random.normal(0, process_noise_std)
        vel += np.random.normal(0, process_noise_std * 0.1)

    # === Add measurement noise ===
    measurements = [p + np.random.normal(0, measurement_noise_std) for p in true_positions]

    # === Run KF and compute expected outputs ===
    kf_outputs = []
    for i in range(num_iters):
        y = np.array([[measurements[i]]])
        x_kf, P_kf = run_kf_iteration(x_kf, P_kf, Phi, Q, H, R, y)
        kf_outputs.append((x_kf[0, 0], x_kf[1, 0]))

    # === Export files ===
    with open("truth.txt", "w") as f:
        for val in true_positions:
            f.write(f"{val:.6f}\n")

    with open("measurements.txt", "w") as f:
        for val in measurements:
            f.write(f"{val:.6f}\n")

    with open("kf_expected.txt", "w") as f:
        for x1, x2 in kf_outputs:
            f.write(f"{x1:.6f} {x2:.6f}\n")

    # Print summary
    print(f"Generated {num_iters} iterations of test data:")
    print(f"  truth.txt        - {num_iters} ground truth positions")
    print(f"  measurements.txt - {num_iters} noisy measurements")
    print(f"  kf_expected.txt  - {num_iters} expected KF outputs (x1 x2)")
    print(f"\nFinal expected values:")
    print(f"  x1 (position) = {kf_outputs[-1][0]:.6f}")
    print(f"  x2 (velocity) = {kf_outputs[-1][1]:.6f}")

if __name__ == "__main__":
    main()
