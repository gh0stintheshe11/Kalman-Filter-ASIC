// -----------------------------------------------------------------------------
// sequencer.v
// - 8-bit PC driving a 256x16 ROM
// - START begins execution at PC=0; READY=1 when idle
// - ctl_c[1:0] controls flow: 00=INC, 01=WAIT(for continue), 10=HALT, 11=INC
// - ROM has a simple write port for TB programming
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

// 256x16 ROM with simple write port (for TB/programming)
module rom_256x16 (
  input              clk,
  input      [7:0]   addr,
  output     [15:0]  dout,
  // programming port
  input              prog_we,
  input      [7:0]   prog_addr,
  input      [15:0]  prog_data
);
  reg [15:0] mem [0:255];
  assign dout = mem[addr];

  always @(posedge clk) begin
    if (prog_we)
      mem[prog_addr] <= prog_data;
  end
endmodule

module sequencer (
  input             clk,
  input             rst_n,      // synchronous active-low reset (paper uses active-high RESET)
  input             start,      // 1-cycle pulse to start a run
  input             continue_i, // from AU (e.g., operation done signal)

  // ROM programming (for testbench/ease of use)
  input             rom_we,
  input      [7:0]  rom_waddr,
  input      [15:0] rom_wdata,

  // Decoded control fields to the rest of the datapath
  output     [4:0]  ctl_a,
  output     [4:0]  ctl_b,
  output     [1:0]  ctl_c,
  output     [1:0]  ctl_d,
  output     [1:0]  ctl_e,

  // Status
  output reg        ready,      // high when idle (paper: READY)
  output     [7:0]  pc_dbg      // (optional) observe current PC
);
  // Run/idle FF
  reg running;

  // 8-bit PC
  reg [7:0] pc;

  // ROM
  wire [15:0] instr;
  rom_256x16 UROM (
    .clk(clk),
    .addr(pc),
    .dout(instr),
    .prog_we(rom_we),
    .prog_addr(rom_waddr),
    .prog_data(rom_wdata)
  );

  // Decode fields (always decode current ROM output)
  assign ctl_a = instr[15:11];
  assign ctl_b = instr[10:6];
  assign ctl_c = instr[5:4];
  assign ctl_d = instr[3:2];
  assign ctl_e = instr[1:0];

  assign pc_dbg = pc;

  // PC increment logic per paper:
  // - ctl_c[1:0]: 00=INC (1-cycle ops), 01=WAIT (multi-cycle), 10=HALT, 11=reserved
  // - PC increments when operation completes
  // - For WAIT: increment when continue_i=1 (operation done signal from AU)
  // - For HALT: stop incrementing, set READY=1
  
  always @(posedge clk) begin
    if (!rst_n) begin
      // Reset: READY=1, PC initialized
      ready <= 1'b1;
      pc    <= 8'd0;
    end else if (ready) begin
      // Idle state - wait for START
      if (start) begin
        // START signal: go to address 0, begin execution, clear READY
        ready <= 1'b0;
        pc    <= 8'd0;
      end
    end else begin
      // Running state: decode ctl_c to control PC
      case (ctl_c)
        2'b00: begin
          // Normal increment: 1-cycle operation (ADD/SUB/MUL)
          pc <= pc + 8'd1;
        end
        2'b01: begin
          // WAIT: multi-cycle operation (DIV/inverse)
          // PC increments only when continue_i=1 (operation done)
          if (continue_i) begin
            pc <= pc + 8'd1;
          end
          // else: hold PC at current value
        end
        2'b10: begin
          // HALT: stop execution, set READY=1, PC freezes
          ready <= 1'b1;
        end
        2'b11: begin
          // Reserved/unused: treat as normal increment
          pc <= pc + 8'd1;
        end
      endcase
    end
  end

  // Initialize ready to 1
  initial begin
    ready = 1'b1;
  end

endmodule
