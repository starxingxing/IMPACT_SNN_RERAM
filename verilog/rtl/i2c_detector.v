module i2c_detector (
    input  wire clk,
    input  wire rst_n,
    input  wire scl,
    input  wire sda,
    output reg  detected,
    output reg  start_seen,
    output reg  stop_seen
);
    reg scl_d, sda_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_d <= 1'b1;
            sda_d <= 1'b1;
            detected <= 1'b0;
            start_seen <= 1'b0;
            stop_seen <= 1'b0;
        end else begin
            scl_d <= scl;
            sda_d <= sda;
            detected <= 1'b0;
            start_seen <= 1'b0;
            stop_seen <= 1'b0;

            if (scl && sda_d && !sda) begin
                start_seen <= 1'b1;
                detected <= 1'b1;
            end

            if (scl && !sda_d && sda) begin
                stop_seen <= 1'b1;
            end
        end
    end
endmodule
