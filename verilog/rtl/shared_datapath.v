`timescale 1ns/1ps
module shared_datapath (
    input  wire        clk, rst_n,
    input  wire [15:0] clk_div,
    output reg         baud_tick,
    output reg         sclk_int,
    input  wire [7:0]  tx_din,
    input  wire        tx_push,
    output wire        tx_full, tx_empty,
    output wire [7:0]  rx_dout,
    input  wire        rx_pop,
    output wire        rx_full, rx_valid,
    input  wire        sr_load,
    input  wire        sr_shift,
    input  wire        sr_lsb_first,
    output wire        serial_out,
    input  wire        rx_sample,
    input  wire        serial_in,
    output wire [7:0]  rx_capture,
    input  wire        bc_clear,
    input  wire        bc_inc,
    output wire [2:0]  bit_count,
    output wire        sr_done,
    input  wire        rx_push,
    input  wire [7:0]  rx_din
);
    reg [15:0] div_cnt, clk_div_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt<=0; clk_div_r<=0; baud_tick<=0; sclk_int<=0;
        end else begin
            baud_tick  <= 0;
            clk_div_r  <= clk_div;
            if (clk_div != clk_div_r) begin
                div_cnt <= 0;
            end else if (div_cnt >= clk_div) begin
                div_cnt   <= 0;
                baud_tick <= 1;
                sclk_int  <= ~sclk_int;
            end else begin
                div_cnt <= div_cnt + 1;
            end
        end
    end

    reg [7:0] tx_sr;
    wire [7:0] tx_fifo_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_sr <= 0;
        else if (sr_load) tx_sr <= tx_fifo_out;
        else if (sr_shift) begin
            if (sr_lsb_first) tx_sr <= {1'b1, tx_sr[7:1]};
            else               tx_sr <= {tx_sr[6:0], 1'b0};
        end
    end
    assign serial_out = sr_lsb_first ? tx_sr[0] : tx_sr[7];

    reg [7:0] rx_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_sr <= 0;
        else if (rx_sample) begin
            if (sr_lsb_first) rx_sr <= {serial_in, rx_sr[7:1]};
            else               rx_sr <= {rx_sr[6:0], serial_in};
        end
    end
    assign rx_capture = rx_sr;

    reg [2:0] bit_cnt_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        bit_cnt_r <= 0;
        else if (bc_clear) bit_cnt_r <= 0;
        else if (bc_inc)   bit_cnt_r <= bit_cnt_r + 1;
    end
    assign bit_count = bit_cnt_r;
    assign sr_done   = (bit_cnt_r == 3'd7);

    reg [7:0] tx_mem [0:7];
    reg [2:0] tx_wptr, tx_rptr;
    reg [3:0] tx_cnt;
    assign tx_full    = (tx_cnt == 4'd8);
    assign tx_empty   = (tx_cnt == 4'd0);
    assign tx_fifo_out = tx_mem[tx_rptr];
    wire tx_pop_en = sr_load && !tx_empty;
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_wptr<=0; tx_rptr<=0; tx_cnt<=0;
        end else begin
            case ({tx_push & ~tx_full, tx_pop_en})
                2'b10: begin tx_mem[tx_wptr]<=tx_din; tx_wptr<=tx_wptr+1; tx_cnt<=tx_cnt+1; end
                2'b01: begin tx_rptr<=tx_rptr+1; tx_cnt<=tx_cnt-1; end
                2'b11: begin tx_mem[tx_wptr]<=tx_din; tx_wptr<=tx_wptr+1; tx_rptr<=tx_rptr+1; end
                default: ;
            endcase
        end
    end

    reg [7:0] rx_mem [0:7];
    reg [2:0] rx_wptr, rx_rptr;
    reg [3:0] rx_cnt;
    assign rx_full  = (rx_cnt == 4'd8);
    assign rx_valid = (rx_cnt != 4'd0);
    assign rx_dout  = rx_mem[rx_rptr];
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
        end else begin
            case ({rx_push & ~rx_full, rx_pop & rx_valid})
                2'b10: begin rx_mem[rx_wptr]<=rx_din; rx_wptr<=rx_wptr+1; rx_cnt<=rx_cnt+1; end
                2'b01: begin rx_rptr<=rx_rptr+1; rx_cnt<=rx_cnt-1; end
                2'b11: begin rx_mem[rx_wptr]<=rx_din; rx_wptr<=rx_wptr+1; rx_rptr<=rx_rptr+1; end
                default: ;
            endcase
        end
    end
endmodule
