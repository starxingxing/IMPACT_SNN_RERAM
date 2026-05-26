`default_nettype wire
`timescale 1ns/1ps

module adaptive_fabric_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        serial_rx,
    input  wire        serial_sclk,
    input  wire        serial_cs_n,
    input  wire        serial_mosi,

    output wire [7:0]  rx_data,
    output wire        rx_valid,
    input  wire        rx_ack,

    output wire [1:0]  active_mode,
    output wire        low_power_en,
    output wire        switch_pulse,
    output wire [3:0]  error_flags,

    input  wire        apb_override,
    input  wire        psel, penable, pwrite,
    input  wire [4:0]  paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready, pslverr
);

    wire rx_s, sclk_s, cs_n_s, mosi_s;

    sync_edge u_sync_rx   (.clk(clk),.rst_n(rst_n),.sig_async(serial_rx),
                            .sig_sync(rx_s),   .rise(),.fall());
    sync_edge u_sync_sclk (.clk(clk),.rst_n(rst_n),.sig_async(serial_sclk),
                            .sig_sync(sclk_s), .rise(),.fall());
    sync_edge u_sync_cs   (.clk(clk),.rst_n(rst_n),.sig_async(serial_cs_n),
                            .sig_sync(cs_n_s), .rise(),.fall());
    sync_edge u_sync_mosi (.clk(clk),.rst_n(rst_n),.sig_async(serial_mosi),
                            .sig_sync(mosi_s), .rise(),.fall());

    wire [1:0]  detected_mode;
    wire [15:0] uart_est_bit_period;
    wire [15:0] uart_start_bp;   // exact start-bit period measurement
    wire        spi_timeout_error;
    wire        uart_measuring;

    protocol_detector u_detector (
        .clk(clk), .rst_n(rst_n),
        .uart_rx(rx_s),
        .spi_sclk(sclk_s), .spi_cs_n(cs_n_s),
        .i2c_scl(sclk_s),  .i2c_sda(rx_s),
        .detected_mode(detected_mode),
        .uart_est_bit_period(uart_est_bit_period),
        .uart_start_bit_period(uart_start_bp),
        .spi_timeout_error(spi_timeout_error),
        .uart_measuring(uart_measuring)
    );

    wire fabric_rx_valid;

    mode_control_fsm #(.IDLE_TO_LOW_POWER(1024)) u_mode_fsm (
        .clk(clk), .rst_n(rst_n),
        .detected_mode(detected_mode),
        .fifo_overflow(fabric_rx_valid & ~rx_ack & ~rx_en_r),
        .spi_timeout_error(spi_timeout_error),
        .active_mode(active_mode),
        .low_power_en(low_power_en),
        .switch_pulse(switch_pulse),
        .error_flags(error_flags),
        .state()
    );

    reg [15:0] spi_edge_timer;
    reg [15:0] spi_half_period;
    reg        sclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_edge_timer  <= 0;
            spi_half_period <= 16'd4;
            sclk_prev       <= 0;
        end else begin
            sclk_prev <= sclk_s;
            if (!cs_n_s) begin
                spi_edge_timer <= spi_edge_timer + 1;
                if (sclk_s != sclk_prev && spi_edge_timer > 0) begin
                    spi_half_period <= spi_edge_timer;
                    spi_edge_timer  <= 0;
                end
            end else begin
                spi_edge_timer <= 0;
            end
        end
    end

    localparam AC_IDLE         = 4'd0;
    localparam AC_BAUD_WAIT    = 4'd1;   // wait for Layer 2 baud estimate to stabilise
    localparam AC_SETUP1       = 4'd2;
    localparam AC_ACCESS1      = 4'd3;
    localparam AC_IDLE_BETWEEN = 4'd4;
    localparam AC_SETUP2       = 4'd5;
    localparam AC_ACCESS2      = 4'd6;
    localparam AC_SETTLE       = 4'd7;
    localparam AC_ARM          = 4'd8;
    localparam AC_DRAIN        = 4'd9;   // discard spurious arm-TX RX byte

    reg [3:0]  ac_state;
    reg [1:0]  pending_mode;
    reg [1:0]  settle_cnt;
    reg [7:0]  baud_wait_cnt;
    reg [1:0]  last_configured_mode;  // tracks last mode we configured fabric for

    reg        auto_psel, auto_penable, auto_pwrite;
    reg [4:0]  auto_paddr;
    reg [31:0] auto_pwdata;
    reg        rx_en_r;      // asserted after fabric is configured

    wire fab_psel    = apb_override ? psel    : auto_psel;
    wire fab_penable = apb_override ? penable : auto_penable;
    wire fab_pwrite  = apb_override ? pwrite  : auto_pwrite;
    wire [4:0]  fab_paddr  = apb_override ? paddr   : auto_paddr;
    wire [31:0] fab_pwdata = apb_override ? pwdata  : auto_pwdata;

    function [31:0] ctrl_word;
        input [1:0] m;
        case (m)
            2'b01:   ctrl_word = 32'h00000004; // UART: fab_mode=00 EN=1
            2'b10:   ctrl_word = 32'h00000005; // SPI:  fab_mode=01 EN=1
            2'b11:   ctrl_word = 32'h00000006; // I2C:  fab_mode=10 EN=1
            default: ctrl_word = 32'h00000000;
        endcase
    endfunction

    function [31:0] div_word;
        input [1:0]  m;
        input [15:0] bp;   // UART est_bit_period
        input [15:0] hp;   // SPI/I2C half-period
        case (m)
            2'b01:   div_word = (uart_start_bp >= 32) ?
                         ({16'b0,(uart_start_bp+16'd8)>>4} - 32'd1) :
                         (bp >= 32) ? ({16'b0,(bp+16'd8)>>4} - 32'd1) : 32'd4;
            2'b10:   div_word = (hp > 0)  ? {16'b0, hp}       : 32'd4;
            2'b11:   div_word = (hp > 0)  ? {16'b0, hp}       : 32'd4;
            default: div_word = 32'd4;
        endcase
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ac_state     <= AC_IDLE;
            auto_psel    <= 0; auto_penable <= 0; auto_pwrite <= 0;
            auto_paddr   <= 0; auto_pwdata  <= 0;
            pending_mode <= 0;
            settle_cnt    <= 0;
            baud_wait_cnt         <= 0;
            last_configured_mode  <= 2'b00;
            rx_en_r               <= 0;
        end else begin
            auto_psel    <= 0;
            auto_penable <= 0;
            auto_pwrite  <= 0;
            case (ac_state)

                AC_IDLE: begin
                    if (switch_pulse && !apb_override &&
                        active_mode != last_configured_mode) begin
                        pending_mode  <= active_mode;
                        baud_wait_cnt <= 8'd0;
                        ac_state      <= AC_BAUD_WAIT;
                    end
                end

                AC_BAUD_WAIT: begin
                    if (!uart_measuring)
                        ac_state <= AC_SETUP1;  // frame done, now configure
                    else
                        baud_wait_cnt <= baud_wait_cnt + 1;  // keep counting
                end

                AC_SETUP1: begin
                    auto_psel   <= 1;
                    auto_pwrite <= 1;
                    auto_paddr  <= 5'h00;
                    auto_pwdata <= ctrl_word(pending_mode);
                    ac_state    <= AC_ACCESS1;
                end

                AC_ACCESS1: begin
                    auto_psel    <= 1;
                    auto_penable <= 1;
                    auto_pwrite  <= 1;
                    auto_paddr   <= 5'h00;
                    auto_pwdata  <= ctrl_word(pending_mode);
                    ac_state     <= AC_IDLE_BETWEEN;
                end

                AC_IDLE_BETWEEN: begin
                    ac_state <= AC_SETUP2;
                end

                AC_SETUP2: begin
                    auto_psel   <= 1;
                    auto_pwrite <= 1;
                    auto_paddr  <= 5'h04;
                    auto_pwdata <= div_word(pending_mode,
                                           uart_est_bit_period,
                                           spi_half_period);
                    ac_state    <= AC_ACCESS2;
                end

                AC_ACCESS2: begin
                    auto_psel    <= 1;
                    auto_penable <= 1;
                    auto_pwrite  <= 1;
                    auto_paddr   <= 5'h04;
                    auto_pwdata  <= div_word(pending_mode,
                                            uart_est_bit_period,
                                            spi_half_period);
                    settle_cnt   <= 2'd2;
                    ac_state     <= AC_SETTLE;
                end

                AC_SETTLE: begin
                    if (settle_cnt == 0)
                        ac_state <= AC_ARM;
                    else
                        settle_cnt <= settle_cnt - 1;
                end

                AC_ARM: begin
                    rx_en_r              <= 1'b1;   // enable RX path
                    last_configured_mode <= pending_mode;
                    ac_state             <= AC_IDLE;
                end

                default: ac_state <= AC_IDLE;

            endcase
        end
    end

    wire [1:0] fab_mode_reg;   // driven from serial_fabric_top fabric_mode port
    wire fab_mode_is_spi = (fab_mode_reg == 2'b01);
    wire pad0_out, pad0_oe, pad1_out, pad2_out, pad2_oe;
    wire fabric_tx_full, fabric_tx_empty;


    serial_fabric_top u_fabric (
        .clk(clk), .rst_n(rst_n),
        .psel(fab_psel), .penable(fab_penable), .pwrite(fab_pwrite),
        .paddr(fab_paddr), .pwdata(fab_pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .tx_din(8'h00),
        .tx_push(1'b0),
        .tx_full(fabric_tx_full),
        .tx_empty(fabric_tx_empty),
        .rx_dout(rx_data),
        .rx_pop(rx_ack),
        .rx_en(rx_en_r),
        .ext_sclk(sclk_s),
        .ext_cs_n(cs_n_s),
        .rx_valid(fabric_rx_valid),
        .pad0_out(pad0_out),
        .pad0_in(fab_mode_is_spi ? mosi_s : rx_s),
        .pad0_oe(pad0_oe),
        .pad1_out(pad1_out),
        .fabric_mode(fab_mode_reg),
        .pad2_out(pad2_out),
        .pad2_oe(pad2_oe)
    );

    assign rx_valid = fabric_rx_valid;

endmodule
