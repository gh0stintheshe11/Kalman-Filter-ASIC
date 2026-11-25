// kf_sequencer.v -- program counter + microcode ROM (paper Sec. 4)
//
// Idle (running = 0, READY = 1) after reset and after HALT.  START while
// idle jumps to PC 0 and runs.  Each cycle the PC advances unless the AU
// stalls it (a DIV in progress); a HALT instruction (c = 10) returns to idle.
// There are no fetch cycles and no instruction register: the ROM output
// drives the datapath directly.
`default_nettype none

module kf_sequencer #(
    parameter integer PCW = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        stall,      // hold the current instruction
    output reg         running,
    output wire [15:0] instr
);
    localparam [1:0] C_HALT = 2'b10;

    reg [PCW-1:0] pc;

    kf_rom u_rom (
        .addr (pc),
        .data (instr)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 1'b0;
            pc      <= {PCW{1'b0}};
        end else if (!running) begin
            if (start) begin
                running <= 1'b1;
                pc      <= {PCW{1'b0}};
            end
        end else if (instr[5:4] == C_HALT) begin
            running <= 1'b0;
        end else if (!stall) begin
            pc <= pc + 1'b1;
        end
    end

endmodule

`default_nettype wire
