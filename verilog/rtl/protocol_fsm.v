`timescale 1ns/1ps

module protocol_fsm (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [1:0]  mode,
    input  wire        en,
    input  wire        cpol,
    input  wire        cpha,
    input  wire        cs_pol,
    input  wire [6:0]  i2c_addr,
    input  wire        i2c_dir,

    input  wire        baud_tick,
    input  wire        sclk_int,
    input  wire        ext_sclk,    // external SCLK for SPI slave (rx_en mode)
    input  wire        ext_cs_n,    // external CS_N for SPI slave frame boundary
    input  wire        tx_empty,
    input  wire        rx_en,
    input  wire [2:0]  bit_count,
    input  wire        sr_done,
    input  wire        serial_in,
    input  wire [7:0]  rx_capture,  // assembled RX byte

    output reg         sr_load,
    output reg         sr_shift,
    output reg         sr_lsb_first,
    output reg         rx_sample,
    output reg         bc_clear,
    output reg         bc_inc,
    output reg         rx_push,
    output reg  [7:0]  rx_din,

    output reg         uart_tx_drive, // 1=drive serial_out to pad, 0=drive tx_level
    output reg         tx_level,      // idle/start/stop level (UART)
    output reg         sclk_out,
    output reg         cs_n,
    output reg         sda_oe,

    output reg         busy,
    output reg         arb_lost
);

    localparam IDLE  = 3'b001;
    localparam FRAME = 3'b010;
    localparam STOP  = 3'b100;

    localparam UART = 2'b00;
    localparam SPI  = 2'b01;
    localparam I2C  = 2'b10;

    reg [2:0]  state, nstate;
    reg        sclk_prev;
    reg        ext_sclk_prev;
    reg        ext_cs_n_prev;
    reg        serial_in_d;
    reg [3:0]  uart_baud_cnt;
    reg        uart_rx_commit;
    reg        uart_started;
    reg        uart_data_started;
    reg        rx_committed;
    reg        uart_saw_idle;
    reg        spi_byte_done;
    reg        i2c_byte_done;
    reg        i2c_phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            sclk_prev     <= 1'b0;
            ext_sclk_prev <= 1'b0;
            ext_cs_n_prev <= 1'b1;
            uart_baud_cnt <= 4'b0;
            i2c_phase     <= 1'b0;
            uart_rx_commit    <= 1'b0;
            uart_started      <= 1'b0;
            uart_data_started <= 1'b0;
            rx_committed      <= 1'b0;
            uart_saw_idle     <= 1'b0;
            spi_byte_done     <= 1'b0;
            i2c_byte_done <= 1'b0;
            serial_in_d   <= 1'b1;
        end else begin
            state       <= nstate;
            sclk_prev     <= sclk_int;
            ext_sclk_prev <= ext_sclk;
            ext_cs_n_prev <= ext_cs_n;
            serial_in_d <= serial_in;
            uart_rx_commit <= 1'b0;
            spi_byte_done  <= 1'b0;
            i2c_byte_done  <= 1'b0;

            if (state != FRAME || mode != UART)
                uart_baud_cnt <= 4'b0;
            else if (baud_tick)
                uart_baud_cnt <= uart_baud_cnt + 1'b1;

            if (state == IDLE) begin
                uart_started      <= 1'b0;
                uart_data_started <= 1'b0;
                rx_committed      <= 1'b0;
                uart_saw_idle     <= 1'b0;
            end
            else if (state == FRAME && mode == UART && !uart_started) begin
                if (rx_en && tx_empty) begin
                    if (baud_tick && uart_baud_cnt == 4'd8 && serial_in)
                        uart_saw_idle <= 1'b1;     // 8+ baud_ticks of line=1: safe to arm
                    if (uart_saw_idle && serial_in_d && !serial_in)
                        uart_baud_cnt <= 4'b0;     // reset counter on start-bit edge
                    else if (uart_saw_idle && baud_tick && uart_baud_cnt == 4'd7 && !serial_in) begin
                        uart_started  <= 1'b1;
                        uart_saw_idle <= 1'b0;     // consume idle — must re-arm after this byte
                        uart_baud_cnt <= 4'b0;     // restart; uart_data_started fires at cnt==7
                    end
                end else begin

                    if (baud_tick && uart_baud_cnt == 4'd15)
                        uart_started <= 1'b1;
                end
            end

            if (state == IDLE)
                i2c_phase <= 1'b0;
            else if (i2c_byte_done && mode == I2C)
                i2c_phase <= ~i2c_phase;

            if (!uart_data_started && uart_started && rx_en && tx_empty &&
                state == FRAME && mode == UART && baud_tick && uart_baud_cnt == 4'd7)
                uart_data_started <= 1'b1;

            if (state == FRAME && mode == UART && uart_started && !rx_committed &&
                baud_tick && uart_baud_cnt == 4'd8 && sr_done) begin
                uart_rx_commit <= 1'b1;
                rx_committed   <= 1'b1;
            end

            if (state == FRAME && mode == SPI) begin
                if (cpol == cpha) begin
                    if ((rx_en&&tx_empty ? (ext_sclk&&!ext_sclk_prev) : (sclk_int&&!sclk_prev)) && sr_done)
                        spi_byte_done <= 1'b1;
                end else begin
                    if ((rx_en&&tx_empty ? (!ext_sclk&&ext_sclk_prev) : (!sclk_int&&sclk_prev)) && sr_done)
                        spi_byte_done <= 1'b1;
                end
            end

            if (state == FRAME && mode == I2C) begin
                if (sclk_int && !sclk_prev && sr_done)
                    i2c_byte_done <= 1'b1;
            end
        end
    end

    always @(*) begin
        nstate = state;
        case (state)
            IDLE:
                if ((en && !tx_empty) || rx_en) nstate = FRAME;

            FRAME:
                case (mode)
                    UART: if (uart_rx_commit && tx_empty)
                              nstate = STOP;
                    SPI:  if (spi_byte_done && tx_empty)
                              nstate = STOP;
                    I2C:  if (i2c_byte_done && i2c_phase)
                              nstate = STOP;
                    default: nstate = IDLE;
                endcase

            STOP:
                if (baud_tick) nstate = IDLE;

            default: nstate = IDLE;
        endcase
    end

    wire sclk_use  = (rx_en && tx_empty) ? ext_sclk : sclk_int;  // slave vs master SCLK
    wire sclk_prev_use = (rx_en && tx_empty) ? ext_sclk_prev : sclk_prev;
    always @(*) begin
        sr_load       = 1'b0;
        sr_shift      = 1'b0;
        sr_lsb_first  = (mode == UART);
        rx_sample     = 1'b0;
        bc_clear      = 1'b0;
        bc_inc        = 1'b0;
        rx_push       = 1'b0;
        rx_din        = 8'b0;
        busy          = (state != IDLE);
        arb_lost      = 1'b0;
        uart_tx_drive = 1'b0;
        tx_level      = 1'b1;       // UART idle high
        sclk_out      = (mode == 2'b10) ? 1'b1 : cpol;  // I2C SCL idles high
        cs_n          = ~cs_pol;
        sda_oe        = 1'b0;

        case (state)
            IDLE: begin
                bc_clear = 1'b1;
                if (en && !tx_empty)
                    sr_load = 1'b1;     // pre-load before entering FRAME
                if (mode == SPI && en && !tx_empty)
                    cs_n = cs_pol;      // pre-assert CS when data pending
                if (mode == I2C && en && !tx_empty) begin
                    sda_oe   = 1'b1;    // drive SDA low = START condition
                    sclk_out = 1'b1;
                end
            end

            FRAME: begin
                case (mode)
                    UART: begin
                        uart_tx_drive = (tx_empty && rx_en) ? 1'b0 : 1'b1;
                        sr_lsb_first  = 1'b1;

                        if (baud_tick) begin
                            if (uart_baud_cnt == 4'd15 && uart_started)
                                sr_shift = 1'b1;

                            if (uart_baud_cnt == 4'd8 && uart_started &&
                                (!(rx_en && tx_empty) || uart_data_started)) begin
                                rx_sample = 1'b1;
                                bc_inc    = 1'b1;
                                if (sr_done)
                                    bc_clear = 1'b1;
                            end
                        end

                        if (uart_rx_commit) begin
                            rx_push = 1'b1;
                            rx_din  = rx_capture;
                            if (!tx_empty) sr_load = 1'b1;
                        end
                    end

                    SPI: begin
                        cs_n          = cs_pol;
                        sclk_out      = sclk_int;   // master drives sclk_int
                        sr_lsb_first  = 1'b0;
                        if (rx_en && tx_empty && !ext_cs_n && ext_cs_n_prev)
                            bc_clear = 1'b1;

                        if (cpol == cpha) begin
                            if (sclk_use && !sclk_prev_use) begin
                                rx_sample = 1'b1;
                                if (!sr_done) bc_inc = 1'b1;
                            end
                            if (!sclk_use && sclk_prev_use && !spi_byte_done)
                                sr_shift = 1'b1;
                        end else begin
                            if (!sclk_use && sclk_prev_use) begin
                                rx_sample = 1'b1;
                                if (!sr_done) bc_inc = 1'b1;
                            end
                            if (sclk_use && !sclk_prev_use && !spi_byte_done)
                                sr_shift = 1'b1;
                        end

                        if (spi_byte_done) begin
                            bc_clear = 1'b1;
                            rx_push  = 1'b1;
                            rx_din   = rx_capture;
                            if (!tx_empty) sr_load = 1'b1;
                        end
                    end

                    I2C: begin
                        sclk_out     = sclk_int;
                        sda_oe       = 1'b1;
                        sr_lsb_first = 1'b0;

                        if (sclk_int && !sclk_prev) begin
                            rx_sample = 1'b1;
                            if (!sr_done) bc_inc = 1'b1;   // sample 8 bits
                            if (serial_in == 1'b0 && sda_oe)
                                arb_lost = 1'b1;
                        end
                        if (!sclk_int && sclk_prev && !i2c_byte_done)
                            sr_shift = 1'b1;

                        if (i2c_byte_done) begin
                            bc_clear = 1'b1;
                            if (i2c_phase && i2c_dir) begin
                                rx_push = 1'b1;
                                rx_din  = rx_capture;
                            end
                            if (!i2c_phase && !tx_empty) sr_load = 1'b1;
                        end
                    end

                    default: ;
                endcase
            end

            STOP: begin
                case (mode)
                    UART: begin
                        uart_tx_drive = 1'b0;
                        tx_level      = 1'b1;   // stop bit = high
                    end
                    SPI: begin
                        cs_n     = ~cs_pol;
                        sclk_out = cpol;
                    end
                    I2C: begin
                        sclk_out = 1'b1;
                        sda_oe   = 1'b0;    // release SDA high = STOP condition
                    end
                    default: ;
                endcase
            end

            default: ;
        endcase
    end

endmodule
