// kf_rom_sim.v -- simulation-only replacement for rtl/kf_rom.v that loads
// an arbitrary program from +rom=<hex file> (one 21-bit word per line).
// Used by the random-program tests; unused addresses read as HALT.
`default_nettype none

module kf_rom (
    input  wire [7:0]  addr,
    output wire [20:0] data
);
    reg [20:0]      mem [0:255];
    reg [8*256-1:0] file;
    integer         i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 21'h020000;
        if ($value$plusargs("rom=%s", file))
            $readmemh(file, mem);
    end

    assign data = mem[addr];
endmodule

`default_nettype wire
