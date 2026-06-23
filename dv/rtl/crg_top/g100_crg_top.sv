/***********************************************************
 * g100_crg_top - SoC-level CRG top (integrates clkmgr/rstmgr/pwrmgr)
 *
 * This is the unit under test in the ST environment. The three IPs are
 * wired together here:
 *   - pwrmgr.main_clk_en_o  -> clkmgr.pwr_main_clk_en
 *   - clkmgr.pwr_main_clk_status -> pwrmgr.main_clk_status_i
 *   - pwrmgr.rst_req_o       -> rstmgr (combined into tree via sw_rst)
 *   - clkmgr.{cpu,gpu,ddr}_clk -> rstmgr domain clocks
 *   - rstmgr.{cpu,gpu,ddr}_rst_n -> SoC
 *
 * APB decode: top 12 bits of paddr select IP.
 ************************************************************/
`ifndef G100_CRG_TOP__SV
`define G100_CRG_TOP__SV

`include "../crg_reg_map.sv"
`include "../clkmgr/clkmgr_top.sv"
`include "../rstmgr/rstmgr_top.sv"
`include "../pwrmgr/pwrmgr_top.sv"

module g100_crg_top (
    input  logic        apb_clk,
    input  logic        por_rst_n,

    // APB (shared)
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // External clocks
    input  logic        osc_clk,
    input  logic        xtal_clk,

    // External async resets
    input  logic        wdg_rst_n,
    input  logic        dbg_rst_n,
    input  logic        sw_rst_n,

    // External wake sources
    input  logic [3:0]  wake_src_i,

    // Clock outputs
    output logic        pll_clk,
    output logic        cpu_clk, gpu_clk, ddr_clk,
    output logic        cpu_clk_g, gpu_clk_g, ddr_clk_g,
    output logic        pll_lock,

    // Reset outputs
    output logic        cpu_rst_n, gpu_rst_n, ddr_rst_n,
    output logic [31:0] rst_reason,

    // Power outputs
    output logic        iso_en,
    output logic        pwr_state
);

    import crg_reg_map_pkg::*;

    // ---- APB reset (sync por) ----
    logic apb_rst_n;
    // simple 2FF sync inline
    logic [1:0] por_sync_q;
    always_ff @(posedge apb_clk or negedge por_rst_n) begin
        if (!por_rst_n) por_sync_q <= 2'b00;
        else            por_sync_q <= {por_sync_q[0], 1'b1};
    end
    assign apb_rst_n = por_sync_q[1];

    // ---- APB decode (per IP) ----
    logic        sel_clkmgr, sel_rstmgr, sel_pwrmgr;
    logic        psel_k, psel_r, psel_p;
    logic [31:0] prdata_k, prdata_r, prdata_p;
    logic        pready_k, pready_r, pready_p;
    logic        pslverr_k, pslverr_r, pslverr_p;

    assign sel_clkmgr = (paddr[31:12] == CLKMGR_BASE[31:12]);
    assign sel_rstmgr = (paddr[31:12] == RSTMGR_BASE[31:12]);
    assign sel_pwrmgr = (paddr[31:12] == PWRMGR_BASE[31:12]);

    assign psel_k = psel & sel_clkmgr;
    assign psel_r = psel & sel_rstmgr;
    assign psel_p = psel & sel_pwrmgr;

    always_comb begin
        prdata  = 32'h0;
        pready  = 1'b1;
        pslverr = 1'b0;
        if (sel_clkmgr) begin
            prdata = prdata_k; pready = pready_k; pslverr = pslverr_k;
        end else if (sel_rstmgr) begin
            prdata = prdata_r; pready = pready_r; pslverr = pslverr_r;
        end else if (sel_pwrmgr) begin
            prdata = prdata_p; pready = pready_p; pslverr = pslverr_p;
        end
    end

    // ---- Handshake wires between IPs ----
    logic main_clk_en_w, main_clk_status_w;
    logic rst_req_w, rst_status_w;

    // rst_req from pwrmgr forces sw_rst path to rstmgr (active low)
    logic combined_sw_rst_n;
    assign combined_sw_rst_n = sw_rst_n & ~rst_req_w;
    assign rst_status_w      = ~(cpu_rst_n & gpu_rst_n & ddr_rst_n); // 1 if any in reset

    // ---- clkmgr ----
    clkmgr_top u_clkmgr (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(psel_k), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata_k), .pready(pready_k), .pslverr(pslverr_k),
        .osc_clk(osc_clk), .xtal_clk(xtal_clk),
        .osc_period_ns(25.0),
        .pwr_main_clk_en(main_clk_en_w),
        .pwr_main_clk_status(main_clk_status_w),
        .pll_clk(pll_clk),
        .div_clk(),
        .cpu_clk(cpu_clk), .gpu_clk(gpu_clk), .ddr_clk(ddr_clk),
        .cpu_clk_g(cpu_clk_g), .gpu_clk_g(gpu_clk_g), .ddr_clk_g(ddr_clk_g),
        .pll_lock(pll_lock)
    );
    // (main_clk_status_w is driven by clkmgr; pwrmgr reads it as input)

    // ---- rstmgr ----
    rstmgr_top u_rstmgr (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(psel_r), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata_r), .pready(pready_r), .pslverr(pslverr_r),
        .por_rst_n(por_rst_n), .wdg_rst_n(wdg_rst_n),
        .dbg_rst_n(dbg_rst_n), .sw_rst_n(combined_sw_rst_n),
        .cpu_clk(cpu_clk), .gpu_clk(gpu_clk), .ddr_clk(ddr_clk),
        .cpu_rst_n(cpu_rst_n), .gpu_rst_n(gpu_rst_n), .ddr_rst_n(ddr_rst_n),
        .rst_reason_o(rst_reason)
    );

    // ---- pwrmgr ----
    pwrmgr_top u_pwrmgr (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(psel_p), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata_p), .pready(pready_p), .pslverr(pslverr_p),
        .wake_src_i(wake_src_i),
        .main_clk_en_o(main_clk_en_w), .main_clk_status_i(main_clk_status_w),
        .rst_req_o(rst_req_w), .rst_status_i(rst_status_w),
        .iso_en_o(iso_en), .pwr_state_o(pwr_state)
    );

endmodule
`endif
