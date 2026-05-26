

module mode_control_fsm #(
    parameter integer IDLE_TO_LOW_POWER = 256
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [1:0] detected_mode,
    input  wire fifo_overflow,
    input  wire spi_timeout_error,
    output reg  [1:0] active_mode,
    output reg  low_power_en,
    output reg  switch_pulse,
    output reg  [3:0] error_flags,
    output reg  [4:0] state
);
    localparam ST_IDLE       = 5'd0;
    localparam ST_DETECT     = 5'd1;
    localparam ST_CFG_UART   = 5'd2;
    localparam ST_CFG_SPI    = 5'd3;
    localparam ST_CFG_I2C    = 5'd4;
    localparam ST_ACTIVE     = 5'd5;
    localparam ST_ERROR      = 5'd6;
    localparam ST_SWITCH     = 5'd7;
    localparam ST_LOW_POWER  = 5'd8;

    reg [15:0] idle_cnt;
    reg [1:0]  latched_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            active_mode <= 2'b00;
            low_power_en <= 1'b0;
            switch_pulse <= 1'b0;
            error_flags <= 4'b0000;
            idle_cnt <= 16'd0;
            latched_mode <= 2'b00;
        end else begin
            switch_pulse <= 1'b0;
            if (detected_mode != 2'b00)
                latched_mode <= detected_mode;
            else if (state == ST_CFG_UART || state == ST_CFG_SPI || state == ST_CFG_I2C)
                latched_mode <= 2'b00;   // clear after acting

            if (fifo_overflow) error_flags <= error_flags | 4'b1000;
            if (spi_timeout_error) error_flags <= error_flags | 4'b0010;

            case (state)
                ST_IDLE: begin
                    active_mode <= 2'b00;
                    low_power_en <= 1'b0;
                    state <= ST_DETECT;
                end

                ST_DETECT: begin
                    if (detected_mode == 2'b01 || latched_mode == 2'b01) state <= ST_CFG_UART;
                    else if (detected_mode == 2'b10 || latched_mode == 2'b10) state <= ST_CFG_SPI;
                    else if (detected_mode == 2'b11 || latched_mode == 2'b11) state <= ST_CFG_I2C;
                    else begin
                        idle_cnt <= idle_cnt + 16'd1;
                        if (idle_cnt > IDLE_TO_LOW_POWER[15:0]) state <= ST_LOW_POWER;
                    end
                end

                ST_CFG_UART: begin active_mode <= 2'b01; switch_pulse <= 1'b1; state <= ST_ACTIVE; end
                ST_CFG_SPI:  begin active_mode <= 2'b10;  switch_pulse <= 1'b1; state <= ST_ACTIVE; end
                ST_CFG_I2C:  begin active_mode <= 2'b11;  switch_pulse <= 1'b1; state <= ST_ACTIVE; end

                ST_ACTIVE: begin
                    if (detected_mode != 2'b00)
                        idle_cnt <= 16'd0;
                    else
                        idle_cnt <= idle_cnt + 16'd1;
                    if (fifo_overflow || spi_timeout_error) state <= ST_ERROR;
                    else if (latched_mode != 2'b00 && latched_mode != active_mode) state <= ST_SWITCH;
                    else if (idle_cnt > IDLE_TO_LOW_POWER[15:0]) begin
                        active_mode <= 2'b00;
                        idle_cnt <= 16'd0;
                        state <= ST_DETECT;
                    end
                end

                ST_SWITCH: begin
                    switch_pulse <= 1'b1;
                    active_mode <= latched_mode;
                    state <= ST_ACTIVE;
                end

                ST_ERROR: begin
                    active_mode <= 2'b00;
                    state <= ST_DETECT;
                end

                ST_LOW_POWER: begin
                    low_power_en <= 1'b1;
                    if (detected_mode != 2'b00) begin
                        low_power_en <= 1'b0;
                        idle_cnt <= 16'd0;
                        state <= ST_DETECT;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
