#!/bin/bash
# -----------------------------------------------------------------------------
# sim_post_syn.sh - Post-Synthesis Simulation Runner
# -----------------------------------------------------------------------------
# Usage:
#   ./sim_post_syn.sh              Run all sub-module post-syn tests
#   ./sim_post_syn.sh -m <module>  Run specific module (au, router_a, etc.)
#   ./sim_post_syn.sh -h           Show help
# -----------------------------------------------------------------------------

SRC_DIR="../src"
SYN_DIR="../syn"
STD_CELL_LIB="tcbn65gplus.v"

# Clean up previous artifacts
rm -rf INCA_libs *.key *.history 2>/dev/null

echo "========================================"
echo "Post-Synthesis Simulation Runner"
echo "========================================"

# Check if standard cell library exists
if [ ! -f "$STD_CELL_LIB" ]; then
    echo "ERROR: Standard cell library not found: $STD_CELL_LIB"
    exit 1
fi

# Run a post-syn testbench
run_post_syn_tb() {
    local MODULE=$1
    local TB_FILE="${SRC_DIR}/${MODULE}_tb.v"
    local SYN_FILE="${SYN_DIR}/${MODULE}_syn.v"
    local LOG_FILE="${MODULE}_post_syn.log"

    # Check files exist
    if [ ! -f "$TB_FILE" ]; then
        echo "ERROR: Testbench not found: $TB_FILE"
        return 1
    fi
    if [ ! -f "$SYN_FILE" ]; then
        echo "ERROR: Synthesized netlist not found: $SYN_FILE"
        return 1
    fi

    echo ""
    echo "--- Post-Syn Test: $MODULE ---"
    ncverilog "$TB_FILE" "$SYN_FILE" "$STD_CELL_LIB" +define+POST_SYN +access+r 2>&1 | tee "$LOG_FILE"
    rm -f *.history 2>/dev/null

    # Check for pass/fail in log
    if grep -q "PASSED" "$LOG_FILE"; then
        echo "Result: PASSED"
    elif grep -q "FAILED" "$LOG_FILE"; then
        echo "Result: FAILED"
    fi
    echo "Log: $LOG_FILE"
}

# Run all sub-module tests
run_all_tests() {
    local modules=("au" "router_a" "router_b" "mem_reg" "sequencer")
    local passed=0
    local failed=0

    for module in "${modules[@]}"; do
        run_post_syn_tb "$module"
        if grep -q "PASSED" "${module}_post_syn.log" 2>/dev/null; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    echo ""
    echo "========================================"
    echo "Summary: $passed passed, $failed failed"
    echo "========================================"
}

# Show help
show_help() {
    echo "Usage:"
    echo "  ./sim_post_syn.sh              Run all sub-module post-syn tests"
    echo "  ./sim_post_syn.sh -m <module>  Run specific module test"
    echo "  ./sim_post_syn.sh -h           Show this help"
    echo ""
    echo "Available modules: au, router_a, router_b, mem_reg, sequencer"
    echo ""
    echo "Example:"
    echo "  ./sim_post_syn.sh -m au        # Test AU module only"
    echo "  ./sim_post_syn.sh              # Test all modules"
}

# Parse arguments
case "$1" in
    -m|--module)
        if [ -z "$2" ]; then
            echo "ERROR: -m requires a module name"
            show_help
            exit 1
        fi
        run_post_syn_tb "$2"
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        run_all_tests
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

# Cleanup
rm -rf INCA_libs *.key *.history 2>/dev/null

echo ""
echo "Done"