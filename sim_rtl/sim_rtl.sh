#!/bin/bash
# -----------------------------------------------------------------------------
# sim_rtl.sh
# Run RTL testbenches and save logs
#
# Usage:
#   ./sim_rtl.sh              Run all basic module tests (no top-level)
#   ./sim_rtl.sh -t <mem>     Run top-level test with specified .mem file
#   ./sim_rtl.sh -a           Run all tests including top-level (1D and 2D)
#
# Examples:
#   ./sim_rtl.sh                        # Run AU (comprehensive), router, mem, sequencer tests
#   ./sim_rtl.sh -t ../src/kf_1d.mem    # Run 1D KF top-level test
#   ./sim_rtl.sh -t ../src/kf_2d.mem    # Run 2D KF top-level test
#   ./sim_rtl.sh -a                     # Run everything
# -----------------------------------------------------------------------------

SRC_DIR="../src"
LOG_DIR="."

# Clean up previous simulation artifacts
rm -rf INCA_libs *.key *.history 2>/dev/null

echo "========================================"
echo "Running RTL Testbenches"
echo "========================================"

# Function to run a testbench and save log
run_tb() {
    local TB_NAME=$1
    local TB_FILE=$2
    shift 2
    local EXTRA_ARGS="$@"

    echo ""
    echo "--- Running $TB_NAME ---"

    # Run simulation
    ncverilog $TB_FILE $EXTRA_ARGS +access+r 2>&1 | tee ${TB_NAME}.log

    # Clean up history files
    rm -f *.history 2>/dev/null

    echo "Log saved: ${TB_NAME}.log"
}

# Function to run top-level test with specified .mem file
run_top_test() {
    local MEM_FILE=$1
    local MEM_NAME=$(basename "$MEM_FILE" .mem)

    if [ ! -f "$MEM_FILE" ]; then
        echo "ERROR: Memory file not found: $MEM_FILE"
        exit 1
    fi

    # Copy .mem file to current directory temporarily
    cp -f "$MEM_FILE" .

    # Determine if 1D or 2D based on filename
    local DEFINE_FLAG=""
    if [[ "$MEM_NAME" == *"1d"* ]] || [[ "$MEM_NAME" == *"1D"* ]]; then
        DEFINE_FLAG="+define+TEST_1D"
    fi

    echo ""
    echo "--- Running KF Top-Level Test: $MEM_NAME ---"
    echo "Memory file: $MEM_FILE"

    # Run simulation
    ncverilog $SRC_DIR/kf_top_tb.v \
        $SRC_DIR/kf_top.v \
        $SRC_DIR/sequencer.v \
        $SRC_DIR/router_a.v \
        $SRC_DIR/router_b.v \
        $SRC_DIR/mem_reg.v \
        $SRC_DIR/au.v \
        $DEFINE_FLAG \
        +access+r 2>&1 | tee ${MEM_NAME}.log

    # Clean up copied .mem file
    rm -f "$(basename "$MEM_FILE")" 2>/dev/null
    rm -f *.history 2>/dev/null

    echo "Log saved: ${MEM_NAME}.log"
}

# Function to run all basic module tests
run_basic_tests() {
    # AU Comprehensive Testbench (ADD, SUB, MUL, DIV, timing)
    run_tb "au" "$SRC_DIR/au_tb.v" "$SRC_DIR/au.v"

    # Router A Testbench
    run_tb "router_a" "$SRC_DIR/router_a_tb.v" "$SRC_DIR/router_a.v"

    # Router B Testbench
    run_tb "router_b" "$SRC_DIR/router_b_tb.v" "$SRC_DIR/router_b.v"

    # Memory Registers Testbench
    run_tb "mem_reg" "$SRC_DIR/mem_reg_tb.v" "$SRC_DIR/mem_reg.v"

    # Sequencer Testbench
    run_tb "sequencer" "$SRC_DIR/sequencer_tb.v" "$SRC_DIR/sequencer.v"
}

# Parse command line arguments
case "$1" in
    -t|--top)
        if [ -z "$2" ]; then
            echo "ERROR: -t requires a .mem file path"
            echo "Usage: ./sim_rtl.sh -t <path/to/file.mem>"
            exit 1
        fi
        run_top_test "$2"
        ;;
    -a|--all)
        run_basic_tests
        run_top_test "$SRC_DIR/kf_1d.mem"
        run_top_test "$SRC_DIR/kf_2d.mem"
        ;;
    -h|--help)
        echo "Usage:"
        echo "  ./sim_rtl.sh              Run all basic module tests (no top-level)"
        echo "  ./sim_rtl.sh -t <mem>     Run top-level test with specified .mem file"
        echo "  ./sim_rtl.sh -a           Run all tests including top-level (1D and 2D)"
        echo ""
        echo "Examples:"
        echo "  ./sim_rtl.sh                        # Run AU (comprehensive), router, mem, sequencer tests"
        echo "  ./sim_rtl.sh -t ../src/kf_1d.mem    # Run 1D KF top-level test"
        echo "  ./sim_rtl.sh -t ../src/kf_2d.mem    # Run 2D KF top-level test"
        echo "  ./sim_rtl.sh -a                     # Run everything"
        exit 0
        ;;
    "")
        # No arguments - run basic tests only
        run_basic_tests
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use -h for help"
        exit 1
        ;;
esac

# Clean up simulation artifacts
rm -rf INCA_libs *.key *.history *.mem 2>/dev/null

echo ""
echo "========================================"
echo "Testbench(es) completed"
echo "========================================"
echo ""
echo "Log files:"
ls -la *.log 2>/dev/null
