`default_nettype none
module user_project_wrapper #(
    parameter BITS = 32
) (
`ifdef USE_POWER_PINS
    inout vdda1, inout vdda2,
    inout vssa1, inout vssa2,
    inout vccd1, inout vccd2,
    inout vssd1, inout vssd2,
`endif

    // Wishbone
    input         wb_clk_i,
    input         wb_rst_i,
    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output        wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // Digital IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // Analog IOs (analog_io[k] <-> GPIO pad k+7)
    inout  [`MPRJ_IO_PADS-10:0] analog_io,

    // Extra user clock
    input   user_clock2,

    // IRQs
    output [2:0] user_irq
);


  wire scan_in_cc;
  wire scan_in_dl;
  wire scan_in_dr;
  wire tm;
  wire scan_out_cc;

  // This is safe for USER analog / unused pins
  //io_out = {38{1'b0}};
  //io_oeb = {38{1'b1}};

  // GPIO 21 = ScanInDR, USER input pulldown
  assign scan_in_dr = io_in[21];
  assign io_out[21] = 1'b0;
  assign io_oeb[21] = 1'b0;

  // GPIO 22 = ScanInDL, USER input pullup
  assign scan_in_dl = io_in[22];
  assign io_out[22] = 1'b1;
  assign io_oeb[22] = 1'b0;

  // GPIO 23 = ScanOutCC, USER output
  assign io_out[23] = scan_out_cc;
  assign io_oeb[23] = 1'b0;

  // GPIO 35 = ScanInCC, USER input pulldown
  assign scan_in_cc = io_in[35];
  assign io_out[35] = 1'b0;
  assign io_oeb[35] = 1'b0;

  // GPIO 36 = TM, USER input pullup
  assign tm = io_in[36];
  assign io_out[36] = 1'b1;
  assign io_oeb[36] = 1'b0;

    // -----------------------------
    // Instantiate your hard macro
    // -----------------------------
   nvm_neuron_core_256x64 neuro_inst (
`ifdef USE_POWER_PINS
  .VDDC1 (vccd1),
  .VDDC2 (vccd2),
  .VDDA1 (vdda1),
  .VDDA2 (vdda2),
  .VSS  (vssd1),
`endif

  // Clocks / resets
  .user_clk (wb_clk_i),
  .user_rst (wb_rst_i),
  .wb_clk_i (wb_clk_i),
  .wb_rst_i (wb_rst_i),

  // Wishbone
  .wbs_stb_i (wbs_stb_i),
  .wbs_cyc_i (wbs_cyc_i),
  .wbs_we_i  (wbs_we_i),
  .wbs_sel_i (wbs_sel_i),
  .wbs_dat_i (wbs_dat_i),
  .wbs_adr_i (wbs_adr_i),
  .wbs_dat_o (wbs_dat_o),
  .wbs_ack_o (wbs_ack_o),

  // Scan/Test
  .ScanInCC  (scan_in_cc),
  .ScanInDL  (scan_in_dl),
  .ScanInDR  (scan_in_dr),
  .TM        (tm),
  .ScanOutCC (scan_out_cc),

  // Analog / bias pins (drive from analog_io[] wires you already built)
  .Iref          (analog_io[27]),
  .Vcc_read      (analog_io[26]),
  .Vcomp         (analog_io[25]),
  .Bias_comp2    (analog_io[24]),
  .Vcc_wl_read   (analog_io[19]),
  .Vcc_wl_set    (analog_io[23]),
  .Vbias         (analog_io[22]),
  .Vcc_wl_reset  (analog_io[21]),
  .Vcc_set       (analog_io[20]),
  .dc_bias       (analog_io[18])
);

adaptive_fabric_top_tapeout fabric_top(
    .clk(io_in[5]),           // pin 1
    .rst_n(io_in[6]),         // pin 2  (active-low)

    .serial_rx(io_in[7]),     // pin 3  UART RX  / I2C SDA
    .serial_sclk(io_in[8]),   // pin 4  SPI SCLK / I2C SCL
    .serial_cs_n(io_in[9]),   // pin 5  SPI CS_N
    .serial_mosi(io_in[10]),   // pin 6  SPI MOSI

    .rx_data(io_out[18:11]),             // <-- Connected to wire
    .rx_valid(io_out[19]),      // <-- Connected to wire
    .rx_ack(io_out[20]),          // <-- Connected to wire

    .active_mode(io_out[24]) // <-- Connected to wire
);




endmodule
`default_nettype wire

