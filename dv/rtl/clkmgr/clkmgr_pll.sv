/***********************************************************
 * clkmgr_pll - Behavioral PLL with dual CK0/CK1 outputs
 *
 * One VCO, two post-divided outputs (CK0 and CK1). This mirrors real
 * SoC PLLs (e.g. PLL_CPU outputs CK0=CPU core freq, CK1=lower fabric freq).
 *
 *   Fvco = Fref * (fbdiv + (dsmen ? frac/2^24 : 0)) / refdiv
 *   Fck0 = Fvco / postdiv1
 *   Fck1 = Fvco / postdiv2
 *
 * Lock FSM: cfg change -> lock=0, count down refdiv*fbdiv cycles -> lock=1.
 *
 * BUG_002 (planted): frac mode uses 2^23 instead of 2^24 -> freq doubled.
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
    input  logic [2:0]  postdiv1,    // for CK0
    input  logic [2:0]  postdiv2,    // for CK1
    output logic        ck0,
    output logic        ck1,
    output logic        lock
);

    real fbdiv_eff;
    always_comb begin
        if (dsmen)
            fbdiv_eff = real'(fbdiv) + real'(frac) / 2.0**23;   // BUG_002: should be 2^24
        else
            fbdiv_eff = real'(fbdiv);
    end

    real pd1_eff, pd2_eff;
    always_comb begin
        pd1_eff = (postdiv1 == 0) ? 1.0 : real'(postdiv1);
        pd2_eff = (postdiv2 == 0) ? 1.0 : real'(postdiv2);
    end

    real vco_period, ck0_period, ck1_period;
    always_comb begin
        if (fbdiv_eff > 0) begin
            vco_period  = ref_period_ns * real'(refdiv) / fbdiv_eff;
            ck0_period  = vco_period * pd1_eff;
            ck1_period  = vco_period * pd2_eff;
        end else begin
            vco_period = 0; ck0_period = 0; ck1_period = 0;
        end
    end

    // ---- Lock FSM ----
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

    // ---- CK0 / CK1 generation ----
    real ck0_half, ck1_half;
    always_comb begin
        ck0_half = (ck0_period > 0) ? ck0_period / 2.0 : 0.0;
        ck1_half = (ck1_period > 0) ? ck1_period / 2.0 : 0.0;
    end

    logic ck0_i, ck1_i;

    // CK0: bypass=ref_clk, else gated by lock
    initial begin
        ck0_i = 1'b0;
        forever begin
            if (bypass) begin
                @(posedge ref_clk); ck0_i = 1'b1;
                @(negedge ref_clk); ck0_i = 1'b0;
            end else if (lock && ck0_half > 0) begin
                ck0_i = 1'b1; #(ck0_half);
                ck0_i = 1'b0; #(ck0_half);
            end else begin
                @(posedge ref_clk);
            end
        end
    end

    // CK1: independent oscillator at ck1_period
    initial begin
        ck1_i = 1'b0;
        forever begin
            if (bypass) begin
                @(posedge ref_clk); ck1_i = 1'b1;
                @(negedge ref_clk); ck1_i = 1'b0;
            end else if (lock && ck1_half > 0) begin
                ck1_i = 1'b1; #(ck1_half);
                ck1_i = 1'b0; #(ck1_half);
            end else begin
                @(posedge ref_clk);
            end
        end
    end

    assign ck0 = ck0_i;
    assign ck1 = ck1_i;

endmodule
`endif
