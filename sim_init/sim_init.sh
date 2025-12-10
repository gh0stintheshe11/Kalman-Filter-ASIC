#!/bin/bash
# -----------------------------------------------------------------------------
# sim_init.sh
# Run all RTL testbenches and save logs
# Usage: ./sim_init.sh
# -----------------------------------------------------------------------------

SRC_DIR="../src"
LOG_DIR="."

# Clean up previous simulation artifacts
rm -rf INCA_libs *.log *.key *.history 2>/dev/null

echo "========================================"
echo "Running RTL Testbenches"
echo "========================================"

# Function to run a testbench and save log
run_tb() {
    local TB_NAME=$1
    local TB_FILE=$2
    shift 2
    local SRC_FILES="$@"

    echo ""
    echo "--- Running $TB_NAME ---"

    # Run simulation
    ncverilog $SRC_DIR/$TB_FILE $SRC_FILES 2>&1 | tee ${TB_NAME}.log

    # Clean up history files (we don't need them)
    rm -f *.history 2>/dev/null

    echo "Log saved: ${TB_NAME}.log"
}

# AU Basic Testbench (ADD, SUB, MUL)
run_tb "au_basic" "au_basic_tb.v" "$SRC_DIR/au.v"

# AU Inverse Testbench (DIV)
run_tb "au_inv" "au_inv_tb.v" "$SRC_DIR/au.v"

# Router A Testbench
run_tb "router_a" "router_a_tb.v" "$SRC_DIR/router_a.v"

# Router B Testbench
run_tb "router_b" "router_b_tb.v" "$SRC_DIR/router_b.v"

# Memory Registers Testbench
run_tb "mem_reg" "mem_reg_tb.v" "$SRC_DIR/mem_reg.v"

# Sequencer Testbench
run_tb "sequencer" "sequencer_tb.v" "$SRC_DIR/sequencer.v"

# KF Top-Level Testbench
run_tb "kf_top" "kf_top_tb.v" \
    "$SRC_DIR/kf_top.v" \
    "$SRC_DIR/sequencer.v" \
    "$SRC_DIR/router_a.v" \
    "$SRC_DIR/router_b.v" \
    "$SRC_DIR/mem_reg.v" \
    "$SRC_DIR/au.v"

# 1D Kalman Filter Algorithm Test
run_tb "kf_1d" "kf_1d_tb.v" \
    "$SRC_DIR/kf_top.v" \
    "$SRC_DIR/sequencer.v" \
    "$SRC_DIR/router_a.v" \
    "$SRC_DIR/router_b.v" \
    "$SRC_DIR/mem_reg.v" \
    "$SRC_DIR/au.v"

# Clean up simulation artifacts
rm -rf INCA_libs *.key *.history 2>/dev/null

echo ""
echo "========================================"
echo "All testbenches completed"
echo "========================================"
echo ""
echo "Log files:"
ls -la *.log 2>/dev/null