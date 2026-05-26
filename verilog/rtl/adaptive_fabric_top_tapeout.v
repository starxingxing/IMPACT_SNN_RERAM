`timescale 1ns/1ps

module adaptive_fabric_top_tapeout (
    input  wire        clk,           // pin 1
    input  wire        rst_n,         // pin 2  (active-low)

    input  wire        serial_rx,     // pin 3  UART RX  / I2C SDA
    input  wire        serial_sclk,   // pin 4  SPI SCLK / I2C SCL
    input  wire        serial_cs_n,   // pin 5  SPI CS_N
    input  wire        serial_mosi,   // pin 6  SPI MOSI

    output wire [7:0]  rx_data,       // pins 7-14  received byte
    output wire        rx_valid,      // pin 15     byte ready to read
    input  wire        rx_ack,        // pin 16     pulse high to pop byte

    output wire [1:0]  active_mode    // pins 17-18 00=idle 01=UART 10=SPI 11=I2C
);

    adaptive_fabric_top u_fabric (
        .clk            (clk),
        .rst_n          (rst_n),

        .serial_rx      (serial_rx),
        .serial_sclk    (serial_sclk),
        .serial_cs_n    (serial_cs_n),
        .serial_mosi    (serial_mosi),

        .rx_data        (rx_data),
        .rx_valid       (rx_valid),
        .rx_ack         (rx_ack),

        .active_mode    (active_mode),
        .low_power_en   (),           
        .switch_pulse   (),          
        .error_flags    (),           

        .apb_override   (1'b0),
        .psel           (1'b0),
        .penable        (1'b0),
        .pwrite         (1'b0),
        .paddr          (5'b0),
        .pwdata         (32'b0),
        .prdata         (),           
        .pready         (),           
        .pslverr        ()            
    );

endmodule
