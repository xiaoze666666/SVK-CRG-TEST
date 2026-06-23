/***********************************************************
 * clkmgr_top - Clock manager with 3-PLL clock tree
 *
 * Structure:
 *   25MHz XTAL -> {PLL_CPU, PLL_SOC, PLL_PERI}
 *   each PLL -> CK0, CK1 (dual output)
 *   3 domain muxes (3:1 select among PLL_CPU/SOC/PERI CK0)
 *   3 domain dividers
 *   leaf fan-out (10 clocks)
 *
 * Domains:
 *   domain0 (CPU):  PLL_CPU CK0 default -> cpu_core_clk, cpu_aclk (gated)
 *   domain1 (SOC):  PLL_SOC CK0 default -> axi_main_clk, ddr_ref_clk
 *   domain2 (PERI): PLL_PERI CK0 default -> ahb_clk->apb_clk chain, periph_clk,
 *                    gmac_tx_clk (from CK1), qspi_ref_clk
 *
 * BUG_001 (planted): glitch-free mux enb_q uses posedge instead of negedge.
 * BUG_002 (planted): PLL frac mode 2^23 vs 2^24.
 * BUG_004 (planted): ICG latch uses posedge instead of negedge.
 ************************************************************/
`ifndef CLKMGR_TOP__SV
`define CLKMGR_TOP__SV

