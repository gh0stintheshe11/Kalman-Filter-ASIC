// -----------------------------------------------------------------------------
// au_inv_tb.v
// Testbench for AU multiplicative inverse (DIV operation)
// Per paper: Multiplicative inverse takes 24 clock cycles
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module au_inv_tb();
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

    // Task to test DIV operation (R / S = R * (1/S))
    // Per paper: DIV uses multiplicative inverse, takes 24 cycles
    task test_div;
        input integer r_val;
        input integer s_val;
        real expected_real, result_real;
        real error;
        integer cycles;
        begin
            $display("\nTesting %0d / %0d:", r_val, s_val);

            // Set up DIV operation
            R = to_fixed(r_val);
            S = to_fixed(s_val);
            I = 0;
            ctl_d = 2'b11;  // DIV operation (per paper: d1d0 = 11)

            start = 1;
            @(posedge clk);
            start = 0;

            cycles = 0;
            // Wait for done signal (per paper: ~24 cycles for inverse)
            while (!done) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cycles < 5 || cycles % 10 == 0)
                    $display("  cycle %0d: done=%b, busy=%b", cycles, done, busy);
                if (cycles > 100) begin
                    $display("  ERROR: TIMEOUT - done never asserted!");
                    $finish;
                end
            end

            @(posedge clk);

            // Check result
            expected_real = (1.0 * r_val) / s_val;
            result_real = to_real(result);
            if (expected_real != 0)
                error = ((result_real - expected_real) / expected_real) * 100.0;
            else
                error = result_real * 100.0;

            $display("  R = %0d, S = %0d", r_val, s_val);
            $display("  Expected R/S = %.6f", expected_real);
            $display("  Got result   = %.6f", result_real);
            $display("  Error = %.2f%%", error);
            $display("  Cycles = %0d (paper specifies 24)", cycles);

            if (error > 10.0 || error < -10.0) begin
                $display("  FAIL - Error too large!");
            end else begin
                $display("  PASS");
            end
        end
    endtask

    initial begin
        // Initialize signals
        start = 0;
        rst_n = 0;
        I = 0;

        // Hold reset for a few cycles
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("========================================");
        $display("Testing AU Multiplicative Inverse (DIV)");
        $display("Per paper: 24 clock cycles per operation");
        $display("========================================");

        // Test 1/S (R=1)
        test_div(1, 1);    // 1/1 = 1.0
        test_div(1, 2);    // 1/2 = 0.5
        test_div(1, 4);    // 1/4 = 0.25
        test_div(1, 8);    // 1/8 = 0.125
        test_div(1, -2);   // 1/-2 = -0.5
        test_div(1, -4);   // 1/-4 = -0.25

        // Test R/S with various R values
        test_div(2, 4);    // 2/4 = 0.5
        test_div(3, 2);    // 3/2 = 1.5
        test_div(-4, 2);   // -4/2 = -2.0

        $display("\n========================================");
        $display("Multiplicative Inverse Tests Completed");
        $display("========================================\n");

        $finish;
    end
endmodule
