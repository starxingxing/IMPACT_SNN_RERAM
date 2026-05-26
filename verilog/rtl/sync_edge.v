module sync_edge (
    input  wire clk,
    input  wire rst_n,
    input  wire sig_async,
    output reg  sig_sync,
    output wire rise,
    output wire fall
);
    reg s0, s1, s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0 <= 1'b0;
            s1 <= 1'b0;
            s2 <= 1'b0;
            sig_sync <= 1'b0;
        end else begin
            s0 <= sig_async;
            s1 <= s0;
            s2 <= s1;
            sig_sync <= s1;
        end
    end

    assign rise =  s1 & ~s2;
    assign fall = ~s1 &  s2;
endmodule
