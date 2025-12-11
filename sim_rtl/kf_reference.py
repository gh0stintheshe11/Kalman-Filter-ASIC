#!/usr/bin/env python3
"""
Kalman Filter Reference Implementation
Computes expected outputs for verifying the ASIC implementation.

2D KF: State = [position, velocity], Measurement = position only
Model per paper:
  x_k = Phi * x_{k-1} + G * u + w   (state transition)
  y_k = H * x_k + v                  (measurement)
"""

import numpy as np

def run_kf_iteration(x, P, Phi, Q, H, R, G, u, y):
    """Run one KF iteration (predict + update)"""

    # === TIME UPDATE (Predict) ===
    # x^- = Phi * x + G * u
    x_pred = Phi @ x + G * u

    # P^- = Phi * P * Phi^T + Q
    P_pred = Phi @ P @ Phi.T + Q

    # === MEASUREMENT UPDATE (Correct) ===
    # S = H * P^- * H^T + R
    S = H @ P_pred @ H.T + R

    # K = P^- * H^T * S^-1
    K = P_pred @ H.T / S

    # Innovation: y - H * x^-
    innovation = y - H @ x_pred

    # x^+ = x^- + K * innovation
    x_upd = x_pred + K * innovation

    # P^+ = (I - K * H) * P^-
    I = np.eye(len(x))
    P_upd = (I - K @ H) @ P_pred

    return x_upd, P_upd, K, x_pred, P_pred, S, innovation

def main():
    print("=" * 60)
    print("Kalman Filter Reference Calculation")
    print("2D State: [position, velocity], 1D Measurement: position")
    print("=" * 60)

    # === System Parameters (same as testbench) ===
    # State transition matrix (constant velocity model)
    dt = 0.1
    Phi = np.array([[1.0, dt],
                    [0.0, 1.0]])

    # Process noise covariance
    Q = np.array([[0.01, 0.0],
                  [0.0,  0.01]])

    # Measurement matrix (observe position only)
    H = np.array([[1.0, 0.0]])

    # Measurement noise covariance
    R = np.array([[0.1]])

    # Control input matrix and input (no control)
    G = np.array([[0.0], [0.0]])
    u = 0.0

    # Initial state and covariance
    x = np.array([[0.0], [1.0]])  # position=0, velocity=1
    P = np.array([[1.0, 0.0],
                  [0.0, 1.0]])

    # Test measurements (same as testbench)
    measurements = [0.5, 0.7, 0.9, 1.2, 1.5]

    print("\nSystem Parameters:")
    print(f"  Phi = {Phi.tolist()}")
    print(f"  Q = {Q.tolist()}")
    print(f"  H = {H.tolist()}")
    print(f"  R = {R.tolist()}")
    print(f"  Initial x = {x.flatten().tolist()}")
    print(f"  Initial P = {P.tolist()}")
    print(f"  Measurements = {measurements}")

    print("\n" + "=" * 60)
    print("Running 5 KF iterations...")
    print("=" * 60)

    for i, y_meas in enumerate(measurements):
        y = np.array([[y_meas]])

        x, P, K, x_pred, P_pred, S, innov = run_kf_iteration(x, P, Phi, Q, H, R, G, u, y)

        print(f"\n=== Iteration {i+1} (y = {y_meas:.2f}) ===")
        print(f"  Predict:")
        print(f"    x^- = [{x_pred[0,0]:.6f}, {x_pred[1,0]:.6f}]")
        print(f"    P^- = [[{P_pred[0,0]:.6f}, {P_pred[0,1]:.6f}],")
        print(f"           [{P_pred[1,0]:.6f}, {P_pred[1,1]:.6f}]]")
        print(f"  Update:")
        print(f"    S = {S[0,0]:.6f}")
        print(f"    K = [{K[0,0]:.6f}, {K[1,0]:.6f}]")
        print(f"    innovation = {innov[0,0]:.6f}")
        print(f"    x^+ = [{x[0,0]:.6f}, {x[1,0]:.6f}]")
        print(f"    P^+ = [[{P[0,0]:.6f}, {P[0,1]:.6f}],")
        print(f"           [{P[1,0]:.6f}, {P[1,1]:.6f}]]")

    print("\n" + "=" * 60)
    print("Final Results (for comparison with ASIC):")
    print("=" * 60)
    print(f"  x1 (position) = {x[0,0]:.6f}")
    print(f"  x2 (velocity) = {x[1,0]:.6f}")
    print(f"  P11 = {P[0,0]:.6f}")
    print(f"  P12 = {P[0,1]:.6f}")
    print(f"  P21 = {P[1,0]:.6f}")
    print(f"  P22 = {P[1,1]:.6f}")

    # Generate comparison table
    print("\n" + "=" * 60)
    print("Comparison Table Format (copy ASIC results here):")
    print("=" * 60)
    print("| Iter | y    | x1 (ref)  | x1 (ASIC) | x2 (ref)  | x2 (ASIC) |")
    print("|------|------|-----------|-----------|-----------|-----------|")

    # Re-run to generate table
    x = np.array([[0.0], [1.0]])
    P = np.array([[1.0, 0.0], [0.0, 1.0]])

    for i, y_meas in enumerate(measurements):
        y = np.array([[y_meas]])
        x, P, K, x_pred, P_pred, S, innov = run_kf_iteration(x, P, Phi, Q, H, R, G, u, y)
        print(f"|  {i+1}   | {y_meas:.2f} | {x[0,0]:.6f}  |           | {x[1,0]:.6f}  |           |")

if __name__ == "__main__":
    main()
