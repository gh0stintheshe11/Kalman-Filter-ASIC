// kf_chip.v -- the chip: IHP sg13g2_io pad ring, SPI slave, Kalman filter
// core.
//
// 16 pads, four per side:
//   clk, rst_n           core clock, asynchronous active-low reset
//   sclk, cs_n, mosi     SPI (mode 0) to kf_spi; miso is tri-stated while
//                        cs_n is high
//   start                rising edge starts an iteration (optional)
//   ready                the core's READY (high when idle)
//   2 x VDD/VSS (1.2 V core), 2 x IOVDD/IOVSS (3.3 V I/O)
// The pad instance names are the ones the pad-ring configuration lists.
`default_nettype none

module kf_chip (
`ifdef USE_POWER_PINS
    inout wire VDD,
    inout wire VSS,
    inout wire IOVDD,
    inout wire IOVSS,
`endif
    inout wire clk_PAD,
    inout wire rst_n_PAD,
    inout wire sclk_PAD,
    inout wire cs_n_PAD,
    inout wire mosi_PAD,
    inout wire start_PAD,
    inout wire miso_PAD,
    inout wire ready_PAD
);
`ifdef USE_POWER_PINS
    `define KF_PAD_POWER .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
    `define KF_PAD_POWER_ONLY .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
`else
    `define KF_PAD_POWER
    `define KF_PAD_POWER_ONLY
`endif

    // ---- power pads ---------------------------------------------------------
    (* keep *) sg13g2_IOPadVdd   vdd_pad_n   (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadVss   vss_pad_n   (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadVdd   vdd_pad_s   (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadVss   vss_pad_s   (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadIOVdd iovdd_pad_e (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadIOVss iovss_pad_e (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadIOVdd iovdd_pad_w (`KF_PAD_POWER_ONLY);
    (* keep *) sg13g2_IOPadIOVss iovss_pad_w (`KF_PAD_POWER_ONLY);

    // ---- signal pads ----------------------------------------------------
    wire clk, rst_n, sclk, cs_n, mosi, start_pin, miso, miso_oe, ready;
    sg13g2_IOPadIn         clk_pad   (`KF_PAD_POWER .pad(clk_PAD),   .p2c(clk));
    sg13g2_IOPadIn         rst_n_pad (`KF_PAD_POWER .pad(rst_n_PAD), .p2c(rst_n));
    sg13g2_IOPadIn         sclk_pad  (`KF_PAD_POWER .pad(sclk_PAD),  .p2c(sclk));
    sg13g2_IOPadIn         cs_n_pad  (`KF_PAD_POWER .pad(cs_n_PAD),  .p2c(cs_n));
    sg13g2_IOPadIn         mosi_pad  (`KF_PAD_POWER .pad(mosi_PAD),  .p2c(mosi));
    sg13g2_IOPadIn         start_pad (`KF_PAD_POWER .pad(start_PAD), .p2c(start_pin));
    sg13g2_IOPadTriOut16mA miso_pad  (`KF_PAD_POWER .pad(miso_PAD),  .c2p(miso), .c2p_en(miso_oe));
    sg13g2_IOPadOut16mA    ready_pad (`KF_PAD_POWER .pad(ready_PAD), .c2p(ready));

    // ---- reset synchronizer for the SPI slave (kf_top has its own) ----------
    reg rst_meta, rst_n_spi;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            rst_meta  <= 1'b0;
            rst_n_spi <= 1'b0;
        end else begin
            rst_meta  <= 1'b1;
            rst_n_spi <= rst_meta;
        end

    // ---- SPI slave and core ------------------------------------------------
    wire        h_start, h_write;
    wire [4:0]  h_dir;
    wire [23:0] h_data_in, h_data_out;

    kf_spi u_spi (
        .clk       (clk),
        .rst_n     (rst_n_spi),
        .sclk      (sclk),
        .cs_n      (cs_n),
        .mosi      (mosi),
        .start_pin (start_pin),
        .miso      (miso),
        .miso_oe   (miso_oe),
        .start     (h_start),
        .write     (h_write),
        .dir       (h_dir),
        .data_in   (h_data_in),
        .ready     (ready),
        .data_out  (h_data_out)
    );

    kf_top u_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (h_start),
        .write    (h_write),
        .dir      (h_dir),
        .data_in  (h_data_in),
        .ready    (ready),
        .data_out (h_data_out)
    );

`undef KF_PAD_POWER
`undef KF_PAD_POWER_ONLY
endmodule

`default_nettype wire