`include "../crg_reg_map.sv"
`include "clkmgr_pll.sv"
`include "clkmgr_div.sv"
`include "clkmgr_gate.sv"
`include "clkmgr_mux.sv"

module clkmgr_top (
    input  logic        apb_clk,
    input  logic        apb_rst_n,

    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    input  logic        osc_clk,        // 25 MHz XTAL
    input  real         osc_period_ns,  // 25.0
    input  logic        gmac_rx_clk_i,  // external GMAC RX (async)

    input  logic        pwr_main_clk_en,
    output logic        pwr_main_clk_status,

    // ---- 3 PLL locks ----
    output logic        pll_cpu_lock,
    output logic        pll_soc_lock,
    output logic        pll_peri_lock,

    // ---- 10 leaf clock outputs ----
    output logic        cpu_core_clk,
    output logic        cpu_aclk,        // gated
    output logic        axi_main_clk,
    output logic        ddr_ref_clk,
    output logic        ahb_clk,
    output logic        apb_leaf_clk,    // APB leaf (renamed to avoid clash with apb_clk input)
    output logic        periph_clk,
    output logic        gmac_tx_clk,
    output logic        gmac_rx_clk,     // buffered external
    output logic        qspi_ref_clk
);

    import crg_reg_map_pkg::*;

    // ---- Register storage ----
    logic [31:0] pll_cpu_cfg0_q,   pll_cpu_cfg0_next;
    logic [31:0] pll_cpu_cfg1_q,   pll_cpu_cfg1_next;
    logic [31:0] pll_cpu_status_q;
    logic [31:0] pll_soc_cfg0_q,   pll_soc_cfg0_next;
    logic [31:0] pll_soc_cfg1_q,   pll_soc_cfg1_next;
    logic [31:0] pll_soc_status_q;
    logic [31:0] pll_peri_cfg0_q,  pll_peri_cfg0_next;
    logic [31:0] pll_peri_cfg1_q,  pll_peri_cfg1_next;
    logic [31:0] pll_peri_status_q;
    logic [31:0] mux_cfg_q,        mux_cfg_next;
    logic [31:0] div_cfg_q,        div_cfg_next;
    logic [31:0] gate_cfg_q,       gate_cfg_next;

    logic wr_access, rd_access;
    logic [31:0] addr_off;
    assign addr_off  = {paddr[11:2], 2'b00};
    assign wr_access = psel & penable & pwrite;
    assign rd_access = psel & penable & ~pwrite;
    assign pready    = 1'b1;
    assign pslverr   = 1'b0;

    always_comb begin
        pll_cpu_cfg0_next  = pll_cpu_cfg0_q;
        pll_cpu_cfg1_next  = pll_cpu_cfg1_q;
        pll_soc_cfg0_next  = pll_soc_cfg0_q;
        pll_soc_cfg1_next  = pll_soc_cfg1_q;
        pll_peri_cfg0_next = pll_peri_cfg0_q;
        pll_peri_cfg1_next = pll_peri_cfg1_q;
        mux_cfg_next       = mux_cfg_q;
        div_cfg_next       = div_cfg_q;
        gate_cfg_next      = gate_cfg_q;
        if (wr_access) begin
            case (addr_off)
                32'h00: pll_cpu_cfg0_next  = pwdata;
                32'h04: pll_cpu_cfg1_next  = pwdata;
                32'h0C: pll_soc_cfg0_next  = pwdata;
                32'h10: pll_soc_cfg1_next  = pwdata;
                32'h18: pll_peri_cfg0_next = pwdata;
                32'h1C: pll_peri_cfg1_next = pwdata;
                32'h24: mux_cfg_next       = pwdata;
                32'h28: div_cfg_next       = pwdata;
                32'h2C: gate_cfg_next      = pwdata;
                default: ;
            endcase
        end
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            pll_cpu_cfg0_q  <= PLL_CPU_CFG0_RST;
            pll_cpu_cfg1_q  <= PLL_CPU_CFG1_RST;
            pll_soc_cfg0_q  <= PLL_SOC_CFG0_RST;
            pll_soc_cfg1_q  <= PLL_SOC_CFG1_RST;
            pll_peri_cfg0_q <= PLL_PERI_CFG0_RST;
            pll_peri_cfg1_q <= PLL_PERI_CFG1_RST;
            mux_cfg_q       <= MUX_CFG_RST;
            div_cfg_q       <= DIV_CFG_RST;
            gate_cfg_q      <= GATE_CFG_RST;
        end else begin
            pll_cpu_cfg0_q  <= pll_cpu_cfg0_next;
            pll_cpu_cfg1_q  <= pll_cpu_cfg1_next;
            pll_soc_cfg0_q  <= pll_soc_cfg0_next;
            pll_soc_cfg1_q  <= pll_soc_cfg1_next;
            pll_peri_cfg0_q <= pll_peri_cfg0_next;
            pll_peri_cfg1_q <= pll_peri_cfg1_next;
            mux_cfg_q       <= mux_cfg_next;
            div_cfg_q       <= div_cfg_next;
            gate_cfg_q      <= gate_cfg_next;
        end
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            pll_cpu_status_q  <= PLL_CPU_STATUS_RST;
            pll_soc_status_q  <= PLL_SOC_STATUS_RST;
            pll_peri_status_q <= PLL_PERI_STATUS_RST;
        end else begin
            pll_cpu_status_q  <= {31'b0, pll_cpu_lock};
            pll_soc_status_q  <= {31'b0, pll_soc_lock};
            pll_peri_status_q <= {31'b0, pll_peri_lock};
        end
    end

    always_comb begin
        prdata = 32'h0;
        if (rd_access) begin
            case (addr_off)
                32'h00: prdata = pll_cpu_cfg0_q;
                32'h04: prdata = pll_cpu_cfg1_q;
                32'h08: prdata = pll_cpu_status_q;
                32'h0C: prdata = pll_soc_cfg0_q;
                32'h10: prdata = pll_soc_cfg1_q;
                32'h14: prdata = pll_soc_status_q;
                32'h18: prdata = pll_peri_cfg0_q;
                32'h1C: prdata = pll_peri_cfg1_q;
                32'h20: prdata = pll_peri_status_q;
                32'h24: prdata = mux_cfg_q;
                32'h28: prdata = div_cfg_q;
                32'h2C: prdata = gate_cfg_q;
                default: prdata = 32'h0;
            endcase
        end
    end

    // ---- Field decode ----
    logic        cpu_bypass;  logic [5:0] cpu_refdiv;  logic [7:0] cpu_fbdiv;
    logic        cpu_dsmen;   logic [23:0] cpu_frac;   logic [2:0] cpu_pd1, cpu_pd2;
    logic        soc_bypass;  logic [5:0] soc_refdiv;  logic [7:0] soc_fbdiv;
    logic        soc_dsmen;   logic [23:0] soc_frac;   logic [2:0] soc_pd1, soc_pd2;
    logic        peri_bypass; logic [5:0] peri_refdiv; logic [7:0] peri_fbdiv;
    logic        peri_dsmen;  logic [23:0] peri_frac;  logic [2:0] peri_pd1, peri_pd2;

    assign cpu_bypass  = pll_cpu_cfg0_q[0];
    assign cpu_refdiv  = pll_cpu_cfg0_q[7:2];
    assign cpu_fbdiv   = pll_cpu_cfg0_q[15:8];
    assign cpu_dsmen   = pll_cpu_cfg1_q[0];
    assign cpu_frac    = pll_cpu_cfg1_q[25:2];
    assign cpu_pd1     = pll_cpu_cfg1_q[28:26];
    assign cpu_pd2     = pll_cpu_cfg1_q[31:29];

    assign soc_bypass  = pll_soc_cfg0_q[0];
    assign soc_refdiv  = pll_soc_cfg0_q[7:2];
    assign soc_fbdiv   = pll_soc_cfg0_q[15:8];
    assign soc_dsmen   = pll_soc_cfg1_q[0];
    assign soc_frac    = pll_soc_cfg1_q[25:2];
    assign soc_pd1     = pll_soc_cfg1_q[28:26];
    assign soc_pd2     = pll_soc_cfg1_q[31:29];

    assign peri_bypass = pll_peri_cfg0_q[0];
    assign peri_refdiv = pll_peri_cfg0_q[7:2];
    assign peri_fbdiv  = pll_peri_cfg0_q[15:8];
    assign peri_dsmen  = pll_peri_cfg1_q[0];
    assign peri_frac   = pll_peri_cfg1_q[25:2];
    assign peri_pd1    = pll_peri_cfg1_q[28:26];
    assign peri_pd2    = pll_peri_cfg1_q[31:29];

    logic [1:0] mux_d0_sel, mux_d1_sel, mux_d2_sel;
    assign mux_d0_sel = mux_cfg_q[1:0];
    assign mux_d1_sel = mux_cfg_q[3:2];
    assign mux_d2_sel = mux_cfg_q[5:4];

    logic [6:0] div_d0_ratio, div_d1_ratio, div_d2_ratio;
    logic       div_d0_half, div_d1_half, div_d2_half;
    assign div_d0_ratio = div_cfg_q[6:0];
    assign div_d0_half  = div_cfg_q[7];
    assign div_d1_ratio = div_cfg_q[14:8];
    assign div_d1_half  = div_cfg_q[15];
    assign div_d2_ratio = div_cfg_q[22:16];
    assign div_d2_half  = div_cfg_q[23];

    logic [9:0] gate_en;
    assign gate_en = gate_cfg_q[9:0];

    // ---- 3 PLLs ----
    logic pll_cpu_ck0, pll_cpu_ck1, pll_soc_ck0, pll_soc_ck1, pll_peri_ck0, pll_peri_ck1;

    clkmgr_pll u_pll_cpu (
        .ref_clk(osc_clk), .ref_period_ns(osc_period_ns),
        .bypass(cpu_bypass), .refdiv(cpu_refdiv), .fbdiv(cpu_fbdiv),
        .dsmen(cpu_dsmen), .frac(cpu_frac),
        .postdiv1(cpu_pd1), .postdiv2(cpu_pd2),
        .ck0(pll_cpu_ck0), .ck1(pll_cpu_ck1), .lock(pll_cpu_lock)
    );
    clkmgr_pll u_pll_soc (
        .ref_clk(osc_clk), .ref_period_ns(osc_period_ns),
        .bypass(soc_bypass), .refdiv(soc_refdiv), .fbdiv(soc_fbdiv),
        .dsmen(soc_dsmen), .frac(soc_frac),
        .postdiv1(soc_pd1), .postdiv2(soc_pd2),
        .ck0(pll_soc_ck0), .ck1(pll_soc_ck1), .lock(pll_soc_lock)
    );
    clkmgr_pll u_pll_peri (
        .ref_clk(osc_clk), .ref_period_ns(osc_period_ns),
        .bypass(peri_bypass), .refdiv(peri_refdiv), .fbdiv(peri_fbdiv),
        .dsmen(peri_dsmen), .frac(peri_frac),
        .postdiv1(peri_pd1), .postdiv2(peri_pd2),
        .ck0(pll_peri_ck0), .ck1(pll_peri_ck1), .lock(pll_peri_lock)
    );

    // ---- 3 domain muxes (each 3:1 glitch-free) ----
    // sel=0 -> PLL_CPU CK0, sel=1 -> PLL_SOC CK0, sel=2 -> PLL_PERI CK0
    // We model the 3:1 as a 2-stage 2:1 mux: sel[0] picks CPU vs (SOC/PERI),
    // sel[1] picks SOC vs PERI in the second branch. Simplified to 2:1 + 2:1.
    logic dom0_clk, dom1_clk, dom2_clk;

    // dom0: sel=0->cpu_ck0, else soc_ck0 (simplified 2:1; full 3:1 needs 2 cascaded mux)
    clkmgr_mux u_mux_d0 (
        .clka(pll_cpu_ck0), .clkb(pll_soc_ck0), .sel(mux_d0_sel[0]), .clk_out(dom0_clk)
    );
    clkmgr_mux u_mux_d1 (
        .clka(pll_soc_ck0), .clkb(pll_cpu_ck0), .sel(mux_d1_sel[0]), .clk_out(dom1_clk)
    );
    clkmgr_mux u_mux_d2 (
        .clka(pll_peri_ck0), .clkb(pll_cpu_ck0), .sel(mux_d2_sel[0]), .clk_out(dom2_clk)
    );

    // ---- 3 domain dividers ----
    logic dom0_div_clk, dom1_div_clk, dom2_div_clk;
    clkmgr_div u_div_d0 (.clk_in(dom0_clk), .div_ratio(div_d0_ratio), .half_en(div_d0_half), .rst_n(apb_rst_n), .clk_out(dom0_div_clk));
    clkmgr_div u_div_d1 (.clk_in(dom1_clk), .div_ratio(div_d1_ratio), .half_en(div_d1_half), .rst_n(apb_rst_n), .clk_out(dom1_div_clk));
    clkmgr_div u_div_d2 (.clk_in(dom2_clk), .div_ratio(div_d2_ratio), .half_en(div_d2_half), .rst_n(apb_rst_n), .clk_out(dom2_div_clk));

    // ---- Leaf fan-out (10 clocks) ----
    // domain0 leaves: cpu_core_clk, cpu_aclk(gated)
    assign cpu_core_clk = dom0_clk;
    clkmgr_gate u_gate_aclk (.clk_in(dom0_clk), .gate_en(gate_en[0]), .rst_n(apb_rst_n), .clk_out(cpu_aclk));

    // domain1 leaves: axi_main_clk, ddr_ref_clk
    assign axi_main_clk = dom1_clk;
    assign ddr_ref_clk  = dom1_div_clk;

    // domain2 leaves: ahb_clk (from div_d2), apb_clk (ahb/2), periph_clk,
    //                 gmac_tx_clk (PLL_PERI CK1), qspi_ref_clk (PLL_PERI CK0)
    assign ahb_clk   = dom2_div_clk;
    // apb_leaf_clk: simple /2 of ahb (toggle FF). For behavioral sim, just forward ahb.
    assign apb_leaf_clk = ahb_clk;  // simplified; real chip has another div stage
    assign periph_clk = pll_peri_ck0;
    assign gmac_tx_clk = pll_peri_ck1;
    assign qspi_ref_clk = pll_peri_ck0;

    // external GMAC RX buffer
    assign gmac_rx_clk = gmac_rx_clk_i;

    // ---- Pwrmgr handshake ----
    assign pwr_main_clk_status = pwr_main_clk_en;

endmodule
`endif
