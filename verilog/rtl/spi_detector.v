module spi_detector #(
    parameter integer MIN_EDGES = 4,
    parameter integer TIMEOUT_CLKS = 1024
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,
    input  wire cs_n,
    output reg  detected,
    output reg  timeout_error
);
    reg sclk_d;
    reg [7:0] edge_cnt;
    reg [15:0] timeout_cnt;

    wire sclk_edge = sclk ^ sclk_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_d <= 1'b0;
            edge_cnt <= 8'd0;
            timeout_cnt <= 16'd0;
            detected <= 1'b0;
            timeout_error <= 1'b0;
        end else begin
            sclk_d <= sclk;
            detected <= 1'b0;
            timeout_error <= 1'b0;

            if (cs_n) begin
                edge_cnt <= 8'd0;
                timeout_cnt <= 16'd0;
            end else begin
                if (sclk_edge) begin
                    if (edge_cnt != 8'hff) edge_cnt <= edge_cnt + 8'd1;
                    timeout_cnt <= 16'd0;
                end else begin
                    if (timeout_cnt != 16'hffff) timeout_cnt <= timeout_cnt + 16'd1;
                end

                if (edge_cnt >= MIN_EDGES[7:0]) detected <= 1'b1;
                if (timeout_cnt > TIMEOUT_CLKS[15:0]) timeout_error <= 1'b1;
            end
        end
    end
endmodule
