/***********************************************************
 * rstmgr_filter - Reset glitch filter
 *
 * Filters runt pulses on in_rst_n. A pulse must stay low for >= glitch_th
 * clk cycles before propagating.
 *
 * BUG_003 (planted): the counter-clear-on-release is inside @(posedge clk).
 * If clk stops toggling, the filter holds the reset forever even after
 * in_rst_n deasserts. Caught by rstmgr_glitch_vseq with clk-stop injection.
 ************************************************************/
`ifndef RSTMGR_FILTER__SV
`define RSTMGR_FILTER__SV

module rstmgr_filter (
    input  logic       clk,
    input  logic       in_rst_n,
    input  logic [7:0] glitch_th,
    input  logic       bypass,
    output logic       out_rst_n
);

    int counter_q;

    always_ff @(posedge clk or negedge in_rst_n) begin
        if (!in_rst_n) begin
            // BUG_003: counter clear path is gated by clk posedge below.
            // If clk stops, counter never resets and out_rst_n stays 0.
            if (counter_q >= int'(glitch_th) || bypass)
                counter_q <= counter_q;
            else
                counter_q <= counter_q + 1;
        end else begin
            counter_q <= 0;
        end
    end

    always_comb begin
        if (bypass)
            out_rst_n = in_rst_n;
        else if (!in_rst_n && (counter_q >= int'(glitch_th)))
            out_rst_n = 1'b0;
        else
            out_rst_n = 1'b1;
    end

endmodule
`endif
