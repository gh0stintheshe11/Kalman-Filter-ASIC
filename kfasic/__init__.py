"""Python tooling for the Kalman filter ASIC.

fixed      bit-accurate Q9.14 sign-magnitude arithmetic (defines the hardware)
asm        microcode assembler (fw/*.s -> ROM image / Verilog)
iss        cycle-accurate instruction-set simulator (golden model)
reference  floating-point Kalman filter and test scenarios
"""
