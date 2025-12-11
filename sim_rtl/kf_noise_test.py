#!/usr/bin/env python3
"""
Kalman Filter Noise Test
Generates ground truth trajectory, adds measurement noise, and compares
KF estimates to ground truth to demonstrate filtering performance.

This script:
1. Generates a ground truth trajectory (constant velocity motion)
2. Adds Gaussian measurement noise to create noisy observations
3. Runs the Kalman Filter on noisy measurements
4. Compares KF estimates vs ground truth vs raw measurements
5. Outputs measurements for ASIC testing
"""

import numpy as np
import sys

def run_kf_iteration(x, P, Phi, Q, H, R, G, u, y):
    """Run one KF iteration (predict + update) per paper Eq. 3-7"""

    # === TIME UPDATE (Predict) - Eq. 3, 4 ===
    x_pred = Phi @ x + G * u
    P_pred = Phi @ P @ Phi.T + Q

    # === MEASUREMENT UPDATE (Correct) - Eq. 5, 6, 7 ===
    S = H @ P_pred @ H.T + R
    K = P_pred @ H.T / S
    innovation = y - H @ x_pred
    x_upd = x_pred + K * innovation
    I = np.eye(len(x))
    P_upd = (I - K @ H) @ P_pred

    return x_upd, P_upd, K, x_pred, P_pred, S, innovation

def generate_ground_truth(num_steps, dt, x0, v0, process_noise_std=0.0):
    """
    Generate ground truth trajectory for constant velocity motion.
    x(t) = x0 + v0*t (with optional process noise)
    """
    positions = []
    velocities = []

    pos = x0
    vel = v0

    for i in range(num_steps):
        positions.append(pos)
        velocities.append(vel)
        # Update with constant velocity model + optional process noise
        pos = pos + vel * dt + np.random.normal(0, process_noise_std)
        vel = vel + np.random.normal(0, process_noise_std * 0.1)  # Small velocity noise

    return np.array(positions), np.array(velocities)

def add_measurement_noise(positions, noise_std):
    """Add Gaussian noise to position measurements"""
    noise = np.random.normal(0, noise_std, len(positions))
    return positions + noise, noise

