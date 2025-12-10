// -----------------------------------------------------------------------------
// au_basic_tb.v
// Testbench for 1-cycle AU operations: ADD, SUB, MUL
// Tests per paper: ADD (1 cycle), SUB (1 cycle), MUL (1 cycle)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module au_basic_tb();
    parameter W = 24;
    parameter FRAC = 14;

    reg clk;
    reg rst_n;
    reg [W-1:0] R, S, I;        // Operands (per paper naming)
    reg [1:0] ctl_d;            // Operation select (per paper naming)
    reg start;
    wire [W-1:0] result;
    wire done, busy;

    // Instantiate AU with paper's port names
    au #(.W(W), .FRAC(FRAC)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .R      (R),
        .S      (S),
        .I      (I),
        .ctl_d  (ctl_d),
        .result (result),
        .done   (done),
        .busy   (busy)
    );

    // Clock generation (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // Convert integer to sign-magnitude Q9.14 format
    function [W-1:0] to_fixed;
        input integer val;
        reg sign_bit;
        reg [W-2:0] magnitude;
        begin
            sign_bit = (val < 0);
            if (val < 0)
                val = -val;
            magnitude = val << FRAC;
            to_fixed = {sign_bit, magnitude};
        end
    endfunction

    // Convert sign-magnitude Q9.14 to real for display
    function real to_real;
        input [W-1:0] fixed_val;
        integer signed_mag;
        integer signed_val;
        begin
            signed_mag = fixed_val[W-2:0];
            signed_val = (fixed_val[W-1]) ? -signed_mag : signed_mag;
            to_real = signed_val / (16384.0); // 2^14
        end
    endfunction

    // Compare two sign-magnitude values (handles +0 vs -0)
    function values_match;
        input [W-1:0] a, b;
        begin
            // If both magnitudes are zero, they match regardless of sign
            if (a[W-2:0] == 0 && b[W-2:0] == 0)
                values_match = 1;
            else
                values_match = (a === b);
        end
    endfunction

    integer i, j;
    reg passed;
    reg [W-1:0] expected;

    initial begin
        // Initialize signals
        start = 0;
        rst_n = 0;
        passed = 1;
        I = 0;  // Immediate not used for basic ops

        // Hold reset for a few cycles
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("========================================");
        $display("Testing AU Basic Operations (1-cycle)");
        $display("Per paper: ADD, SUB, MUL each take 1 cycle");
        $display("========================================");

        // ==================== Test ADD ====================
        $display("\n--- Testing ADD (ctl_d=00) ---");
        ctl_d = 2'b00;
        for (i = -4; i <= 4; i = i + 1) begin
            for (j = -4; j <= 4; j = j + 1) begin
                R = to_fixed(i);
                S = to_fixed(j);
                start = 1;
                @(posedge clk);
                start = 0;
                @(posedge clk); // ST_SIMPLE state
                @(posedge clk); // Result registered

                expected = to_fixed(i + j);
                if (!values_match(result, expected)) begin
                    passed = 0;
                    $display("FAIL: %0d + %0d = %.3f (expected %.3f)",
                             i, j, to_real(result), to_real(expected));
                end
            end
        end
        $display("ADD tests completed");

        // ==================== Test SUB ====================
        $display("\n--- Testing SUB (ctl_d=01) ---");
        ctl_d = 2'b01;
        for (i = -4; i <= 4; i = i + 1) begin
            for (j = -4; j <= 4; j = j + 1) begin
                R = to_fixed(i);
                S = to_fixed(j);
                start = 1;
                @(posedge clk);
                start = 0;
                @(posedge clk);
                @(posedge clk);

                expected = to_fixed(i - j);
                if (!values_match(result, expected)) begin
                    passed = 0;
                    $display("FAIL: %0d - %0d = %.3f (expected %.3f)",
                             i, j, to_real(result), to_real(expected));
                end
            end
        end
        $display("SUB tests completed");

        // ==================== Test MUL ====================
        $display("\n--- Testing MUL (ctl_d=10) ---");
        ctl_d = 2'b10;
        for (i = -4; i <= 4; i = i + 1) begin
            for (j = -4; j <= 4; j = j + 1) begin
                R = to_fixed(i);
                S = to_fixed(j);
                start = 1;
                @(posedge clk);
                start = 0;
                @(posedge clk);
                @(posedge clk);

                expected = to_fixed(i * j);
                if (!values_match(result, expected)) begin
                    passed = 0;
                    $display("FAIL: %0d * %0d = %.3f (expected %.3f)",
                             i, j, to_real(result), to_real(expected));
                end
            end
        end
        $display("MUL tests completed");

        // Summary
        $display("\n========================================");
        if (passed)
            $display("ALL BASIC TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        $display("========================================\n");

        $finish;
    end
endmodule
