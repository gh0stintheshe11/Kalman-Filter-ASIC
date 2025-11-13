`timescale 1ns/1ps
module multiplicative_inverse #(parameter W=24, parameter FRAC=14)(
  input              clk,
  input              rst,        // active-high, synchronous (paper)
  input              start,      // 1-cycle pulse
  input  [W-2:0]     den_mag,    // >0 (caller clamps zero)
  output reg [W-2:0] q_mag,      // floor((1<<(2*FRAC))/den_mag) in Q(FRAC)
  output reg         rdy         // 1-cycle pulse when q_mag valid
);
  // Remainder holds numerator and intermediate remainders.
  // Width must fit 1<<(2*FRAC) and the running subtracts.
  localparam REM_W = 2*FRAC + (W-1);

  reg              run;
  reg [7:0]        cnt;                // (W-1) <= 255
  reg [REM_W-1:0]  rem;

  // Denominator extended to remainder width (NO right shift!)
  // We divide N by D directly; D_ext is just zero-extended.
  wire [REM_W-1:0] D_ext = {{(REM_W-(W-1)){1'b0}}, den_mag};

  // Shift-left remainder for this iteration
  wire [REM_W-1:0] rem_sh = {rem[REM_W-2:0], 1'b0};

  always @(posedge clk) begin
    if (rst) begin
      run   <= 1'b0;
      rdy   <= 1'b0;
      cnt   <= 8'd0;
      q_mag <= {(W-1){1'b0}};
      rem   <= {REM_W{1'b0}};
    end else if (start && !run) begin
      // Numerator N = 1<<(2*FRAC), placed exactly in REM_W bits
      // Width check: zeros = REM_W - (2*FRAC+1)
      rem   <= {{(REM_W-(2*FRAC+1)){1'b0}}, 1'b1, {(2*FRAC){1'b0}}};
      q_mag <= {(W-1){1'b0}};
      cnt   <= (W-1);     // emit W-1 quotient bits
      run   <= 1'b1;
      rdy   <= 1'b0;
    end else if (run) begin
      if (rem_sh >= D_ext) begin
        rem   <= rem_sh - D_ext;
        q_mag <= {q_mag[W-3:0], 1'b1};
      end else begin
        rem   <= rem_sh;
        q_mag <= {q_mag[W-3:0], 1'b0};
      end

      if (cnt == 8'd1) begin
        run <= 1'b0;
        rdy <= 1'b1;      // single-cycle pulse
      end else begin
        cnt <= cnt - 1'b1;
        rdy <= 1'b0;
      end
    end else begin
      rdy <= 1'b0;
    end
  end
endmodule
