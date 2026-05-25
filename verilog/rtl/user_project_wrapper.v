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

    // -------------------------------------------------------------------------
    // Tie off unused outputs - using direct constant assignment pattern
    // from known-good tape-out wrapper. No (* keep *) attributes - let
    // synthesis handle constant outputs naturally.
    // -------------------------------------------------------------------------

    /*// Logic Analyzer: not used, drive low
    assign la_data_out = 128'b0;

    // IRQs: not used, drive low
    assign user_irq = 3'b0;

    // io_oeb: all high (input mode / Hi-Z) except bit [23] which is driven
    // low because that bit is the output for ScanOutCC
    assign io_oeb[`MPRJ_IO_PADS-1:24] = {(`MPRJ_IO_PADS-24){1'b1}};
    assign io_oeb[23]                 = 1'b0;
    assign io_oeb[22:0]               = {23{1'b1}};

    // io_out: drive low for all bits except bit [23] (ScanOutCC from mprj)
    assign io_out[`MPRJ_IO_PADS-1:24] = {(`MPRJ_IO_PADS-24){1'b0}};
    assign io_out[22:0]               = 23'b0;
    // io_out[23] is driven by mprj.ScanOutCC below
*/

// -------------------------------------------------------------------------
    // Tie off unused Caravel system outputs
    // -------------------------------------------------------------------------
    assign la_data_out = 128'b0;
    assign user_irq    = 3'b0;

    // -------------------------------------------------------------------------
    // IO Output Enable Bar (io_oeb) Assignments
    // 0 = Output Enabled (Driven), 1 = Input Enabled (Hi-Z Output)
    // -------------------------------------------------------------------------

    // Default all bits to 1 (Input/Hi-Z) first, then override the outputs
    //assign io_oeb = {`MPRJ_IO_PADS{1'b1}};

    // Override to '0' for pins that are explicitly OUTPUTS:
    //assign io_oeb[18:11] = 8'b0;  // rx_data [cite: 2205]
    //assign io_oeb[30]    = 1'b0;  // ScanOutCC
    //assign io_oeb[32]    = 1'b0;  // rx_ack [cite: 2206]
    //assign io_oeb[34:33] = 2'b0;  // active_mode [cite: 2206]
    //assign io_oeb[37]    = 1'b0;  // rx_valid [cite: 2206]


    // -------------------------------------------------------------------------
    // IO Output Enable Bar (io_oeb) Assignments
    // 0 = Output Enabled (Driven), 1 = Input Enabled (Hi-Z Output)
    // -------------------------------------------------------------------------

    assign io_oeb = {
        14'b11111111111111,
        13'b0000000000000,  // 18:11: rx_data (Outputs)
        11'b11111111111  // 10:0 : fabric_top serial inputs & Unused (Inputs)
    };


    // -------------------------------------------------------------------------
    // IO Output Data (io_out) Assignments
    // -------------------------------------------------------------------------

    // Wire up your outputs directly to the submodules
    wire    [7:0]   rx_data;
    wire            scan_out_cc_wire;
    wire            rx_ack_wire;
    wire    [1:0]   active_mode_wire;
    wire            rx_valid_wire;

    assign io_out[18:11] = rx_data;
    assign io_out[23]    = scan_out_cc_wire;
    assign io_out[19]    = rx_ack_wire;
    assign io_out[21:20] = active_mode_wire;
    assign io_out[22]    = rx_valid_wire;

    // For all other pins, safely tie io_out to 0 so they don't float during synthesis
    // (Verilog allows us to do this cleanly by assigning individual bits/slices)
    assign io_out[10:0]  = 11'b0;
    assign io_out[37:24] = 13'b0;

    //assign io_out[31]    = 1'b0;
    //assign io_out[36:35] = 2'b0;
    //assign io_out[`MPRJ_IO_PADS-1:38] = {(`MPRJ_IO_PADS-38){1'b0}};


    // -------------------------------------------------------------------------
    // Instantiate the neuromorphic core
    // -------------------------------------------------------------------------
    nvm_neuron_core_256x64 mprj (
`ifdef USE_POWER_PINS
        .VDDC1 (vccd1),
        .VDDC2 (vccd2),
        .VDDA1 (vdda1),
        .VDDA2 (vdda2),
        .VSS   (vssd1),
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
        .ScanInCC  (io_in[36]),
        .ScanInDL  (io_in[37]),
        .ScanInDR  (io_in[24]),
        .TM        (io_in[25]),
        .ScanOutCC (scan_out_cc_wire),

        // Analog / bias pins
        .Iref          (analog_io[19]),
        .Vcc_read      (analog_io[20]),
        .Vcomp         (analog_io[21]),
        .Bias_comp2    (analog_io[22]),
        .Vcc_wl_read   (analog_io[23]),
        .Vcc_wl_set    (analog_io[24]),
        .Vbias         (analog_io[25]),
        .Vcc_wl_reset  (analog_io[26]),
        .Vcc_set       (analog_io[27]),
        .dc_bias       (analog_io[28])
    );

    adaptive_fabric_top_tapeout fabric_top(
    .clk(io_in[5]),           // pin 1
    .rst_n(io_in[6]),         // pin 2  (active-low)

    .serial_rx(io_in[7]),     // pin 3  UART RX  / I2C SDA
    .serial_sclk(io_in[8]),   // pin 4  SPI SCLK / I2C SCL
    .serial_cs_n(io_in[9]),   // pin 5  SPI CS_N
    .serial_mosi(io_in[10]),   // pin 6  SPI MOSI

    .rx_data(rx_data),             // <-- Connected to wire
    .rx_valid(rx_valid_wire),      // <-- Connected to wire
    .rx_ack(rx_ack_wire),          // <-- Connected to wire

    .active_mode(active_mode_wire) // <-- Connected to wire
);


endmodule
`default_nettype wire
