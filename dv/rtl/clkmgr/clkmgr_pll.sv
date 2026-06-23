/***********************************************************
 * clkmgr_pll - Behavioral PLL model
 *
 * Implements lock FSM and fractional/int divider math.
 *
 *   Fvco = Fref * (fbdiv + (dsmen ? frac/2^24 : 0)) / refdiv
 *   Fout = Fvco / (postdiv1 * postdiv2)
 *
 * BUG_002 (planted): frac mode uses 2^23 instead of 2^24 -> freq doubled.
 * Caught by clkmgr_frequency_vseq via scoreboard period check.
 ************************************************************/
`ifndef CLKMGR_PLL__SV
`define CLKMGR_PLL__SV

module clkmgr_pll (
    input  logic        ref_clk,
    input  real         ref_period_ns,
    input  logic        bypass,
    input  logic [5:0]  refdiv,
    input  logic [7:0]  fbdiv,
    input  logic        dsmen,
    input  logic [23:0] frac,
    input  logic [2:0]  postdiv1,
    input  logic [2:0]  postdiv2,
    output logic        clk_out,
    output logic        lock
);

    real fbdiv_eff;
    always_comb begin
        if (dsmen)
            // BUG_002: spec is 2^24, RTL uses 2^23 -> freq doubled
            fbdiv_eff = real'(fbdiv) + real'(frac) / 2.0**23;
        else
            fbdiv_eff = real'(fbdiv);
    end

    real postdiv_total;
    always_comb begin
        postdiv_total = real'(postdiv1) * real'(postdiv2);
        if (postdiv_total == 0) postdiv_total = 1.0;
    end

    real out_period;
    always_comb begin
        if (fbdiv_eff > 0 && postdiv_total > 0)
            out_period = ref_period_ns * real'(refdiv) / fbdiv_eff * postdiv_total;
        else
            out_period = 0.0;
    end

    // Lock FSM
    int lock_counter;
    logic [5:0]  refdiv_d;
    logic [7:0]  fbdiv_d;
    logic        dsmen_d;
    logic [23:0] frac_d;
    logic        cfg_changed;

    always_ff @(posedge ref_clk) begin
        refdiv_d <= refdiv;
        fbdiv_d  <= fbdiv;
        dsmen_d  <= dsmen;
        frac_d   <= frac;
    end
    always_comb cfg_changed = (refdiv_d != refdiv) || (fbdiv_d != fbdiv) ||
                              (dsmen_d != dsmen)   || (frac_d  != frac);

    always_ff @(posedge ref_clk) begin
        if (bypass) begin
            lock <= 1'b0;
        end else begin
            if (cfg_changed) begin
                lock_counter <= int'(real'(refdiv) * real'(fbdiv)) + 5;
                lock         <= 1'b0;
            end else if (lock_counter > 0) begin
                lock_counter <= lock_counter - 1;
                lock         <= 1'b0;
            end else begin
                lock <= 1'b1;
            end
        end
    end

    real half_period;
    bit  clk_i;
    always_comb half_period = (out_period > 0) ? out_period / 2.0 : 0.0;

    initial begin
        clk_i = 1'b0;
        forever begin
            if (bypass) begin
                @(posedge ref_clk);
                clk_i = 1'b1;
                @(negedge ref_clk);
                clk_i = 1'b0;
            end else if (lock && half_period > 0) begin
                clk_i = 1'b1; #(half_period);
                clk_i = 1'b0; #(half_period);
            end else begin
                @(posedge ref_clk);
            end
        end
    end

    assign clk_out = clk_i;

endmodule
`endif
