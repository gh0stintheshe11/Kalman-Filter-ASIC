###############################################################
#  IO File for kf_top (Kalman Filter ASIC)
#  TSMC 65nm with tpan65gpgv2od3 IO pad library
#
#  Total: 91 signal pins + 8 power/ground + 4 corners = 103
#
#  Layout (clockwise from topleft):
#    Left:   DATA_IN[23:0] + VDD + VSS = 26 pads
#    Top:    Control + loop_addr + VDD + VSS = 20 pads
#    Right:  DATA_OUT[23:0] + VDD + VSS = 26 pads
#    Bottom: ROM signals + VDD + VSS = 27 pads
#
#  Corner orientations:
#    TopLeft: R180, TopRight: R90, BottomRight: R0, BottomLeft: R270
###############################################################

(globals
    version = 3
    io_order = clockwise
)

(iopad
    (topleft
        (inst name="corner_TL" cell=PCORNERA offset=0 orientation=R180 place_status=fixed)
    )

    (left
        (inst name="pad_DATA_IN_0"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_1"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_2"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_3"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_4"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_5"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_6"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_7"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_8"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_9"   cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_10"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_11"  cell=PDB2A place_status=fixed)
        (inst name="pad_VDD_W"       cell=PVDD3A place_status=fixed)
        (inst name="pad_VSS_W"       cell=PVSS2A place_status=fixed)
        (inst name="pad_DATA_IN_12"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_13"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_14"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_15"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_16"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_17"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_18"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_19"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_20"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_21"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_22"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_IN_23"  cell=PDB2A place_status=fixed)
    )

    (bottomleft
        (inst name="corner_BL" cell=PCORNERA offset=0 orientation=R270 place_status=fixed)
    )

    (bottom
        (inst name="pad_rom_we"       cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_0"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_1"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_2"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_3"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_4"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_5"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_6"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_waddr_7"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_0"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_1"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_2"  cell=PDB2A place_status=fixed)
        (inst name="pad_VDD_S"        cell=PVDD3A place_status=fixed)
        (inst name="pad_VSS_S"        cell=PVSS2A place_status=fixed)
        (inst name="pad_rom_wdata_3"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_4"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_5"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_6"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_7"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_8"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_9"  cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_10" cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_11" cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_12" cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_13" cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_14" cell=PDB2A place_status=fixed)
        (inst name="pad_rom_wdata_15" cell=PDB2A place_status=fixed)
    )

    (bottomright
        (inst name="corner_BR" cell=PCORNERA offset=0 orientation=R0 place_status=fixed)
    )

    (right
        (inst name="pad_DATA_OUT_0"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_1"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_2"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_3"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_4"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_5"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_6"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_7"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_8"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_9"  cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_10" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_11" cell=PDB2A place_status=fixed)
        (inst name="pad_VDD_E"       cell=PVDD3A place_status=fixed)
        (inst name="pad_VSS_E"       cell=PVSS2A place_status=fixed)
        (inst name="pad_DATA_OUT_12" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_13" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_14" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_15" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_16" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_17" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_18" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_19" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_20" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_21" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_22" cell=PDB2A place_status=fixed)
        (inst name="pad_DATA_OUT_23" cell=PDB2A place_status=fixed)
    )

    (topright
        (inst name="corner_TR" cell=PCORNERA offset=0 orientation=R90 place_status=fixed)
    )

    (top
        (inst name="pad_clk"         cell=PDB2A place_status=fixed)
        (inst name="pad_rst_n"       cell=PDB2A place_status=fixed)
        (inst name="pad_START"       cell=PDB2A place_status=fixed)
        (inst name="pad_WRITE"       cell=PDB2A place_status=fixed)
        (inst name="pad_DIR_0"       cell=PDB2A place_status=fixed)
        (inst name="pad_DIR_1"       cell=PDB2A place_status=fixed)
        (inst name="pad_DIR_2"       cell=PDB2A place_status=fixed)
        (inst name="pad_DIR_3"       cell=PDB2A place_status=fixed)
        (inst name="pad_DIR_4"       cell=PDB2A place_status=fixed)
        (inst name="pad_VDD_N"       cell=PVDD3A place_status=fixed)
        (inst name="pad_VSS_N"       cell=PVSS2A place_status=fixed)
        (inst name="pad_READY"       cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_0" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_1" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_2" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_3" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_4" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_5" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_6" cell=PDB2A place_status=fixed)
        (inst name="pad_loop_addr_7" cell=PDB2A place_status=fixed)
    )
)
