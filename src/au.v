// -----------------------------------------------------------------------------
// au.v  -- Arithmetic Unit (per paper Figure 3)
// -----------------------------------------------------------------------------
// Sign-magnitude fixed-point arithmetic unit for Kalman Filter ASIC.
// Per paper Section 4: "The arithmetic unit includes the following blocks:
//   adder-subs, multiplier and the multiplicative-inverse."
//
// Operations:
//   ADD (1 cycle)  - Addition
//   SUB (1 cycle)  - Subtraction
//   MUL (1 cycle)  - Multiplication
//   INV (24 cycles) - Multiplicative Inverse (computes R/S as R * (1/S))
//
// Per paper: "The multiplicative-inverse follows a successive approximation
// technique using the multiplier block and an internal numeric comparator
// to determine the result bit by bit, requiring 24 clock cycles."
//
// Fixed-point format (per paper Section 3):
//   - Sign-and-magnitude: 1 sign bit + 9 integer bits + 14 fractional bits
//   - Total word length: 24 bits (W=24, FRAC=14)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

// =============================================================================
// Multiplicative Inverse Unit (per paper Section 4)
// =============================================================================
// Computes 1/S using successive approximation with multiplier and comparator.
// Algorithm: Build result Q bit-by-bit from MSB to LSB.
//   For each bit position i (from W-2 down to 0):
//     - Try Q_test = Q | (1 << i)
//     - Compute P = Q_test * S (using the multiplier)
//     - If P <= 1.0 (i.e., P <= 2^FRAC), keep the bit; else clear it
// Result: Q ≈ 1/S in the same Q format
// =============================================================================
module mult_inv
#(parameter W=24, parameter FRAC=14)
(
  input              clk,
  input              rst_n,
  input              start,       // pulse to begin computation
  input  [W-2:0]     S_mag,       // magnitude of divisor S (must be > 0)
  output reg [W-2:0] Q_mag,       // magnitude of 1/S
  output reg         rdy          // high for 1 cycle when Q_mag valid
);

  // Bit counter: counts from W-2 (MSB) down to 0
  localparam BITS = W - 1;        // 23 magnitude bits
  localparam CNTW = 5;            // enough bits to count 0..22

  reg [CNTW-1:0] bit_pos;         // current bit position being tested
  reg            running;

  // Test value: Q with current bit set
  wire [W-2:0] Q_test = Q_mag | ({{(W-2){1'b0}}, 1'b1} << bit_pos);

  // Product: Q_test * S_mag (full precision before scaling)
  // This is a 23x23 -> 46 bit multiply
  wire [2*BITS-1:0] product_full = Q_test * S_mag;

  // Compare product with 1.0 (which is 2^FRAC in Q format)
  // After Q scaling, product should be <= 2^FRAC for the bit to be valid
  // product_full represents Q_test * S_mag in Q(2*FRAC) format
  // We compare against 1.0 in Q(2*FRAC) = 2^(2*FRAC)
  // But product_full has 46 bits and 2^28 fits, so we check if product <= 2^(2*FRAC)
  wire product_le_one = (product_full <= ({{(2*BITS-2*FRAC-1){1'b0}}, 1'b1, {(2*FRAC){1'b0}}}));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      Q_mag   <= {(W-1){1'b0}};
      bit_pos <= {CNTW{1'b0}};
      running <= 1'b0;
      rdy     <= 1'b0;
    end else if (start && !running) begin
      // Start new computation
      Q_mag   <= {(W-1){1'b0}};       // Start with Q = 0
      bit_pos <= BITS - 1;            // Start at MSB (bit 22)
      running <= 1'b1;
      rdy     <= 1'b0;
    end else if (running) begin
      // Successive approximation: test current bit
      if (product_le_one) begin
        // Product <= 1.0, keep this bit set
        Q_mag <= Q_test;
      end
      // else: product > 1.0, leave bit clear (Q_mag unchanged)

      if (bit_pos == 0) begin
        // Done with all bits
        running <= 1'b0;
        rdy     <= 1'b1;
      end else begin
        bit_pos <= bit_pos - 1;
        rdy     <= 1'b0;
      end
    end else begin
      rdy <= 1'b0;
    end
  end

endmodule

// =============================================================================
// Arithmetic Unit (per paper Figure 3)
// =============================================================================
// Contains:
//   Adder/Subs  - Addition/Subtraction (1 cycle)
//   Multiplier  - Multiplication (1 cycle, combinational)
//   Mult_Inv    - Multiplicative Inverse (24 cycles, successive approximation)
//   SR          - Result register (internal)
//
// Inputs (from Router B, per paper Figure 3):
//   R           - First operand (sign-magnitude)
//   S           - Second operand (sign-magnitude)
//
// Output (to Router A, per paper Figure 3):
//   result      - AU result from SR register
//
// Control (from sequencer via ctl_d):
//   ctl_d[1:0]  - 00=ADD, 01=SUB, 10=MUL, 11=INV (multiplicative inverse)
// =============================================================================
module au
#(parameter W=24, parameter FRAC=14)
(
  input               clk,
  input               rst_n,
  input               start,        // pulse to start operation (from ctl_e)

  // Operands from Router B (per paper Figure 3 naming)
  input  [W-1:0]      R,            // First operand (sign-magnitude)
  input  [W-1:0]      S,            // Second operand (sign-magnitude)
  input  [W-1:0]      I,            // Immediate value (unused in basic ops)

  // Control (from sequencer)
  input  [1:0]        ctl_d,        // 00=ADD, 01=SUB, 10=MUL, 11=INV

  // Result / status (per paper Figure 3)
  output reg [W-1:0]  result,       // AU result (from SR register, to Router A)
  output reg          done,         // 1 when result valid (continue signal)
  output              busy          // AU busy (during multiplicative inverse)
);

  // ========== Constants ==========
  localparam [W-2:0] MAG_MAX = {(W-1){1'b1}};  // Max magnitude (all 1s)
  localparam [W-2:0] ONE_MAG = {1'b1, {(FRAC-1){1'b0}}, {(W-1-FRAC){1'b0}}};  // 1.0 in Q format = 2^FRAC

  // ========== Sign-Magnitude <-> Two's Complement Conversion ==========

  // Convert sign-magnitude to two's complement (with extra bit for overflow)
  function [W:0] sm_to_tc;
    input [W-1:0] sm;
    reg [W-2:0] mag;
    begin
      mag = sm[W-2:0];
      sm_to_tc = sm[W-1] ? -{{1'b0}, mag} : {{1'b0}, mag};
    end
  endfunction

  // Convert two's complement back to sign-magnitude with saturation
  function [W-1:0] tc_to_sm_sat;
    input signed [W:0] val;
    reg sign;
    reg [W-2:0] mag;
    reg signed [W:0] absval;
    begin
      sign = (val < 0);
      absval = sign ? -val : val;
      // Saturate magnitude to max
      if (absval[W-1:0] > MAG_MAX)
        mag = MAG_MAX;
      else
        mag = absval[W-2:0];
      tc_to_sm_sat = {sign, mag};
    end
  endfunction

  // ========== Latched Operands ==========
  // Latch operands when operation starts (for multi-cycle ops)
  reg [W-1:0] R_lat, S_lat;
  reg [1:0]   op_lat;

  // ========== Adder/Subtractor (1 cycle, combinational) ==========
  wire signed [W:0] R_lat_tc = sm_to_tc(R_lat);
  wire signed [W:0] S_lat_tc = sm_to_tc(S_lat);
  wire signed [W:0] add_tc   = R_lat_tc + S_lat_tc;
  wire signed [W:0] sub_tc   = R_lat_tc - S_lat_tc;
  wire [W-1:0]      add_sm   = tc_to_sm_sat(add_tc);
  wire [W-1:0]      sub_sm   = tc_to_sm_sat(sub_tc);

  // ========== Multiplier (1 cycle, combinational) ==========
  // Per paper: "The multiplier is a combinational circuit that allows
  // multiplications to be performed in a clock cycle."

  // Magnitudes for multiplication
  wire [W-2:0] R_lat_mag = R_lat[W-2:0];
  wire [W-2:0] mul_Y_mag;              // Y input to multiplier (S or 1/S)
  wire         mul_Y_sign;             // Sign of Y input

  // Full product (23x23 -> 46 bits)
  wire [2*(W-1)-1:0] prod_full = R_lat_mag * mul_Y_mag;

  // Q scaling: shift right by FRAC bits (truncation)
  // Take bits [FRAC + W-2 : FRAC] for W-1 bit result
  wire [W-2:0] prod_scaled = prod_full[FRAC + W - 2 : FRAC];

  // Saturate if overflow
  wire [W-2:0] mul_mag_sat = (|prod_full[2*(W-1)-1 : FRAC+W-1]) ? MAG_MAX : prod_scaled;

  // Result sign (XOR of operand signs)
  wire mul_sign = R_lat[W-1] ^ mul_Y_sign;
  wire [W-1:0] mul_sm = {mul_sign, mul_mag_sat};

  // ========== Multiplicative Inverse (24 cycles) ==========
  // Per paper: successive approximation using multiplier and comparator

  wire [W-2:0] inv_Q_mag;             // 1/S result magnitude
  wire         inv_rdy;               // Inverse computation done
  reg          inv_start;             // Start inverse computation
  reg          inv_start_d;           // Delayed start for proper timing

  // Handle divide-by-zero: clamp small values to minimum non-zero
  wire [W-2:0] S_lat_mag = S_lat[W-2:0];
  wire [W-2:0] S_mag_safe = (S_lat_mag == {(W-1){1'b0}}) ? {{(W-2){1'b0}}, 1'b1} : S_lat_mag;

  mult_inv #(.W(W), .FRAC(FRAC)) Mult_Inv (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (inv_start_d),
    .S_mag  (S_mag_safe),
    .Q_mag  (inv_Q_mag),
    .rdy    (inv_rdy)
  );

  // ========== Y Input Selection for Multiplier ==========
  // For MUL: Y = S (direct multiplication)
  // For INV: Y = 1/S (multiplication by reciprocal to compute R/S)
  reg [W-1:0] mul_Y;
  assign mul_Y_mag  = mul_Y[W-2:0];
  assign mul_Y_sign = mul_Y[W-1];

  // ========== FSM States ==========
  localparam ST_IDLE   = 2'd0;        // Waiting for start
  localparam ST_SIMPLE = 2'd1;        // ADD/SUB/MUL (1 cycle)
  localparam ST_WAITR  = 2'd2;        // Waiting for reciprocal
  localparam ST_MULINV = 2'd3;        // Multiply by reciprocal

  reg [1:0] state, next_state;

  assign busy = (state == ST_WAITR);

  // ========== Next State Logic ==========
  // Use 'done' (registered) to prevent restart. When done=1, we just completed
  // an operation and the sequencer is about to increment PC. We shouldn't start
  // a new operation until done goes back to 0.
  always @* begin
    next_state = state;
    inv_start  = 1'b0;

    case (state)
      ST_IDLE: begin
        // Only start if:
        // 1. start is high (e=1 in instruction)
        // 2. done is low (we haven't just completed an operation)
        //
        // When done=1, the sequencer will increment PC on the next clock edge.
        // At that edge, done will go to 0, and we can start the new operation.
        if (start && !done) begin
          if (ctl_d == 2'b11) begin
            // INV operation: start multiplicative inverse
            next_state = ST_WAITR;
            inv_start  = 1'b1;
          end else begin
            // ADD/SUB/MUL: single cycle operation
            next_state = ST_SIMPLE;
          end
        end
      end

      ST_SIMPLE: begin
        // Result ready after 1 cycle
        next_state = ST_IDLE;
      end

      ST_WAITR: begin
        // Wait for multiplicative inverse to complete
        if (inv_rdy) begin
          next_state = ST_MULINV;
        end
      end

      ST_MULINV: begin
        // Multiply R by 1/S, result ready
        next_state = ST_IDLE;
      end
    endcase
  end

  // ========== Operand Latching ==========
  always @(posedge clk) begin
    if (state == ST_IDLE && start) begin
      R_lat  <= R;
      S_lat  <= S;
      op_lat <= ctl_d;
    end
  end

  // ========== Multiplier Y Input Selection ==========
  always @* begin
    case (state)
      ST_SIMPLE: begin
        // MUL operation: Y = S
        mul_Y = S_lat;
      end
      ST_MULINV: begin
        // INV operation: Y = 1/S (with S's sign for correct result sign)
        mul_Y = {S_lat[W-1], inv_Q_mag};
      end
      default: begin
        mul_Y = S_lat;
      end
    endcase
  end

  // ========== Result Register ==========
  always @(posedge clk) begin
    case (state)
      ST_SIMPLE: begin
        case (op_lat)
          2'b00: result <= add_sm;   // ADD
          2'b01: result <= sub_sm;   // SUB
          2'b10: result <= mul_sm;   // MUL
          default: result <= {W{1'b0}};
        endcase
      end
      ST_MULINV: begin
        // R / S = R * (1/S)
        result <= mul_sm;
      end
    endcase
  end

  // ========== State Register and Done Signal ==========
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      done        <= 1'b0;
      inv_start_d <= 1'b0;
    end else begin
      state       <= next_state;
      done        <= (state == ST_SIMPLE || state == ST_MULINV);
      inv_start_d <= inv_start;
    end
  end

endmodule
