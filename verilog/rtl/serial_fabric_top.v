`timescale 1ns/1ps

module serial_fabric_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        psel, penable, pwrite,
    input  wire [4:0]  paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready, pslverr,

    input  wire [7:0]  tx_din,
    input  wire        tx_push,
    output wire        tx_full,
    output wire        tx_empty,

    output wire [7:0]  rx_dout,
    input  wire        rx_pop,
    output wire        rx_valid,
    input  wire        rx_en,
    input  wire        ext_sclk,   // external SCLK for SPI slave
    input  wire        ext_cs_n,   // external CS_N for SPI slave frame boundary

    output wire        pad0_out,
    input  wire        pad0_in,
    output wire        pad0_oe,
    output wire        pad1_out,
    output wire        pad2_out,
    output wire        pad2_oe,

    output wire [1:0]  fabric_mode
);

    wire [1:0]  mode;
    wire        en;
    wire [15:0] clk_div;
    wire        cpol, cpha, cs_pol;
    wire [6:0]  i2c_addr;
    wire        i2c_dir;

    wire        baud_tick, sclk_int;
    wire        tx_full_i, tx_empty_i;
    wire        rx_full, rx_valid_i;
    wire        sr_load, sr_shift, sr_lsb_first;
    wire        rx_sample;
    wire        serial_out;
    wire [7:0]  rx_capture;
    wire        sr_done;
    wire [2:0]  bit_count;
    wire        bc_clear, bc_inc;
    wire        rx_push;
    wire [7:0]  rx_din;
    wire        uart_tx_drive, tx_level;
    wire        sclk_out, cs_n, sda_oe;
    wire        busy, arb_lost;

    assign tx_full    = tx_full_i;
    assign tx_empty   = tx_empty_i;
    assign rx_valid   = rx_valid_i;
    assign fabric_mode = mode;

    mode_decoder u_mode (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr),
        .mode(mode), .en(en), .clk_div(clk_div),
        .cpol(cpol), .cpha(cpha), .cs_pol(cs_pol),
        .i2c_addr(i2c_addr), .i2c_dir(i2c_dir),
        .tx_empty(tx_empty_i),
        .rx_valid(rx_valid_i),
        .busy(busy), .arb_lost(arb_lost)
    );

    shared_datapath u_dp (
        .clk(clk), .rst_n(rst_n),
        .clk_div(clk_div),
        .baud_tick(baud_tick), .sclk_int(sclk_int),
        .tx_din(tx_din), .tx_push(tx_push),
        .tx_full(tx_full_i), .tx_empty(tx_empty_i),
        .rx_dout(rx_dout), .rx_pop(rx_pop),
        .rx_full(rx_full), .rx_valid(rx_valid_i),
        .sr_load(sr_load), .sr_shift(sr_shift),
        .sr_lsb_first(sr_lsb_first),
        .serial_out(serial_out),
        .rx_sample(rx_sample), .serial_in(pad0_in),
        .rx_capture(rx_capture),
        .bc_clear(bc_clear), .bc_inc(bc_inc),
        .bit_count(bit_count), .sr_done(sr_done),
        .rx_push(rx_push), .rx_din(rx_din)
    );

    protocol_fsm u_fsm (
        .clk(clk), .rst_n(rst_n),
        .mode(mode), .en(en),
        .cpol(cpol), .cpha(cpha), .cs_pol(cs_pol),
        .i2c_addr(i2c_addr), .i2c_dir(i2c_dir),
        .baud_tick(baud_tick), .sclk_int(sclk_int),
        .tx_empty(tx_empty_i),
        .rx_en(rx_en),
        .ext_sclk(ext_sclk),
        .ext_cs_n(ext_cs_n),
        .bit_count(bit_count), .sr_done(sr_done),
        .serial_in(pad0_in), .rx_capture(rx_capture),
        .sr_load(sr_load), .sr_shift(sr_shift),
        .sr_lsb_first(sr_lsb_first),
        .rx_sample(rx_sample),
        .bc_clear(bc_clear), .bc_inc(bc_inc),
        .rx_push(rx_push), .rx_din(rx_din),
        .uart_tx_drive(uart_tx_drive), .tx_level(tx_level),
        .sclk_out(sclk_out), .cs_n(cs_n), .sda_oe(sda_oe),
        .busy(busy), .arb_lost(arb_lost)
    );

    assign pad0_out = (mode == 2'b00) ?
                          (uart_tx_drive ? serial_out : tx_level) :
                      (mode == 2'b10) ?
                          (sda_oe ? serial_out : 1'b1) :
                          serial_out;
    assign pad0_oe  = (mode == 2'b10) ? sda_oe : 1'b1;
    assign pad1_out = (mode == 2'b00) ? 1'b1 : sclk_out;
    assign pad2_out = (mode == 2'b01) ? cs_n  : 1'b1;
    assign pad2_oe  = (mode == 2'b01) ? 1'b1  : 1'b0;

endmodule
