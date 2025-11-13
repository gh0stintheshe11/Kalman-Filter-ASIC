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
  input             rst_n,      // synchronous active-low reset
  input             start,      // 1-cycle pulse to start a run
  input             continue_i, // from AU (e.g., reciprocal done)

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
  output            ready,      // high when idle (HALTed)
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

  // Decode fields (valid whenever running; harmless when idle)
  assign ctl_a = instr[15:11];
  assign ctl_b = instr[10:6];
  assign ctl_c = instr[5:4];
  assign ctl_d = instr[3:2];
  assign ctl_e = instr[1:0];

  // READY when not running
  assign ready  = ~running;
  assign pc_dbg = pc;

  // Next-PC logic uses ctl_c
  // 00: pc+1, 01: wait for continue_i then pc+1, 10: halt & pc=0, 11: pc+1 (reserved)
  always @(posedge clk) begin
    if (!rst_n) begin
      running <= 1'b0;
      pc      <= 8'd0;
    end else begin
      // start a new run if asked while idle
      if (!running && start) begin
        running <= 1'b1;
        pc      <= 8'd0;
      end else if (running) begin
        case (ctl_c)
          2'b00: pc <= pc + 8'd1;                       // normal step
          2'b01: if (continue_i) pc <= pc + 8'd1;       // wait
          2'b10: begin                                   // halt
                    running <= 1'b0;
                    pc      <= 8'd0;
                  end
          default: pc <= pc + 8'd1;                     // reserved → step
        endcase
      end
    end
  end
endmodule
