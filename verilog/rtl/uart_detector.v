module uart_detector #(
    parameter integer MIN_BIT_CLKS =   16,
    parameter integer MAX_BIT_CLKS = 8680
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,
    output reg         detected,
    output reg  [15:0] est_bit_period,
    output reg  [15:0] start_bit_period,
    output reg         measuring
);
    reg        rx_d;
    reg [15:0] idle_cnt;
    reg        seen_idle;

    reg [15:0] edge_timer;

    reg [15:0] buf0, buf1, buf2, buf3;  // explicit register (no array indexing)
    reg [1:0]  widx;                    // circular write pointer
    reg [2:0]  count;                   // samples accumulated, capped at 4
    reg [17:0] sum;                     // sum of valid samples

    reg [17:0] next_sum;
    reg [2:0]  next_count;
    reg [15:0] next_est;
    reg [15:0] evicted;    // oldest sample being replaced

    always @(*) begin
        case (widx)
            2'd0: evicted = buf0;
            2'd1: evicted = buf1;
            2'd2: evicted = buf2;
            2'd3: evicted = buf3;
            default: evicted = 0;
        endcase
    end

    always @(*) begin
        if (count < 3'd4) begin
            next_sum   = sum + {2'b0, edge_timer};
            next_count = count + 1;
        end else begin
            next_sum   = sum - {2'b0, evicted} + {2'b0, edge_timer};
            next_count = 3'd4;
        end
        case (next_count)
			3'd1:    next_est = next_sum[15:0];
			3'd2:    next_est = next_sum[16:1];
			3'd3:    next_est = next_sum[17:2];  // synthesis-safe approximation
			default: next_est = next_sum[17:2];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d          <= 1'b1;
            idle_cnt      <= 0;
            seen_idle     <= 0;
            edge_timer    <= 0;
            measuring     <= 0;
            detected      <= 0;
            est_bit_period    <= 0;
            start_bit_period <= 0;
            buf0<=0; buf1<=0; buf2<=0; buf3<=0;
            widx  <= 0;
            count <= 0;
            sum   <= 0;
        end else begin
            rx_d     <= rx;
            detected <= 0;

            if (rx) begin
                if (idle_cnt != 16'hffff) idle_cnt <= idle_cnt + 1;
            if (!measuring && idle_cnt >= MIN_BIT_CLKS[15:0]) seen_idle <= 1;
            end else begin
                idle_cnt <= 0;
            end

            if (measuring)
                if (edge_timer != 16'hffff) edge_timer <= edge_timer + 1;

            if (!rx_d && rx && measuring) begin
                if (edge_timer >= MIN_BIT_CLKS[15:0] &&
                    edge_timer <= MAX_BIT_CLKS[15:0]) begin
                    sum   <= next_sum;
                    count <= next_count;
                    case (widx)
                        2'd0: buf0 <= edge_timer;
                        2'd1: buf1 <= edge_timer;
                        2'd2: buf2 <= edge_timer;
                        2'd3: buf3 <= edge_timer;
                    endcase
                    widx           <= widx + 1;
                    if (count == 3'd0)
                        start_bit_period <= edge_timer;
                    est_bit_period <= next_est;  // correct average, no lag
                end
                edge_timer <= 0;
            end

            if (rx_d && !rx) begin
                if (seen_idle) begin
                    detected   <= 1;
                    seen_idle  <= 0;
                    measuring  <= 1;
                    edge_timer <= 0;
                    buf0<=0; buf1<=0; buf2<=0; buf3<=0;
                    widx  <= 0;
                    count <= 0;
                    sum   <= 0;
                    if (idle_cnt >= MIN_BIT_CLKS[15:0] &&
                        idle_cnt <= MAX_BIT_CLKS[15:0])
                        est_bit_period <= idle_cnt;
                end else if (measuring) begin
                    if (edge_timer >= MIN_BIT_CLKS[15:0] &&
                        edge_timer <= MAX_BIT_CLKS[15:0]) begin
                        sum   <= next_sum;
                        count <= next_count;
                        case (widx)
                            2'd0: buf0 <= edge_timer;
                            2'd1: buf1 <= edge_timer;
                            2'd2: buf2 <= edge_timer;
                            2'd3: buf3 <= edge_timer;
                        endcase
                        widx           <= widx + 1;
                        est_bit_period <= next_est;
                    end
                    edge_timer <= 0;
                end else begin
                    measuring <= 0;
                end
            end

            if (rx && measuring && est_bit_period > 0 &&
                idle_cnt > est_bit_period)  // > 1 bit period = stop bit done
                measuring <= 0;
        end
    end
endmodule
