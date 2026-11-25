// kf_spi.v -- SPI slave that drives the host interface of kf_top.
//
// SPI mode 0 (SCLK idles low, data sampled on the rising edge and changed
// on the falling edge), MSB first, 32-bit frames framed by CS_N.  SCLK,
// CS_N and MOSI are sampled with the core clock through two-flop
// synchronizers, so f_SCLK <= f_CLK / 8, and CS_N must be low for 4 CLK
// periods before the first rising SCLK edge (and high for 4 between
// frames).
//
//   MOSI  [31:29] op  [28:24] addr  [23:0] data
//   MISO  [31:24] status            [23:0] DB[addr] for READ, else 0
//
//   op 0 NOP          status only
//      1 WRITE        DB[addr] <= data
//      2 READ         DB[addr] is returned in the same frame
//      3 WRITE_START  DB[addr] <= data, then start a filter iteration
//      4 START        start a filter iteration
//      5 CONTROL      data[0]: run continuously (CONT)
//      6, 7           reserved (NOP)
//
//   status = {READY, CONT, ERR, ITER[4:0]}: READY of the core, the
//   continuous-run bit, ERR = the previous frame did not have exactly 32
//   bits (it was ignored), ITER = completed iterations mod 32.
//
// WRITE and START take effect when CS_N rises.  If the core is busy they
// wait for READY (an iteration takes ~25 core cycles, far less than a
// frame), so they are never lost.  A READ while the core is busy returns 0
// (the core's data_out); poll READY first.  In continuous mode the core is
// restarted whenever it is ready and no request is pending: iterations run
// back to back, for power measurements.  A rising edge on the START pin
// (synchronized) also starts an iteration.  MISO is enabled while CS_N is
// low (synchronized).
`default_nettype none

module kf_spi (
    input  wire        clk,
    input  wire        rst_n,       // released synchronously to clk
    input  wire        sclk,        // asynchronous inputs
    input  wire        cs_n,
    input  wire        mosi,
    input  wire        start_pin,
    output reg         miso,
    output wire        miso_oe,
    // kf_top host interface
    output reg         start,
    output reg         write,
    output reg  [4:0]  dir,
    output reg  [23:0] data_in,
    input  wire        ready,
    input  wire [23:0] data_out
);
    localparam [2:0] OP_WRITE = 3'd1, OP_READ = 3'd2, OP_WRITE_START = 3'd3,
                     OP_START = 3'd4, OP_CONTROL = 3'd5;

    // ---- synchronizers --------------------------------------------------
    reg [2:0] sclk_s, cs_s, pin_s;
    reg [1:0] mosi_s;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            sclk_s <= 3'b000;
            cs_s   <= 3'b111;
            pin_s  <= 3'b000;
            mosi_s <= 2'b00;
        end else begin
            sclk_s <= {sclk_s[1:0], sclk};
            cs_s   <= {cs_s[1:0], cs_n};
            pin_s  <= {pin_s[1:0], start_pin};
            mosi_s <= {mosi_s[0], mosi};
        end
    wire sclk_rise = sclk_s[1] & ~sclk_s[2];
    wire sclk_fall = ~sclk_s[1] & sclk_s[2];
    wire selected  = ~cs_s[1];
    wire frame_beg = ~cs_s[1] & cs_s[2];
    wire frame_end = cs_s[1] & ~cs_s[2];
    wire pin_rise  = pin_s[1] & ~pin_s[2];
    assign miso_oe = selected;

    // ---- frame, requests, host interface ------------------------------
    reg  [31:0] rx;                    // received bits, newest in bit 0
    reg  [5:0]  nbits;                 // rising edges in this frame (saturates at 33)
    reg  [30:0] tx;                    // the bits after the one on MISO
    reg         cont;
    reg         err;
    reg  [4:0]  iter;
    reg  [1:0]  rd_step;               // READ in progress: 1 address out, 2 data valid
    reg         wr_req, st_req;        // requests waiting for READY
    reg  [4:0]  req_addr;
    reg  [23:0] req_data;
    reg         ready_d, started;

    wire [7:0]  status = {ready, cont, err, iter};
    wire        header = selected & sclk_rise & (nbits == 6'd7);   // 8th bit arrives
    wire        is_read = (rx[6:4] == OP_READ);                    // header op, before the 8th shift
    wire        issue = ready & ~write & ~start & (rd_step == 2'd0) & ~header;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            rx       <= 32'd0;
            nbits    <= 6'd0;
            tx       <= 31'd0;
            miso     <= 1'b0;
            cont     <= 1'b0;
            err      <= 1'b0;
            iter     <= 5'd0;
            rd_step  <= 2'd0;
            wr_req   <= 1'b0;
            st_req   <= 1'b0;
            req_addr <= 5'd0;
            req_data <= 24'd0;
            start    <= 1'b0;
            write    <= 1'b0;
            dir      <= 5'd0;
            data_in  <= 24'd0;
            ready_d  <= 1'b0;
            started  <= 1'b0;
        end else begin
            // receive and transmit
            if (frame_beg) begin
                nbits <= 6'd0;
                tx    <= {status[6:0], 24'd0};
                miso  <= status[7];
                err   <= 1'b0;                     // reported once
            end else if (selected) begin
                if (sclk_rise) begin
                    rx <= {rx[30:0], mosi_s[1]};
                    if (nbits != 6'd33)
                        nbits <= nbits + 6'd1;
                end
                if (sclk_fall) begin
                    tx   <= {tx[29:0], 1'b0};
                    miso <= tx[30];
                end
            end

            // READ: the address goes to the core the cycle after the header,
            // the core registers it, and its data_out is valid one cycle
            // later; it is loaded where the next falling edges shift it out
            if (header & is_read) begin
                dir     <= {rx[3:0], mosi_s[1]};
                rd_step <= 2'd1;
            end else if (rd_step == 2'd1) begin
                rd_step <= 2'd2;
            end else if (rd_step == 2'd2) begin
                tx[30:7] <= data_out;
                rd_step  <= 2'd0;
            end

            // end of frame: queue the request
            if (frame_end) begin
                if (nbits != 6'd32) begin
                    err <= 1'b1;
                end else begin
                    case (rx[31:29])
                        OP_WRITE:       wr_req <= 1'b1;
                        OP_WRITE_START: begin wr_req <= 1'b1; st_req <= 1'b1; end
                        OP_START:       st_req <= 1'b1;
                        OP_CONTROL:     cont   <= rx[0];
                        default:        ;
                    endcase
                    req_addr <= rx[28:24];
                    req_data <= rx[23:0];
                end
            end
            if (pin_rise)
                st_req <= 1'b1;

            // issue one request at a time while the core is ready: the
            // write first, a start (or the continuous restart) after it
            write <= 1'b0;
            start <= 1'b0;
            if (issue) begin
                if (wr_req) begin
                    write   <= 1'b1;
                    dir     <= req_addr;
                    data_in <= req_data;
                    wr_req  <= 1'b0;
                end else if (st_req | cont) begin
                    start   <= 1'b1;
                    st_req  <= 1'b0;
                end
            end

            // completed iterations
            ready_d <= ready;
            if (start)
                started <= 1'b1;
            else if (ready & ~ready_d & started) begin
                iter    <= iter + 5'd1;
                started <= 1'b0;
            end
        end
endmodule

`default_nettype wire
