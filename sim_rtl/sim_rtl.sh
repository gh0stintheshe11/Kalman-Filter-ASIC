#!/bin/bash
# -----------------------------------------------------------------------------
# sim_rtl.sh - RTL Testbench Runner
# -----------------------------------------------------------------------------
# Usage:
#   ./sim_rtl.sh              Run basic module tests (AU, router, mem, sequencer)
#   ./sim_rtl.sh -t <mem>     Run top-level test with specified .mem file
#   ./sim_rtl.sh -e <N>       Run extended test with N iterations
#   ./sim_rtl.sh -a           Run all tests
#
# Examples:
#   ./sim_rtl.sh -t ../src/kf_2d.mem    # Run 2D KF test
#   ./sim_rtl.sh -e 200                  # Run 200-iteration extended test
#   ./sim_rtl.sh -e 50                   # Run 50-iteration extended test
# -----------------------------------------------------------------------------

SRC_DIR="../src"

# Clean up previous artifacts
rm -rf INCA_libs *.key *.history 2>/dev/null

echo "========================================"
echo "RTL Testbench Runner"
echo "========================================"

# Run a testbench
run_tb() {
    local TB_NAME=$1
    local TB_FILE=$2
    shift 2
    local EXTRA_ARGS="$@"

    echo ""
    echo "--- Running $TB_NAME ---"
    ncverilog $TB_FILE $EXTRA_ARGS +access+r 2>&1 | tee ${TB_NAME}.log
    rm -f *.history 2>/dev/null
    echo "Log: ${TB_NAME}.log"
}

# Run top-level test with .mem file
run_top_test() {
    local MEM_FILE=$1
    local MEM_NAME=$(basename "$MEM_FILE" .mem)

    if [ ! -f "$MEM_FILE" ]; then
        echo "ERROR: File not found: $MEM_FILE"
        exit 1
    fi

    cp -f "$MEM_FILE" .

    local DEFINE_FLAG=""
    if [[ "$MEM_NAME" == *"1d"* ]] || [[ "$MEM_NAME" == *"1D"* ]]; then
        DEFINE_FLAG="+define+TEST_1D"
    fi

    echo ""
    echo "--- Running KF Test: $MEM_NAME ---"
    ncverilog $SRC_DIR/kf_top_tb.v \
        $SRC_DIR/kf_top.v $SRC_DIR/sequencer.v \
        $SRC_DIR/router_a.v $SRC_DIR/router_b.v \
        $SRC_DIR/mem_reg.v $SRC_DIR/au.v \
        $DEFINE_FLAG +access+r 2>&1 | tee ${MEM_NAME}.log

    rm -f "$(basename "$MEM_FILE")" *.history 2>/dev/null
    echo "Log: ${MEM_NAME}.log"
}

# Run extended test
run_ext_test() {
    local NUM_ITERS=$1

    if [ -z "$NUM_ITERS" ]; then
        echo "ERROR: -e requires number of iterations"
        echo "Usage: ./sim_rtl.sh -e <N>"
        exit 1
    fi

    echo ""
    echo "========================================"
    echo "Extended KF Test - $NUM_ITERS iterations"
    echo "========================================"

    # Step 1: Generate test data
    echo ""
    echo "Step 1: Generating test data..."
    python3 kf_gen_test.py $NUM_ITERS

    if [ ! -f "measurements.txt" ] || [ ! -f "truth.txt" ] || [ ! -f "kf_expected.txt" ]; then
        echo "ERROR: Failed to generate test data"
        exit 1
    fi

    # Step 2: Run ASIC simulation
    echo ""
    echo "Step 2: Running ASIC simulation..."
    cp -f "$SRC_DIR/kf_2d.mem" .

    ncverilog $SRC_DIR/kf_top_tb.v \
        $SRC_DIR/kf_top.v $SRC_DIR/sequencer.v \
        $SRC_DIR/router_a.v $SRC_DIR/router_b.v \
        $SRC_DIR/mem_reg.v $SRC_DIR/au.v \
        +define+TEST_EXT +define+NUM_ITERS=$NUM_ITERS \
        +access+r 2>&1 | tee kf_ext.log

    rm -f kf_2d.mem *.history 2>/dev/null

    echo ""
    echo "========================================"
    echo "Extended test complete"
    echo "========================================"
    echo "Log: kf_ext.log"
    echo "Test data: measurements.txt, truth.txt, kf_expected.txt, kf_asic.txt"

    # Step 3: Generate plot
    echo ""
    echo "Step 3: Generating plot..."
    python3 kf_gen_test.py --plot
}

# Run basic module tests
run_basic_tests() {
    run_tb "au" "$SRC_DIR/au_tb.v" "$SRC_DIR/au.v"
    run_tb "router_a" "$SRC_DIR/router_a_tb.v" "$SRC_DIR/router_a.v"
    run_tb "router_b" "$SRC_DIR/router_b_tb.v" "$SRC_DIR/router_b.v"
    run_tb "mem_reg" "$SRC_DIR/mem_reg_tb.v" "$SRC_DIR/mem_reg.v"
    run_tb "sequencer" "$SRC_DIR/sequencer_tb.v" "$SRC_DIR/sequencer.v"
}

# Parse arguments
case "$1" in
    -t|--top)
        if [ -z "$2" ]; then
            echo "ERROR: -t requires a .mem file"
            exit 1
        fi
        run_top_test "$2"
        ;;
    -e|--ext)
        run_ext_test "$2"
        ;;
    -a|--all)
        run_basic_tests
        run_top_test "$SRC_DIR/kf_1d.mem"
        run_top_test "$SRC_DIR/kf_2d.mem"
        ;;
    -h|--help)
        echo "Usage:"
        echo "  ./sim_rtl.sh              Run basic module tests"
        echo "  ./sim_rtl.sh -t <mem>     Run top-level test with .mem file"
        echo "  ./sim_rtl.sh -e <N>       Run extended test with N iterations"
        echo "  ./sim_rtl.sh -a           Run all tests"
        echo ""
        echo "Examples:"
        echo "  ./sim_rtl.sh -t ../src/kf_2d.mem    # 2D KF test"
        echo "  ./sim_rtl.sh -e 200                  # 200 iterations"
        echo "  ./sim_rtl.sh -e 50                   # 50 iterations"
        exit 0
        ;;
    "")
        run_basic_tests
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use -h for help"
        exit 1
        ;;
esac

# Cleanup
rm -rf INCA_libs *.key *.history 2>/dev/null

echo ""
echo "========================================"
echo "Done"
echo "========================================"
