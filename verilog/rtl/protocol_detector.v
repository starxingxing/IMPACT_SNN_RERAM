module protocol_detector (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    input  wire spi_sclk,
    input  wire spi_cs_n,
    input  wire i2c_scl,
    input  wire i2c_sda,
    output reg  [1:0] detected_mode,
    output wire [15:0] uart_est_bit_period,
    output wire [15:0] uart_start_bit_period,
    output wire spi_timeout_error,
    output wire        uart_measuring
);
    wire uart_det;
    wire spi_det;
    wire i2c_det;
    wire i2c_start, i2c_stop;

    uart_detector u_uart_det (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx),
        .detected(uart_det), .est_bit_period(uart_est_bit_period),
        .start_bit_period(uart_start_bit_period),
        .measuring(uart_measuring)
    );

    spi_detector u_spi_det (
        .clk(clk), .rst_n(rst_n), .sclk(spi_sclk), .cs_n(spi_cs_n),
        .detected(spi_det), .timeout_error(spi_timeout_error)
    );

    i2c_detector u_i2c_det (
        .clk(clk), .rst_n(rst_n), .scl(i2c_scl), .sda(i2c_sda),
        .detected(i2c_det), .start_seen(i2c_start), .stop_seen(i2c_stop)
    );

    always @(*) begin
        if (i2c_det)       detected_mode = 2'b11;
        else if (spi_det)  detected_mode = 2'b10;
        else if (uart_det) detected_mode = 2'b01;
        else               detected_mode = 2'b00;
    end
endmodule
