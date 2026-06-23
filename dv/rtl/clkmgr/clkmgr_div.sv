/***********************************************************
 * clkmgr_div - Dynamic clock divider (clkmgr internal)
 *
 * Divides clk_in by (div_ratio + 1). half_en=1 adds half a cycle so
 * non-integer ratios (1.5, 2.5, ...) are supported. Config changes commit
 * on clk_in's falling edge to avoid runt pulses.
 ************************************************************/
`ifndef CLKMGR_DIV__SV
`define CLKMGR_DIV__SV

module clkmgr_div (
    input  logic       clk_in,
    input  logic [6:0] div_ratio,
    input  logic       half_en,
    input  logic       rst_n,
    output logic       clk_out
);

    logic [6:0] div_ratio_q;
    logic       half_en_q;
    int         total_half;
    int         counter_q;
    bit         out_q;

    always_ff @(negedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            div_ratio_q <= 7'd0;
            half_en_q   <= 1'b0;
        end else begin
            div_ratio_q <= div_ratio;
            half_en_q   <= half_en;
        end
    end

    always_comb begin
        total_half = 2 * (int'(div_ratio_q) + 1);
        if (half_en_q) total_half = total_half - 1;
        if (total_half < 1) total_half = 1;
    end

    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            counter_q <= 0;
            out_q     <= 1'b0;
        end else begin
            if (counter_q >= total_half - 1) begin
                counter_q <= 0;
                out_q     <= ~out_q;
            end else begin
                counter_q <= counter_q + 1;
            end
        end
    end

    assign clk_out = out_q;

endmodule
`endif
