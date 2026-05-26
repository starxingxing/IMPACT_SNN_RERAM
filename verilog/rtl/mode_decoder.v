`timescale 1ns/1ps
module mode_decoder (
    input  wire        clk, rst_n,
    input  wire        psel, penable, pwrite,
    input  wire [4:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready, pslverr,
    output reg  [1:0]  mode,
    output reg         en,
    output reg  [15:0] clk_div,
    output reg         cpol, cpha, cs_pol,
    output reg  [6:0]  i2c_addr,
    output reg         i2c_dir,
    input  wire        tx_empty, rx_valid, busy, arb_lost
);
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode    <= 2'b00; en      <= 1'b0;
            clk_div <= 16'd53;
            cpol    <= 1'b0;  cpha    <= 1'b0;  cs_pol  <= 1'b0;
            i2c_addr<= 7'h50; i2c_dir <= 1'b0;
        end else if (psel && penable && pwrite) begin
            case (paddr[4:2])
                3'h0: begin mode <= pwdata[1:0]; en <= pwdata[2]; end
                3'h1: clk_div  <= pwdata[15:0];
                3'h2: begin cpol<=pwdata[0]; cpha<=pwdata[1]; cs_pol<=pwdata[2]; end
                3'h3: begin i2c_addr<=pwdata[6:0]; i2c_dir<=pwdata[7]; end
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (paddr[4:2])
            3'h0: prdata = {29'b0, en, mode};
            3'h1: prdata = {16'b0, clk_div};
            3'h2: prdata = {29'b0, cs_pol, cpha, cpol};
            3'h3: prdata = {24'b0, i2c_dir, i2c_addr};
            3'h4: prdata = {28'b0, arb_lost, busy, rx_valid, tx_empty};
            default: prdata = 32'hDEAD_BEEF;
        endcase
    end
endmodule
