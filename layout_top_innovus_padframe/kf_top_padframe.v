/////////////////////////////////////////////////////////////
// Padframe Wrapper for kf_top (Kalman Filter ASIC)
// TSMC 65nm with tpan65gpgv2od3 IO pad library
//
// Pad cells used:
//   - PDB2A: Bidirectional I/O pad (signal pads)
//   - PVDD3A: VDD power pad (pins: AVDD, TAVDD)
//   - PVSS2A: VSS ground pad (pin: VSS)
//   - PCORNERA: Corner cell (no pins)
//   - PFILLER20A: Filler pad (no pins)
//
// Total: 91 signal + 8 power/ground + 1 filler + 4 corners = 104 pads
// Perfectly balanced: 25 pads per side
/////////////////////////////////////////////////////////////

module kf_top_padframe (
    // External pad connections (active signals at chip boundary)
    inout wire pad_clk,
    inout wire pad_rst_n,
    inout wire pad_START,
    inout wire pad_WRITE,
    inout wire [4:0] pad_DIR,
    inout wire [23:0] pad_DATA_IN,
    inout wire [23:0] pad_DATA_OUT,
    inout wire pad_READY,
    inout wire pad_rom_we,
    inout wire [7:0] pad_rom_waddr,
    inout wire [15:0] pad_rom_wdata,
    inout wire [7:0] pad_loop_addr,
    // Power pads - directly connected to power ring
    inout wire AVDD_N, AVDD_S, AVDD_E, AVDD_W,
    inout wire TAVDD_N, TAVDD_S, TAVDD_E, TAVDD_W,
    inout wire TVSS_N, TVSS_S, TVSS_E, TVSS_W
);

    //-----------------------------------------------------------
    // Internal signals connecting pads to core
    //-----------------------------------------------------------
    wire clk_core;
    wire rst_n_core;
    wire START_core;
    wire WRITE_core;
    wire [4:0] DIR_core;
    wire [23:0] DATA_IN_core;
    wire [23:0] DATA_OUT_core;
    wire READY_core;
    wire rom_we_core;
    wire [7:0] rom_waddr_core;
    wire [15:0] rom_wdata_core;
    wire [7:0] loop_addr_core;

    //-----------------------------------------------------------
    // Core instantiation
    //-----------------------------------------------------------
    kf_top u_core (
        .clk        (clk_core),
        .rst_n      (rst_n_core),
        .START      (START_core),
        .WRITE      (WRITE_core),
        .DIR        (DIR_core),
        .DATA_IN    (DATA_IN_core),
        .DATA_OUT   (DATA_OUT_core),
        .READY      (READY_core),
        .rom_we     (rom_we_core),
        .rom_waddr  (rom_waddr_core),
        .rom_wdata  (rom_wdata_core),
        .loop_addr  (loop_addr_core)
    );

    //===========================================================
    // CORNER CELLS (4 total)
    //===========================================================
    PCORNERA corner_TL ();
    PCORNERA corner_TR ();
    PCORNERA corner_BL ();
    PCORNERA corner_BR ();

    //===========================================================
    // FILLER PAD (1 total - on top side)
    //===========================================================
    PFILLER20A pad_FILLER_N ();

    //===========================================================
    // POWER PADS (4 VDD + 4 VSS = 8 total)
    //===========================================================
    // North side power
    PVDD3A pad_VDD_N (.AVDD(AVDD_N), .TAVDD(TAVDD_N));
    PVSS2A pad_VSS_N (.VSS(TVSS_N));

    // South side power
    PVDD3A pad_VDD_S (.AVDD(AVDD_S), .TAVDD(TAVDD_S));
    PVSS2A pad_VSS_S (.VSS(TVSS_S));

    // East side power
    PVDD3A pad_VDD_E (.AVDD(AVDD_E), .TAVDD(TAVDD_E));
    PVSS2A pad_VSS_E (.VSS(TVSS_E));

    // West side power
    PVDD3A pad_VDD_W (.AVDD(AVDD_W), .TAVDD(TAVDD_W));
    PVSS2A pad_VSS_W (.VSS(TVSS_W));

    //===========================================================
    // LEFT SIDE - DATA_IN[22:0] (23 pads) - DATA_IN[23] moved to top
    //===========================================================
    PDB2A pad_DATA_IN_0  (.AIO(pad_DATA_IN[0]));
    PDB2A pad_DATA_IN_1  (.AIO(pad_DATA_IN[1]));
    PDB2A pad_DATA_IN_2  (.AIO(pad_DATA_IN[2]));
    PDB2A pad_DATA_IN_3  (.AIO(pad_DATA_IN[3]));
    PDB2A pad_DATA_IN_4  (.AIO(pad_DATA_IN[4]));
    PDB2A pad_DATA_IN_5  (.AIO(pad_DATA_IN[5]));
    PDB2A pad_DATA_IN_6  (.AIO(pad_DATA_IN[6]));
    PDB2A pad_DATA_IN_7  (.AIO(pad_DATA_IN[7]));
    PDB2A pad_DATA_IN_8  (.AIO(pad_DATA_IN[8]));
    PDB2A pad_DATA_IN_9  (.AIO(pad_DATA_IN[9]));
    PDB2A pad_DATA_IN_10 (.AIO(pad_DATA_IN[10]));
    PDB2A pad_DATA_IN_11 (.AIO(pad_DATA_IN[11]));
    PDB2A pad_DATA_IN_12 (.AIO(pad_DATA_IN[12]));
    PDB2A pad_DATA_IN_13 (.AIO(pad_DATA_IN[13]));
    PDB2A pad_DATA_IN_14 (.AIO(pad_DATA_IN[14]));
    PDB2A pad_DATA_IN_15 (.AIO(pad_DATA_IN[15]));
    PDB2A pad_DATA_IN_16 (.AIO(pad_DATA_IN[16]));
    PDB2A pad_DATA_IN_17 (.AIO(pad_DATA_IN[17]));
    PDB2A pad_DATA_IN_18 (.AIO(pad_DATA_IN[18]));
    PDB2A pad_DATA_IN_19 (.AIO(pad_DATA_IN[19]));
    PDB2A pad_DATA_IN_20 (.AIO(pad_DATA_IN[20]));
    PDB2A pad_DATA_IN_21 (.AIO(pad_DATA_IN[21]));
    PDB2A pad_DATA_IN_22 (.AIO(pad_DATA_IN[22]));

    // Connect pads to core (DATA_IN is input to core)
    assign DATA_IN_core = {pad_DATA_IN[23], pad_DATA_IN[22], pad_DATA_IN[21], pad_DATA_IN[20],
                           pad_DATA_IN[19], pad_DATA_IN[18], pad_DATA_IN[17], pad_DATA_IN[16],
                           pad_DATA_IN[15], pad_DATA_IN[14], pad_DATA_IN[13], pad_DATA_IN[12],
                           pad_DATA_IN[11], pad_DATA_IN[10], pad_DATA_IN[9],  pad_DATA_IN[8],
                           pad_DATA_IN[7],  pad_DATA_IN[6],  pad_DATA_IN[5],  pad_DATA_IN[4],
                           pad_DATA_IN[3],  pad_DATA_IN[2],  pad_DATA_IN[1],  pad_DATA_IN[0]};

    //===========================================================
    // RIGHT SIDE - DATA_OUT[22:0] (23 pads) - DATA_OUT[23] moved to top
    //===========================================================
    PDB2A pad_DATA_OUT_0  (.AIO(pad_DATA_OUT[0]));
    PDB2A pad_DATA_OUT_1  (.AIO(pad_DATA_OUT[1]));
    PDB2A pad_DATA_OUT_2  (.AIO(pad_DATA_OUT[2]));
    PDB2A pad_DATA_OUT_3  (.AIO(pad_DATA_OUT[3]));
    PDB2A pad_DATA_OUT_4  (.AIO(pad_DATA_OUT[4]));
    PDB2A pad_DATA_OUT_5  (.AIO(pad_DATA_OUT[5]));
    PDB2A pad_DATA_OUT_6  (.AIO(pad_DATA_OUT[6]));
    PDB2A pad_DATA_OUT_7  (.AIO(pad_DATA_OUT[7]));
    PDB2A pad_DATA_OUT_8  (.AIO(pad_DATA_OUT[8]));
    PDB2A pad_DATA_OUT_9  (.AIO(pad_DATA_OUT[9]));
    PDB2A pad_DATA_OUT_10 (.AIO(pad_DATA_OUT[10]));
    PDB2A pad_DATA_OUT_11 (.AIO(pad_DATA_OUT[11]));
    PDB2A pad_DATA_OUT_12 (.AIO(pad_DATA_OUT[12]));
    PDB2A pad_DATA_OUT_13 (.AIO(pad_DATA_OUT[13]));
    PDB2A pad_DATA_OUT_14 (.AIO(pad_DATA_OUT[14]));
    PDB2A pad_DATA_OUT_15 (.AIO(pad_DATA_OUT[15]));
    PDB2A pad_DATA_OUT_16 (.AIO(pad_DATA_OUT[16]));
    PDB2A pad_DATA_OUT_17 (.AIO(pad_DATA_OUT[17]));
    PDB2A pad_DATA_OUT_18 (.AIO(pad_DATA_OUT[18]));
    PDB2A pad_DATA_OUT_19 (.AIO(pad_DATA_OUT[19]));
    PDB2A pad_DATA_OUT_20 (.AIO(pad_DATA_OUT[20]));
    PDB2A pad_DATA_OUT_21 (.AIO(pad_DATA_OUT[21]));
    PDB2A pad_DATA_OUT_22 (.AIO(pad_DATA_OUT[22]));

    // Connect core output to pads (DATA_OUT is output from core)
    assign pad_DATA_OUT = DATA_OUT_core;

    //===========================================================
    // TOP SIDE - Control + loop_addr + DATA_IN[23] + DATA_OUT[23] + rom_wdata[14:15] (22 signal pads)
    //===========================================================
    PDB2A u_pad_clk   (.AIO(pad_clk));
    PDB2A u_pad_rst_n (.AIO(pad_rst_n));
    PDB2A u_pad_START (.AIO(pad_START));
    PDB2A u_pad_WRITE (.AIO(pad_WRITE));
    PDB2A u_pad_DIR_0 (.AIO(pad_DIR[0]));
    PDB2A u_pad_DIR_1 (.AIO(pad_DIR[1]));
    PDB2A u_pad_DIR_2 (.AIO(pad_DIR[2]));
    PDB2A u_pad_DIR_3 (.AIO(pad_DIR[3]));
    PDB2A u_pad_DIR_4 (.AIO(pad_DIR[4]));
    PDB2A u_pad_READY (.AIO(pad_READY));
    PDB2A u_pad_loop_addr_0 (.AIO(pad_loop_addr[0]));
    PDB2A u_pad_loop_addr_1 (.AIO(pad_loop_addr[1]));
    PDB2A u_pad_loop_addr_2 (.AIO(pad_loop_addr[2]));
    PDB2A u_pad_loop_addr_3 (.AIO(pad_loop_addr[3]));
    PDB2A u_pad_loop_addr_4 (.AIO(pad_loop_addr[4]));
    PDB2A u_pad_loop_addr_5 (.AIO(pad_loop_addr[5]));
    PDB2A u_pad_loop_addr_6 (.AIO(pad_loop_addr[6]));
    PDB2A u_pad_loop_addr_7 (.AIO(pad_loop_addr[7]));
    PDB2A u_pad_rom_wdata_14 (.AIO(pad_rom_wdata[14]));
    PDB2A u_pad_rom_wdata_15 (.AIO(pad_rom_wdata[15]));
    PDB2A pad_DATA_IN_23  (.AIO(pad_DATA_IN[23]));
    PDB2A pad_DATA_OUT_23 (.AIO(pad_DATA_OUT[23]));

    // Connect pads to core (inputs)
    assign clk_core = pad_clk;
    assign rst_n_core = pad_rst_n;
    assign START_core = pad_START;
    assign WRITE_core = pad_WRITE;
    assign DIR_core = pad_DIR;
    assign loop_addr_core = pad_loop_addr;

    // Connect core to pad (output)
    assign pad_READY = READY_core;

    //===========================================================
    // BOTTOM SIDE - ROM signals: rom_we + rom_waddr[7:0] + rom_wdata[13:0] (23 signal pads)
    //===========================================================
    PDB2A u_pad_rom_we       (.AIO(pad_rom_we));
    PDB2A u_pad_rom_waddr_0  (.AIO(pad_rom_waddr[0]));
    PDB2A u_pad_rom_waddr_1  (.AIO(pad_rom_waddr[1]));
    PDB2A u_pad_rom_waddr_2  (.AIO(pad_rom_waddr[2]));
    PDB2A u_pad_rom_waddr_3  (.AIO(pad_rom_waddr[3]));
    PDB2A u_pad_rom_waddr_4  (.AIO(pad_rom_waddr[4]));
    PDB2A u_pad_rom_waddr_5  (.AIO(pad_rom_waddr[5]));
    PDB2A u_pad_rom_waddr_6  (.AIO(pad_rom_waddr[6]));
    PDB2A u_pad_rom_waddr_7  (.AIO(pad_rom_waddr[7]));
    PDB2A u_pad_rom_wdata_0  (.AIO(pad_rom_wdata[0]));
    PDB2A u_pad_rom_wdata_1  (.AIO(pad_rom_wdata[1]));
    PDB2A u_pad_rom_wdata_2  (.AIO(pad_rom_wdata[2]));
    PDB2A u_pad_rom_wdata_3  (.AIO(pad_rom_wdata[3]));
    PDB2A u_pad_rom_wdata_4  (.AIO(pad_rom_wdata[4]));
    PDB2A u_pad_rom_wdata_5  (.AIO(pad_rom_wdata[5]));
    PDB2A u_pad_rom_wdata_6  (.AIO(pad_rom_wdata[6]));
    PDB2A u_pad_rom_wdata_7  (.AIO(pad_rom_wdata[7]));
    PDB2A u_pad_rom_wdata_8  (.AIO(pad_rom_wdata[8]));
    PDB2A u_pad_rom_wdata_9  (.AIO(pad_rom_wdata[9]));
    PDB2A u_pad_rom_wdata_10 (.AIO(pad_rom_wdata[10]));
    PDB2A u_pad_rom_wdata_11 (.AIO(pad_rom_wdata[11]));
    PDB2A u_pad_rom_wdata_12 (.AIO(pad_rom_wdata[12]));
    PDB2A u_pad_rom_wdata_13 (.AIO(pad_rom_wdata[13]));

    // Connect pads to core (inputs)
    assign rom_we_core = pad_rom_we;
    assign rom_waddr_core = pad_rom_waddr;
    assign rom_wdata_core = pad_rom_wdata;

endmodule