def main():
    # Set random seed for reproducibility
    np.random.seed(42)

    print("=" * 70)
    print("Kalman Filter Noise Test - Ground Truth vs Noisy Measurements vs KF")
    print("=" * 70)

    # === Parameters (matching ASIC implementation) ===
    dt = 0.1                    # Time step
    num_iterations = 20         # Number of KF iterations

    # Initial true state
    true_x0 = 0.0               # Initial position
    true_v0 = 1.0               # Initial velocity (constant)

    # Noise parameters
    measurement_noise_std = 0.3  # Standard deviation of measurement noise (sqrt(R))
    process_noise_std = 0.1      # Small process noise for realism

    # KF System matrices (same as ASIC)
    Phi = np.array([[1.0, dt],
                    [0.0, 1.0]])

    Q = np.array([[0.01, 0.0],
                  [0.0,  0.01]])

    H = np.array([[1.0, 0.0]])

    R = np.array([[0.1]])  # measurement_noise_std^2 ~ 0.09, using 0.1

    G = np.array([[0.0], [0.0]])
    u = 0.0

    # Initial KF state (uncertain initial estimate)
    x_kf = np.array([[0.0], [1.0]])
    P_kf = np.array([[1.0, 0.0],
                     [0.0, 1.0]])

    print("\nSystem Configuration:")
    print(f"  Time step (dt): {dt}")
    print(f"  Number of iterations: {num_iterations}")
    print(f"  True initial position: {true_x0}")
    print(f"  True initial velocity: {true_v0}")
    print(f"  Measurement noise std: {measurement_noise_std}")
    print(f"  R (measurement variance): {R[0,0]}")
    print(f"  Q (process noise): diag({Q[0,0]}, {Q[1,1]})")

    # === Step 1: Generate Ground Truth ===
    print("\n" + "=" * 70)
    print("Step 1: Generating Ground Truth Trajectory")
    print("=" * 70)

    true_positions, true_velocities = generate_ground_truth(
        num_iterations, dt, true_x0, true_v0, process_noise_std
    )

    # === Step 2: Add Measurement Noise ===
    print("\nStep 2: Adding Measurement Noise")

    noisy_measurements, noise_values = add_measurement_noise(
        true_positions, measurement_noise_std
    )

    # === Step 3: Run Kalman Filter ===
    print("\nStep 3: Running Kalman Filter on Noisy Measurements")
    print("=" * 70)

    kf_positions = []
    kf_velocities = []
    kf_position_errors = []
    kf_velocity_errors = []
    raw_position_errors = []

    print(f"\n{'Iter':>4} | {'True Pos':>9} | {'Measured':>9} | {'KF Est':>9} | "
          f"{'Raw Err':>8} | {'KF Err':>8} | {'True Vel':>9} | {'KF Vel':>9}")
    print("-" * 95)

    for i in range(num_iterations):
        y = np.array([[noisy_measurements[i]]])

        # Run KF iteration
        x_kf, P_kf, K, x_pred, P_pred, S, innov = run_kf_iteration(
            x_kf, P_kf, Phi, Q, H, R, G, u, y
        )

        # Store results
        kf_pos = x_kf[0, 0]
        kf_vel = x_kf[1, 0]
        kf_positions.append(kf_pos)
        kf_velocities.append(kf_vel)

        # Calculate errors
        raw_err = abs(noisy_measurements[i] - true_positions[i])
        kf_err = abs(kf_pos - true_positions[i])
        vel_err = abs(kf_vel - true_velocities[i])

        kf_position_errors.append(kf_err)
        kf_velocity_errors.append(vel_err)
        raw_position_errors.append(raw_err)

        print(f"{i+1:>4} | {true_positions[i]:>9.4f} | {noisy_measurements[i]:>9.4f} | "
              f"{kf_pos:>9.4f} | {raw_err:>8.4f} | {kf_err:>8.4f} | "
              f"{true_velocities[i]:>9.4f} | {kf_vel:>9.4f}")

    # === Step 4: Statistical Analysis ===
    print("\n" + "=" * 70)
    print("Step 4: Error Analysis")
    print("=" * 70)

    raw_rmse = np.sqrt(np.mean(np.array(raw_position_errors)**2))
    kf_rmse = np.sqrt(np.mean(np.array(kf_position_errors)**2))
    vel_rmse = np.sqrt(np.mean(np.array(kf_velocity_errors)**2))

    print(f"\nPosition Estimation:")
    print(f"  Raw Measurement RMSE:  {raw_rmse:.6f}")
    print(f"  KF Estimate RMSE:      {kf_rmse:.6f}")
    print(f"  Improvement:           {(1 - kf_rmse/raw_rmse)*100:.1f}%")

    print(f"\nVelocity Estimation:")
    print(f"  KF Velocity RMSE:      {vel_rmse:.6f}")
    print(f"  (Note: velocity is not directly measured, only estimated by KF)")

    print(f"\nFinal State Comparison:")
    print(f"  True Position:    {true_positions[-1]:.6f}")
    print(f"  KF Position:      {kf_positions[-1]:.6f}")
    print(f"  True Velocity:    {true_velocities[-1]:.6f}")
    print(f"  KF Velocity:      {kf_velocities[-1]:.6f}")

    # === Step 5: Output for ASIC Testing ===
    print("\n" + "=" * 70)
    print("Step 5: Measurements for ASIC Testing")
    print("=" * 70)
    print("\nCopy these measurements to testbench for ASIC verification:")
    print("(First 10 measurements shown, use --all for complete list)")

    n_show = min(10, num_iterations)
    print(f"\nreal measurements [0:{n_show-1}];")
    for i in range(n_show):
        # Clamp to reasonable fixed-point range
        val = max(-7.9, min(7.9, noisy_measurements[i]))
        print(f"measurements[{i}] = {val:.4f};")

    print(f"\n// Expected KF results after {n_show} iterations:")
    print(f"// x1 (position) = {kf_positions[n_show-1]:.6f}")
    print(f"// x2 (velocity) = {kf_velocities[n_show-1]:.6f}")

    # === Optional: Generate Verilog-compatible output ===
    if "--verilog" in sys.argv:
        print("\n" + "=" * 70)
        print("Verilog Testbench Code")
        print("=" * 70)
        print(f"\n// {num_iterations} noisy measurements for KF testing")
        print(f"real measurements [0:{num_iterations-1}];")
        print("initial begin")
        for i in range(num_iterations):
            val = max(-7.9, min(7.9, noisy_measurements[i]))
            print(f"  measurements[{i}] = {val:.6f};")
        print("end")

    # === Summary ===
    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    print(f"""
The Kalman Filter successfully reduces measurement noise:
- Raw measurements have RMSE of {raw_rmse:.4f}
- KF estimates have RMSE of {kf_rmse:.4f} ({(1 - kf_rmse/raw_rmse)*100:.1f}% improvement)
- KF also estimates velocity ({kf_velocities[-1]:.4f}) which is not directly measured

This demonstrates the KF's ability to:
1. Filter out measurement noise
2. Estimate hidden state variables (velocity)
3. Provide smoother trajectory estimates
""")

if __name__ == "__main__":
    main()